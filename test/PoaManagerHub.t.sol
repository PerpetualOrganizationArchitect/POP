// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {MockMailbox} from "./mocks/MockMailbox.sol";
import {IMessageRecipient} from "../src/crosschain/interfaces/IHyperlane.sol";

/*──────────── Dummy implementations for testing ───────────*/
contract HubDummyImplV1 {
    function version() external pure returns (string memory) {
        return "v1";
    }
}

contract HubDummyImplV2 {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

/// @dev No-op Hyperlane recipient so MockMailbox's synchronous delivery doesn't revert.
contract NoopRecipient is IMessageRecipient {
    function handle(uint32, bytes32, bytes calldata) external override {}
}

contract PoaManagerHubTest is Test {
    ImplementationRegistry reg;
    PoaManager pm;
    MockMailbox mailbox;
    PoaManagerHub hub;
    NoopRecipient noopSatellite;

    HubDummyImplV1 implV1;
    HubDummyImplV2 implV2;

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

        // Deploy MockMailbox on domain 1
        mailbox = new MockMailbox(1);

        // Deploy Hub
        hub = new PoaManagerHub(address(pm), address(mailbox));

        // Transfer PM ownership to hub
        pm.transferOwnership(address(hub));

        // Deploy dummy impls
        implV1 = new HubDummyImplV1();
        implV2 = new HubDummyImplV2();

        // Deploy a no-op satellite recipient for cross-chain tests
        noopSatellite = new NoopRecipient();
    }

    // ══════════════════════════════════════════════════════════
    //  1. upgradeBeaconCrossChain upgrades local AND dispatches
    // ══════════════════════════════════════════════════════════

    function testUpgradeBeaconCrossChainUpgradesLocalAndDispatches() public {
        hub.addContractType("Widget", address(implV1));
        hub.registerSatellite(42, address(noopSatellite));

        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        // Local beacon upgraded
        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));

        // Mailbox received 1 dispatch
        assertEq(mailbox.dispatchedCount(), 1);

        // Verify payload
        (uint32 destDomain, bytes32 recipient, bytes memory body) = mailbox.dispatched(0);
        assertEq(destDomain, 42);
        assertEq(recipient, bytes32(uint256(uint160(address(noopSatellite)))));

        (uint8 msgType, string memory typeName, address newImpl, string memory ver) =
            abi.decode(body, (uint8, string, address, string));
        assertEq(msgType, 0x01);
        assertEq(typeName, "Widget");
        assertEq(newImpl, address(implV2));
        assertEq(ver, "v2");
    }

    // ══════════════════════════════════════════════════════════
    //  2. upgradeBeaconLocal — no dispatch
    // ══════════════════════════════════════════════════════════

    function testUpgradeBeaconLocalNoDispatch() public {
        hub.addContractType("Widget", address(implV1));
        hub.registerSatellite(42, address(noopSatellite));

        hub.upgradeBeaconLocal("Widget", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));
        assertEq(mailbox.dispatchedCount(), 0);
    }

    // ══════════════════════════════════════════════════════════
    //  3. registerSatellite / removeSatellite
    // ══════════════════════════════════════════════════════════

    function testRegisterAndRemoveSatellite() public {
        hub.registerSatellite(10, address(0xAAAA));
        hub.registerSatellite(20, address(0xBBBB));
        assertEq(hub.satelliteCount(), 2);

        (uint32 d1, bytes32 s1, bool a1) = hub.satellites(0);
        assertEq(d1, 10);
        assertEq(s1, bytes32(uint256(uint160(address(0xAAAA)))));
        assertTrue(a1);

        hub.removeSatellite(0);
        (,, bool a1After) = hub.satellites(0);
        assertFalse(a1After);

        (,, bool a2) = hub.satellites(1);
        assertTrue(a2);
    }

    // ══════════════════════════════════════════════════════════
    //  4. Paused hub blocks cross-chain upgrades
    // ══════════════════════════════════════════════════════════

    function testPausedHubBlocksCrossChain() public {
        hub.addContractType("Widget", address(implV1));
        hub.registerSatellite(42, address(noopSatellite));
        hub.setPaused(true);

        vm.expectRevert(PoaManagerHub.IsPaused.selector);
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");
    }

    // ══════════════════════════════════════════════════════════
    //  5. Paused hub allows local upgrade
    // ══════════════════════════════════════════════════════════

    function testPausedHubAllowsLocalUpgrade() public {
        hub.addContractType("Widget", address(implV1));
        hub.setPaused(true);

        hub.upgradeBeaconLocal("Widget", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));
    }

    // ══════════════════════════════════════════════════════════
    //  6. Only owner can upgrade
    // ══════════════════════════════════════════════════════════

    function testOnlyOwnerCanUpgrade() public {
        hub.addContractType("Widget", address(implV1));

        vm.prank(nonOwner);
        vm.expectRevert();
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        vm.prank(nonOwner);
        vm.expectRevert();
        hub.upgradeBeaconLocal("Widget", address(implV2), "v2");
    }

    // ══════════════════════════════════════════════════════════
    //  7. Only owner can register satellite
    // ══════════════════════════════════════════════════════════

    function testOnlyOwnerCanRegisterSatellite() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hub.registerSatellite(42, address(0x1234));
    }

    // ══════════════════════════════════════════════════════════
    //  8. addContractType (local only)
    // ══════════════════════════════════════════════════════════

    function testAddContractType() public {
        hub.addContractType("Widget", address(implV1));

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV1));
    }

    // ══════════════════════════════════════════════════════════
    //  9. addContractTypeCrossChain dispatches to active satellites
    // ══════════════════════════════════════════════════════════

    function testAddContractTypeCrossChain() public {
        NoopRecipient noopSatellite2 = new NoopRecipient();
        hub.registerSatellite(42, address(noopSatellite));
        hub.registerSatellite(99, address(noopSatellite2));
        hub.removeSatellite(1); // deactivate domain 99

        hub.addContractTypeCrossChain("Widget", address(implV1));

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV1));

        // Only 1 dispatch (inactive satellite skipped)
        assertEq(mailbox.dispatchedCount(), 1);

        (uint32 destDomain,, bytes memory body) = mailbox.dispatched(0);
        assertEq(destDomain, 42);

        (uint8 msgType, string memory typeName, address sentImpl) = abi.decode(body, (uint8, string, address));
        assertEq(msgType, 0x02);
        assertEq(typeName, "Widget");
        assertEq(sentImpl, address(implV1));
    }
}
