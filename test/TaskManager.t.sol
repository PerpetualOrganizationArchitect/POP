// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {TaskPerm} from "../src/libs/TaskPerm.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

/*────────────────── Mock Contracts ──────────────────*/
contract MockToken is Test, IERC20 {
    string public constant name = "PT";
    string public constant symbol = "PT";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    /* --- unused ERC‑20 bits (bare minimum for tests) --- */
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

/*──────────────────── Test Suite ────────────────────*/
contract TaskManagerTest is Test {
    /* test actors */
    address creator1 = makeAddr("creator1");
    address creator2 = makeAddr("creator2");
    address pm1 = makeAddr("pm1");
    address member1 = makeAddr("member1");
    address outsider = makeAddr("outsider");
    address executor = makeAddr("executor");

    uint256 constant CREATOR_HAT = 1;
    uint256 constant PM_HAT = 2;
    uint256 constant MEMBER_HAT = 3;

    /* project IDs - will be populated at runtime */
    bytes32 UNLIM_ID;
    bytes32 CAPPED_ID;
    bytes32 BUD_ID;
    bytes32 FLOW_ID;
    bytes32 UPD_ID;
    bytes32 CAN_ID;
    bytes32 ACC_ID;
    bytes32 PROJECT_A_ID;
    bytes32 PROJECT_B_ID;
    bytes32 PROJECT_C_ID;
    bytes32 GOV_TEST_ID;
    bytes32 NEW_PROJECT_ID;
    bytes32 MULTI_PM_ID;
    bytes32 EDGE_ID;
    bytes32 MEGA_ID;
    bytes32 CAPPED_BIG_ID;
    bytes32 TO_DELETE_ID;
    bytes32 ZERO_CAP_ID;
    bytes32 EXECUTOR_TEST_ID;
    bytes32 EXECUTOR_BYPASS_ID;
    bytes32 SHOULD_FAIL_ID;

    /* deployed contracts */
    TaskManager tm;
    MockToken token;
    MockHats hats;

    /* helpers */
    function setHat(address who, uint256 hatId) internal {
        hats.mintHat(hatId, who);
    }

    function setUp() public {
        token = new MockToken();
        hats = new MockHats();

        // give creator hat to two addresses, other hats to pm1 / member1
        setHat(creator1, CREATOR_HAT);
        setHat(creator2, CREATOR_HAT);
        setHat(pm1, PM_HAT);
        setHat(member1, MEMBER_HAT);

        // initialize TaskManager
        tm = new TaskManager();
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT;

        vm.prank(creator1);
        tm.initialize(address(token), address(hats), creatorHats, executor);

        // Set up default global permissions
        vm.prank(executor);
        tm.setRolePerm(PM_HAT, TaskPerm.CREATE | TaskPerm.REVIEW | TaskPerm.ASSIGN);
        vm.prank(executor);
        tm.setRolePerm(MEMBER_HAT, TaskPerm.CLAIM);
    }

    /*───────────────── PROJECT SCENARIOS ───────────────*/

    function test_CreateUnlimitedProjectAndTaskByAnotherCreator() public {
        // Create project with specific hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        UNLIM_ID = tm.createProject(bytes("UNLIM"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // creator2 creates a task (should succeed, cap == 0)
        vm.prank(creator2);
        tm.createTask(1 ether, bytes("ipfs://meta"), UNLIM_ID);

        (,, address claimer,) = tm.getTask(0);
        assertEq(claimer, address(0), "should be unclaimed");
    }

    function test_CreateCappedProjectAndBudgetEnforcement() public {
        address[] memory managers = new address[](1);
        managers[0] = pm1;

        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = PM_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        CAPPED_ID = tm.createProject(bytes("CAPPED"), 3 ether, managers, createHats, claimHats, reviewHats, assignHats);

        // pm1 can create tasks until cap reached
        vm.prank(pm1);
        tm.createTask(1 ether, bytes("a"), CAPPED_ID);

        vm.prank(pm1);
        tm.createTask(2 ether, bytes("b"), CAPPED_ID);

        // next task (1 wei over budget) reverts
        vm.prank(pm1);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1, bytes("c"), CAPPED_ID);
    }

    function test_ProjectSpecificRolePermissions() public {
        // Create custom hats
        uint256 customCreateHat = 10;
        uint256 customReviewHat = 11;
        address customCreator = makeAddr("customCreator");
        address customReviewer = makeAddr("customReviewer");
        setHat(customCreator, customCreateHat);
        setHat(customReviewer, customReviewHat);

        // Set up project with custom hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = customCreateHat;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = customReviewHat;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("CUSTOM_HATS"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Custom creator should be able to create tasks
        vm.prank(customCreator);
        tm.createTask(1 ether, bytes("custom_task"), projectId);

        // But not review tasks
        vm.prank(member1);
        tm.claimTask(0);

        vm.prank(member1);
        tm.submitTask(0, bytes("submitted"));

        vm.prank(customCreator);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);

        // Custom reviewer should be able to review
        vm.prank(customReviewer);
        tm.completeTask(0);
    }

    function test_ProjectRolePermissionOverrides() public {
        // Create a hat with global permissions
        uint256 globalHat = 20;
        address globalUser = makeAddr("globalUser");
        setHat(globalUser, globalHat);

        // Set global permissions
        vm.prank(executor);
        tm.setRolePerm(globalHat, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Create project with different permissions for the same hat
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = globalHat;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT; // Note: globalHat not included here
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("OVERRIDE"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Global user should be able to create (global permission)
        vm.prank(globalUser);
        tm.createTask(1 ether, bytes("task"), projectId);

        // But not review (project override)
        vm.prank(member1);
        tm.claimTask(0);

        vm.prank(member1);
        tm.submitTask(0, bytes("submitted"));

        vm.prank(globalUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);
    }

    function test_UpdateProjectCapLowerThanSpentShouldRevert() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        BUD_ID =
            tm.createProject(bytes("BUD"), 2 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("foo"), BUD_ID);

        // try lowering cap below spent
        vm.prank(executor);
        vm.expectRevert(TaskManager.CapBelowCommitted.selector);
        tm.updateProjectCap(BUD_ID, 1 ether);
    }

    /*───────────────── TASK LIFECYCLE ───────────────────*/

    function _prepareFlow() internal returns (uint256 id) {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        FLOW_ID =
            tm.createProject(bytes("FLOW"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);

        address[] memory mgr = new address[](1);
        mgr[0] = pm1;

        // assign pm1 retroactively
        vm.prank(executor);
        tm.addProjectManager(FLOW_ID, pm1);

        vm.prank(pm1);
        tm.createTask(1 ether, bytes("hash"), FLOW_ID);
        return 0;
    }

    function test_TaskFullLifecycleWithMint() public {
        uint256 id = _prepareFlow();

        // member1 claims
        vm.prank(member1);
        tm.claimTask(id);

        // member1 submits
        vm.prank(member1);
        tm.submitTask(id, bytes("hash2"));

        // pm1 completes, mints token
        uint256 balBefore = token.balanceOf(member1);

        vm.prank(pm1);
        tm.completeTask(id);

        assertEq(token.balanceOf(member1), balBefore + 1 ether, "minted payout");
        (, TaskManager.Status st,,) = tm.getTask(id);
        assertEq(uint8(st), uint8(TaskManager.Status.COMPLETED));
    }

    function test_UpdateTaskBeforeClaimAdjustsBudget() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        UPD_ID =
            tm.createProject(bytes("UPD"), 3 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("foo"), UPD_ID);

        // raise payout by 1 ether
        vm.prank(creator1);
        tm.updateTask(0, 2 ether, bytes("bar"));

        // spent should now be 2 ether
        (uint256 cap, uint256 spent,) = tm.getProjectInfo(UPD_ID);
        assertEq(cap, 3 ether);
        assertEq(spent, 2 ether);
    }

    function test_UpdateTaskAfterClaimOnlyIPFS() public {
        uint256 id = _prepareFlow();

        vm.prank(member1);
        tm.claimTask(id);

        // attempt to change payout should still emit but NOT change storage
        vm.prank(pm1);
        tm.updateTask(id, 5 ether, bytes("newhash"));

        (uint256 payout,,,) = tm.getTask(id);
        assertEq(payout, 1 ether, "payout unchanged");
    }

    function test_CancelTaskRefundsSpent() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        CAN_ID =
            tm.createProject(bytes("CAN"), 2 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("foo"), CAN_ID);

        (uint256 cap, uint256 spentBefore, bool isManager) = tm.getProjectInfo(CAN_ID);
        assertEq(spentBefore, 1 ether);

        vm.prank(creator1);
        tm.cancelTask(0);

        (, uint256 spentAfter,) = tm.getProjectInfo(CAN_ID);
        assertEq(spentAfter, 0);
    }

    /*───────────────── ACCESS CONTROL ───────────────────*/

    function test_CreateTaskByNonMemberReverts() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        ACC_ID = tm.createProject(bytes("ACC"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // outsider has no role and no permissions
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1, bytes("x"), ACC_ID);
    }

    function test_OnlyAuthorizedCanAssignTask() public {
        uint256 id = _prepareFlow();

        // outsider has no permissions
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(id, member1);

        // creator1 has ASSIGN permission
        vm.prank(creator1);
        tm.assignTask(id, member1); // should succeed
    }

    function test_ProjectSpecificPermissions() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PERM_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Set up a custom hat with specific permissions
        uint256 customHat = 70;
        address customUser = makeAddr("customUser");
        setHat(customUser, customHat);

        // Set project-specific permissions
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, customHat, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Custom user should be able to create tasks
        vm.prank(customUser);
        tm.createTask(1 ether, bytes("custom_task"), projectId);

        // But not assign tasks (no ASSIGN permission)
        vm.prank(customUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(0, member1);

        // Member should be able to claim (has global CLAIM permission)
        vm.prank(member1);
        tm.claimTask(0);
    }

    function test_GlobalVsProjectPermissions() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PERM_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Set up a hat with global permissions
        uint256 globalHat = 50;
        address globalUser = makeAddr("globalUser");
        setHat(globalUser, globalHat);

        // Set global permissions
        vm.prank(executor);
        tm.setRolePerm(globalHat, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Override in project
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, globalHat, TaskPerm.CREATE);

        // User should only have CREATE permission in this project
        vm.prank(globalUser);
        tm.createTask(1 ether, bytes("task"), projectId);

        // But not REVIEW (project override removed it)
        vm.prank(member1);
        tm.claimTask(0);

        vm.prank(member1);
        tm.submitTask(0, bytes("submitted"));

        vm.prank(globalUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);
    }

    /*───────────────── COMPLEX SCENARIOS ───────────────────*/

    function test_MultiProjectTaskManagement() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Create three projects with different caps
        vm.startPrank(creator1);
        PROJECT_A_ID = tm.createProject(
            bytes("PROJECT_A"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );
        PROJECT_B_ID = tm.createProject(
            bytes("PROJECT_B"), 3 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );
        PROJECT_C_ID =
            tm.createProject(bytes("PROJECT_C"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);
        vm.stopPrank();

        // Create multiple tasks across projects
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1_A"), PROJECT_A_ID);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task1_B"), PROJECT_B_ID);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task1_C"), PROJECT_C_ID);

        // Member claims tasks from different projects
        vm.startPrank(member1);
        tm.claimTask(0); // PROJECT_A task
        tm.claimTask(2); // PROJECT_C task
        vm.stopPrank();

        // Budget verification
        (uint256 capA, uint256 spentA,) = tm.getProjectInfo(PROJECT_A_ID);
        assertEq(spentA, 1 ether, "PROJECT_A spent should be 1 ether");
        assertEq(capA, 5 ether, "PROJECT_A cap should be 5 ether");

        (uint256 capB, uint256 spentB,) = tm.getProjectInfo(PROJECT_B_ID);
        assertEq(spentB, 2 ether, "PROJECT_B spent should be 2 ether");

        // Test trying to exceed PROJECT_B budget
        vm.prank(creator1);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1 ether + 1, bytes("task2_B"), PROJECT_B_ID); // Would exceed cap

        // Complete task from PROJECT_C
        vm.prank(member1);
        tm.submitTask(2, bytes("completed_C"));

        vm.prank(creator1);
        tm.completeTask(2);

        // Verify token minting worked
        assertEq(token.balanceOf(member1), 2 ether, "Member should receive 2 ether from task completion");
    }

    function test_GovernanceAndRoleChanges() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Initial setup
        vm.prank(creator1);
        GOV_TEST_ID = tm.createProject(
            bytes("GOV_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Add new hat to the creator hats using the executor
        uint256 NEW_HAT = 100;
        vm.prank(executor);
        tm.setCreatorHatAllowed(NEW_HAT, true);

        // Assign new hat to an address
        address newCreator = makeAddr("newCreator");
        setHat(newCreator, NEW_HAT);

        // Test that new hat can create projects
        vm.prank(newCreator);
        NEW_PROJECT_ID = tm.createProject(
            bytes("NEW_PROJECT"), 1 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Verify new project exists by creating a task
        vm.prank(newCreator);
        tm.createTask(0.5 ether, bytes("new_task"), NEW_PROJECT_ID);

        // Disable the hat using the executor
        vm.prank(executor);
        tm.setCreatorHatAllowed(NEW_HAT, false);

        // Verify the hat can no longer create projects
        vm.prank(newCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject(bytes("SHOULD_FAIL"), 1 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);
    }

    function test_ProjectManagerHierarchy() public {
        // Create a project with multiple managers and specific hat permissions
        address[] memory managers = new address[](2);
        managers[0] = pm1;
        address pm2 = makeAddr("pm2");
        // Note: pm2 has no hat initially
        managers[1] = pm2;

        // Set up hat permissions - only PM_HAT has permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = PM_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        MULTI_PM_ID =
            tm.createProject(bytes("MULTI_PM"), 10 ether, managers, createHats, claimHats, reviewHats, assignHats);

        // Both PMs should be able to create tasks (as project managers)
        vm.prank(pm1);
        tm.createTask(2 ether, bytes("pm1_task"), MULTI_PM_ID);

        vm.prank(pm2);
        tm.createTask(3 ether, bytes("pm2_task"), MULTI_PM_ID);

        // PM1 can complete PM2's task (as project manager)
        vm.prank(member1);
        tm.claimTask(1);

        vm.prank(member1);
        tm.submitTask(1, bytes("completed_by_member"));

        vm.prank(pm1);
        tm.completeTask(1);

        // Remove PM2 as project manager
        vm.prank(executor);
        tm.removeProjectManager(MULTI_PM_ID, pm2);

        // PM2 can no longer create tasks (no longer a project manager and no role)
        vm.prank(pm2);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("should_fail"), MULTI_PM_ID);

        // But PM1 still can (still a project manager)
        vm.prank(pm1);
        tm.createTask(1 ether, bytes("still_works"), MULTI_PM_ID);

        // Now give PM2 the PM_HAT
        setHat(pm2, PM_HAT);

        // PM2 should now be able to create tasks again (has PM_HAT with CREATE permission)
        vm.prank(pm2);
        tm.createTask(1 ether, bytes("pm2_with_hat"), MULTI_PM_ID);

        // Verify overall budget tracking
        (, uint256 spent,) = tm.getProjectInfo(MULTI_PM_ID);
        assertEq(spent, 7 ether, "Project should track 7 ether spent");
    }

    function test_TaskLifecycleEdgeCases() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        vm.prank(creator1);
        EDGE_ID =
            tm.createProject(bytes("EDGE"), 10 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // Create and immediately cancel a task
        vm.startPrank(creator1);
        tm.createTask(1 ether, bytes("to_cancel"), EDGE_ID);
        tm.cancelTask(0);
        vm.stopPrank();

        // Verify project budget is refunded
        (, uint256 spent,) = tm.getProjectInfo(EDGE_ID);
        assertEq(spent, 0, "Budget should be refunded after cancel");

        // Create a task, assign it, then try operations that should fail
        vm.prank(creator1);
        tm.createTask(2 ether, bytes("edge_task"), EDGE_ID);

        vm.prank(creator1);
        tm.assignTask(1, member1);

        // Try to claim an already claimed task
        vm.prank(member1);
        vm.expectRevert(TaskManager.AlreadyClaimed.selector);
        tm.claimTask(1);

        // Try to submit without claiming
        address nonClaimer = makeAddr("nonClaimer");
        setHat(nonClaimer, MEMBER_HAT);

        vm.prank(nonClaimer);
        vm.expectRevert(TaskManager.NotClaimer.selector);
        tm.submitTask(1, bytes("wrong_submitter"));

        // Submit correctly
        vm.prank(member1);
        tm.submitTask(1, bytes("correct_submission"));

        // Try to cancel after submission
        vm.prank(creator1);
        vm.expectRevert(TaskManager.AlreadyClaimed.selector);
        tm.cancelTask(1);

        // Complete the task
        vm.prank(creator1);
        tm.completeTask(1);

        // Try to complete again
        vm.prank(creator1);
        vm.expectRevert(TaskManager.AlreadyCompleted.selector);
        tm.completeTask(1);
    }

    function test_ProjectStress() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Create a large unlimited project
        vm.prank(creator1);
        MEGA_ID = tm.createProject(bytes("MEGA"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // Add multiple project managers
        address[] memory pms = new address[](3);
        pms[0] = pm1;

        address pm2 = makeAddr("pm2");
        address pm3 = makeAddr("pm3");
        setHat(pm2, PM_HAT);
        setHat(pm3, PM_HAT);
        pms[1] = pm2;
        pms[2] = pm3;

        for (uint256 i = 0; i < pms.length; i++) {
            vm.prank(executor);
            tm.addProjectManager(MEGA_ID, pms[i]);
        }

        // Create multiple members
        address[] memory members = new address[](5);
        for (uint256 i = 0; i < members.length; i++) {
            members[i] = makeAddr(string(abi.encodePacked("member", i)));
            setHat(members[i], MEMBER_HAT);
        }

        // Create multiple tasks
        uint256 totalTasks = 10;
        uint256 totalValue = 0;

        for (uint256 i = 0; i < totalTasks; i++) {
            uint256 payout = 0.5 ether + (i * 0.1 ether);
            totalValue += payout;

            // Alternate between PMs for task creation
            address creator = pms[i % pms.length];

            vm.prank(creator);
            bytes memory taskMetadata = abi.encodePacked("task", i);
            tm.createTask(payout, taskMetadata, MEGA_ID);

            // Assign tasks to different members
            address assignee = members[i % members.length];

            vm.prank(creator);
            tm.assignTask(i, assignee);
        }

        // Verify project spent
        (, uint256 spent,) = tm.getProjectInfo(MEGA_ID);
        assertEq(spent, totalValue, "Project should track all task value");

        // Submit half the tasks
        for (uint256 i = 0; i < totalTasks / 2; i++) {
            address submitter = members[i % members.length];

            vm.prank(submitter);
            bytes memory completedMetadata = abi.encodePacked("completed", i);
            tm.submitTask(i, completedMetadata);
        }

        // Complete a third of all tasks
        uint256 completedTasks = totalTasks / 3;
        uint256 completedValue = 0;

        for (uint256 i = 0; i < completedTasks; i++) {
            (uint256 payout,,,) = tm.getTask(i);
            completedValue += payout;

            vm.prank(pms[0]);
            tm.completeTask(i);
        }

        // Create a second project with a hard cap
        vm.prank(creator1);
        CAPPED_BIG_ID =
            tm.createProject(bytes("CAPPED_BIG"), 10 ether, pms, createHats, claimHats, reviewHats, assignHats);

        // Create tasks up to the cap
        uint256 cappedTaskCount = 0;
        uint256 cappedSpent = 0;

        while (cappedSpent < 9.5 ether) {
            uint256 payout = 0.3 ether;

            vm.prank(pms[0]);
            bytes memory taskMetadata = abi.encodePacked("capped_task", cappedTaskCount);
            tm.createTask(payout, taskMetadata, CAPPED_BIG_ID);

            cappedTaskCount++;
            cappedSpent += payout;
        }

        // Verify we can't exceed cap
        vm.prank(pms[0]);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1 ether, bytes("exceeds_cap"), CAPPED_BIG_ID);

        // Verify task counts and budget usage
        (uint256 cap, uint256 actualSpent,) = tm.getProjectInfo(CAPPED_BIG_ID);
        assertEq(cap, 10 ether, "Cap should be preserved");
        assertEq(actualSpent, cappedSpent, "Spent should match tracked value");

        // Verify token minting totals
        uint256 totalTokenMinted = 0;
        for (uint256 i = 0; i < members.length; i++) {
            totalTokenMinted += token.balanceOf(members[i]);
        }

        assertEq(totalTokenMinted, completedValue, "Total minted tokens should match completed tasks");
    }

    function test_ProjectDeletionAndUpdating() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Create a project that will be deleted
        vm.prank(creator1);
        TO_DELETE_ID = tm.createProject(
            bytes("TO_DELETE"), 3 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create a task, complete it, then verify project can be deleted
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), TO_DELETE_ID);

        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("completed"));

        vm.prank(creator1);
        tm.completeTask(0);

        // Create another task and cancel it
        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task2"), TO_DELETE_ID);

        vm.prank(creator1);
        tm.cancelTask(1);

        // Verify spent amount is 1 ether (from completed task)
        (uint256 cap, uint256 spent,) = tm.getProjectInfo(TO_DELETE_ID);
        assertEq(spent, 1 ether, "Project spent should only reflect completed task");

        // Try to delete - should fail because cap (3 ether) != spent (1 ether)
        vm.prank(creator1);
        vm.expectRevert(TaskManager.CapBelowCommitted.selector);
        tm.deleteProject(TO_DELETE_ID, bytes("TO_DELETE"));

        // Update the cap to match spent amount
        vm.prank(executor);
        tm.updateProjectCap(TO_DELETE_ID, 1 ether);

        // Now deletion should succeed
        vm.prank(creator1);
        tm.deleteProject(TO_DELETE_ID, bytes("TO_DELETE"));

        // Verify project no longer exists by trying to get info
        vm.prank(creator1);
        vm.expectRevert(TaskManager.UnknownProject.selector);
        tm.getProjectInfo(TO_DELETE_ID);

        // Create a zero-cap project
        vm.prank(creator1);
        ZERO_CAP_ID =
            tm.createProject(bytes("ZERO_CAP"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // Add tasks, verify we can still delete with non-zero spent
        vm.prank(creator1);
        tm.createTask(3 ether, bytes("unlimited_task"), ZERO_CAP_ID);

        // Delete should succeed with zero cap, non-zero spent
        vm.prank(creator1);
        tm.deleteProject(ZERO_CAP_ID, bytes("ZERO_CAP"));
    }

    function test_ExecutorRoleManagement() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Create new executor
        address executor2 = makeAddr("executor2");

        // Non-executor can't set executor
        vm.prank(creator1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setExecutor(executor2);

        // Executor can update executor
        vm.prank(executor);
        tm.setExecutor(executor2);

        // Old executor can no longer set creator hats
        uint256 TEST_HAT = 123;
        vm.prank(executor);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setCreatorHatAllowed(TEST_HAT, true);

        // New executor can set creator hats
        vm.prank(executor2);
        tm.setCreatorHatAllowed(TEST_HAT, true);

        // Assign the new hat to a user
        address testCreator = makeAddr("testCreator");
        setHat(testCreator, TEST_HAT);

        // Verify the new hat works for creating projects
        vm.prank(testCreator);
        EXECUTOR_TEST_ID = tm.createProject(
            bytes("EXECUTOR_TEST"), 1 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // New executor can revoke the hat
        vm.prank(executor2);
        tm.setCreatorHatAllowed(TEST_HAT, false);

        // Hat should no longer work
        vm.prank(testCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject(bytes("SHOULD_FAIL"), 1 ether, new address[](0), createHats, claimHats, reviewHats, assignHats);
    }

    function test_ExecutorBypassMemberCheck() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        // Create project
        vm.prank(creator1);
        EXECUTOR_BYPASS_ID = tm.createProject(
            bytes("EXECUTOR_BYPASS"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Executor should be able to create tasks even without member role
        // (executor address has no role but should bypass the member check)
        vm.prank(executor);
        tm.createTask(1 ether, bytes("executor_task"), EXECUTOR_BYPASS_ID);

        // Executor should be able to claim tasks
        vm.prank(executor);
        tm.claimTask(0);

        // Executor should be able to submit tasks
        vm.prank(executor);
        tm.submitTask(0, bytes("executor_submission"));

        // Verify task status and submission
        (, TaskManager.Status status,,) = tm.getTask(0);
        assertEq(uint8(status), uint8(TaskManager.Status.SUBMITTED));
    }

    /*───────────────── GRANULAR PERMISSION TESTS ────────────────────*/

    function test_CombinedPermissions() public {
        // Create a new hat with combined permissions
        uint256 MULTI_HAT = 150;
        address multiUser = makeAddr("multiUser");
        setHat(multiUser, MULTI_HAT);

        // Set global permissions (CREATE | CLAIM)
        vm.prank(executor);
        tm.setRolePerm(MULTI_HAT, TaskPerm.CREATE | TaskPerm.CLAIM);

        // Create project (use creator1 who has creator hat)
        uint256[] memory emptyHats = new uint256[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("COMBINED_TEST"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // User should be able to create tasks with CREATE permission
        vm.prank(multiUser);
        tm.createTask(1 ether, bytes("multi_task"), projectId);

        // User should be able to claim tasks with CLAIM permission
        vm.prank(multiUser);
        tm.claimTask(0);

        // But not complete tasks (no REVIEW permission)
        vm.prank(multiUser);
        tm.submitTask(0, bytes("submission"));

        vm.prank(multiUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);
    }

    function test_PermissionChangesAfterCreation() public {
        // Create new hat and user
        uint256 DYNAMIC_HAT = 160;
        address dynamicUser = makeAddr("dynamicUser");
        setHat(dynamicUser, DYNAMIC_HAT);

        // Initially no permissions for this hat

        // Create project
        uint256[] memory emptyHats = new uint256[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("DYNAMIC_TEST"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // User can't create tasks (no permissions)
        vm.prank(dynamicUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("should_fail"), projectId);

        // Grant CREATE permission at project level
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, DYNAMIC_HAT, TaskPerm.CREATE);

        // Now user can create tasks
        vm.prank(dynamicUser);
        tm.createTask(1 ether, bytes("now_works"), projectId);

        // Another user claims and submits
        vm.prank(member1);
        tm.claimTask(0);

        vm.prank(member1);
        tm.submitTask(0, bytes("submitted"));

        // User still can't complete (no REVIEW permission)
        vm.prank(dynamicUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);

        // Add REVIEW permission
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, DYNAMIC_HAT, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Now user can complete tasks
        vm.prank(dynamicUser);
        tm.completeTask(0);
    }

    function test_GlobalVsProjectPermissionOverrides() public {
        // Create a hat with global permissions
        uint256 OVERRIDE_HAT = 170;
        address overrideUser = makeAddr("overrideUser");
        setHat(overrideUser, OVERRIDE_HAT);

        // Set full permissions globally
        vm.prank(executor);
        tm.setRolePerm(OVERRIDE_HAT, TaskPerm.CREATE | TaskPerm.CLAIM | TaskPerm.REVIEW | TaskPerm.ASSIGN);

        // Create project
        uint256[] memory emptyHats = new uint256[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("OVERRIDE_TEST"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // Create a second project to verify global perms still work there
        vm.prank(creator1);
        bytes32 projectId2 = tm.createProject(
            bytes("GLOBAL_TEST"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // Restrict permissions on the first project (only CREATE)
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, OVERRIDE_HAT, TaskPerm.CREATE);

        // User can create tasks in both projects
        vm.prank(overrideUser);
        tm.createTask(1 ether, bytes("task1"), projectId);

        vm.prank(overrideUser);
        tm.createTask(1 ether, bytes("task2"), projectId2);

        // In first project, user can't assign tasks (project override)
        vm.prank(overrideUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(0, member1);

        // But in second project, user can assign tasks (global permission)
        vm.prank(overrideUser);
        tm.assignTask(1, member1);

        // User can submit claimed task
        vm.prank(member1);
        tm.submitTask(1, bytes("submission"));

        // In first project, user can't complete tasks (project override)
        vm.prank(member1);
        tm.claimTask(0);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        vm.prank(overrideUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(0);

        // But in second project, user can complete tasks (global permission)
        vm.prank(overrideUser);
        tm.completeTask(1);
    }

    function test_RevokePermissions() public {
        // Create hat and user
        uint256 TEMP_HAT = 180;
        address tempUser = makeAddr("tempUser");
        setHat(tempUser, TEMP_HAT);

        // Give CREATE permission
        vm.prank(executor);
        tm.setRolePerm(TEMP_HAT, TaskPerm.CREATE);

        // Create project
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("TEMP"),
            5 ether,
            new address[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0)
        );

        // User can create tasks
        vm.prank(tempUser);
        tm.createTask(1 ether, bytes("task"), projectId);

        // Revoke permission
        vm.prank(executor);
        tm.setRolePerm(TEMP_HAT, 0);

        // User can't create tasks anymore
        vm.prank(tempUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("fail"), projectId);
    }

    function test_IndividualPermissionFlags() public {
        // Create 4 hats, each with a single permission flag
        uint256 CREATE_HAT = 200;
        uint256 CLAIM_HAT = 201;
        uint256 REVIEW_HAT = 202;
        uint256 ASSIGN_HAT = 203;

        // Create 4 users with respective hats
        address createUser = makeAddr("createUser");
        address claimUser = makeAddr("claimUser");
        address reviewUser = makeAddr("reviewUser");
        address assignUser = makeAddr("assignUser");

        setHat(createUser, CREATE_HAT);
        setHat(claimUser, CLAIM_HAT);
        setHat(reviewUser, REVIEW_HAT);
        setHat(assignUser, ASSIGN_HAT);

        // Set permissions
        vm.startPrank(executor);
        tm.setRolePerm(CREATE_HAT, TaskPerm.CREATE);
        tm.setRolePerm(CLAIM_HAT, TaskPerm.CLAIM);
        tm.setRolePerm(REVIEW_HAT, TaskPerm.REVIEW);
        tm.setRolePerm(ASSIGN_HAT, TaskPerm.ASSIGN);
        vm.stopPrank();

        // Create project
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PERM_FLAGS"),
            5 ether,
            new address[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0),
            new uint256[](0)
        );

        // Test CREATE permission - should succeed
        vm.prank(createUser);
        tm.createTask(1 ether, bytes("create_task"), projectId);

        // createUser should not be able to claim or assign
        vm.prank(createUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.claimTask(0);

        vm.prank(createUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(0, claimUser);

        // Test ASSIGN permission - should succeed
        vm.prank(assignUser);
        tm.assignTask(0, claimUser);

        // assignUser should not be able to create or review
        vm.prank(assignUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("assign_fail"), projectId);

        // Test CLAIM permission - indirectly tested by previous assign
        // Create a new task for claiming
        vm.prank(createUser);
        tm.createTask(1 ether, bytes("for_claiming"), projectId);

        // claimUser should be able to claim
        vm.prank(claimUser);
        tm.claimTask(1);

        // claimUser can submit but not complete
        vm.prank(claimUser);
        tm.submitTask(1, bytes("claim_submission"));

        vm.prank(claimUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.completeTask(1);

        // Test REVIEW permission - should succeed
        vm.prank(reviewUser);
        tm.completeTask(1);

        // reviewUser should not be able to create or assign
        vm.prank(reviewUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("review_fail"), projectId);

        vm.prank(reviewUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(0, claimUser);
    }
}
