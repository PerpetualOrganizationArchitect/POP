// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Membership.sol";

contract MembershipTest is Test {
    Membership membership;
    address executor = makeAddr("executor");
    address quickJoinAddr = makeAddr("quickJoin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");

    bytes32 constant DEFAULT_ROLE = keccak256("DEFAULT");
    bytes32 constant EXEC_ROLE = keccak256("EXECUTIVE");
    bytes32 constant OTHER_ROLE = keccak256("OTHER");

    function setUp() public {
        membership = new Membership();
        string[] memory names = new string[](3);
        names[0] = "EXECUTIVE";
        names[1] = "DEFAULT";
        names[2] = "OTHER";
        string[] memory images = new string[](3);
        images[0] = "exec";
        images[1] = "default";
        images[2] = "other";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = false;
        voting[2] = true;
        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = EXEC_ROLE;

        vm.prank(executor);
        membership.initialize(executor, "Member", names, images, voting, execRoles);

        vm.prank(user1);
        membership.setQuickJoin(quickJoinAddr);
    }

    function testQuickJoinFirstMemberIsExecutive() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);

        assertTrue(membership.isMember(user1));
        assertEq(membership.roleOf(user1), EXEC_ROLE);
        assertTrue(membership.canVote(user1));
    }

    function testQuickJoinSecondMemberDefault() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user2);

        assertEq(membership.roleOf(user2), DEFAULT_ROLE);
        assertFalse(membership.canVote(user2));
    }

    function testSetQuickJoinUpdateRequiresExecutor() public {
        address newQJ = makeAddr("newQJ");
        vm.prank(quickJoinAddr);
        vm.expectRevert(Membership.Unauthorized.selector);
        membership.setQuickJoin(newQJ);

        vm.prank(executor);
        membership.setQuickJoin(newQJ);
        assertEq(membership.quickJoin(), newQJ);
    }

    function testExecutiveCanMintOrChange() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);

        vm.prank(user1);
        membership.mintOrChange(user2, OTHER_ROLE);
        assertEq(membership.roleOf(user2), OTHER_ROLE);
    }

    function testNonExecutiveCannotMintOrChange() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user2);

        vm.prank(user2);
        vm.expectRevert(Membership.NotExecutive.selector);
        membership.mintOrChange(user3, DEFAULT_ROLE);
    }

    function testResignBurnsToken() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);

        vm.prank(user1);
        membership.resign();
        assertFalse(membership.isMember(user1));
        vm.expectRevert();
        membership.ownerOf(1);
    }

    function testDowngradeExecutiveEnforcesCooldown() public {
        vm.prank(quickJoinAddr);
        membership.quickJoinMint(user1);

        vm.prank(executor);
        membership.mintOrChange(user2, EXEC_ROLE);

        vm.warp(block.timestamp + 1 weeks);
        vm.prank(user2);
        membership.downgradeExecutive(user1);
        assertEq(membership.roleOf(user1), DEFAULT_ROLE);

        vm.prank(user2);
        vm.expectRevert(Membership.NotExecutive.selector);
        membership.downgradeExecutive(user1);
    }
}
