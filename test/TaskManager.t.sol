// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TaskManager} from "../src/TaskManager.sol";

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

    bytes32 constant CREATOR_ROLE = keccak256("CREATOR");

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
        setRole(pm1, bytes32("PM"));
        setRole(member1, bytes32("MEMBER"));

        // initialize TaskManager
        tm = new TaskManager();
        bytes32[] memory creatorRoles = new bytes32[](1);
        creatorRoles[0] = CREATOR_ROLE;

        vm.prank(creator1);
        tm.initialize(address(token), address(membership), creatorRoles);
    }

    /*───────────────── PROJECT SCENARIOS ───────────────*/

    function test_CreateUnlimitedProjectAndTaskByAnotherCreator() public {
        vm.prank(creator1);
        tm.createProject("UNLIM", 0, new address[](0));

        // creator2 creates a task (should succeed, cap == 0)
        vm.prank(creator2);
        tm.createTask(1 ether, "ipfs://meta", "UNLIM");

        (,, address claimer,,) = tm.getTask(0);
        assertEq(claimer, address(0), "should be unclaimed");
    }

    function test_CreateCappedProjectAndBudgetEnforcement() public {
        address[] memory managers = new address[](1);
        managers[0] = pm1;

        vm.prank(creator1);
        tm.createProject("CAPPED", 3 ether, managers);

        // pm1 can create tasks until cap reached
        vm.prank(pm1);
        tm.createTask(1 ether, "a", "CAPPED");

        vm.prank(pm1);
        tm.createTask(2 ether, "b", "CAPPED");

        // next task (1 wei over budget) reverts
        vm.prank(pm1);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1, "c", "CAPPED");
    }

    function test_UpdateProjectCapLowerThanSpentShouldRevert() public {
        vm.prank(creator1);
        tm.createProject("BUD", 2 ether, new address[](0));

        vm.prank(creator1);
        tm.createTask(2 ether, "foo", "BUD");

        // try lowering cap below spent
        vm.prank(creator1);
        vm.expectRevert(TaskManager.CapBelowCommitted.selector);
        tm.updateProjectCap("BUD", 1 ether);
    }

    /*───────────────── TASK LIFECYCLE ───────────────────*/

    function _prepareFlow() internal returns (uint256 id) {
        vm.prank(creator1);
        tm.createProject("FLOW", 5 ether, new address[](0));

        address[] memory mgr = new address[](1);
        mgr[0] = pm1;

        // assign pm1 retroactively
        vm.prank(creator1);
        tm.addProjectManager("FLOW", pm1);

        vm.prank(pm1);
        tm.createTask(1 ether, "hash", "FLOW");
        return 0;
    }

    function test_TaskFullLifecycleWithMint() public {
        uint256 id = _prepareFlow();

        // member1 claims
        vm.prank(member1);
        tm.claimTask(id);

        // member1 submits
        vm.prank(member1);
        tm.submitTask(id, "hash2");

        // pm1 completes, mints token
        uint256 balBefore = token.balanceOf(member1);

        vm.prank(pm1);
        tm.completeTask(id);

        assertEq(token.balanceOf(member1), balBefore + 1 ether, "minted payout");
        (, TaskManager.Status st,,,) = tm.getTask(id);
        assertEq(uint8(st), uint8(TaskManager.Status.COMPLETED));
    }

    function test_UpdateTaskBeforeClaimAdjustsBudget() public {
        vm.prank(creator1);
        tm.createProject("UPD", 3 ether, new address[](0));

        vm.prank(creator1);
        tm.createTask(1 ether, "foo", "UPD");

        // raise payout by 1 ether
        vm.prank(creator1);
        tm.updateTask(0, 2 ether, "bar");

        // spent should now be 2 ether
        (uint256 cap, uint256 spent,) = tm.getProjectInfo("UPD");
        assertEq(cap, 3 ether);
        assertEq(spent, 2 ether);
    }

    function test_UpdateTaskAfterClaimOnlyIPFS() public {
        uint256 id = _prepareFlow();

        vm.prank(member1);
        tm.claimTask(id);

        // attempt to change payout should still emit but NOT change storage
        vm.prank(pm1);
        tm.updateTask(id, 5 ether, "newhash");

        (,,,, string memory h) = tm.getTask(id);
        assertEq(h, "newhash");

        (uint256 payout,,,,) = tm.getTask(id);
        assertEq(payout, 1 ether, "payout unchanged");
    }

    function test_CancelTaskRefundsSpent() public {
        vm.prank(creator1);
        tm.createProject("CAN", 2 ether, new address[](0));

        vm.prank(creator1);
        tm.createTask(1 ether, "foo", "CAN");

        (uint256 cap, uint256 spentBefore, bool isManager) = tm.getProjectInfo("CAN");
        assertEq(spentBefore, 1 ether);

        vm.prank(creator1);
        tm.cancelTask(0);

        (, uint256 spentAfter,) = tm.getProjectInfo("CAN");
        assertEq(spentAfter, 0);
    }

    /*───────────────── ACCESS CONTROL ───────────────────*/

    function test_CreateTaskByNonMemberReverts() public {
        vm.prank(creator1);
        tm.createProject("ACC", 0, new address[](0));

        // creator2 is a member? => no, role==CREATOR, but our onlyMember modifier
        // checks roleOf != 0, so still passes. Use outsider (no role) to trigger revert.
        vm.prank(outsider);
        vm.expectRevert(TaskManager.NotMember.selector);
        tm.createTask(1, "x", "ACC");
    }

    function test_OnlyPMOrCreatorCanAssignTask() public {
        uint256 id = _prepareFlow();

        vm.prank(outsider);
        vm.expectRevert(TaskManager.NotPM.selector);
        tm.assignTask(id, member1);

        vm.prank(creator1);
        tm.assignTask(id, member1); // should succeed
    }

    /*───────────────── COMPLEX SCENARIOS ───────────────────*/

    function test_MultiProjectTaskManagement() public {
        // Create three projects with different caps
        vm.startPrank(creator1);
        tm.createProject("PROJECT_A", 5 ether, new address[](0));
        tm.createProject("PROJECT_B", 3 ether, new address[](0));
        tm.createProject("PROJECT_C", 0, new address[](0)); // Unlimited
        vm.stopPrank();

        // Create multiple tasks across projects
        vm.prank(creator1);
        tm.createTask(1 ether, "task1_A", "PROJECT_A");

        vm.prank(creator1);
        tm.createTask(2 ether, "task1_B", "PROJECT_B");

        vm.prank(creator1);
        tm.createTask(2 ether, "task1_C", "PROJECT_C");

        // Member claims tasks from different projects
        vm.startPrank(member1);
        tm.claimTask(0); // PROJECT_A task
        tm.claimTask(2); // PROJECT_C task
        vm.stopPrank();

        // Budget verification
        (uint256 capA, uint256 spentA,) = tm.getProjectInfo("PROJECT_A");
        assertEq(spentA, 1 ether, "PROJECT_A spent should be 1 ether");
        assertEq(capA, 5 ether, "PROJECT_A cap should be 5 ether");

        (uint256 capB, uint256 spentB,) = tm.getProjectInfo("PROJECT_B");
        assertEq(spentB, 2 ether, "PROJECT_B spent should be 2 ether");

        // Test trying to exceed PROJECT_B budget
        vm.prank(creator1);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1 ether + 1, "task2_B", "PROJECT_B"); // Would exceed cap

        // Complete task from PROJECT_C
        vm.prank(member1);
        tm.submitTask(2, "completed_C");

        vm.prank(creator1);
        tm.completeTask(2);

        // Verify token minting worked
        assertEq(token.balanceOf(member1), 2 ether, "Member should receive 2 ether from task completion");
    }

    function test_GovernanceAndRoleChanges() public {
        // Initial setup
        vm.prank(creator1);
        tm.createProject("GOV_TEST", 5 ether, new address[](0));

        // Set up an executor
        address executor = makeAddr("executor");

        // First setExecutor call can be made by anyone since executor is not set yet
        vm.prank(creator1);
        tm.setExecutor(executor);

        // Add new role to the creator roles using the executor
        bytes32 NEW_ROLE = keccak256("NEW_CREATOR");
        vm.prank(executor);
        tm.setCreatorRole(NEW_ROLE, true);

        // Assign new role to an address
        address newCreator = makeAddr("newCreator");
        setRole(newCreator, NEW_ROLE);

        // Test that new role can create projects
        vm.prank(newCreator);
        tm.createProject("NEW_PROJECT", 1 ether, new address[](0));

        // Verify new project exists by creating a task
        vm.prank(newCreator);
        tm.createTask(0.5 ether, "new_task", "NEW_PROJECT");

        // Disable the role using the executor
        vm.prank(executor);
        tm.setCreatorRole(NEW_ROLE, false);

        // Verify the role can no longer create projects
        vm.prank(newCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject("SHOULD_FAIL", 1 ether, new address[](0));
    }

    function test_ProjectManagerHierarchy() public {
        // Create a project with multiple managers
        address[] memory managers = new address[](2);
        managers[0] = pm1;
        address pm2 = makeAddr("pm2");
        setRole(pm2, bytes32("PM"));
        managers[1] = pm2;

        vm.prank(creator1);
        tm.createProject("MULTI_PM", 10 ether, managers);

        // Each PM creates tasks
        vm.prank(pm1);
        tm.createTask(2 ether, "pm1_task", "MULTI_PM");

        vm.prank(pm2);
        tm.createTask(3 ether, "pm2_task", "MULTI_PM");

        // PM1 can complete PM2's task
        vm.prank(member1);
        tm.claimTask(1);

        vm.prank(member1);
        tm.submitTask(1, "completed_by_member");

        vm.prank(pm1);
        tm.completeTask(1);

        // Creator removes PM2
        vm.prank(creator1);
        tm.removeProjectManager("MULTI_PM", pm2);

        // PM2 can no longer create tasks
        vm.prank(pm2);
        vm.expectRevert(TaskManager.NotPM.selector);
        tm.createTask(1 ether, "should_fail", "MULTI_PM");

        // But PM1 still can
        vm.prank(pm1);
        tm.createTask(1 ether, "still_works", "MULTI_PM");

        // Verify overall budget tracking
        (, uint256 spent,) = tm.getProjectInfo("MULTI_PM");
        assertEq(spent, 6 ether, "Project should track 6 ether spent");
    }

    function test_TaskLifecycleEdgeCases() public {
        vm.prank(creator1);
        tm.createProject("EDGE", 10 ether, new address[](0));

        // Create and immediately cancel a task
        vm.startPrank(creator1);
        tm.createTask(1 ether, "to_cancel", "EDGE");
        tm.cancelTask(0);
        vm.stopPrank();

        // Verify project budget is refunded
        (, uint256 spent,) = tm.getProjectInfo("EDGE");
        assertEq(spent, 0, "Budget should be refunded after cancel");

        // Create a task, assign it, then try operations that should fail
        vm.prank(creator1);
        tm.createTask(2 ether, "edge_task", "EDGE");

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
        tm.submitTask(1, "wrong_submitter");

        // Submit correctly
        vm.prank(member1);
        tm.submitTask(1, "correct_submission");

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
        // Create a large unlimited project
        vm.prank(creator1);
        tm.createProject("MEGA", 0, new address[](0));

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
            vm.prank(creator1);
            tm.addProjectManager("MEGA", pms[i]);
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
            tm.createTask(payout, string(abi.encodePacked("task", i)), "MEGA");

            // Assign tasks to different members
            address assignee = members[i % members.length];

            vm.prank(creator);
            tm.assignTask(i, assignee);
        }

        // Verify project spent
        (, uint256 spent,) = tm.getProjectInfo("MEGA");
        assertEq(spent, totalValue, "Project should track all task value");

        // Submit half the tasks
        for (uint256 i = 0; i < totalTasks / 2; i++) {
            address submitter = members[i % members.length];

            vm.prank(submitter);
            tm.submitTask(i, string(abi.encodePacked("completed", i)));
        }

        // Complete a third of all tasks
        uint256 completedTasks = totalTasks / 3;
        uint256 completedValue = 0;

        for (uint256 i = 0; i < completedTasks; i++) {
            (uint256 payout,,,,) = tm.getTask(i);
            completedValue += payout;

            vm.prank(pms[0]);
            tm.completeTask(i);
        }

        // Create a second project with a hard cap
        vm.prank(creator1);
        tm.createProject("CAPPED_BIG", 10 ether, pms);

        // Create tasks up to the cap
        uint256 cappedTaskCount = 0;
        uint256 cappedSpent = 0;

        while (cappedSpent < 9.5 ether) {
            uint256 payout = 0.3 ether;

            vm.prank(pms[0]);
            tm.createTask(payout, string(abi.encodePacked("capped_task", cappedTaskCount)), "CAPPED_BIG");

            cappedTaskCount++;
            cappedSpent += payout;
        }

        // Verify we can't exceed cap
        vm.prank(pms[0]);
        vm.expectRevert(TaskManager.BudgetExceeded.selector);
        tm.createTask(1 ether, "exceeds_cap", "CAPPED_BIG");

        // Verify task counts and budget usage
        (uint256 cap, uint256 actualSpent,) = tm.getProjectInfo("CAPPED_BIG");
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
        // Create a project that will be deleted
        vm.prank(creator1);
        tm.createProject("TO_DELETE", 3 ether, new address[](0));

        // Create a task, complete it, then verify project can be deleted
        vm.prank(creator1);
        tm.createTask(1 ether, "task1", "TO_DELETE");

        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, "completed");

        vm.prank(creator1);
        tm.completeTask(0);

        // Create another task and cancel it
        vm.prank(creator1);
        tm.createTask(2 ether, "task2", "TO_DELETE");

        vm.prank(creator1);
        tm.cancelTask(1);

        // Verify spent amount is 1 ether (from completed task)
        (uint256 cap, uint256 spent,) = tm.getProjectInfo("TO_DELETE");
        assertEq(spent, 1 ether, "Project spent should only reflect completed task");

        // Try to delete - should fail because cap (3 ether) != spent (1 ether)
        vm.prank(creator1);
        vm.expectRevert(TaskManager.CapBelowCommitted.selector);
        tm.deleteProject("TO_DELETE");

        // Update the cap to match spent amount
        vm.prank(creator1);
        tm.updateProjectCap("TO_DELETE", 1 ether);

        // Now deletion should succeed
        vm.prank(creator1);
        tm.deleteProject("TO_DELETE");

        // Verify project no longer exists by trying to get info
        vm.prank(creator1);
        vm.expectRevert(TaskManager.UnknownProject.selector);
        tm.getProjectInfo("TO_DELETE");

        // Create a zero-cap project
        vm.prank(creator1);
        tm.createProject("ZERO_CAP", 0, new address[](0));

        // Add tasks, verify we can still delete with non-zero spent
        vm.prank(creator1);
        tm.createTask(3 ether, "unlimited_task", "ZERO_CAP");

        // Delete should succeed with zero cap, non-zero spent
        vm.prank(creator1);
        tm.deleteProject("ZERO_CAP");
    }

    function test_ExecutorRoleManagement() public {
        // Create initial executor
        address executor1 = makeAddr("executor1");
        address executor2 = makeAddr("executor2");

        // Anyone can set the executor for the first time
        vm.prank(creator1);
        tm.setExecutor(executor1);

        // Try to set another executor from non-executor address (should fail)
        vm.prank(creator1);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.setExecutor(executor2);

        // Only executor can update executor
        vm.prank(executor1);
        tm.setExecutor(executor2);

        // Only executor can set creator roles
        bytes32 TEST_ROLE = keccak256("TEST_ROLE");

        // Non-executor can't set creator roles
        vm.prank(creator1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setCreatorRole(TEST_ROLE, true);

        // Executor can set creator roles
        vm.prank(executor2);
        tm.setCreatorRole(TEST_ROLE, true);

        // Assign the new role to a user
        address testCreator = makeAddr("testCreator");
        setRole(testCreator, TEST_ROLE);

        // Verify the new role works for creating projects
        vm.prank(testCreator);
        tm.createProject("EXECUTOR_TEST", 1 ether, new address[](0));

        // Executor can revoke the role
        vm.prank(executor2);
        tm.setCreatorRole(TEST_ROLE, false);

        // Role should no longer work
        vm.prank(testCreator);
        vm.expectRevert(TaskManager.NotCreator.selector);
        tm.createProject("SHOULD_FAIL", 1 ether, new address[](0));
    }

    function test_ExecutorBypassMemberCheck() public {
        // Set up executor
        address executor = makeAddr("bypass_executor");
        vm.prank(creator1);
        tm.setExecutor(executor);

        // Create project
        vm.prank(creator1);
        tm.createProject("EXECUTOR_BYPASS", 5 ether, new address[](0));

        // Executor should be able to create tasks even without member role
        // (executor address has no role but should bypass the member check)
        vm.prank(executor);
        tm.createTask(1 ether, "executor_task", "EXECUTOR_BYPASS");

        // Executor should be able to claim tasks
        vm.prank(executor);
        tm.claimTask(0);

        // Executor should be able to submit tasks
        vm.prank(executor);
        tm.submitTask(0, "executor_submission");

        // Verify task status and submission
        (, TaskManager.Status status,,, string memory ipfs) = tm.getTask(0);
        assertEq(uint8(status), uint8(TaskManager.Status.SUBMITTED));
        assertEq(ipfs, "executor_submission");
    }
}
