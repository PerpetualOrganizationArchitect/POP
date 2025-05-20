// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Executor.sol";

contract Target {
    uint256 public val;

    function setVal(uint256 v) external payable {
        val = v;
    }
}

contract ExecutorTest is Test {
    Executor exec;
    address owner = address(this);
    address caller = address(0x1);
    Target target;

    function setUp() public {
        exec = new Executor();
        exec.initialize(owner);
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
}
