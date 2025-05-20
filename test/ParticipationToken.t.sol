// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ParticipationToken.sol";

contract MockMembership is IMembership {
    mapping(address => bytes32) public roles;
    mapping(bytes32 => bool) public exec;

    function roleOf(address u) external view override returns (bytes32) {
        return roles[u];
    }

    function isExecutiveRole(bytes32 r) external view override returns (bool) {
        return exec[r];
    }

    function setRole(address u, bytes32 r, bool isExec) external {
        roles[u] = r;
        exec[r] = isExec;
    }
}

contract ParticipationTokenTest is Test {
    ParticipationToken token;
    MockMembership membership;
    address executor = address(0x1);
    address taskManager = address(0x2);
    address educationHub = address(0x3);
    address user = address(0x4);

    bytes32 constant EXEC_ROLE = keccak256("EXEC");

    function setUp() public {
        membership = new MockMembership();
        membership.setRole(executor, EXEC_ROLE, true);
        token = new ParticipationToken();
        token.initialize(executor, "PToken", "PTK", address(membership));
    }

    function testInitializeStores() public {
        assertEq(token.executor(), executor);
        assertEq(address(token.membership()), address(membership));
    }

    function testSetTaskManagerOnceAndByExecutor() public {
        token.setTaskManager(taskManager);
        assertEq(token.taskManager(), taskManager);
        vm.prank(executor);
        token.setTaskManager(address(0x5));
        assertEq(token.taskManager(), address(0x5));
    }

    function testSetEducationHubOnceAndByExecutor() public {
        token.setEducationHub(educationHub);
        assertEq(token.educationHub(), educationHub);
        vm.prank(executor);
        token.setEducationHub(address(0x6));
        assertEq(token.educationHub(), address(0x6));
    }

    function testMintOnlyAuthorized() public {
        token.setTaskManager(taskManager);
        vm.prank(taskManager);
        token.mint(user, 1 ether);
        assertEq(token.balanceOf(user), 1 ether);
        vm.prank(executor);
        token.mint(user, 1 ether);
        assertEq(token.balanceOf(user), 2 ether);
        vm.expectRevert(ParticipationToken.NotTaskOrEdu.selector);
        token.mint(user, 1 ether);
    }

    function testRequestApproveAndCancel() public {
        membership.setRole(user, EXEC_ROLE, true);
        vm.prank(user);
        token.requestTokens(1 ether, "ipfs://req");
        (address req,, bool approved,) = token.requests(1);
        assertEq(req, user);
        assertFalse(approved);

        vm.prank(executor);
        token.approveRequest(1);
        assertEq(token.balanceOf(user), 1 ether);

        vm.prank(user);
        vm.expectRevert(ParticipationToken.AlreadyApproved.selector);
        token.cancelRequest(1);
    }

    function testTransfersDisabled() public {
        vm.expectRevert(ParticipationToken.TransfersDisabled.selector);
        token.transfer(address(1), 1);
    }
}
