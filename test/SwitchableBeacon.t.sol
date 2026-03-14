// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SwitchableBeacon.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract SwitchableBeaconTest is Test {
    SwitchableBeacon public switchableBeacon;
    UpgradeableBeacon public poaBeacon;

    MockImplementationV1 public implV1;
    MockImplementationV2 public implV2;

    address public owner = address(this);
    address public newOwner = address(0x1234);
    address public unauthorized = address(0x5678);

    // Events (must match OZ + SwitchableBeacon)
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event ModeChanged(SwitchableBeacon.Mode mode);
    event MirrorSet(address indexed mirrorBeacon);
    event Pinned(address indexed implementation);

    function setUp() public {
        implV1 = new MockImplementationV1();
        implV2 = new MockImplementationV2();
        poaBeacon = new UpgradeableBeacon(address(implV1), owner);
        switchableBeacon = new SwitchableBeacon(owner, address(poaBeacon), address(0), SwitchableBeacon.Mode.Mirror);
    }

    // ============ Constructor State Tests ============

    function testConstructorSetsInitialState() public {
        assertEq(switchableBeacon.owner(), owner);
        assertEq(switchableBeacon.pendingOwner(), address(0));
        assertEq(switchableBeacon.mirrorBeacon(), address(poaBeacon));
        assertEq(switchableBeacon.staticImplementation(), address(0));
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
    }

    function testConstructorStaticModeSetsAllFields() public {
        SwitchableBeacon sb =
            new SwitchableBeacon(newOwner, address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);

        assertEq(sb.owner(), newOwner);
        assertEq(sb.mirrorBeacon(), address(poaBeacon));
        assertEq(sb.staticImplementation(), address(implV1));
        assertEq(uint256(sb.mode()), uint256(SwitchableBeacon.Mode.Static));
    }

    // ============ Mirror Mode Tests ============

    function testMirrorModeTracksPoaBeacon() public {
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(switchableBeacon.implementation(), address(implV1));

        poaBeacon.upgradeTo(address(implV2));

        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    function testMirrorModeWithZeroImplementationReverts() public {
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        SwitchableBeacon beacon =
            new SwitchableBeacon(owner, address(brokenBeacon), address(0), SwitchableBeacon.Mode.Mirror);

        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        beacon.implementation();
    }

    // ============ Static Mode Tests ============

    function testStaticModeIsolatesFromPoaUpdates() public {
        SwitchableBeacon staticBeacon =
            new SwitchableBeacon(owner, address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);

        assertEq(uint256(staticBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(staticBeacon.implementation(), address(implV1));

        poaBeacon.upgradeTo(address(implV2));

        assertEq(staticBeacon.implementation(), address(implV1));
    }

    function testStaticModeWithZeroImplementationReverts() public {
        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        new SwitchableBeacon(owner, address(poaBeacon), address(0), SwitchableBeacon.Mode.Static);
    }

    // ============ Mode Switching Tests ============

    function testPinToCurrent() public {
        assertEq(switchableBeacon.implementation(), address(implV1));
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));

        vm.expectEmit(true, false, false, true);
        emit Pinned(address(implV1));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Static);

        switchableBeacon.pinToCurrent();

        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(switchableBeacon.implementation(), address(implV1));
        assertEq(switchableBeacon.staticImplementation(), address(implV1));

        poaBeacon.upgradeTo(address(implV2));

        assertEq(switchableBeacon.implementation(), address(implV1));
    }

    function testPinToSpecificImplementation() public {
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));

        vm.expectEmit(true, false, false, true);
        emit Pinned(address(implV2));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Static);

        switchableBeacon.pin(address(implV2));

        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    function testSetMirrorResumesFollowing() public {
        SwitchableBeacon staticBeacon =
            new SwitchableBeacon(owner, address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);

        poaBeacon.upgradeTo(address(implV2));

        assertEq(staticBeacon.implementation(), address(implV1));

        vm.expectEmit(true, false, false, true);
        emit MirrorSet(address(poaBeacon));
        vm.expectEmit(false, false, false, true);
        emit ModeChanged(SwitchableBeacon.Mode.Mirror);

        staticBeacon.setMirror(address(poaBeacon));

        assertEq(uint256(staticBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(staticBeacon.implementation(), address(implV2));
    }

    function testSetMirrorWithNewBeacon() public {
        UpgradeableBeacon poaBeacon2 = new UpgradeableBeacon(address(implV2), owner);

        switchableBeacon.setMirror(address(poaBeacon2));

        assertEq(switchableBeacon.mirrorBeacon(), address(poaBeacon2));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    // ============ Access Control Tests ============

    function testOnlyOwnerCanPin() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        switchableBeacon.pin(address(implV2));

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        switchableBeacon.pinToCurrent();
    }

    function testOnlyOwnerCanSetMirror() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        switchableBeacon.setMirror(address(poaBeacon));
    }

    function testOnlyOwnerCanTransferOwnership() public {
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        switchableBeacon.transferOwnership(newOwner);
    }

    function testOwnershipTransfer() public {
        // Initiate ownership transfer
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferStarted(owner, newOwner);

        switchableBeacon.transferOwnership(newOwner);

        assertEq(switchableBeacon.owner(), owner);
        assertEq(switchableBeacon.pendingOwner(), newOwner);

        // Pending owner accepts ownership
        vm.prank(newOwner);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(owner, newOwner);
        switchableBeacon.acceptOwnership();

        assertEq(switchableBeacon.owner(), newOwner);
        assertEq(switchableBeacon.pendingOwner(), address(0));

        // Old owner can't perform restricted operations
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        switchableBeacon.pin(address(implV2));

        // New owner can perform operations
        vm.prank(newOwner);
        switchableBeacon.pin(address(implV2));
        assertEq(switchableBeacon.implementation(), address(implV2));
    }

    function testAcceptOwnershipRevertsIfNotPendingOwner() public {
        switchableBeacon.transferOwnership(newOwner);

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        switchableBeacon.acceptOwnership();
    }

    function testTransferOwnershipOverwritesPendingOwner() public {
        // Initiate transfer to newOwner
        switchableBeacon.transferOwnership(newOwner);
        assertEq(switchableBeacon.pendingOwner(), newOwner);

        // Overwrite with different pending owner (replaces cancel functionality)
        address anotherOwner = address(0xABCD);
        switchableBeacon.transferOwnership(anotherOwner);
        assertEq(switchableBeacon.pendingOwner(), anotherOwner);

        // Original pending owner can no longer accept
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        switchableBeacon.acceptOwnership();

        // New pending owner can accept
        vm.prank(anotherOwner);
        switchableBeacon.acceptOwnership();
        assertEq(switchableBeacon.owner(), anotherOwner);
    }

    // ============ Renounce Ownership Tests ============

    function testRenounceOwnershipReverts() public {
        vm.expectRevert(SwitchableBeacon.CannotRenounce.selector);
        switchableBeacon.renounceOwnership();
    }

    function testRenounceOwnershipRevertsFromAnyone() public {
        vm.prank(unauthorized);
        vm.expectRevert(SwitchableBeacon.CannotRenounce.selector);
        switchableBeacon.renounceOwnership();
    }

    // ============ Constructor Validation Tests ============

    function testConstructorRevertsOnZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new SwitchableBeacon(address(0), address(poaBeacon), address(implV1), SwitchableBeacon.Mode.Static);
    }

    function testConstructorRevertsOnZeroMirrorBeacon() public {
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        new SwitchableBeacon(owner, address(0), address(implV1), SwitchableBeacon.Mode.Mirror);
    }

    function testConstructorRevertsOnNonContractMirrorBeacon() public {
        address eoa = address(0x1234);
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        new SwitchableBeacon(owner, eoa, address(0), SwitchableBeacon.Mode.Mirror);
    }

    function testConstructorRevertsOnNonContractStaticImpl() public {
        address eoa = address(0x1234);
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        new SwitchableBeacon(owner, address(poaBeacon), eoa, SwitchableBeacon.Mode.Static);
    }

    // ============ Input Validation Tests ============

    function testPinRevertsOnZeroAddress() public {
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.pin(address(0));
    }

    function testPinRevertsOnNonContract() public {
        address eoa = address(0x5678);
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.pin(eoa);
    }

    function testSetMirrorRevertsOnZeroAddress() public {
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.setMirror(address(0));
    }

    function testSetMirrorRevertsOnNonContract() public {
        address eoa = address(0x9999);
        vm.expectRevert(SwitchableBeacon.NotContract.selector);
        switchableBeacon.setMirror(eoa);
    }

    function testSetMirrorRevertsOnBrokenBeacon() public {
        MockBrokenBeacon brokenBeacon = new MockBrokenBeacon();

        vm.expectRevert(SwitchableBeacon.ImplNotSet.selector);
        switchableBeacon.setMirror(address(brokenBeacon));
    }

    function testTransferOwnershipToZeroClearsPending() public {
        // First set a pending owner
        switchableBeacon.transferOwnership(newOwner);
        assertEq(switchableBeacon.pendingOwner(), newOwner);

        // Transfer to zero effectively cancels the pending transfer
        switchableBeacon.transferOwnership(address(0));
        assertEq(switchableBeacon.pendingOwner(), address(0));

        // Original pending owner can no longer accept
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner));
        switchableBeacon.acceptOwnership();
    }

    // ============ View Functions ============

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
        bytes memory initData = abi.encodeWithSignature("initialize()");
        BeaconProxy proxy = new BeaconProxy(address(switchableBeacon), initData);

        MockImplementationV1 proxyV1 = MockImplementationV1(address(proxy));
        assertEq(proxyV1.version(), "V1");

        poaBeacon.upgradeTo(address(implV2));

        MockImplementationV2 proxyV2 = MockImplementationV2(address(proxy));
        assertEq(proxyV2.version(), "V2");
        assertEq(proxyV2.newFeature(), "New in V2");

        switchableBeacon.pinToCurrent();

        poaBeacon.upgradeTo(address(implV1));

        assertEq(proxyV2.version(), "V2");
    }

    // ============ Fuzz Tests ============

    function testFuzzPin(uint256 seed) public {
        vm.assume(seed > 0 && seed < 1000);

        address impl;
        if (seed % 3 == 0) {
            impl = address(new MockImplementationV1());
        } else if (seed % 3 == 1) {
            impl = address(new MockImplementationV2());
        } else {
            impl = address(new MockImplementationV1());
        }

        switchableBeacon.pin(impl);
        assertEq(switchableBeacon.implementation(), impl);
        assertEq(switchableBeacon.staticImplementation(), impl);
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Static));
    }

    function testFuzzSetMirror(uint256 seed) public {
        vm.assume(seed > 0 && seed < 100);

        MockImplementationV1 newImpl;
        if (seed % 2 == 0) {
            newImpl = new MockImplementationV1();
        } else {
            newImpl = new MockImplementationV1();
        }

        UpgradeableBeacon newBeacon = new UpgradeableBeacon(address(newImpl), owner);

        switchableBeacon.setMirror(address(newBeacon));
        assertEq(switchableBeacon.mirrorBeacon(), address(newBeacon));
        assertEq(uint256(switchableBeacon.mode()), uint256(SwitchableBeacon.Mode.Mirror));
        assertEq(switchableBeacon.implementation(), address(newImpl));
    }

    function testFuzzOwnershipTransfer(address newAddr) public {
        vm.assume(newAddr != address(0));

        switchableBeacon.transferOwnership(newAddr);
        assertEq(switchableBeacon.pendingOwner(), newAddr);
        assertEq(switchableBeacon.owner(), owner);

        vm.prank(newAddr);
        switchableBeacon.acceptOwnership();
        assertEq(switchableBeacon.owner(), newAddr);
        assertEq(switchableBeacon.pendingOwner(), address(0));
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
