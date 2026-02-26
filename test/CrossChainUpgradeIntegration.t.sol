// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {SwitchableBeacon} from "../src/SwitchableBeacon.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManagerSatellite} from "../src/crosschain/PoaManagerSatellite.sol";
import {MockMailbox} from "./mocks/MockMailbox.sol";

/// @title CrossChainUpgradeIntegrationTest
/// @notice End-to-end test simulating cross-chain upgrade propagation
///         with 1 home chain + 2 satellite chains using MockMailbox.
contract CrossChainUpgradeIntegrationTest is Test {
    // Home chain (domain 1)
    PoaManager homePm;
    PoaManagerHub hub;
    MockMailbox mailbox;

    // Satellite 1 (domain 2)
    PoaManager sat1Pm;
    PoaManagerSatellite satellite1;

    // Satellite 2 (domain 3)
    PoaManager sat2Pm;
    PoaManagerSatellite satellite2;

    // Implementations
    IntegrationImplV1 implV1;
    IntegrationImplV2 implV2;
    IntegrationImplV3 implV3;

    function setUp() public {
        implV1 = new IntegrationImplV1();
        implV2 = new IntegrationImplV2();
        implV3 = new IntegrationImplV3();

        // Deploy MockMailbox (domain 1 = home)
        mailbox = new MockMailbox(1);

        // ── Home Chain ──
        homePm = _deployPoaManager();
        hub = new PoaManagerHub(address(homePm), address(mailbox));
        homePm.transferOwnership(address(hub));

        // ── Satellite 1 ──
        sat1Pm = _deployPoaManager();
        satellite1 = new PoaManagerSatellite(address(sat1Pm), address(mailbox), 1, address(hub));
        sat1Pm.transferOwnership(address(satellite1));

        // ── Satellite 2 ──
        sat2Pm = _deployPoaManager();
        satellite2 = new PoaManagerSatellite(address(sat2Pm), address(mailbox), 1, address(hub));
        sat2Pm.transferOwnership(address(satellite2));

        // Register satellites in Hub
        hub.registerSatellite(2, address(satellite1));
        hub.registerSatellite(3, address(satellite2));

        // Register "TestType" on all chains with V1
        hub.addContractType("TestType", address(implV1));
        satellite1.addContractType("TestType", address(implV1));
        satellite2.addContractType("TestType", address(implV1));
    }

    /*──────────── Helpers ───────────*/

    function _deployPoaManager() internal returns (PoaManager) {
        ImplementationRegistry regImpl = new ImplementationRegistry();
        UpgradeableBeacon regBeacon = new UpgradeableBeacon(address(regImpl), address(this));
        ImplementationRegistry reg = ImplementationRegistry(address(new BeaconProxy(address(regBeacon), "")));
        reg.initialize(address(this));

        PoaManager pm = new PoaManager(address(reg));
        reg.transferOwnership(address(pm));
        return pm;
    }

    // ══════════════════════════════════════════════════════════
    //  1. Cross-chain upgrade propagates to all satellites
    // ══════════════════════════════════════════════════════════

    function testCrossChainUpgradePropagatesToAllSatellites() public {
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("TestType"));

        // All three chains should have V2
        assertEq(homePm.getCurrentImplementationById(typeId), address(implV2), "Home should be V2");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2), "Sat1 should be V2");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV2), "Sat2 should be V2");
    }

    // ══════════════════════════════════════════════════════════
    //  2. SwitchableBeacon in mirror mode follows upgrade
    // ══════════════════════════════════════════════════════════

    function testSwitchableBeaconMirrorFollowsCrossChainUpgrade() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // Create SwitchableBeacons in Mirror mode on home and sat1
        address homeBeacon = homePm.getBeaconById(typeId);
        SwitchableBeacon homeSB =
            new SwitchableBeacon(address(this), homeBeacon, address(0), SwitchableBeacon.Mode.Mirror);

        address sat1Beacon = sat1Pm.getBeaconById(typeId);
        SwitchableBeacon sat1SB =
            new SwitchableBeacon(address(this), sat1Beacon, address(0), SwitchableBeacon.Mode.Mirror);

        // Both should return V1
        assertEq(homeSB.implementation(), address(implV1));
        assertEq(sat1SB.implementation(), address(implV1));

        // Upgrade cross-chain
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        // Both should now return V2
        assertEq(homeSB.implementation(), address(implV2), "Home SwitchableBeacon should follow to V2");
        assertEq(sat1SB.implementation(), address(implV2), "Sat1 SwitchableBeacon should follow to V2");
    }

    // ══════════════════════════════════════════════════════════
    //  3. SwitchableBeacon in static mode ignores upgrade
    // ══════════════════════════════════════════════════════════

    function testSwitchableBeaconStaticIgnoresCrossChainUpgrade() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // Create SwitchableBeacon in Static mode on sat1 (pinned to V1)
        address sat1Beacon = sat1Pm.getBeaconById(typeId);
        SwitchableBeacon sat1SB =
            new SwitchableBeacon(address(this), sat1Beacon, address(implV1), SwitchableBeacon.Mode.Static);

        assertEq(sat1SB.implementation(), address(implV1));

        // Upgrade cross-chain to V2
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        // Static beacon should still return V1
        assertEq(sat1SB.implementation(), address(implV1), "Static SwitchableBeacon should ignore upgrade");
    }

    // ══════════════════════════════════════════════════════════
    //  4. Sequential upgrades V1 → V2 → V3
    // ══════════════════════════════════════════════════════════

    function testSequentialUpgradesV1V2V3() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // V1 → V2
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        assertEq(homePm.getCurrentImplementationById(typeId), address(implV2));
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2));
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV2));

        // V2 → V3
        hub.upgradeBeaconCrossChain("TestType", address(implV3), "v3");

        assertEq(homePm.getCurrentImplementationById(typeId), address(implV3), "Home should be V3");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV3), "Sat1 should be V3");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV3), "Sat2 should be V3");
    }

    // ══════════════════════════════════════════════════════════
    //  5. Local-only upgrade does NOT propagate
    // ══════════════════════════════════════════════════════════

    function testLocalOnlyUpgradeDoesNotPropagate() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        hub.upgradeBeaconLocal("TestType", address(implV2), "v2");

        assertEq(homePm.getCurrentImplementationById(typeId), address(implV2), "Home should be V2");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV1), "Sat1 should still be V1");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV1), "Sat2 should still be V1");
    }

    // ══════════════════════════════════════════════════════════
    //  6. addContractTypeCrossChain propagates new type
    // ══════════════════════════════════════════════════════════

    function testAddContractTypeCrossChain() public {
        IntegrationImplV1 newTypeImpl = new IntegrationImplV1();

        hub.addContractTypeCrossChain("NewModule", address(newTypeImpl));

        bytes32 typeId = keccak256(bytes("NewModule"));
        assertEq(homePm.getCurrentImplementationById(typeId), address(newTypeImpl), "Home should have NewModule");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(newTypeImpl), "Sat1 should have NewModule");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(newTypeImpl), "Sat2 should have NewModule");
    }

    // ══════════════════════════════════════════════════════════
    //  7. Full E2E with BeaconProxy delegation
    // ══════════════════════════════════════════════════════════

    function testFullE2EWithBeaconProxyDelegation() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // Create SwitchableBeacon + BeaconProxy on satellite 1
        address sat1OZBeacon = sat1Pm.getBeaconById(typeId);
        SwitchableBeacon sb =
            new SwitchableBeacon(address(this), sat1OZBeacon, address(0), SwitchableBeacon.Mode.Mirror);
        BeaconProxy proxy = new BeaconProxy(address(sb), "");

        // Call through proxy — should use V1
        IntegrationImplV1 proxyV1 = IntegrationImplV1(address(proxy));
        assertEq(proxyV1.version(), 1);

        // Cross-chain upgrade to V2
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        // Same proxy now uses V2
        IntegrationImplV2 proxyV2 = IntegrationImplV2(address(proxy));
        assertEq(proxyV2.version(), 2);
    }
}

// ══════════════════════════════════════════════════════════════
//  Mock implementations
// ══════════════════════════════════════════════════════════════

contract IntegrationImplV1 {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract IntegrationImplV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract IntegrationImplV3 {
    function version() external pure returns (uint256) {
        return 3;
    }
}
