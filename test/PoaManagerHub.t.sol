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

    // ══════════════════════════════════════════════════════════
    //  10. Constructor reverts on zero poaManager address
    // ══════════════════════════════════════════════════════════

    function testConstructorRevertsZeroPoaManager() public {
        vm.expectRevert(PoaManagerHub.ZeroAddress.selector);
        new PoaManagerHub(address(0), address(mailbox));
    }

    // ══════════════════════════════════════════════════════════
    //  11. Constructor reverts on zero mailbox address
    // ══════════════════════════════════════════════════════════

    function testConstructorRevertsZeroMailbox() public {
        vm.expectRevert(PoaManagerHub.ZeroAddress.selector);
        new PoaManagerHub(address(pm), address(0));
    }

    // ══════════════════════════════════════════════════════════
    //  12. registerSatellite reverts on zero address
    // ══════════════════════════════════════════════════════════

    function testRegisterSatelliteRevertsZeroAddress() public {
        vm.expectRevert(PoaManagerHub.ZeroAddress.selector);
        hub.registerSatellite(42, address(0));
    }

    // ══════════════════════════════════════════════════════════
    //  13. Non-owner cannot removeSatellite
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotRemoveSatellite() public {
        hub.registerSatellite(42, address(noopSatellite));

        vm.prank(nonOwner);
        vm.expectRevert();
        hub.removeSatellite(0);
    }

    // ══════════════════════════════════════════════════════════
    //  14. Non-owner cannot setPaused
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotSetPaused() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hub.setPaused(true);
    }

    // ══════════════════════════════════════════════════════════
    //  15. Non-owner cannot addContractType
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotAddContractType() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hub.addContractType("Widget", address(implV1));
    }

    // ══════════════════════════════════════════════════════════
    //  16. Non-owner cannot addContractTypeCrossChain
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotAddContractTypeCrossChain() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hub.addContractTypeCrossChain("Widget", address(implV1));
    }

    // ══════════════════════════════════════════════════════════
    //  17. Non-owner cannot updateImplRegistry
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotUpdateImplRegistry() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        hub.updateImplRegistry(address(0x1234));
    }

    // ══════════════════════════════════════════════════════════
    //  18. Paused hub blocks addContractTypeCrossChain
    // ══════════════════════════════════════════════════════════

    function testPausedHubBlocksAddContractTypeCrossChain() public {
        hub.registerSatellite(42, address(noopSatellite));
        hub.setPaused(true);

        vm.expectRevert(PoaManagerHub.IsPaused.selector);
        hub.addContractTypeCrossChain("Widget", address(implV1));
    }

    // ══════════════════════════════════════════════════════════
    //  19. Multiple active satellites all receive dispatch
    // ══════════════════════════════════════════════════════════

    function testMultipleActiveSatellitesAllReceiveDispatch() public {
        NoopRecipient noop2 = new NoopRecipient();
        NoopRecipient noop3 = new NoopRecipient();
        hub.registerSatellite(10, address(noopSatellite));
        hub.registerSatellite(20, address(noop2));
        hub.registerSatellite(30, address(noop3));

        hub.addContractType("Widget", address(implV1));
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        assertEq(mailbox.dispatchedCount(), 3, "All 3 active satellites should receive dispatch");

        (uint32 d0,,) = mailbox.dispatched(0);
        (uint32 d1,,) = mailbox.dispatched(1);
        (uint32 d2,,) = mailbox.dispatched(2);
        assertEq(d0, 10);
        assertEq(d1, 20);
        assertEq(d2, 30);
    }

    // ══════════════════════════════════════════════════════════
    //  20. Upgrade with no satellites registered dispatches nothing
    // ══════════════════════════════════════════════════════════

    function testUpgradeWithNoSatellitesDispatchesNothing() public {
        hub.addContractType("Widget", address(implV1));

        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2), "Local upgrade should still work");
        assertEq(mailbox.dispatchedCount(), 0, "No dispatch with empty satellite list");
    }

    // ══════════════════════════════════════════════════════════
    //  21. updateImplRegistry passthrough works
    // ══════════════════════════════════════════════════════════

    function testUpdateImplRegistryPassthrough() public {
        // Deploy a new registry
        ImplementationRegistry newRegImpl = new ImplementationRegistry();
        UpgradeableBeacon newRegBeacon = new UpgradeableBeacon(address(newRegImpl), address(this));
        ImplementationRegistry newReg = ImplementationRegistry(address(new BeaconProxy(address(newRegBeacon), "")));
        newReg.initialize(address(this));
        newReg.transferOwnership(address(pm));

        hub.updateImplRegistry(address(newReg));
        assertEq(address(pm.registry()), address(newReg), "Registry should be updated via hub");
    }

    // ══════════════════════════════════════════════════════════
    //  22. Pause and unpause toggle works
    // ══════════════════════════════════════════════════════════

    function testPauseUnpauseToggle() public {
        hub.addContractType("Widget", address(implV1));
        hub.registerSatellite(42, address(noopSatellite));

        hub.setPaused(true);
        assertTrue(hub.paused());

        vm.expectRevert(PoaManagerHub.IsPaused.selector);
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        hub.setPaused(false);
        assertFalse(hub.paused());

        // Should work again after unpause
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");
        bytes32 typeId = keccak256(bytes("Widget"));
        assertEq(pm.getCurrentImplementationById(typeId), address(implV2));
    }

    // ══════════════════════════════════════════════════════════
    //  23. Events emitted on cross-chain upgrade
    // ══════════════════════════════════════════════════════════

    function testEmitsCrossChainUpgradeDispatchedEvent() public {
        hub.addContractType("Widget", address(implV1));
        hub.registerSatellite(42, address(noopSatellite));

        bytes32 typeId = keccak256(bytes("Widget"));

        vm.expectEmit(true, true, false, false);
        emit PoaManagerHub.CrossChainUpgradeDispatched(typeId, address(implV2), "v2", 42, bytes32(0));
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");
    }

    // ══════════════════════════════════════════════════════════
    //  24. Events emitted on satellite registration
    // ══════════════════════════════════════════════════════════

    function testEmitsSatelliteRegisteredEvent() public {
        vm.expectEmit(true, false, false, true);
        emit PoaManagerHub.SatelliteRegistered(42, address(noopSatellite));
        hub.registerSatellite(42, address(noopSatellite));
    }

    // ══════════════════════════════════════════════════════════
    //  25. Events emitted on satellite removal
    // ══════════════════════════════════════════════════════════

    function testEmitsSatelliteRemovedEvent() public {
        hub.registerSatellite(42, address(noopSatellite));

        vm.expectEmit(true, false, false, false);
        emit PoaManagerHub.SatelliteRemoved(42);
        hub.removeSatellite(0);
    }

    // ══════════════════════════════════════════════════════════
    //  26. Events emitted on pause set
    // ══════════════════════════════════════════════════════════

    function testEmitsPauseSetEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PoaManagerHub.PauseSet(true);
        hub.setPaused(true);
    }

    // ══════════════════════════════════════════════════════════
    //  27. withdrawETH rescues stuck ETH
    // ══════════════════════════════════════════════════════════

    function testWithdrawETHRescuesStuckFunds() public {
        // Send ETH to hub via payable function (simulating accidental overpayment)
        vm.deal(address(hub), 1 ether);

        address payable recipient = payable(address(0xCAFE));
        uint256 before = recipient.balance;

        hub.withdrawETH(recipient);

        assertEq(recipient.balance - before, 1 ether, "Recipient should receive 1 ether");
        assertEq(address(hub).balance, 0, "Hub should have 0 balance");
    }

    // ══════════════════════════════════════════════════════════
    //  28. withdrawETH reverts on zero address
    // ══════════════════════════════════════════════════════════

    function testWithdrawETHRevertsZeroAddress() public {
        vm.deal(address(hub), 1 ether);

        vm.expectRevert(PoaManagerHub.ZeroAddress.selector);
        hub.withdrawETH(payable(address(0)));
    }

    // ══════════════════════════════════════════════════════════
    //  29. Non-owner cannot withdrawETH
    // ══════════════════════════════════════════════════════════

    function testNonOwnerCannotWithdrawETH() public {
        vm.deal(address(hub), 1 ether);

        vm.prank(nonOwner);
        vm.expectRevert();
        hub.withdrawETH(payable(nonOwner));
    }

    // ══════════════════════════════════════════════════════════
    //  30. withdrawETH with zero balance succeeds (no-op)
    // ══════════════════════════════════════════════════════════

    function testWithdrawETHWithZeroBalanceSucceeds() public {
        assertEq(address(hub).balance, 0);

        address payable recipient = payable(address(0xCAFE));
        hub.withdrawETH(recipient);

        assertEq(recipient.balance, 0, "No ETH to send");
    }

    // ══════════════════════════════════════════════════════════
    //  31. Duplicate satellite registration causes duplicate dispatches
    // ══════════════════════════════════════════════════════════

    function testDuplicateSatelliteCausesDuplicateDispatches() public {
        // Register the same satellite twice
        hub.registerSatellite(42, address(noopSatellite));
        hub.registerSatellite(42, address(noopSatellite));
        assertEq(hub.satelliteCount(), 2, "Should have 2 entries (duplicates allowed)");

        hub.addContractType("Widget", address(implV1));
        hub.upgradeBeaconCrossChain("Widget", address(implV2), "v2");

        // Both entries dispatch, so 2 messages sent (duplicate)
        assertEq(mailbox.dispatchedCount(), 2, "Duplicate satellite = duplicate dispatch");
    }
}
