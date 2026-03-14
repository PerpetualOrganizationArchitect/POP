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

    // ══════════════════════════════════════════════════════════
    //  8. Removed satellite excluded from upgrade
    // ══════════════════════════════════════════════════════════

    function testRemovedSatelliteExcludedFromUpgrade() public {
        // Remove satellite 2 (index 1 in hub's satellite array)
        hub.removeSatellite(1);

        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("TestType"));
        assertEq(homePm.getCurrentImplementationById(typeId), address(implV2), "Home should be V2");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2), "Sat1 should be V2");
        // Sat2 was removed — still on V1
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV1), "Sat2 should still be V1");
    }

    // ══════════════════════════════════════════════════════════
    //  9. Emergency direct upgrade on satellite
    // ══════════════════════════════════════════════════════════

    function testEmergencyDirectUpgradeOnSatellite() public {
        satellite1.upgradeBeaconDirect("TestType", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("TestType"));
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2), "Sat1 should be V2 via direct");
        // Others unaffected
        assertEq(homePm.getCurrentImplementationById(typeId), address(implV1), "Home should still be V1");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV1), "Sat2 should still be V1");
    }

    // ══════════════════════════════════════════════════════════
    //  10. Dynamic satellite registration receives future upgrades
    // ══════════════════════════════════════════════════════════

    function testDynamicSatelliteRegistration() public {
        // Deploy a third satellite
        PoaManager sat3Pm = _deployPoaManager();
        PoaManagerSatellite satellite3 = new PoaManagerSatellite(address(sat3Pm), address(mailbox), 1, address(hub));
        sat3Pm.transferOwnership(address(satellite3));
        satellite3.addContractType("TestType", address(implV1));

        // Register it on the hub
        hub.registerSatellite(4, address(satellite3));

        // Now upgrade — all 3 satellites should get it
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        bytes32 typeId = keccak256(bytes("TestType"));
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2), "Sat1 should be V2");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV2), "Sat2 should be V2");
        assertEq(sat3Pm.getCurrentImplementationById(typeId), address(implV2), "Sat3 should be V2");
    }

    // ══════════════════════════════════════════════════════════
    //  11. Multiple independent contract types
    // ══════════════════════════════════════════════════════════

    function testMultipleIndependentContractTypes() public {
        IntegrationImplV1 implA = new IntegrationImplV1();
        IntegrationImplV2 implB = new IntegrationImplV2();

        // Register a second type on all chains
        hub.addContractType("TypeB", address(implA));
        satellite1.addContractType("TypeB", address(implA));
        satellite2.addContractType("TypeB", address(implA));

        // Upgrade only TestType
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        bytes32 testTypeId = keccak256(bytes("TestType"));
        bytes32 typeBId = keccak256(bytes("TypeB"));

        // TestType upgraded everywhere
        assertEq(homePm.getCurrentImplementationById(testTypeId), address(implV2));
        assertEq(sat1Pm.getCurrentImplementationById(testTypeId), address(implV2));

        // TypeB unchanged
        assertEq(homePm.getCurrentImplementationById(typeBId), address(implA), "TypeB should be unchanged");
        assertEq(sat1Pm.getCurrentImplementationById(typeBId), address(implA), "TypeB should be unchanged on sat1");

        // Now upgrade TypeB independently
        hub.upgradeBeaconCrossChain("TypeB", address(implB), "v2");
        assertEq(homePm.getCurrentImplementationById(typeBId), address(implB), "TypeB should now be upgraded");
        assertEq(sat1Pm.getCurrentImplementationById(typeBId), address(implB), "TypeB sat1 should be upgraded");
    }

    // ══════════════════════════════════════════════════════════
    //  12. Cross-chain admin call propagates to all chains
    // ══════════════════════════════════════════════════════════

    function testCrossChainAdminCallPropagates() public {
        // Deploy MockAdminTarget on home chain (owned by homePm)
        IntegrationAdminTarget homeTarget = new IntegrationAdminTarget(address(homePm));
        // Deploy MockAdminTarget on satellite 1 (owned by sat1Pm)
        IntegrationAdminTarget sat1Target = new IntegrationAdminTarget(address(sat1Pm));
        // Deploy MockAdminTarget on satellite 2 (owned by sat2Pm)
        IntegrationAdminTarget sat2Target = new IntegrationAdminTarget(address(sat2Pm));

        // All targets must be at the same address for cross-chain admin calls.
        // Since they won't be, we test with separate calls for realism.
        // The hub dispatches the same (target, data) to all satellites.
        // For this integration test, we use separate target addresses and
        // do two calls: one for home+sat1 target and one for sat2 target.

        // Actually, cross-chain admin call sends the same target address to all chains.
        // In production the target must be deployed at the same address on all chains.
        // In our synchronous mock, all contracts are on the same EVM, so we can
        // test by deploying a single target that accepts calls from any PoaManager.

        // Let's use a permissive target instead:
        IntegrationAdminTargetPermissive sharedTarget = new IntegrationAdminTargetPermissive();

        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 999);
        hub.adminCallCrossChain(address(sharedTarget), data);

        // The call is executed 3 times: once locally (via homePm) and once per satellite (via sat1Pm, sat2Pm)
        // Since the mock mailbox delivers synchronously, all 3 calls happen
        assertEq(sharedTarget.value(), 999, "Target value should be set");
        assertEq(sharedTarget.callCount(), 3, "Should be called 3 times (home + 2 satellites)");
    }

    // ══════════════════════════════════════════════════════════
    //  13. Cross-chain infra beacon upgrade
    // ══════════════════════════════════════════════════════════

    function testCrossChainInfraBeaconUpgrade() public {
        // Add an infra-style type "OrgDeployer" on all chains
        hub.addContractType("OrgDeployer", address(implV1));
        satellite1.addContractType("OrgDeployer", address(implV1));
        satellite2.addContractType("OrgDeployer", address(implV1));

        bytes32 typeId = keccak256(bytes("OrgDeployer"));

        // Verify all chains start with V1
        assertEq(homePm.getCurrentImplementationById(typeId), address(implV1), "Home should start at V1");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV1), "Sat1 should start at V1");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV1), "Sat2 should start at V1");

        // Upgrade cross-chain to V2
        hub.upgradeBeaconCrossChain("OrgDeployer", address(implV2), "v2");

        // Verify all chains upgraded to V2
        assertEq(homePm.getCurrentImplementationById(typeId), address(implV2), "Home should be V2");
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2), "Sat1 should be V2");
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV2), "Sat2 should be V2");
    }

    // ══════════════════════════════════════════════════════════
    //  14. Mixed: one satellite pinned, one mirroring
    // ══════════════════════════════════════════════════════════

    function testMixedPinnedAndMirroringSatellites() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // Sat1 SwitchableBeacon in Mirror mode
        address sat1Beacon = sat1Pm.getBeaconById(typeId);
        SwitchableBeacon sat1Mirror =
            new SwitchableBeacon(address(this), sat1Beacon, address(0), SwitchableBeacon.Mode.Mirror);

        // Sat2 SwitchableBeacon in Static mode (pinned to V1)
        address sat2Beacon = sat2Pm.getBeaconById(typeId);
        SwitchableBeacon sat2Static =
            new SwitchableBeacon(address(this), sat2Beacon, address(implV1), SwitchableBeacon.Mode.Static);

        assertEq(sat1Mirror.implementation(), address(implV1));
        assertEq(sat2Static.implementation(), address(implV1));

        // Upgrade cross-chain
        hub.upgradeBeaconCrossChain("TestType", address(implV2), "v2");

        // Mirror follows, static stays
        assertEq(sat1Mirror.implementation(), address(implV2), "Mirror should follow upgrade");
        assertEq(sat2Static.implementation(), address(implV1), "Static should stay pinned");

        // Both underlying PoaManagers are upgraded
        assertEq(sat1Pm.getCurrentImplementationById(typeId), address(implV2));
        assertEq(sat2Pm.getCurrentImplementationById(typeId), address(implV2));
    }

    // ══════════════════════════════════════════════════════════
    //  13. Full E2E: upgrade, then proxy on each chain
    // ══════════════════════════════════════════════════════════

    function testFullE2EProxiesOnAllChains() public {
        bytes32 typeId = keccak256(bytes("TestType"));

        // Create a BeaconProxy on each chain via SwitchableBeacon (Mirror)
        address homeOZBeacon = homePm.getBeaconById(typeId);
        SwitchableBeacon homeSB =
            new SwitchableBeacon(address(this), homeOZBeacon, address(0), SwitchableBeacon.Mode.Mirror);
        BeaconProxy homeProxy = new BeaconProxy(address(homeSB), "");

        address sat1OZBeacon = sat1Pm.getBeaconById(typeId);
        SwitchableBeacon sat1SB =
            new SwitchableBeacon(address(this), sat1OZBeacon, address(0), SwitchableBeacon.Mode.Mirror);
        BeaconProxy sat1Proxy = new BeaconProxy(address(sat1SB), "");

        address sat2OZBeacon = sat2Pm.getBeaconById(typeId);
        SwitchableBeacon sat2SB =
            new SwitchableBeacon(address(this), sat2OZBeacon, address(0), SwitchableBeacon.Mode.Mirror);
        BeaconProxy sat2Proxy = new BeaconProxy(address(sat2SB), "");

        // All proxies use V1
        assertEq(IntegrationImplV1(address(homeProxy)).version(), 1);
        assertEq(IntegrationImplV1(address(sat1Proxy)).version(), 1);
        assertEq(IntegrationImplV1(address(sat2Proxy)).version(), 1);

        // Cross-chain upgrade to V3
        hub.upgradeBeaconCrossChain("TestType", address(implV3), "v3");

        // All proxies now use V3
        assertEq(IntegrationImplV3(address(homeProxy)).version(), 3, "Home proxy should be V3");
        assertEq(IntegrationImplV3(address(sat1Proxy)).version(), 3, "Sat1 proxy should be V3");
        assertEq(IntegrationImplV3(address(sat2Proxy)).version(), 3, "Sat2 proxy should be V3");
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

/// @dev Admin target gated behind a specific PoaManager (for single-chain tests)
contract IntegrationAdminTarget {
    address public poaManager;
    uint256 public value;

    constructor(address _pm) {
        poaManager = _pm;
    }

    function setValueOnlyPM(uint256 _val) external {
        require(msg.sender == poaManager, "not pm");
        value = _val;
    }
}

/// @dev Permissive admin target that accepts calls from any PoaManager (for cross-chain integration tests)
contract IntegrationAdminTargetPermissive {
    uint256 public value;
    uint256 public callCount;

    function setValue(uint256 _val) external {
        value = _val;
        callCount++;
    }
}
