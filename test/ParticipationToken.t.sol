// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ParticipationToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

contract ParticipationTokenTest is Test {
    ParticipationToken token;
    MockHats hats;
    address executor = address(0x1);
    address taskManager = address(0x2);
    address educationHub = address(0x3);
    address member = address(0x4);
    address approver = address(0x5);

    uint256 constant MEMBER_HAT_ID = 1;
    uint256 constant APPROVER_HAT_ID = 2;

    function setUp() public {
        hats = new MockHats();
        
        // Mint member hat to member
        hats.mintHat(MEMBER_HAT_ID, member);
        
        // Mint approver hat to approver
        hats.mintHat(APPROVER_HAT_ID, approver);

        ParticipationToken impl = new ParticipationToken();
        uint256[] memory initialMemberHats = new uint256[](1);
        initialMemberHats[0] = MEMBER_HAT_ID;
        uint256[] memory initialApproverHats = new uint256[](1);
        initialApproverHats[0] = APPROVER_HAT_ID;
        
        bytes memory data = abi.encodeCall(
            ParticipationToken.initialize,
            (executor, "PToken", "PTK", address(hats), initialMemberHats, initialApproverHats)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        token = ParticipationToken(address(proxy));
    }

    function testInitializeStores() public {
        assertEq(token.executor(), executor);
        assertEq(address(token.hats()), address(hats));
        assertEq(token.memberHatIds()[0], MEMBER_HAT_ID);
        assertEq(token.approverHatIds()[0], APPROVER_HAT_ID);
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
        token.mint(member, 1 ether);
        assertEq(token.balanceOf(member), 1 ether);
        vm.prank(executor);
        token.mint(member, 1 ether);
        assertEq(token.balanceOf(member), 2 ether);
        vm.expectRevert(ParticipationToken.NotTaskOrEdu.selector);
        token.mint(member, 1 ether);
    }

    function testRequestApproveAndCancel() public {
        // Member requests tokens
        vm.prank(member);
        token.requestTokens(1 ether, "ipfs://req");
        (address req,, bool approved,) = token.requests(1);
        assertEq(req, member);
        assertFalse(approved);

        // Approver approves request
        vm.prank(approver);
        token.approveRequest(1);
        assertEq(token.balanceOf(member), 1 ether);

        // Cannot cancel approved request
        vm.prank(member);
        vm.expectRevert(ParticipationToken.AlreadyApproved.selector);
        token.cancelRequest(1);
    }

    function testRequestRequiresMemberHat() public {
        address nonMember = address(0x6);
        vm.prank(nonMember);
        vm.expectRevert(ParticipationToken.NotMember.selector);
        token.requestTokens(1 ether, "ipfs://req");
    }

    function testApproveRequiresApproverHat() public {
        vm.prank(member);
        token.requestTokens(1 ether, "ipfs://req");
        
        address nonApprover = address(0x6);
        vm.prank(nonApprover);
        vm.expectRevert(ParticipationToken.NotApprover.selector);
        token.approveRequest(1);
    }

    function testSetMemberHatAllowed() public {
        uint256 newHatId = 123;
        address newMember = address(0xbeef);
        
        // Create and assign new hat
        hats.createHat(newHatId, "New Member Hat", 1, address(0), address(0), true, "");
        hats.mintHat(newHatId, newMember);
        
        // Should fail without hat permission
        vm.prank(newMember);
        vm.expectRevert(ParticipationToken.NotMember.selector);
        token.requestTokens(1 ether, "ipfs://req");
        
        // Enable new hat as member hat
        vm.prank(executor);
        token.setMemberHatAllowed(newHatId, true);

        // Should now succeed
        vm.prank(newMember);
        token.requestTokens(1 ether, "ipfs://req");
        
        // Disable new hat
        vm.prank(executor);
        token.setMemberHatAllowed(newHatId, false);
        
        // Should now fail again
        vm.prank(newMember);
        vm.expectRevert(ParticipationToken.NotMember.selector);
        token.requestTokens(1 ether, "ipfs://req2");
    }

    function testSetApproverHatAllowed() public {
        uint256 newHatId = 456;
        address newApprover = address(0xcafe);
        
        // Create and assign new hat
        hats.createHat(newHatId, "New Approver Hat", 1, address(0), address(0), true, "");
        hats.mintHat(newHatId, newApprover);
        
        // Create a request first
        vm.prank(member);
        token.requestTokens(1 ether, "ipfs://req");
        
        // Should fail without hat permission
        vm.prank(newApprover);
        vm.expectRevert(ParticipationToken.NotApprover.selector);
        token.approveRequest(1);
        
        // Enable new hat as approver hat
        vm.prank(executor);
        token.setApproverHatAllowed(newHatId, true);

        // Should now succeed
        vm.prank(newApprover);
        token.approveRequest(1);
        assertEq(token.balanceOf(member), 1 ether);
    }

    function testExecutorBypassesHatChecks() public {
        // Test 1: Executor can request tokens without member hat
        vm.prank(executor);
        token.requestTokens(1 ether, "ipfs://exec-req");
        
        // Test 2: Executor can approve someone else's request without approver hat
        // First, have the member make a request
        vm.prank(member);
        token.requestTokens(2 ether, "ipfs://member-req");
        
        // Now executor can approve the member's request (ID 2)
        vm.prank(executor);
        token.approveRequest(2);
        assertEq(token.balanceOf(member), 2 ether);
        
        // Test 3: Someone with approver hat can approve the executor's request
        vm.prank(approver);
        token.approveRequest(1);
        assertEq(token.balanceOf(executor), 1 ether);
    }

    function testTransfersDisabled() public {
        vm.expectRevert(ParticipationToken.TransfersDisabled.selector);
        token.transfer(address(1), 1);
    }
}
