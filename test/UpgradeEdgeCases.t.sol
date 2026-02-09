// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {SwitchableBeacon} from "../src/SwitchableBeacon.sol";

/// @title UpgradeEdgeCasesTest
/// @notice Tests the full upgrade chain: PoaBeacon → SwitchableBeacon → BeaconProxy → delegatecall
///         with real proxy state, mode switches, multi-tenancy, and recovery scenarios.
contract UpgradeEdgeCasesTest is Test {
    UpgradeableBeacon poaBeacon;
    MockUpgradeableV1 implV1;
    MockUpgradeableV2 implV2;
    MockUpgradeableV3 implV3;

    function setUp() public {
        implV1 = new MockUpgradeableV1();
        implV2 = new MockUpgradeableV2();
        implV3 = new MockUpgradeableV3();
        poaBeacon = new UpgradeableBeacon(address(implV1), address(this));
    }

    /// @dev Helper: create a SwitchableBeacon in Mirror mode + a BeaconProxy using it
    function _deployMirrorProxy() internal returns (SwitchableBeacon switchable, MockUpgradeableV1 proxy) {
        switchable = new SwitchableBeacon(address(this), address(poaBeacon), address(0), SwitchableBeacon.Mode.Mirror);
        BeaconProxy bp = new BeaconProxy(address(switchable), "");
        proxy = MockUpgradeableV1(address(bp));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 1: Full upgrade chain flows through Mirror to proxy
    // ══════════════════════════════════════════════════════════════════════

    function testPoaBeaconUpgradeFlowsThroughMirrorToProxy() public {
        (SwitchableBeacon switchable, MockUpgradeableV1 proxy) = _deployMirrorProxy();

        // Write state through V1
        proxy.setValue(42);
        assertEq(proxy.value(), 42);
        assertEq(proxy.version(), 1);

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Verify chain: proxy → switchable → poaBeacon → V2
        assertEq(switchable.implementation(), address(implV2));

        // State preserved, V2 features available
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(address(proxy));
        assertEq(proxyV2.value(), 42);
        assertEq(proxyV2.version(), 2);
        proxyV2.setNewField(99);
        assertEq(proxyV2.newField(), 99);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 2: Pinned proxy ignores POA upgrade
    // ══════════════════════════════════════════════════════════════════════

    function testPinnedProxyIgnoresPoaUpgrade() public {
        (SwitchableBeacon switchable, MockUpgradeableV1 proxy) = _deployMirrorProxy();

        proxy.setValue(77);
        assertEq(proxy.version(), 1);

        // Pin to current V1
        switchable.pinToCurrent();
        assertFalse(switchable.isMirrorMode());

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Proxy still on V1
        assertEq(proxy.version(), 1);
        assertEq(proxy.value(), 77);
        assertEq(switchable.implementation(), address(implV1));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 3: Two proxies with divergent modes (multi-tenancy)
    // ══════════════════════════════════════════════════════════════════════

    function testTwoProxiesDivergentModes() public {
        // Org1: Mirror mode
        (SwitchableBeacon switchable1, MockUpgradeableV1 proxy1) = _deployMirrorProxy();
        // Org2: starts Mirror, will pin
        (SwitchableBeacon switchable2, MockUpgradeableV1 proxy2) = _deployMirrorProxy();

        // Write distinct state
        proxy1.setValue(10);
        proxy2.setValue(20);

        // Org2 pins to current V1
        switchable2.pinToCurrent();

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Org1 (mirror) → V2
        MockUpgradeableV2 proxy1V2 = MockUpgradeableV2(address(proxy1));
        assertEq(proxy1V2.version(), 2);
        assertEq(proxy1V2.value(), 10);

        // Org2 (pinned) → still V1
        assertEq(proxy2.version(), 1);
        assertEq(proxy2.value(), 20);

        // No cross-contamination
        assertEq(switchable1.implementation(), address(implV2));
        assertEq(switchable2.implementation(), address(implV1));
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 4: State preserved through Mirror → Static → Mirror cycle
    // ══════════════════════════════════════════════════════════════════════

    function testProxyStatePreservedThroughMirrorStaticMirrorCycle() public {
        (SwitchableBeacon switchable, MockUpgradeableV1 proxy) = _deployMirrorProxy();

        // 1. Mirror mode, V1
        proxy.setValue(42);
        assertEq(proxy.value(), 42);
        assertEq(proxy.version(), 1);

        // 2. Pin → Static
        switchable.pinToCurrent();
        assertFalse(switchable.isMirrorMode());

        // 3. Upgrade POA to V2 (proxy should NOT see it)
        poaBeacon.upgradeTo(address(implV2));
        assertEq(proxy.version(), 1);
        assertEq(proxy.value(), 42);

        // 4. Back to Mirror
        switchable.setMirror(address(poaBeacon));
        assertTrue(switchable.isMirrorMode());

        // 5. Now on V2, state preserved
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(address(proxy));
        assertEq(proxyV2.version(), 2);
        assertEq(proxyV2.value(), 42);

        // V2 features work
        proxyV2.setNewField(100);
        assertEq(proxyV2.newField(), 100);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 5: pinToCurrent reverts when mirror returns zero
    // ══════════════════════════════════════════════════════════════════════

    function testPinToCurrentWhenMirrorReturnsZero() public {
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        SwitchableBeacon switchable =
            new SwitchableBeacon(address(this), address(brokenBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        // pinToCurrent should revert - mirror returns address(0)
        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        switchable.pinToCurrent();

        // State unchanged - still in Mirror mode
        assertTrue(switchable.isMirrorMode());
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 6: Recovery from broken mirror via pin to known good
    // ══════════════════════════════════════════════════════════════════════

    function testRecoveryFromBrokenMirrorViaPinToKnownGood() public {
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        SwitchableBeacon switchable =
            new SwitchableBeacon(address(this), address(brokenBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        // implementation() reverts
        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        switchable.implementation();

        // tryGetImplementation returns failure
        (bool success,) = switchable.tryGetImplementation();
        assertFalse(success);

        // Recovery: pin to known-good implementation
        switchable.pin(address(implV1));
        assertEq(switchable.implementation(), address(implV1));
        assertFalse(switchable.isMirrorMode());

        // Proxy using this beacon now works
        BeaconProxy bp = new BeaconProxy(address(switchable), "");
        MockUpgradeableV1 proxy = MockUpgradeableV1(address(bp));
        proxy.setValue(55);
        assertEq(proxy.value(), 55);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 7: Multiple sequential upgrades preserve state
    // ══════════════════════════════════════════════════════════════════════

    function testMultipleSequentialUpgradesPreserveState() public {
        (, MockUpgradeableV1 proxy) = _deployMirrorProxy();

        // V1: set value
        proxy.setValue(10);
        assertEq(proxy.version(), 1);

        // Upgrade to V2, set V2 field
        poaBeacon.upgradeTo(address(implV2));
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(address(proxy));
        assertEq(proxyV2.version(), 2);
        assertEq(proxyV2.value(), 10); // V1 state preserved
        proxyV2.setNewField(20);

        // Upgrade to V3, set V3 field
        poaBeacon.upgradeTo(address(implV3));
        MockUpgradeableV3 proxyV3 = MockUpgradeableV3(address(proxy));
        assertEq(proxyV3.version(), 3);
        assertEq(proxyV3.value(), 10); // V1 state preserved
        assertEq(proxyV3.newField(), 20); // V2 state preserved
        proxyV3.setThirdField(30);
        assertEq(proxyV3.thirdField(), 30);
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 8: Pin to arbitrary impl not from mirror
    // ══════════════════════════════════════════════════════════════════════

    function testPinToArbitraryImplNotFromMirror() public {
        (SwitchableBeacon switchable, MockUpgradeableV1 proxy) = _deployMirrorProxy();

        proxy.setValue(33);
        assertEq(proxy.version(), 1);

        // Pin directly to V3 (never served by mirror, which has V1)
        switchable.pin(address(implV3));
        assertEq(switchable.implementation(), address(implV3));
        assertFalse(switchable.isMirrorMode());

        // Proxy now uses V3
        MockUpgradeableV3 proxyV3 = MockUpgradeableV3(address(proxy));
        assertEq(proxyV3.version(), 3);
        assertEq(proxyV3.value(), 33); // State preserved

        // POA beacon upgrade to V2 has no effect
        poaBeacon.upgradeTo(address(implV2));
        assertEq(proxyV3.version(), 3); // Still pinned to V3
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 9: setMirror to a different POA beacon
    // ══════════════════════════════════════════════════════════════════════

    function testSetMirrorToDifferentPoaBeacon() public {
        // BeaconA has V1, BeaconB has V2
        UpgradeableBeacon beaconB = new UpgradeableBeacon(address(implV2), address(this));

        (SwitchableBeacon switchable, MockUpgradeableV1 proxy) = _deployMirrorProxy();
        proxy.setValue(50);
        assertEq(proxy.version(), 1); // tracking beaconA (V1)

        // Switch to tracking beaconB
        switchable.setMirror(address(beaconB));
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(address(proxy));
        assertEq(proxyV2.version(), 2); // now on V2
        assertEq(proxyV2.value(), 50); // state preserved

        // Upgrade beaconA to V3 - no effect (tracking beaconB now)
        poaBeacon.upgradeTo(address(implV3));
        assertEq(proxyV2.version(), 2); // still V2

        // Upgrade beaconB to V3 - this one matters
        beaconB.upgradeTo(address(implV3));
        MockUpgradeableV3 proxyV3 = MockUpgradeableV3(address(proxy));
        assertEq(proxyV3.version(), 3);
        assertEq(proxyV3.value(), 50); // state preserved through all transitions
    }

    // ══════════════════════════════════════════════════════════════════════
    //  Test 10: Ownership transfer and subsequent pin
    // ══════════════════════════════════════════════════════════════════════

    function testBeaconOwnershipTransferAndSubsequentPin() public {
        address factory = address(this);
        address executor = address(0xE1E2);

        SwitchableBeacon switchable =
            new SwitchableBeacon(factory, address(poaBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        // Factory initiates transfer to executor
        switchable.transferOwnership(executor);
        assertEq(switchable.owner(), factory);
        assertEq(switchable.pendingOwner(), executor);

        // Factory can still manage beacon (owner until accepted)
        switchable.pin(address(implV1));
        assertEq(switchable.implementation(), address(implV1));
        switchable.setMirror(address(poaBeacon)); // back to mirror

        // Executor accepts ownership
        vm.prank(executor);
        switchable.acceptOwnership();
        assertEq(switchable.owner(), executor);
        assertEq(switchable.pendingOwner(), address(0));

        // Factory can no longer manage
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchable.pin(address(implV2));

        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchable.setMirror(address(poaBeacon));

        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchable.pinToCurrent();

        // Executor can manage
        vm.prank(executor);
        switchable.pin(address(implV2));
        assertEq(switchable.implementation(), address(implV2));
    }
}

// ══════════════════════════════════════════════════════════════════════
//  Mock implementations with storage-compatible layout progression
// ══════════════════════════════════════════════════════════════════════

contract MockUpgradeableV1 {
    uint256 public value; // slot 0

    function setValue(uint256 v) external {
        value = v;
    }

    function version() external pure returns (uint256) {
        return 1;
    }
}

contract MockUpgradeableV2 {
    uint256 public value; // slot 0 (same as V1)
    uint256 public newField; // slot 1 (new, doesn't overwrite)

    function setValue(uint256 v) external {
        value = v;
    }

    function setNewField(uint256 v) external {
        newField = v;
    }

    function version() external pure returns (uint256) {
        return 2;
    }
}

contract MockUpgradeableV3 {
    uint256 public value; // slot 0
    uint256 public newField; // slot 1
    uint256 public thirdField; // slot 2

    function setValue(uint256 v) external {
        value = v;
    }

    function setNewField(uint256 v) external {
        newField = v;
    }

    function setThirdField(uint256 v) external {
        thirdField = v;
    }

    function version() external pure returns (uint256) {
        return 3;
    }
}

contract MockBrokenBeacon {
    function implementation() external pure returns (address) {
        return address(0);
    }
}
