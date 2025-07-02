// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {EducationHub, IParticipationToken} from "../src/EducationHub.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

/*////////////////////////////////////////////////////////////
Mock contracts to satisfy external dependencies of EducationHub
////////////////////////////////////////////////////////////*/

contract MockPT is Test, IParticipationToken {
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;
    address public edu;

    function mint(address to, uint256 amount) external override {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function setEducationHub(address eh) external override {
        edu = eh;
    }

    /* Unused IERC20 functions */
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



contract EducationHubTest is Test {
    EducationHub hub;
    MockPT token;
    MockHats hats;
    address executor = address(0xEF);
    uint256 constant CREATOR_HAT = 1;
    uint256 constant MEMBER_HAT = 2;
    address creator = address(0xCA);
    address learner = address(0x1);

    function setUp() public {
        token = new MockPT();
        hats = new MockHats();

        // Mint hats to users
        hats.mintHat(CREATOR_HAT, creator);
        hats.mintHat(MEMBER_HAT, creator); // creator is also a member
        hats.mintHat(MEMBER_HAT, learner);

        hub = new EducationHub();
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT;
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = MEMBER_HAT;
        hub.initialize(address(token), address(hats), executor, creatorHats, memberHats);
    }

    /*////////////////////////////////////////////////////////////
                                INITIALIZE
    ////////////////////////////////////////////////////////////*/
    function testInitializeStoresArgs() public {
        assertEq(address(hub.token()), address(token));
        assertEq(address(hub.hats()), address(hats));
        assertEq(hub.executor(), executor);
        uint256[] memory creatorHats = hub.creatorHatIds();
        assertEq(creatorHats.length, 1);
        assertEq(creatorHats[0], CREATOR_HAT);
        uint256[] memory memberHats = hub.memberHatIds();
        assertEq(memberHats.length, 1);
        assertEq(memberHats[0], MEMBER_HAT);
    }

    function testInitializeZeroAddressReverts() public {
        EducationHub tmp = new EducationHub();
        uint256[] memory creatorHats = new uint256[](0);
        uint256[] memory memberHats = new uint256[](0);
        vm.expectRevert(EducationHub.ZeroAddress.selector);
        tmp.initialize(address(0), address(hats), executor, creatorHats, memberHats);
    }

    /*////////////////////////////////////////////////////////////
                                ADMIN SETTERS
    ////////////////////////////////////////////////////////////*/
    function testSetExecutor() public {
        address newExec = address(0xAB);
        vm.prank(executor);
        hub.setExecutor(newExec);
        assertEq(hub.executor(), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(EducationHub.NotExecutor.selector);
        hub.setExecutor(address(0xAB));
    }

    function testSetCreatorHatAllowed() public {
        uint256 newHat = 99;
        address newCreator = address(0xbeef);
        
        // Mint the new hat to the new creator
        hats.mintHat(newHat, newCreator);
        
        // Add the new hat as a creator hat
        vm.prank(executor);
        hub.setCreatorHatAllowed(newHat, true);
        
        // Verify the hat was added
        uint256[] memory creatorHats = hub.creatorHatIds();
        assertEq(creatorHats.length, 2);
        bool found = false;
        for (uint256 i = 0; i < creatorHats.length; i++) {
            if (creatorHats[i] == newHat) {
                found = true;
                break;
            }
        }
        assertTrue(found, "New creator hat should be in the array");
        
        // New creator should be able to create modules
        vm.prank(newCreator);
        hub.createModule(bytes("test"), 5, 1);
        
        // Remove the hat
        vm.prank(executor);
        hub.setCreatorHatAllowed(newHat, false);
        
        // Verify the hat was removed
        creatorHats = hub.creatorHatIds();
        assertEq(creatorHats.length, 1);
        
        // New creator should no longer be able to create modules
        vm.prank(newCreator);
        vm.expectRevert(EducationHub.NotCreator.selector);
        hub.createModule(bytes("test2"), 5, 1);
    }

    function testSetMemberHatAllowed() public {
        uint256 newHat = 88;
        address newMember = address(0xcafe);
        
        // Mint the new hat to the new member
        hats.mintHat(newHat, newMember);
        
        // Add the new hat as a member hat
        vm.prank(executor);
        hub.setMemberHatAllowed(newHat, true);
        
        // Verify the hat was added
        uint256[] memory memberHats = hub.memberHatIds();
        assertEq(memberHats.length, 2);
        bool found = false;
        for (uint256 i = 0; i < memberHats.length; i++) {
            if (memberHats[i] == newHat) {
                found = true;
                break;
            }
        }
        assertTrue(found, "New member hat should be in the array");
        
        // First create a module for testing
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 2);
        
        // New member should be able to complete modules
        vm.prank(newMember);
        hub.completeModule(0, 2);
        assertEq(token.balanceOf(newMember), 5);
    }

    /*////////////////////////////////////////////////////////////
                                PAUSE CONTROL
    ////////////////////////////////////////////////////////////*/
    function testPauseUnpause() public {
        vm.prank(executor);
        hub.pause();
        vm.prank(executor);
        hub.unpause();
    }

    /*////////////////////////////////////////////////////////////
                                MODULE CRUD
    ////////////////////////////////////////////////////////////*/
    function testCreateModuleAndGet() public {
        vm.prank(creator);
        hub.createModule(bytes("ipfs://m"), 10, 1);
        (uint256 payout, bool exists) = hub.getModule(0);
        assertEq(payout, 10);
        assertTrue(exists);
        assertEq(hub.nextModuleId(), 1);
    }

    function testCreateModuleInvalidBytesReverts() public {
        vm.prank(creator);
        vm.expectRevert(EducationHub.InvalidBytes.selector);
        hub.createModule("", 1, 1);
    }

    function testUpdateModule() public {
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 1);
        vm.prank(creator);
        hub.updateModule(0, bytes("new"), 8);
        (uint256 payout,) = hub.getModule(0);
        assertEq(payout, 8);
    }

    function testRemoveModule() public {
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 1);
        vm.prank(creator);
        hub.removeModule(0);
        vm.expectRevert(EducationHub.ModuleUnknown.selector);
        hub.getModule(0);
    }

    /*////////////////////////////////////////////////////////////
                                COMPLETION
    ////////////////////////////////////////////////////////////*/
    function testCompleteModuleMintsAndMarks() public {
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 2);
        vm.prank(learner);
        hub.completeModule(0, 2);
        assertEq(token.balanceOf(learner), 5);
        assertTrue(hub.hasCompleted(learner, 0));
    }

    function testCompleteModuleWrongAnswerReverts() public {
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 2);
        vm.prank(learner);
        vm.expectRevert(EducationHub.InvalidAnswer.selector);
        hub.completeModule(0, 1);
    }

    function testCompleteModuleAlreadyCompletedReverts() public {
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 2);
        vm.prank(learner);
        hub.completeModule(0, 2);
        vm.prank(learner);
        vm.expectRevert(EducationHub.AlreadyCompleted.selector);
        hub.completeModule(0, 2);
    }

    /*////////////////////////////////////////////////////////////
                            PERMISSION TESTS
    ////////////////////////////////////////////////////////////*/
    function testNonCreatorCannotCreateModule() public {
        address nonCreator = address(0xbad);
        // Give them member hat but not creator hat
        hats.mintHat(MEMBER_HAT, nonCreator);
        
        vm.prank(nonCreator);
        vm.expectRevert(EducationHub.NotCreator.selector);
        hub.createModule(bytes("test"), 5, 1);
    }

    function testNonMemberCannotCompleteModule() public {
        address nonMember = address(0xbad);
        // Don't give them any hat
        
        // First create a module
        vm.prank(creator);
        hub.createModule(bytes("data"), 5, 2);
        
        vm.prank(nonMember);
        vm.expectRevert(EducationHub.NotMember.selector);
        hub.completeModule(0, 2);
    }

    function testExecutorBypassesHatChecks() public {
        // Executor should be able to create modules even without creator hat
        vm.prank(executor);
        hub.createModule(bytes("executor module"), 10, 3);
        
        // Executor should be able to complete modules even without member hat
        vm.prank(executor);
        hub.completeModule(0, 3);
        assertEq(token.balanceOf(executor), 10);
    }
}
