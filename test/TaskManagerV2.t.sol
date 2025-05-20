// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/TaskManagerV2.sol";

contract MockMembership is IMembership {
    mapping(address => bytes32) public roles;

    function roleOf(address u) external view returns (bytes32) {
        return roles[u];
    }

    function setRole(address u, bytes32 r) external {
        roles[u] = r;
    }
}

contract MockToken is IParticipationToken {
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function mint(address to, uint256 amt) external override {
        balanceOf[to] += amt;
        totalSupply += amt;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract TaskManagerV2Test is Test {
    TaskManagerV2 tm;
    MockMembership m;
    MockToken t;
    address exec = address(this);
    bytes32 CREATOR = keccak256("CREATOR");

    function setUp() public {
        m = new MockMembership();
        t = new MockToken();
        m.setRole(address(this), CREATOR);
        tm = new TaskManagerV2();
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = CREATOR;
        tm.initialize(address(t), address(m), roles, exec);
    }

    function testFooAndPriority() public {
        vm.prank(exec);
        tm.setFoo(10);
        assertEq(tm.getFoo(), 10);
        vm.prank(exec);
        bytes32 pid = tm.createProject(
            "m", 0, new address[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0)
        );
        vm.prank(exec);
        tm.createTask(1, "m", pid);
        vm.prank(exec);
        tm.setTaskPriority(0, 5);
        assertEq(tm.getTaskPriority(0), 5);
    }
}
