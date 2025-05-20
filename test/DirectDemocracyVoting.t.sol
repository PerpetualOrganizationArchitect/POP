// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DirectDemocracyVoting.sol";

contract MockMembership is IMembership {
    mapping(address => bytes32) public role;
    mapping(address => bool) public voters;

    function roleOf(address u) external view returns (bytes32) {
        return role[u];
    }

    function canVote(address u) external view returns (bool) {
        return voters[u];
    }

    function setRole(address u, bytes32 r, bool canV) external {
        role[u] = r;
        voters[u] = canV;
    }
}

contract MockExecutor is IExecutor {
    Call[] public last;

    function execute(uint256, Call[] calldata batch) external {
        delete last;
        for (uint256 i; i < batch.length; ++i) {
            last.push(batch[i]);
        }
    }
}

contract DDVotingTest is Test {
    DirectDemocracyVoting dd;
    MockMembership m;
    MockExecutor exec;
    address creator = address(0x1);
    address voter = address(0x2);

    bytes32 constant ROLE = keccak256("ROLE");

    function setUp() public {
        m = new MockMembership();
        exec = new MockExecutor();
        m.setRole(creator, ROLE, true);
        m.setRole(voter, ROLE, true);
        dd = new DirectDemocracyVoting();
    }

    function testInitializeReverts() public {
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE;
        vm.expectRevert("InvalidInitialization()");
        dd.initialize(address(m), address(exec), roles, new address[](0), 50);
    }
}
