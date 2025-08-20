// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SwitchableBeacon.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/**
 * @title SwitchableBeaconTest
 * @notice Comprehensive unit tests for the SwitchableBeacon contract
 * @dev Tests mirror mode, static mode, mode switching, access control, and edge cases
 */
contract SwitchableBeaconTest is Test {
    // Test contracts
    SwitchableBeacon public switchableBeacon;
    UpgradeableBeacon public poaBeacon;

    // Mock implementation contracts
    MockImplementationV1 public implV1;
    MockImplementationV2 public implV2;

    // Test addresses
    address public owner = address(this);
    address public newOwner = address(0x1234);
    address public unauthorized = address(0x5678);

    // Events
    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);
    event ModeChanged(SwitchableBeacon.Mode mode);
    event MirrorSet(address indexed mirrorBeacon);
    event Pinned(address indexed implementation);

    function setUp() public {
        // Deploy mock implementations
        implV1 = new MockImplementationV1();
        implV2 = new MockImplementationV2();

        // Deploy POA global beacon with V1
        poaBeacon = new UpgradeableBeacon(address(implV1), owner);

        // Deploy SwitchableBeacon in Mirror mode initially
        switchableBeacon = new SwitchableBeacon(
            owner,
            address(poaBeacon),
            address(0), // No static impl needed for Mirror mode
            SwitchableBeacon.Mode.Mirror
        );
    }

    // ============ Mirror Mode Tests ============

    function testMirrorModeTracksPoaBeacon() public {
        // Verify initial state
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(switchableBeacon.implementation(), address(implV1));

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Verify SwitchableBeacon now returns V2
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    function testMirrorModeWithZeroImplementationReverts() public {
        // Deploy a beacon that returns zero address
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        // Create SwitchableBeacon pointing to broken beacon
        SwitchableBeacon beacon =
            new SwitchableBeacon(owner, address(brokenBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        // Should revert when trying to get implementation
        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        beacon.implementation();
    }

    // ============ Static Mode Tests ============

    function testStaticModeIsolatesFromPoaUpdates() public {
        // Deploy in Static mode with V1
        SwitchableBeacon staticBeacon =
            new SwitchableBeacon(owner, address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);

        // Verify initial state
        assertEq(uint256(staticBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(staticBeacon.implementation(), address(implV1));

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Verify static beacon still returns V1
        assertEq(staticBeacon.implementation(), address(implV1));
    }

    function testStaticModeWithZeroImplementationReverts() public {
        // Should revert when creating in Static mode with zero implementation
        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        new SwitchableBeacon(owner, address(poaBeacon), address(0), SwitchableBeacon.Mode.Static);
    }

    // ============ Mode Switching Tests ============

    function testPinToCurrent() public {
        // Start in Mirror mode tracking V1
        assertEq(switchableBeacon.implementation(), address(implV1));
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));

        // Pin to current implementation
        vm.expectEmit(true, false, false, true);
        emit Pinned(address(implV1));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Static);

        switchableBeacon.pinToCurrent();

        // Verify mode changed to Static
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(switchableBeacon.implementation(), address(implV1));
        assertEq(switchableBeacon.staticImplementation(), address(implV1));

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Verify still pinned to V1
        assertEq(switchableBeacon.implementation(), address(implV1));
    }

    function testPinToSpecificImplementation() public {
        // Start in Mirror mode
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));

        // Pin to V2 directly
        vm.expectEmit(true, false, false, true);
        emit Pinned(address(implV2));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Static);

        switchableBeacon.pin(address(implV2));

        // Verify pinned to V2
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    function testSetMirrorResumesFollowing() public {
        // Start in Static mode with V1
        SwitchableBeacon staticBeacon =
            new SwitchableBeacon(owner, address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Verify still on V1
        assertEq(staticBeacon.implementation(), address(implV1));

        // Switch to Mirror mode
        vm.expectEmit(true, false, false, true);
        emit MirrorSet(address(poaBeacon));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Mirror);

        staticBeacon.setMirror(address(poaBeacon));

        // Verify now following V2
        assertEq(uint256(staticBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(staticBeacon.implementation(), address(implV2));
    }

    function testSetMirrorWithNewBeacon() public {
        // Create a second POA beacon with V2
        UpgradeableBeacon poaBeacon2 = new UpgradeableBeacon(address(implV2), owner);

        // Switch to the new beacon
        switchableBeacon.setMirror(address(poaBeacon2));

        // Verify now following new beacon
        assertEq(switchableBeacon.mirrorBeacon(), address(poaBeacon2));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    // ============ Access Control Tests ============

    function testOnlyOwnerCanPin() public {
        vm.prank(unauthorized);
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchableBeacon.pin(address(implV2));

        vm.prank(unauthorized);
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchableBeacon.pinToCurrent();
    }

    function testOnlyOwnerCanSetMirror() public {
        vm.prank(unauthorized);
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchableBeacon.setMirror(address(poaBeacon));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(unauthorized);
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchableBeacon.transferOwnership(newOwner);
    }

    function testOwnershipTransfer() public {
        // Transfer ownership
        vm.expectEmit(true, true, false, false);
        emit OwnerTransferred(owner, newOwner);

        switchableBeacon.transferOwnership(newOwner);

        // Verify new owner
        assertEq(switchableBeacon.owner(), newOwner);

        // Old owner can't perform restricted operations
        vm.expectRevert(SwitchableBeacon.NotOwner.selector);
        switchableBeacon.pin(address(implV2));

        // New owner can perform operations
        vm.prank(newOwner);
        switchableBeacon.pin(address(implV2));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    // ============ Zero Address Guards ============

    function testConstructorRevertsOnZeroOwner() public {
        vm.expectRevert(SwitchableBeacon.ZeroAddress.selector);
        new SwitchableBeacon(address(0), address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);
    }

    function testConstructorRevertsOnZeroMirrorBeacon() public {
        vm.expectRevert(SwitchableBeacon.ZeroAddress.selector);
        new SwitchableBeacon(owner, address(0), address(implV1), SwitchableBeacon.Mode.Mirror);
    }
    
    // ============ Contract Validation Tests ============
    
    function testConstructorRevertsOnNonContractMirrorBeacon() public {
        address eoa = address(0x1234); // EOA address
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        new SwitchableBeacon(owner, eoa, address(0), SwitchableBeacon.Mode.Mirror);
    }
    
    function testConstructorRevertsOnNonContractStaticImpl() public {
        address eoa = address(0x1234); // EOA address
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        new SwitchableBeacon(owner, address(poaBeacon), eoa, SwitchableBeacon.Mode.Static);
    }

    function testPinRevertsOnZeroAddress() public {
        vm.expectRevert(SwitchableBeacon.ZeroAddress.selector);
        switchableBeacon.pin(address(0));
    }
    
    function testPinRevertsOnNonContract() public {
        address eoa = address(0x5678); // EOA address
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.pin(eoa);
    }

    function testSetMirrorRevertsOnZeroAddress() public {
        vm.expectRevert(SwitchableBeacon.ZeroAddress.selector);
        switchableBeacon.setMirror(address(0));
    }
    
    function testSetMirrorRevertsOnNonContract() public {
        address eoa = address(0x9999); // EOA address
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.setMirror(eoa);
    }

    function testSetMirrorRevertsOnBrokenBeacon() public {
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        switchableBeacon.setMirror(address(brokenBeacon));
    }

    function testTransferOwnershipRevertsOnZeroAddress() public {
        vm.expectRevert(SwitchableBeacon.ZeroAddress.selector);
        switchableBeacon.transferOwnership(address(0));
    }

    // ============ Helper View Functions ============

    function testIsMirrorMode() public {
        // Initially in Mirror mode
        assertTrue(switchableBeacon.isMirrorMode());

        // Pin to static
        switchableBeacon.pin(address(implV1));
        assertFalse(switchableBeacon.isMirrorMode());

        // Back to mirror
        switchableBeacon.setMirror(address(poaBeacon));
        assertTrue(switchableBeacon.isMirrorMode());
    }

    function testTryGetImplementation() public {
        // Test in Mirror mode
        (bool success, address impl) = switchableBeacon.tryGetImplementation();
        assertTrue(success);
        assertEq(impl, address(implV1));

        // Test in Static mode
        switchableBeacon.pin(address(implV2));
        (success, impl) = switchableBeacon.tryGetImplementation();
        assertTrue(success);
        assertEq(impl, address(implV2));

        // Test with broken beacon
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();
        SwitchableBeacon brokenSwitchable =
            new SwitchableBeacon(owner, address(brokenBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        (success, impl) = brokenSwitchable.tryGetImplementation();
        assertFalse(success);
        assertEq(impl, address(0));
    }

    // ============ Integration with BeaconProxy ============

    function testBeaconProxyIntegration() public {
        // Deploy a BeaconProxy pointing to our SwitchableBeacon
        bytes memory initData = abi.encodeWithSignature("initialize()");
        BeaconProxy proxy = new BeaconProxy(address(switchableBeacon), initData);

        // Call through proxy (should use V1)
        MockImplementationV1 proxyV1 = MockImplementationV1(address(proxy));
        assertEq(proxyV1.version(), "V1");

        // Upgrade POA beacon to V2
        poaBeacon.upgradeTo(address(implV2));

        // Call through proxy (should now use V2 in Mirror mode)
        MockImplementationV2 proxyV2 = MockImplementationV2(address(proxy));
        assertEq(proxyV2.version(), "V2");
        assertEq(proxyV2.newFeature(), "New in V2");

        // Pin to V2
        switchableBeacon.pinToCurrent();

        // Upgrade POA beacon to V1 again
        poaBeacon.upgradeTo(address(implV1));

        // Proxy should still use V2 (pinned)
        assertEq(proxyV2.version(), "V2");
    }

    // ============ Fuzz Tests ============

    function testFuzzPin(uint256 seed) public {
        vm.assume(seed > 0 && seed < 1000);
        
        // Create a valid contract address to pin
        address impl;
        if (seed % 3 == 0) {
            impl = address(new MockImplementationV1());
        } else if (seed % 3 == 1) {
            impl = address(new MockImplementationV2());
        } else {
            // Deploy another mock contract
            impl = address(new MockImplementationV1());
        }

        switchableBeacon.pin(impl);
        assertEq(switchableBeacon.implementation(), impl);
        assertEq(switchableBeacon.staticImplementation(), impl);
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
    }

    function testFuzzSetMirror(uint256 seed) public {
        // Instead of fuzzing addresses directly, create valid beacons
        vm.assume(seed > 0 && seed < 100);

        // Create different mock implementations based on seed
        MockImplementationV1 newImpl;
        if (seed % 2 == 0) {
            newImpl = new MockImplementationV1();
        } else {
            // Deploy another instance
            newImpl = new MockImplementationV1();
        }

        // Deploy a new UpgradeableBeacon with the implementation
        UpgradeableBeacon newBeacon = new UpgradeableBeacon(address(newImpl), owner);

        // Set the new beacon as mirror
        switchableBeacon.setMirror(address(newBeacon));
        assertEq(switchableBeacon.mirrorBeacon(), address(newBeacon));
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(switchableBeacon.implementation(), address(newImpl));
    }

    function testFuzzOwnershipTransfer(address newAddr) public {
        vm.assume(newAddr != address(0));

        switchableBeacon.transferOwnership(newAddr);
        assertEq(switchableBeacon.owner(), newAddr);
    }
}

// ============ Mock Contracts ============

contract MockImplementationV1 {
    bool public initialized;

    function initialize() external {
        initialized = true;
    }

    function version() external pure returns (string memory) {
        return "V1";
    }
}

contract MockImplementationV2 {
    bool public initialized;

    function initialize() external {
        initialized = true;
    }

    function version() external pure returns (string memory) {
        return "V2";
    }

    function newFeature() external pure returns (string memory) {
        return "New in V2";
    }
}

contract MockBrokenBeacon {
    function implementation() external pure returns (address) {
        return address(0);
    }
}

