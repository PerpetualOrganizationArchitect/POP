// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/Executor.sol";
import "./mocks/MockHats.sol";

contract Target {
    uint256 public val;

    function setVal(uint256 v) external payable {
        val = v;
    }
}

contract ExecutorTest is Test {
    Executor exec;
    MockHats hats;
    address owner = address(this);
    address caller = address(0x1);
    Target target;

    function setUp() public {
        hats = new MockHats();
        Executor impl = new Executor();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        exec = Executor(payable(address(new BeaconProxy(address(beacon), ""))));
        exec.initialize(owner, address(hats));
        target = new Target();
        exec.setCaller(caller);
    }

    function testExecuteBatch() public {
        IExecutor.Call[] memory batch = new IExecutor.Call[](1);
        batch[0] =
            IExecutor.Call({target: address(target), value: 0, data: abi.encodeWithSignature("setVal(uint256)", 42)});
        vm.prank(caller);
        exec.execute(1, batch);
        assertEq(target.val(), 42);
    }

    function testUnauthorizedReverts() public {
        IExecutor.Call[] memory batch = new IExecutor.Call[](0);
        vm.expectRevert(Executor.EmptyBatch.selector);
        vm.prank(caller);
        exec.execute(1, batch);
    }

    function testHatMintingAuthorization() public {
        address minter = address(0x2);
        address user = address(0x3);
        uint256 hatId = 1;

        // Test unauthorized minting fails
        uint256[] memory hatIds = new uint256[](1);
        hatIds[0] = hatId;
        vm.prank(minter);
        vm.expectRevert(Executor.UnauthorizedCaller.selector);
        exec.mintHatsForUser(user, hatIds);

        // Authorize minter
        exec.setHatMinterAuthorization(minter, true);

        // Test authorized minting succeeds
        vm.prank(minter);
        exec.mintHatsForUser(user, hatIds);
        assertTrue(hats.isWearerOfHat(user, hatId));

        // Test deauthorization
        exec.setHatMinterAuthorization(minter, false);
        vm.prank(minter);
        vm.expectRevert(Executor.UnauthorizedCaller.selector);
        exec.mintHatsForUser(user, hatIds);
    }

    function testSetCallerUnauthorizedReverts() public {
        address random = address(0x99);
        vm.prank(random);
        vm.expectRevert(Executor.UnauthorizedCaller.selector);
        exec.setCaller(address(0x5));
    }

    function testSetCallerZeroAddressReverts() public {
        vm.expectRevert(Executor.ZeroAddress.selector);
        exec.setCaller(address(0));
    }

    function testAllowedCallerCanSetNewCaller() public {
        address newCaller = address(0x5);
        vm.prank(caller);
        exec.proposeCaller(newCaller);

        vm.warp(block.timestamp + 2 days);

        vm.prank(caller);
        exec.acceptCaller();
        assertEq(exec.allowedCaller(), newCaller);
    }

    function testProposeCallerUnauthorizedReverts() public {
        address random = address(0x99);
        vm.prank(random);
        vm.expectRevert(Executor.UnauthorizedCaller.selector);
        exec.proposeCaller(address(0x5));
    }

    function testAcceptCallerBeforeTimelockReverts() public {
        vm.prank(caller);
        exec.proposeCaller(address(0x5));

        // Try to accept immediately (before 2-day delay)
        vm.prank(caller);
        vm.expectRevert(Executor.TimelockNotExpired.selector);
        exec.acceptCaller();
    }

    function testCancelCallerChange() public {
        address newCaller = address(0x5);
        vm.prank(caller);
        exec.proposeCaller(newCaller);

        // Cancel the change
        vm.prank(caller);
        exec.cancelCallerChange();

        // Warp past delay and try to accept — should fail (pending cleared)
        vm.warp(block.timestamp + 2 days);
        vm.prank(caller);
        vm.expectRevert(Executor.ZeroAddress.selector);
        exec.acceptCaller();

        // Caller should be unchanged
        assertEq(exec.allowedCaller(), caller);
    }

    function testProposeCallerZeroAddressReverts() public {
        vm.prank(caller);
        vm.expectRevert(Executor.ZeroAddress.selector);
        exec.proposeCaller(address(0));
    }
}
