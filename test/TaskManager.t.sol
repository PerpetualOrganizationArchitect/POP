// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {TaskPerm} from "../src/libs/TaskPerm.sol";

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

interface IMembership {
    function roleOf(address user) external view returns (bytes32);
}

contract MockMembership is IMembership {
    mapping(address => bytes32) public roles;

    function setRole(address who, bytes32 r) external {
        roles[who] = r;
    }

    function roleOf(address user) external view override returns (bytes32) {
        return roles[user];
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

    bytes32 constant CREATOR_ROLE = keccak256("CREATOR");
    bytes32 constant PM_ROLE = keccak256("PM");
    bytes32 constant MEMBER_ROLE = keccak256("MEMBER");

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
    MockMembership membership;

    /* helpers */
    function setRole(address who, bytes32 r) internal {
        membership.setRole(who, r);
    }

    function setUp() public {
        token = new MockToken();
        membership = new MockMembership();

        // give creator role to two addresses, membership role to pm1 / member1
        setRole(creator1, CREATOR_ROLE);
        setRole(creator2, CREATOR_ROLE);
        setRole(pm1, PM_ROLE);
        setRole(member1, MEMBER_ROLE);

        // initialize TaskManager
        tm = new TaskManager();
        bytes32[] memory creatorRoles = new bytes32[](1);
        creatorRoles[0] = CREATOR_ROLE;

        vm.prank(creator1);
        tm.initialize(address(token), address(membership), creatorRoles, executor);

        // Set up default global permissions
        vm.prank(executor);
        tm.setRolePerm(PM_ROLE, TaskPerm.CREATE | TaskPerm.REVIEW | TaskPerm.ASSIGN);
        vm.prank(executor);
        tm.setRolePerm(MEMBER_ROLE, TaskPerm.CLAIM);
    }

    /*───────────────── PROJECT SCENARIOS ───────────────*/

    function test_CreateUnlimitedProjectAndTaskByAnotherCreator() public {
        // Create project with specific role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        UNLIM_ID =
            tm.createProject(bytes("UNLIM"), 0, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

        // creator2 creates a task (should succeed, cap == 0)
        vm.prank(creator2);
        tm.createTask(1 ether, bytes("ipfs://meta"), UNLIM_ID);

        (,, address claimer,) = tm.getTask(0);
        assertEq(claimer, address(0), "should be unclaimed");
    }

    function test_CreateCappedProjectAndBudgetEnforcement() public {
        address[] memory managers = new address[](1);
        managers[0] = pm1;

        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = PM_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        CAPPED_ID =
            tm.createProject(bytes("CAPPED"), 3 ether, managers, createRoles, claimRoles, reviewRoles, assignRoles);

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
        // Create custom roles
        bytes32 customCreateRole = keccak256("CUSTOM_CREATE");
        bytes32 customReviewRole = keccak256("CUSTOM_REVIEW");
        address customCreator = makeAddr("customCreator");
        address customReviewer = makeAddr("customReviewer");
        setRole(customCreator, customCreateRole);
        setRole(customReviewer, customReviewRole);

        // Set up project with custom role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = customCreateRole;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = customReviewRole;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("CUSTOM_ROLES"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
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
        // Create a role with global permissions
        bytes32 globalRole = keccak256("GLOBAL");
        address globalUser = makeAddr("globalUser");
        setRole(globalUser, globalRole);

        // Set global permissions
        vm.prank(executor);
        tm.setRolePerm(globalRole, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Create project with different permissions for the same role
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = globalRole;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE; // Note: globalRole not included here
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("OVERRIDE"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        BUD_ID =
            tm.createProject(bytes("BUD"), 2 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("foo"), BUD_ID);

        // try lowering cap below spent
        vm.prank(executor);
        vm.expectRevert(TaskManager.CapBelowCommitted.selector);
        tm.updateProjectCap(BUD_ID, 1 ether);
    }

    /*───────────────── TASK LIFECYCLE ───────────────────*/

    function _prepareFlow() internal returns (uint256 id) {
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        FLOW_ID = tm.createProject(
            bytes("FLOW"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        UPD_ID =
            tm.createProject(bytes("UPD"), 3 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        CAN_ID =
            tm.createProject(bytes("CAN"), 2 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        ACC_ID = tm.createProject(bytes("ACC"), 0, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PERM_TEST"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

        // Set up a custom role with specific permissions
        bytes32 customRole = keccak256("CUSTOM");
        address customUser = makeAddr("customUser");
        setRole(customUser, customRole);

        // Set project-specific permissions
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, customRole, TaskPerm.CREATE | TaskPerm.REVIEW);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PERM_TEST"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

        // Set up a role with global permissions
        bytes32 globalRole = keccak256("GLOBAL");
        address globalUser = makeAddr("globalUser");
        setRole(globalUser, globalRole);

        // Set global permissions
        vm.prank(executor);
        tm.setRolePerm(globalRole, TaskPerm.CREATE | TaskPerm.REVIEW);

        // Override in project
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, globalRole, TaskPerm.CREATE);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Create three projects with different caps
        vm.startPrank(creator1);
        PROJECT_A_ID = tm.createProject(
            bytes("PROJECT_A"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );
        PROJECT_B_ID = tm.createProject(
            bytes("PROJECT_B"), 3 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );
        PROJECT_C_ID =
            tm.createProject(bytes("PROJECT_C"), 0, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);
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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Initial setup
        vm.prank(creator1);
        GOV_TEST_ID = tm.createProject(
            bytes("GOV_TEST"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

        // Add new role to the creator roles using the executor
        bytes32 NEW_ROLE = keccak256("NEW_CREATOR");
        vm.prank(executor);
        tm.setCreatorRole(NEW_ROLE, true);

        // Assign new role to an address
        address newCreator = makeAddr("newCreator");
        setRole(newCreator, NEW_ROLE);

        // Test that new role can create projects
        vm.prank(newCreator);
        NEW_PROJECT_ID = tm.createProject(
            bytes("NEW_PROJECT"), 1 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

        // Verify new project exists by creating a task
        vm.prank(newCreator);
        tm.createTask(0.5 ether, bytes("new_task"), NEW_PROJECT_ID);

        // Disable the role using the executor
        vm.prank(executor);
        tm.setCreatorRole(NEW_ROLE, false);

        // Verify the role can no longer create projects
        vm.prank(newCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject(
            bytes("SHOULD_FAIL"), 1 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );
    }

    function test_ProjectManagerHierarchy() public {
        // Create a project with multiple managers and specific role permissions
        address[] memory managers = new address[](2);
        managers[0] = pm1;
        address pm2 = makeAddr("pm2");
        // Note: pm2 has no role initially
        managers[1] = pm2;

        // Set up role permissions - only PM_ROLE has permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = PM_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        MULTI_PM_ID =
            tm.createProject(bytes("MULTI_PM"), 10 ether, managers, createRoles, claimRoles, reviewRoles, assignRoles);

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

        // Now give PM2 the PM_ROLE
        setRole(pm2, PM_ROLE);

        // PM2 should now be able to create tasks again (has PM_ROLE with CREATE permission)
        vm.prank(pm2);
        tm.createTask(1 ether, bytes("pm2_with_role"), MULTI_PM_ID);

        // Verify overall budget tracking
        (, uint256 spent,) = tm.getProjectInfo(MULTI_PM_ID);
        assertEq(spent, 7 ether, "Project should track 7 ether spent");
    }

    function test_TaskLifecycleEdgeCases() public {
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        vm.prank(creator1);
        EDGE_ID = tm.createProject(
            bytes("EDGE"), 10 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

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
        setRole(nonClaimer, bytes32("MEMBER"));

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Create a large unlimited project
        vm.prank(creator1);
        MEGA_ID =
            tm.createProject(bytes("MEGA"), 0, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

        // Add multiple project managers
        address[] memory pms = new address[](3);
        pms[0] = pm1;

        address pm2 = makeAddr("pm2");
        address pm3 = makeAddr("pm3");
        setRole(pm2, bytes32("PM"));
        setRole(pm3, bytes32("PM"));
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
            setRole(members[i], bytes32("MEMBER"));
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
            tm.createProject(bytes("CAPPED_BIG"), 10 ether, pms, createRoles, claimRoles, reviewRoles, assignRoles);

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
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Create a project that will be deleted
        vm.prank(creator1);
        TO_DELETE_ID = tm.createProject(
            bytes("TO_DELETE"), 3 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
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
            tm.createProject(bytes("ZERO_CAP"), 0, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles);

        // Add tasks, verify we can still delete with non-zero spent
        vm.prank(creator1);
        tm.createTask(3 ether, bytes("unlimited_task"), ZERO_CAP_ID);

        // Delete should succeed with zero cap, non-zero spent
        vm.prank(creator1);
        tm.deleteProject(ZERO_CAP_ID, bytes("ZERO_CAP"));
    }

    function test_ExecutorRoleManagement() public {
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Create new executor
        address executor2 = makeAddr("executor2");

        // Non-executor can't set executor
        vm.prank(creator1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setExecutor(executor2);

        // Executor can update executor
        vm.prank(executor);
        tm.setExecutor(executor2);

        // Old executor can no longer set creator roles
        bytes32 TEST_ROLE = keccak256("TEST_ROLE");
        vm.prank(executor);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setCreatorRole(TEST_ROLE, true);

        // New executor can set creator roles
        vm.prank(executor2);
        tm.setCreatorRole(TEST_ROLE, true);

        // Assign the new role to a user
        address testCreator = makeAddr("testCreator");
        setRole(testCreator, TEST_ROLE);

        // Verify the new role works for creating projects
        vm.prank(testCreator);
        EXECUTOR_TEST_ID = tm.createProject(
            bytes("EXECUTOR_TEST"), 1 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );

        // New executor can revoke the role
        vm.prank(executor2);
        tm.setCreatorRole(TEST_ROLE, false);

        // Role should no longer work
        vm.prank(testCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject(
            bytes("SHOULD_FAIL"), 1 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );
    }

    function test_ExecutorBypassMemberCheck() public {
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = MEMBER_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = PM_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = PM_ROLE;

        // Create project
        vm.prank(creator1);
        EXECUTOR_BYPASS_ID = tm.createProject(
            bytes("EXECUTOR_BYPASS"), 5 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
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
        // Create a new role with combined permissions
        bytes32 MULTI_ROLE = keccak256("MULTI_ROLE");
        address multiUser = makeAddr("multiUser");
        setRole(multiUser, MULTI_ROLE);
        
        // Set global permissions (CREATE | CLAIM)
        vm.prank(executor);
        tm.setRolePerm(MULTI_ROLE, TaskPerm.CREATE | TaskPerm.CLAIM);
        
        // Create project
        bytes32[] memory emptyRoles = new bytes32[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("COMBINED_TEST"), 5 ether, new address[](0), emptyRoles, emptyRoles, emptyRoles, emptyRoles
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
        // Create new role and user
        bytes32 DYNAMIC_ROLE = keccak256("DYNAMIC_ROLE");
        address dynamicUser = makeAddr("dynamicUser");
        setRole(dynamicUser, DYNAMIC_ROLE);
        
        // Initially no permissions for this role
        
        // Create project
        bytes32[] memory emptyRoles = new bytes32[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("DYNAMIC_TEST"), 5 ether, new address[](0), emptyRoles, emptyRoles, emptyRoles, emptyRoles
        );
        
        // User can't create tasks (no permissions)
        vm.prank(dynamicUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("should_fail"), projectId);
        
        // Grant CREATE permission at project level
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, DYNAMIC_ROLE, TaskPerm.CREATE);
        
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
        tm.setProjectRolePerm(projectId, DYNAMIC_ROLE, TaskPerm.CREATE | TaskPerm.REVIEW);
        
        // Now user can complete tasks
        vm.prank(dynamicUser);
        tm.completeTask(0);
    }

    function test_GlobalVsProjectPermissionOverrides() public {
        // Create a role with global permissions
        bytes32 OVERRIDE_ROLE = keccak256("OVERRIDE_ROLE");
        address overrideUser = makeAddr("overrideUser");
        setRole(overrideUser, OVERRIDE_ROLE);
        
        // Set full permissions globally
        vm.prank(executor);
        tm.setRolePerm(OVERRIDE_ROLE, TaskPerm.CREATE | TaskPerm.CLAIM | TaskPerm.REVIEW | TaskPerm.ASSIGN);
        
        // Create project
        bytes32[] memory emptyRoles = new bytes32[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("OVERRIDE_TEST"), 5 ether, new address[](0), emptyRoles, emptyRoles, emptyRoles, emptyRoles
        );
        
        // Create a second project to verify global perms still work there
        vm.prank(creator1);
        bytes32 projectId2 = tm.createProject(
            bytes("GLOBAL_TEST"), 5 ether, new address[](0), emptyRoles, emptyRoles, emptyRoles, emptyRoles
        );
        
        // Restrict permissions on the first project (only CREATE)
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, OVERRIDE_ROLE, TaskPerm.CREATE);
        
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
        // Create role and user
        bytes32 TEMP_ROLE = keccak256("TEMP_ROLE");
        address tempUser = makeAddr("tempUser");
        setRole(tempUser, TEMP_ROLE);
        
        // Give CREATE permission
        vm.prank(executor);
        tm.setRolePerm(TEMP_ROLE, TaskPerm.CREATE);
        
        // Create project
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(bytes("TEMP"), 5 ether, new address[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0));
        
        // User can create tasks
        vm.prank(tempUser);
        tm.createTask(1 ether, bytes("task"), projectId);
        
        // Revoke permission
        vm.prank(executor);
        tm.setRolePerm(TEMP_ROLE, 0);
        
        // User can't create tasks anymore
        vm.prank(tempUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("fail"), projectId);
    }

    function test_IndividualPermissionFlags() public {
        // Create 4 roles, each with a single permission flag
        bytes32 CREATE_ROLE = keccak256("CREATE_ONLY");
        bytes32 CLAIM_ROLE = keccak256("CLAIM_ONLY");
        bytes32 REVIEW_ROLE = keccak256("REVIEW_ONLY");
        bytes32 ASSIGN_ROLE = keccak256("ASSIGN_ONLY");
        
        // Create 4 users with respective roles
        address createUser = makeAddr("createUser");
        address claimUser = makeAddr("claimUser");
        address reviewUser = makeAddr("reviewUser");
        address assignUser = makeAddr("assignUser");
        
        setRole(createUser, CREATE_ROLE);
        setRole(claimUser, CLAIM_ROLE);
        setRole(reviewUser, REVIEW_ROLE);
        setRole(assignUser, ASSIGN_ROLE);
        
        // Set permissions
        vm.startPrank(executor);
        tm.setRolePerm(CREATE_ROLE, TaskPerm.CREATE);
        tm.setRolePerm(CLAIM_ROLE, TaskPerm.CLAIM);
        tm.setRolePerm(REVIEW_ROLE, TaskPerm.REVIEW);
        tm.setRolePerm(ASSIGN_ROLE, TaskPerm.ASSIGN);
        vm.stopPrank();
        
        // Create project
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(bytes("PERM_FLAGS"), 5 ether, new address[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0), new bytes32[](0));
        
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
