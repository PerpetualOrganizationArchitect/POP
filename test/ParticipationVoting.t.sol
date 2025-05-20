// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ParticipationVoting.sol";

contract MockMembership is IMembership {
    mapping(address => bytes32) public role;

    function roleOf(address u) external view returns (bytes32) {
        return role[u];
    }

    function canVote(address) external pure returns (bool) {
        return true;
    }

    function setRole(address u, bytes32 r) external {
        role[u] = r;
    }
}

contract MockToken is IERC20 {
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

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

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }
}

contract MockExecutor is IExecutor {
    function execute(uint256, Call[] calldata) external {}
}

contract PVotingTest is Test {
    ParticipationVoting pv;
    MockMembership m;
    MockToken t;
    MockExecutor exec;
    address creator = address(0x1);
    address voter = address(0x2);
    bytes32 constant ROLE = keccak256("ROLE");

    function setUp() public {
        m = new MockMembership();
        t = new MockToken();
        exec = new MockExecutor();
        m.setRole(creator, ROLE);
        m.setRole(voter, ROLE);
        t.mint(voter, 10 ether);
        pv = new ParticipationVoting();
    }

    function testInitializeReverts() public {
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE;
        vm.expectRevert("InvalidInitialization()");
        pv.initialize(address(exec), address(m), address(t), roles, new address[](0), 50, false, 1);
    }
}
