// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {PoaManagerSatellite} from "../src/crosschain/PoaManagerSatellite.sol";

/*──────────── Dummy implementations for testing ───────────*/
contract SatDummyImplV1 {
    function version() external pure returns (string memory) {
        return "v1";
    }
}

contract SatDummyImplV2 {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

contract PoaManagerSatelliteTest is Test {
    ImplementationRegistry reg;
    PoaManager pm;
    PoaManagerSatellite satellite;

    SatDummyImplV1 implV1;
    SatDummyImplV2 implV2;

    address mailbox = address(0xAA11);
    uint32 hubDomain = 1;
    address hubAddr = address(0x4455);
    address nonOwner = address(0xBEEF);

    function setUp() public {
        // Deploy ImplementationRegistry behind a beacon proxy
        ImplementationRegistry regImpl = new ImplementationRegistry();
        UpgradeableBeacon regBeacon = new UpgradeableBeacon(address(regImpl), address(this));
        reg = ImplementationRegistry(address(new BeaconProxy(address(regBeacon), "")));
        reg.initialize(address(this));

        // Deploy PoaManager with registry
        pm = new PoaManager(address(reg));
        reg.transferOwnership(address(pm));

        // Deploy Satellite
        satellite = new PoaManagerSatellite(address(pm), mailbox, hubDomain, hubAddr);

        // Transfer PM ownership to satellite
        pm.transferOwnership(address(satellite));

        // Deploy dummy impls
        implV1 = new SatDummyImplV1();
        implV2 = new SatDummyImplV2();
    }

    /*──────────── Helpers ───────────*/

    function _upgradePayload(string memory typeName, address newImpl, string memory ver)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encode(uint8(0x01), typeName, newImpl, ver);
    }

    function _addTypePayload(string memory typeName, address impl) internal pure returns (bytes memory) {
        return abi.encode(uint8(0x02), typeName, impl);
    }

    function _deliverMessage(bytes memory body) internal {
        vm.prank(mailbox);
        satellite.handle(hubDomain, bytes32(uint256(uint160(hubAddr))), body);
    }

    // ══════════════════════════════════════════════════════════
    //  1. handle upgrades local beacon
    // ══════════════════════════════════════════════════════════

    function testHandleUpgradesLocalBeacon() public {
        satellite.addContractType("Widget", address(implV1));

        _deliverMessage(_upgradePayload("Widget", address(implV2), "v2"));

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));
    }

    // ══════════════════════════════════════════════════════════
    //  2. handle adds contract type
    // ══════════════════════════════════════════════════════════

    function testHandleAddsContractType() public {
        _deliverMessage(_addTypePayload("Gadget", address(implV1)));

        bytes32 typeId = keccak256(bytes("Gadget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV1));
    }

    // ══════════════════════════════════════════════════════════
    //  3. Rejects non-mailbox caller
    // ══════════════════════════════════════════════════════════

    function testRejectsNonMailboxCaller() public {
        bytes memory body = _addTypePayload("Widget", address(implV1));

        vm.prank(address(0xDEAD));
        vm.expectRevert(PoaManagerSatellite.UnauthorizedMailbox.selector);
        satellite.handle(hubDomain, bytes32(uint256(uint160(hubAddr))), body);
    }

    // ══════════════════════════════════════════════════════════
    //  4. Rejects wrong origin domain
    // ══════════════════════════════════════════════════════════

    function testRejectsWrongOriginDomain() public {
        bytes memory body = _addTypePayload("Widget", address(implV1));

        vm.prank(mailbox);
        vm.expectRevert(PoaManagerSatellite.UnauthorizedOrigin.selector);
        satellite.handle(999, bytes32(uint256(uint160(hubAddr))), body);
    }

    // ══════════════════════════════════════════════════════════
    //  5. Rejects wrong sender address
    // ══════════════════════════════════════════════════════════

    function testRejectsWrongSenderAddress() public {
        bytes memory body = _addTypePayload("Widget", address(implV1));

        vm.prank(mailbox);
        vm.expectRevert(PoaManagerSatellite.UnauthorizedSender.selector);
        satellite.handle(hubDomain, bytes32(uint256(uint160(address(0xBAD)))), body);
    }

    // ══════════════════════════════════════════════════════════
    //  6. Rejects unknown message type
    // ══════════════════════════════════════════════════════════

    function testRejectsUnknownMessageType() public {
        bytes memory body = abi.encode(uint8(0xFF), "Widget", address(implV1));

        vm.prank(mailbox);
        vm.expectRevert(PoaManagerSatellite.UnknownMessageType.selector);
        satellite.handle(hubDomain, bytes32(uint256(uint160(hubAddr))), body);
    }

    // ══════════════════════════════════════════════════════════
    //  7. upgradeBeaconDirect by owner (emergency)
    // ══════════════════════════════════════════════════════════

    function testUpgradeBeaconDirectByOwner() public {
        satellite.addContractType("Widget", address(implV1));

        satellite.upgradeBeaconDirect("Widget", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));
    }

    // ══════════════════════════════════════════════════════════
    //  8. Non-owner cannot upgradeBeaconDirect
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotUpgradeBeaconDirect() public {
        satellite.addContractType("Widget", address(implV1));

        vm.prank(nonOwner);
        vm.expectRevert();
        satellite.upgradeBeaconDirect("Widget", address(implV2), "v2");
    }

    // ══════════════════════════════════════════════════════════
    //  9. handle reverts if impl has no code
    // ══════════════════════════════════════════════════════════

    function testHandleRevertsIfImplNotDeployed() public {
        address noCode = address(0xDEADC0DE);
        bytes memory body = _addTypePayload("Ghost", noCode);

        vm.prank(mailbox);
        vm.expectRevert(PoaManager.ImplZero.selector);
        satellite.handle(hubDomain, bytes32(uint256(uint160(hubAddr))), body);
    }
}
