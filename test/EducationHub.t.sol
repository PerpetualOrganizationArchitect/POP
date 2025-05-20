// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

import {EducationHub, IParticipationToken, IMembership} from "../src/EducationHub.sol";

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

contract MockMembership is IMembership {
    mapping(address => bool) public members;
    mapping(address => bytes32) public roles;

    function setMember(address user, bytes32 role) external {
        members[user] = true;
        roles[user] = role;
    }

    function isMember(address user) external view returns (bool) {
        return members[user];
    }

    function roleOf(address user) external view returns (bytes32) {
        return roles[user];
    }
}

contract EducationHubTest is Test {
    EducationHub hub;
    MockPT token;
    MockMembership membership;
    address executor = address(0xEF);
    bytes32 constant CREATOR_ROLE = keccak256("CREATOR");
    address creator = address(0xCA);
    address learner = address(0x1);

    function setUp() public {
        token = new MockPT();
        membership = new MockMembership();
        membership.setMember(creator, CREATOR_ROLE);
        membership.setMember(learner, bytes32(uint256(1))); // any non-zero role marks member

        hub = new EducationHub();
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = CREATOR_ROLE;
        hub.initialize(address(token), address(membership), executor, roles);
    }

    /*////////////////////////////////////////////////////////////
                                INITIALIZE
    ////////////////////////////////////////////////////////////*/
    function testInitializeStoresArgs() public {
        assertEq(address(hub.token()), address(token));
        assertEq(address(hub.membership()), address(membership));
        assertEq(hub.executor(), executor);
        assertTrue(hub.isCreatorRole(CREATOR_ROLE));
    }

    function testInitializeZeroAddressReverts() public {
        EducationHub tmp = new EducationHub();
        bytes32[] memory roles = new bytes32[](0);
        vm.expectRevert(EducationHub.ZeroAddress.selector);
        tmp.initialize(address(0), address(membership), executor, roles);
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
}
