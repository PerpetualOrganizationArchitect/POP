// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ElectionContract.sol";

contract MockMembership is INFTMembership {
    address public last;
    bytes32 public lastRole;

    function mintOrChange(address m, bytes32 r) external {
        last = m;
        lastRole = r;
    }
}

contract ElectionContractTest is Test {
    ElectionContract ec;
    MockMembership membership;
    address voting = address(this);

    function setUp() public {
        membership = new MockMembership();
        ec = new ElectionContract();
        ec.initialize(address(this), address(membership), voting);
    }

    function testFullFlow() public {
        uint256 electionId = ec.createElection(1);
        ec.addCandidate(1, address(0x1), "Alice");
        ec.concludeElection(1, 0);
        assertEq(membership.last(), address(0x1));
        ec.clearCandidates(electionId);
    }
}
