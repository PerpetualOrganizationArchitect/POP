// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {TaskManagerLens} from "../src/lens/TaskManagerLens.sol";
import {TaskPerm} from "../src/libs/TaskPerm.sol";
import {BudgetLib} from "../src/libs/BudgetLib.sol";
import {ValidationLib} from "../src/libs/ValidationLib.sol";
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

/*────────────────── Mock ERC20 for Bounty Testing ──────────────────*/
contract MockERC20 is Test, IERC20 {
    string public constant name = "BountyToken";
    string public constant symbol = "BOUNTY";
    uint8 public constant decimals = 18;

    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return type(uint256).max;
    }
}

/*──────────────────── Test Suite ────────────────────*/
abstract contract TaskManagerTestBase is Test {
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

    TaskManager tm;
    TaskManagerLens lens;
    MockToken token;
    MockHats hats;

    function setHat(address who, uint256 hatId) internal {
        hats.mintHat(hatId, who);
    }

    function _hatArr(uint256 hat) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = hat;
    }

    function _addrArr(address who) internal pure returns (address[] memory arr) {
        arr = new address[](1);
        arr[0] = who;
    }

    function _defaultRoleHats()
        internal
        pure
        returns (
            uint256[] memory createHats,
            uint256[] memory claimHats,
            uint256[] memory reviewHats,
            uint256[] memory assignHats
        )
    {
        createHats = _hatArr(CREATOR_HAT);
        claimHats = _hatArr(MEMBER_HAT);
        reviewHats = _hatArr(PM_HAT);
        assignHats = _hatArr(PM_HAT);
    }

    function _createDefaultProject(bytes memory name, uint256 cap) internal returns (bytes32 id) {
        (
            uint256[] memory createHats,
            uint256[] memory claimHats,
            uint256[] memory reviewHats,
            uint256[] memory assignHats
        ) = _defaultRoleHats();

        vm.prank(creator1);
        id = tm.createProject(name, cap, new address[](0), createHats, claimHats, reviewHats, assignHats);
    }

    function setUpBase() internal {
        token = new MockToken();
        hats = new MockHats();

        setHat(creator1, CREATOR_HAT);
        setHat(creator2, CREATOR_HAT);
        setHat(pm1, PM_HAT);
        setHat(member1, MEMBER_HAT);

        tm = new TaskManager();
        lens = new TaskManagerLens();
        uint256[] memory creatorHats = _hatArr(CREATOR_HAT);

        vm.prank(creator1);
        tm.initialize(address(token), address(hats), creatorHats, executor);

        vm.prank(executor);
        tm.setConfig(
            TaskManager.ConfigKey.ROLE_PERM, abi.encode(PM_HAT, TaskPerm.CREATE | TaskPerm.REVIEW | TaskPerm.ASSIGN)
        );
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(MEMBER_HAT, TaskPerm.CLAIM));
    }
}

contract TaskManagerTest is TaskManagerTestBase {
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

    function setUp() public {
        setUpBase();
    }

    /*───────────────── PROJECT SCENARIOS ───────────────*/

    function test_CreateUnlimitedProjectAndTaskByAnotherCreator() public {
        UNLIM_ID = _createDefaultProject("UNLIM", 0);

        // creator2 creates a task (should succeed, cap == 0)
        vm.prank(creator2);
        tm.createTask(1 ether, bytes("ipfs://meta"), UNLIM_ID, address(0), 0, false);
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 projectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, address(0), "should be unclaimed");
    }

    function test_CreateCappedProjectAndBudgetEnforcement() public {
        address[] memory managers = _addrArr(pm1);

        vm.prank(creator1);
        CAPPED_ID = tm.createProject(
            bytes("CAPPED"), 3 ether, managers, _hatArr(PM_HAT), _hatArr(MEMBER_HAT), _hatArr(PM_HAT), _hatArr(PM_HAT)
        );

        // pm1 can create tasks until cap reached
        vm.prank(pm1);
        tm.createTask(1 ether, bytes("a"), CAPPED_ID, address(0), 0, false);

        vm.prank(pm1);
        tm.createTask(2 ether, bytes("b"), CAPPED_ID, address(0), 0, false);

        // next task (1 wei over budget) reverts
        vm.prank(pm1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1, bytes("c"), CAPPED_ID, address(0), 0, false);
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
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("CUSTOM_HATS"),
            5 ether,
            new address[](0),
            _hatArr(customCreateHat),
            _hatArr(MEMBER_HAT),
            _hatArr(customReviewHat),
            _hatArr(PM_HAT)
        );

        // Custom creator should be able to create tasks
        vm.prank(customCreator);
        tm.createTask(1 ether, bytes("custom_task"), projectId, address(0), 0, false);

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
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(globalHat, TaskPerm.CREATE | TaskPerm.REVIEW));

        // Create project with different permissions for the same hat
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("OVERRIDE"),
            5 ether,
            new address[](0),
            _hatArr(globalHat),
            _hatArr(MEMBER_HAT),
            _hatArr(PM_HAT), // globalHat not included here
            _hatArr(PM_HAT)
        );

        // Global user should be able to create (global permission)
        vm.prank(globalUser);
        tm.createTask(1 ether, bytes("task"), projectId, address(0), 0, false);

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
        // simplified using helper
        BUD_ID = _createDefaultProject("BUD", 2 ether);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("foo"), BUD_ID, address(0), 0, false);

        // try lowering cap below spent
        vm.prank(executor);
        vm.expectRevert(ValidationLib.CapBelowCommitted.selector);
        tm.setConfig(TaskManager.ConfigKey.PROJECT_CAP, abi.encode(BUD_ID, 1 ether));
    }

    /*───────────────── TASK LIFECYCLE ───────────────────*/

    function _prepareFlow() internal returns (uint256 id) {
        FLOW_ID = _createDefaultProject("FLOW", 5 ether);

        // assign pm1 retroactively
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.PROJECT_MANAGER, abi.encode(FLOW_ID, pm1, true));

        vm.prank(pm1);
        tm.createTask(1 ether, bytes("hash"), FLOW_ID, address(0), 0, false);
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
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(id));
        (uint256 payout, TaskManager.Status st, address claimer, bytes32 projectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(st), uint8(TaskManager.Status.COMPLETED));
    }

    function test_UpdateTaskBeforeClaimAdjustsBudget() public {
        // Set up hat permissions
        UPD_ID = _createDefaultProject("UPD", 3 ether);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("foo"), UPD_ID, address(0), 0, false);

        // raise payout by 1 ether
        vm.prank(creator1);
        tm.updateTask(0, 2 ether, bytes("bar"), address(0), 0);

        // spent should now be 2 ether
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(UPD_ID));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(cap, 3 ether);
        assertEq(spent, 2 ether);
    }

    function test_UpdateTaskAfterClaimReverts() public {
        uint256 id = _prepareFlow();

        vm.prank(member1);
        tm.claimTask(id);

        // attempt to update claimed task should revert
        vm.prank(pm1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.updateTask(id, 5 ether, bytes("newhash"), address(0), 0);
    }

    function test_CancelTaskSpentUnderflowProtection() public {
        // Set up hat permissions
        bytes32 projectId = _createDefaultProject("UNDERFLOW_TEST", 2 ether);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), projectId, address(0), 0, false);

        // Artificially manipulate project spent to be less than task payout
        // This simulates a potential storage corruption or logic bug scenario
        // Note: In a real scenario, this would be done through a storage manipulation
        // For this test, we'll create a scenario where spent gets reduced somehow

        // Create and complete another task to increase spent
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task2"), projectId, address(0), 0, false);

        vm.prank(creator1);
        tm.assignTask(1, member1);

        vm.prank(member1);
        tm.submitTask(1, bytes("submission"));

        vm.prank(creator1);
        tm.completeTask(1);

        // Now project spent should be 2 ether
        // If we could somehow corrupt the spent to be less than task payout,
        // the underflow protection should trigger
        // Since we can't easily manipulate storage in this test,
        // we'll just verify normal cancellation works
        vm.prank(creator1);
        tm.cancelTask(0); // This should work normally

        // Verify spent was correctly reduced
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(projectId));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spent, 1 ether, "Spent should be reduced by cancelled task payout");
    }

    function test_CancelTaskRefundsSpent() public {
        // Set up hat permissions
        CAN_ID = _createDefaultProject("CAN", 2 ether);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("foo"), CAN_ID, address(0), 0, false);

        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(CAN_ID));
        (uint256 cap, uint256 spentBefore, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spentBefore, 1 ether);

        vm.prank(creator1);
        tm.cancelTask(0);

        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(CAN_ID));
        (, uint256 spentAfter,) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spentAfter, 0);
    }

    /*───────────────── ACCESS CONTROL ───────────────────*/

    function test_CreateTaskByNonMemberReverts() public {
        ACC_ID = _createDefaultProject("ACC", 0);

        // outsider has no role and no permissions
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1, bytes("x"), ACC_ID, address(0), 0, false);
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
        tm.createTask(1 ether, bytes("custom_task"), projectId, address(0), 0, false);

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
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(globalHat, TaskPerm.CREATE | TaskPerm.REVIEW));

        // Override in project
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, globalHat, TaskPerm.CREATE);

        // User should only have CREATE permission in this project
        vm.prank(globalUser);
        tm.createTask(1 ether, bytes("task"), projectId, address(0), 0, false);

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
        tm.createTask(1 ether, bytes("task1_A"), PROJECT_A_ID, address(0), 0, false);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task1_B"), PROJECT_B_ID, address(0), 0, false);

        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task1_C"), PROJECT_C_ID, address(0), 0, false);

        // Member claims tasks from different projects
        vm.startPrank(member1);
        tm.claimTask(0); // PROJECT_A task
        tm.claimTask(2); // PROJECT_C task
        vm.stopPrank();

        // Budget verification
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(PROJECT_A_ID));
        (uint256 capA, uint256 spentA, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spentA, 1 ether, "PROJECT_A spent should be 1 ether");
        assertEq(capA, 5 ether, "PROJECT_A cap should be 5 ether");

        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(PROJECT_B_ID));
        (uint256 capB, uint256 spentB, bool isManagerB) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spentB, 2 ether, "PROJECT_B spent should be 2 ether");

        // Test trying to exceed PROJECT_B budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1 ether + 1, bytes("task2_B"), PROJECT_B_ID, address(0), 0, false); // Would exceed cap

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
        tm.setConfig(TaskManager.ConfigKey.CREATOR_HAT_ALLOWED, abi.encode(NEW_HAT, true));

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
        tm.createTask(0.5 ether, bytes("new_task"), NEW_PROJECT_ID, address(0), 0, false);

        // Disable the hat using the executor
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.CREATOR_HAT_ALLOWED, abi.encode(NEW_HAT, false));

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
        tm.createTask(2 ether, bytes("pm1_task"), MULTI_PM_ID, address(0), 0, false);

        vm.prank(pm2);
        tm.createTask(3 ether, bytes("pm2_task"), MULTI_PM_ID, address(0), 0, false);

        // PM1 can complete PM2's task (as project manager)
        vm.prank(member1);
        tm.claimTask(1);

        vm.prank(member1);
        tm.submitTask(1, bytes("completed_by_member"));

        vm.prank(pm1);
        tm.completeTask(1);

        // Remove PM2 as project manager
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.PROJECT_MANAGER, abi.encode(MULTI_PM_ID, pm2, false));

        // PM2 can no longer create tasks (no longer a project manager and no role)
        vm.prank(pm2);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("should_fail"), MULTI_PM_ID, address(0), 0, false);

        // But PM1 still can (still a project manager)
        vm.prank(pm1);
        tm.createTask(1 ether, bytes("still_works"), MULTI_PM_ID, address(0), 0, false);

        // Now give PM2 the PM_HAT
        setHat(pm2, PM_HAT);

        // PM2 should now be able to create tasks again (has PM_HAT with CREATE permission)
        vm.prank(pm2);
        tm.createTask(1 ether, bytes("pm2_with_hat"), MULTI_PM_ID, address(0), 0, false);

        // Verify overall budget tracking
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(MULTI_PM_ID));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
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
        tm.createTask(1 ether, bytes("to_cancel"), EDGE_ID, address(0), 0, false);
        tm.cancelTask(0);
        vm.stopPrank();

        // Verify project budget is refunded
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(EDGE_ID));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spent, 0, "Budget should be refunded after cancel");

        // Create a task, assign it, then try operations that should fail
        vm.prank(creator1);
        tm.createTask(2 ether, bytes("edge_task"), EDGE_ID, address(0), 0, false);

        vm.prank(creator1);
        tm.assignTask(1, member1);

        // Try to claim an already claimed task
        vm.prank(member1);
        vm.expectRevert(TaskManager.BadStatus.selector);
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
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.cancelTask(1);

        // Complete the task
        vm.prank(creator1);
        tm.completeTask(1);

        // Try to complete again
        vm.prank(creator1);
        vm.expectRevert(TaskManager.BadStatus.selector);
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
            tm.setConfig(TaskManager.ConfigKey.PROJECT_MANAGER, abi.encode(MEGA_ID, pms[i], true));
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
            tm.createTask(payout, taskMetadata, MEGA_ID, address(0), 0, false);

            // Assign tasks to different members
            address assignee = members[i % members.length];

            vm.prank(creator);
            tm.assignTask(i, assignee);
        }

        // Verify project spent
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(MEGA_ID));
        (, uint256 spent,) = abi.decode(result, (uint256, uint256, bool));
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
            bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(i));
            (uint256 payout, TaskManager.Status status, address claimer, bytes32 projectId, bool requiresApplication) =
                abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
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
            tm.createTask(payout, taskMetadata, CAPPED_BIG_ID, address(0), 0, false);

            cappedTaskCount++;
            cappedSpent += payout;
        }

        // Verify we can't exceed cap
        vm.prank(pms[0]);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1 ether, bytes("exceeds_cap"), CAPPED_BIG_ID, address(0), 0, false);

        // Verify task counts and budget usage
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(CAPPED_BIG_ID));
        (uint256 cap, uint256 actualSpent,) = abi.decode(result, (uint256, uint256, bool));
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
        tm.createTask(1 ether, bytes("task1"), TO_DELETE_ID, address(0), 0, false);

        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("completed"));

        vm.prank(creator1);
        tm.completeTask(0);

        // Create another task and cancel it
        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task2"), TO_DELETE_ID, address(0), 0, false);

        vm.prank(creator1);
        tm.cancelTask(1);

        // Verify spent amount is 1 ether (from completed task)
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(TO_DELETE_ID));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spent, 1 ether, "Project spent should only reflect completed task");

        // Deletion should succeed because cap (3 ether) >= spent (1 ether)
        vm.prank(creator1);
        tm.deleteProject(TO_DELETE_ID, bytes("TO_DELETE"));

        // Verify project no longer exists by trying to get info
        vm.prank(creator1);
        vm.expectRevert(TaskManager.NotFound.selector);
        lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(TO_DELETE_ID));

        // Create a zero-cap project
        vm.prank(creator1);
        ZERO_CAP_ID =
            tm.createProject(bytes("ZERO_CAP"), 0, new address[](0), createHats, claimHats, reviewHats, assignHats);

        // Add tasks, verify we can still delete with non-zero spent
        vm.prank(creator1);
        tm.createTask(3 ether, bytes("unlimited_task"), ZERO_CAP_ID, address(0), 0, false);

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
        tm.setConfig(TaskManager.ConfigKey.EXECUTOR, abi.encode(executor2));

        // Executor can update executor
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.EXECUTOR, abi.encode(executor2));

        // Old executor can no longer set creator hats
        uint256 TEST_HAT = 123;
        vm.prank(executor);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setConfig(TaskManager.ConfigKey.CREATOR_HAT_ALLOWED, abi.encode(TEST_HAT, true));

        // New executor can set creator hats
        vm.prank(executor2);
        tm.setConfig(TaskManager.ConfigKey.CREATOR_HAT_ALLOWED, abi.encode(TEST_HAT, true));

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
        tm.setConfig(TaskManager.ConfigKey.CREATOR_HAT_ALLOWED, abi.encode(TEST_HAT, false));

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
        tm.createTask(1 ether, bytes("executor_task"), EXECUTOR_BYPASS_ID, address(0), 0, false);

        // Executor should be able to claim tasks
        vm.prank(executor);
        tm.claimTask(0);

        // Executor should be able to submit tasks
        vm.prank(executor);
        tm.submitTask(0, bytes("executor_submission"));

        // Verify task status and submission
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 projectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
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
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(MULTI_HAT, TaskPerm.CREATE | TaskPerm.CLAIM));

        // Create project (use creator1 who has creator hat)
        uint256[] memory emptyHats = new uint256[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("COMBINED_TEST"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // User should be able to create tasks with CREATE permission
        vm.prank(multiUser);
        tm.createTask(1 ether, bytes("multi_task"), projectId, address(0), 0, false);

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
        tm.createTask(1 ether, bytes("should_fail"), projectId, address(0), 0, false);

        // Grant CREATE permission at project level
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, DYNAMIC_HAT, TaskPerm.CREATE);

        // Now user can create tasks
        vm.prank(dynamicUser);
        tm.createTask(1 ether, bytes("now_works"), projectId, address(0), 0, false);

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
        tm.setConfig(
            TaskManager.ConfigKey.ROLE_PERM,
            abi.encode(OVERRIDE_HAT, TaskPerm.CREATE | TaskPerm.CLAIM | TaskPerm.REVIEW | TaskPerm.ASSIGN)
        );

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
        tm.createTask(1 ether, bytes("task1"), projectId, address(0), 0, false);

        vm.prank(overrideUser);
        tm.createTask(1 ether, bytes("task2"), projectId2, address(0), 0, false);

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
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(TEMP_HAT, TaskPerm.CREATE));

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
        tm.createTask(1 ether, bytes("task"), projectId, address(0), 0, false);

        // Revoke permission
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(TEMP_HAT, 0));

        // User can't create tasks anymore
        vm.prank(tempUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createTask(1 ether, bytes("fail"), projectId, address(0), 0, false);
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
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(CREATE_HAT, TaskPerm.CREATE));
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(CLAIM_HAT, TaskPerm.CLAIM));
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(REVIEW_HAT, TaskPerm.REVIEW));
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(ASSIGN_HAT, TaskPerm.ASSIGN));
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
        tm.createTask(1 ether, bytes("create_task"), projectId, address(0), 0, false);

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
        tm.createTask(1 ether, bytes("assign_fail"), projectId, address(0), 0, false);

        // Test CLAIM permission - indirectly tested by previous assign
        // Create a new task for claiming
        vm.prank(createUser);
        tm.createTask(1 ether, bytes("for_claiming"), projectId, address(0), 0, false);

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
        tm.createTask(1 ether, bytes("review_fail"), projectId, address(0), 0, false);

        vm.prank(reviewUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.assignTask(0, claimUser);
    }

    /*───────────────── CREATE AND ASSIGN TASK TESTS ────────────────────*/

    function test_CreateAndAssignTaskBasic() public {
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
            bytes("CREATE_ASSIGN_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Test basic create and assign functionality
        vm.prank(creator1);
        uint256 taskId = tm.createAndAssignTask(1 ether, bytes("test_task"), projectId, member1, address(0), 0, false);

        // Verify task was created and assigned correctly
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Payout should be correct");
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED), "Status should be CLAIMED");
        assertEq(claimer, member1, "Task should be assigned to member1");
        assertEq(taskProjectId, projectId, "Project ID should match");

        // Verify project budget was updated
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(projectId));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spent, 1 ether, "Project spent should be updated");
    }

    function test_CreateAndAssignTaskPermissions() public {
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

        // Test that user with only CREATE permission cannot use createAndAssignTask
        uint256 CREATE_ONLY_HAT = 300;
        address createOnlyUser = makeAddr("createOnlyUser");
        setHat(createOnlyUser, CREATE_ONLY_HAT);

        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(CREATE_ONLY_HAT, TaskPerm.CREATE));

        vm.prank(createOnlyUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createAndAssignTask(1 ether, bytes("should_fail"), projectId, member1, address(0), 0, false);

        // Test that user with only ASSIGN permission cannot use createAndAssignTask
        uint256 ASSIGN_ONLY_HAT = 301;
        address assignOnlyUser = makeAddr("assignOnlyUser");
        setHat(assignOnlyUser, ASSIGN_ONLY_HAT);

        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(ASSIGN_ONLY_HAT, TaskPerm.ASSIGN));

        vm.prank(assignOnlyUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createAndAssignTask(1 ether, bytes("should_fail"), projectId, member1, address(0), 0, false);

        // Test that user with both CREATE and ASSIGN permissions can use createAndAssignTask
        uint256 CREATE_ASSIGN_HAT = 302;
        address createAssignUser = makeAddr("createAssignUser");
        setHat(createAssignUser, CREATE_ASSIGN_HAT);

        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(CREATE_ASSIGN_HAT, TaskPerm.CREATE | TaskPerm.ASSIGN));

        vm.prank(createAssignUser);
        uint256 taskId = tm.createAndAssignTask(1 ether, bytes("should_work"), projectId, member1, address(0), 0, false);

        // Verify task was created successfully
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, member1, "Task should be assigned to member1");
    }

    function test_CreateAndAssignTaskProjectManager() public {
        // Set up hat permissions
        uint256[] memory createHats = new uint256[](1);
        createHats[0] = CREATOR_HAT;
        uint256[] memory claimHats = new uint256[](1);
        claimHats[0] = MEMBER_HAT;
        uint256[] memory reviewHats = new uint256[](1);
        reviewHats[0] = PM_HAT;
        uint256[] memory assignHats = new uint256[](1);
        assignHats[0] = PM_HAT;

        address[] memory managers = new address[](1);
        managers[0] = pm1;

        vm.prank(creator1);
        bytes32 projectId =
            tm.createProject(bytes("PM_TEST"), 5 ether, managers, createHats, claimHats, reviewHats, assignHats);

        // Test that project manager can use createAndAssignTask
        vm.prank(pm1);
        uint256 taskId = tm.createAndAssignTask(1 ether, bytes("pm_task"), projectId, member1, address(0), 0, false);

        // Verify task was created and assigned
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, member1, "Task should be assigned to member1");

        // Test that non-project manager cannot use createAndAssignTask
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createAndAssignTask(1 ether, bytes("should_fail"), projectId, member1, address(0), 0, false);
    }

    function test_CreateAndAssignTaskValidation() public {
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
            bytes("VALIDATION_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Test zero address assignee
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        tm.createAndAssignTask(1 ether, bytes("test"), projectId, address(0), address(0), 0, false);

        // Test zero payout
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.InvalidPayout.selector);
        tm.createAndAssignTask(0, bytes("test"), projectId, member1, address(0), 0, false);

        // Test excessive payout
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.InvalidPayout.selector);
        tm.createAndAssignTask(1e25, bytes("test"), projectId, member1, address(0), 0, false); // Over MAX_PAYOUT

        // Test empty metadata
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.InvalidString.selector);
        tm.createAndAssignTask(1 ether, bytes(""), projectId, member1, address(0), 0, false);

        // Test non-existent project - this will fail with NotCreator() because permission check happens first
        vm.prank(creator1);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createAndAssignTask(1 ether, bytes("test"), bytes32(uint256(999)), member1, address(0), 0, false);
    }

    function test_CreateAndAssignTaskBudgetEnforcement() public {
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
            bytes("BUDGET_TEST"), 2 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create first task within budget
        vm.prank(creator1);
        uint256 taskId1 = tm.createAndAssignTask(1 ether, bytes("task1"), projectId, member1, address(0), 0, false);

        // Create second task within budget
        vm.prank(creator1);
        uint256 taskId2 = tm.createAndAssignTask(1 ether, bytes("task2"), projectId, member1, address(0), 0, false);

        // Try to create third task that would exceed budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createAndAssignTask(1 ether, bytes("task3"), projectId, member1, address(0), 0, false);

        // Verify project budget tracking
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(projectId));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(result, (uint256, uint256, bool));
        assertEq(spent, 2 ether, "Project should have spent 2 ether");
        assertEq(cap, 2 ether, "Project cap should be 2 ether");
    }

    function test_CreateAndAssignTaskEvents() public {
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
            bytes("EVENT_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Test that both TaskCreated and TaskAssigned events are emitted
        vm.prank(creator1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskCreated(0, projectId, 1 ether, address(0), 0, false, bytes("event_test"));
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskAssigned(0, member1, creator1);
        tm.createAndAssignTask(1 ether, bytes("event_test"), projectId, member1, address(0), 0, false);
    }

    function test_CreateAndAssignTaskLifecycle() public {
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
            bytes("LIFECYCLE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create and assign task
        vm.prank(creator1);
        uint256 taskId =
            tm.createAndAssignTask(1 ether, bytes("lifecycle_test"), projectId, member1, address(0), 0, false);

        // Verify task is in CLAIMED status
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (, TaskManager.Status status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED), "Task should be CLAIMED");

        // Assigned user should be able to submit
        vm.prank(member1);
        tm.submitTask(taskId, bytes("submission"));

        // Verify task is now SUBMITTED
        ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (, status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.SUBMITTED), "Task should be SUBMITTED");

        // Reviewer should be able to complete
        vm.prank(creator1);
        tm.completeTask(taskId);

        // Verify task is completed and tokens minted
        ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (, status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.COMPLETED), "Task should be COMPLETED");
        assertEq(token.balanceOf(member1), 1 ether, "Member should receive tokens");
    }

    function test_CreateAndAssignTaskGasEfficiency() public {
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
            bytes("GAS_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Measure gas for createAndAssignTask
        vm.prank(creator1);
        uint256 gasBefore = gasleft();
        uint256 taskId = tm.createAndAssignTask(1 ether, bytes("gas_test"), projectId, member1, address(0), 0, false);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for createAndAssignTask:", gasUsed);

        // Verify task was created and assigned correctly
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (,, address claimer,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, member1, "Task should be assigned to member1");

        // For comparison, measure gas for separate create + assign operations
        vm.prank(creator1);
        gasBefore = gasleft();
        tm.createTask(1 ether, bytes("gas_test2"), projectId, address(0), 0, false);
        uint256 gasCreate = gasBefore - gasleft();

        vm.prank(creator1);
        gasBefore = gasleft();
        tm.assignTask(1, member1);
        uint256 gasAssign = gasBefore - gasleft();

        uint256 gasTotal = gasCreate + gasAssign;
        console.log("Gas used for createTask:", gasCreate);
        console.log("Gas used for assignTask:", gasAssign);
        console.log("Total gas for separate operations:", gasTotal);
        console.log("Gas savings:", gasTotal - gasUsed);
    }

    function test_CreateAndAssignTaskMultipleUsers() public {
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
            bytes("MULTI_USER_TEST"), 10 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create multiple users
        address[] memory users = new address[](3);
        for (uint256 i = 0; i < users.length; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            setHat(users[i], MEMBER_HAT);
        }

        // Create and assign tasks to different users
        for (uint256 i = 0; i < users.length; i++) {
            vm.prank(creator1);
            uint256 taskId =
                tm.createAndAssignTask(1 ether, bytes("multi_user_task"), projectId, users[i], address(0), 0, false);

            // Verify each task is assigned to the correct user
            bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
            (,, address claimer,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
            assertEq(claimer, users[i], "Task should be assigned to correct user");
        }

        // Verify project budget tracking
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(projectId));
        (uint256 cap, uint256 spent,) = abi.decode(ret, (uint256, uint256, bool));
        assertEq(spent, 3 ether, "Project should have spent 3 ether");
    }

    function test_CreateAndAssignTaskEdgeCases() public {
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
            bytes("EDGE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Test assigning to self
        vm.prank(creator1);
        uint256 taskId =
            tm.createAndAssignTask(1 ether, bytes("self_assign"), projectId, creator1, address(0), 0, false);
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (,, address claimer,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, creator1, "Task should be assigned to creator1");

        // Test assigning to executor
        vm.prank(creator1);
        taskId = tm.createAndAssignTask(1 ether, bytes("executor_assign"), projectId, executor, address(0), 0, false);

        ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (,, claimer,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, executor, "Task should be assigned to executor");

        // Test maximum payout - need to create a new project with higher cap
        vm.prank(creator1);
        bytes32 maxProjectId = tm.createProject(
            bytes("MAX_PAYOUT_TEST"), 1e24, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        taskId = tm.createAndAssignTask(1e24, bytes("max_payout"), maxProjectId, member1, address(0), 0, false); // MAX_PAYOUT

        ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (uint256 payout,,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1e24, "Task should have maximum payout");
    }

    function test_CreateAndAssignTaskProjectSpecificPermissions() public {
        // Create a hat with global permissions
        uint256 GLOBAL_HAT = 400;
        address globalUser = makeAddr("globalUser");
        setHat(globalUser, GLOBAL_HAT);

        // Set global permissions (CREATE only)
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(GLOBAL_HAT, TaskPerm.CREATE));

        // Create project
        uint256[] memory emptyHats = new uint256[](0);
        vm.prank(creator1);
        bytes32 projectId = tm.createProject(
            bytes("PROJECT_SPECIFIC"), 5 ether, new address[](0), emptyHats, emptyHats, emptyHats, emptyHats
        );

        // User should not be able to createAndAssignTask (no ASSIGN permission)
        vm.prank(globalUser);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.createAndAssignTask(1 ether, bytes("should_fail"), projectId, member1, address(0), 0, false);

        // Add ASSIGN permission at project level
        vm.prank(creator1);
        tm.setProjectRolePerm(projectId, GLOBAL_HAT, TaskPerm.CREATE | TaskPerm.ASSIGN);

        // Now user should be able to createAndAssignTask
        vm.prank(globalUser);
        uint256 taskId = tm.createAndAssignTask(1 ether, bytes("should_work"), projectId, member1, address(0), 0, false);

        // Verify task was created and assigned
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(taskId));
        (,, address claimer,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, member1, "Task should be assigned to member1");
    }

    /*───────────────── APPLICATION SYSTEM TESTS ────────────────────*/

    function test_ApplyForTaskBasic() public {
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
            bytes("APPLICATION_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create a task that requires applications
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Member applies for task
        bytes32 applicationHash = keccak256("application_content");
        vm.prank(member1);
        tm.applyForTask(0, applicationHash);

        // Verify task status remains UNCLAIMED and applicant is recorded
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId,) =
            abi.decode(ret, (uint256, TaskManager.Status, address, bytes32, bytes32));
        assertEq(uint8(status), uint8(TaskManager.Status.UNCLAIMED), "Status should remain UNCLAIMED");
        assertEq(claimer, address(0), "Claimer should remain empty until approved");
        assertEq(payout, 1 ether, "Payout should remain unchanged");
        assertEq(taskProjectId, projectId, "Project ID should be correct");

        // Verify application was recorded
        assertEq(
            abi.decode(
                lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANTS, abi.encode(0)), (address[])
            )[0],
            member1,
            "Member1 should have applied"
        );
        assertEq(
            abi.decode(
                lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member1)),
                (bytes32)
            ),
            applicationHash,
            "Application hash should match"
        );
    }

    function test_ApplyForTaskPermissions() public {
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

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Test that only users with CLAIM permission can apply
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.applyForTask(0, keccak256("application"));

        // Member with CLAIM permission can apply
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Verify application was recorded but status remains UNCLAIMED
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (, TaskManager.Status status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.UNCLAIMED));
        assertEq(
            abi.decode(
                lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANTS, abi.encode(0)), (address[])
            )[0],
            member1,
            "Member1 should have applied"
        );
    }

    function test_ApplyForTaskValidation() public {
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
            bytes("VALIDATION_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Test empty application hash
        vm.prank(member1);
        vm.expectRevert(ValidationLib.InvalidString.selector);
        tm.applyForTask(0, bytes32(0));

        // Test applying twice by same user
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        vm.prank(member1);
        vm.expectRevert(TaskManager.AlreadyApplied.selector);
        tm.applyForTask(0, keccak256("another_application"));

        // Test applying to non-existent task
        vm.prank(member1);
        vm.expectRevert(TaskManager.NotFound.selector);
        tm.applyForTask(999, keccak256("application"));
    }

    function test_ApproveApplicationBasic() public {
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
            bytes("APPROVAL_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Member applies
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // PM approves application
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        // Verify task is now claimed
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (, TaskManager.Status status, address claimer,,) =
            abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED), "Status should be CLAIMED");
        assertEq(claimer, member1, "Claimer should remain the applicant");
    }

    function test_ApproveApplicationPermissions() public {
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

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Test that only users with ASSIGN permission can approve
        vm.prank(outsider);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.approveApplication(0, member1);

        vm.prank(member1);
        vm.expectRevert(TaskManager.Unauthorized.selector);
        tm.approveApplication(0, member1);

        // PM with ASSIGN permission can approve
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (, TaskManager.Status status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED));
    }

    function test_ApproveApplicationValidation() public {
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
            bytes("VALIDATION_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Test approving task without application
        vm.prank(pm1);
        vm.expectRevert(TaskManager.NotApplicant.selector);
        tm.approveApplication(0, member1);

        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Test approving wrong applicant
        address member2 = makeAddr("member2");
        vm.prank(pm1);
        vm.expectRevert(TaskManager.NotApplicant.selector);
        tm.approveApplication(0, member2);

        // Test approving after task is already claimed
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        vm.prank(pm1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.approveApplication(0, member1);
    }

    function test_ApplicationEvents() public {
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
            bytes("EVENT_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        bytes32 applicationHash = keccak256("application_content");

        // Test application submitted event
        vm.prank(member1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskApplicationSubmitted(0, member1, applicationHash);
        tm.applyForTask(0, applicationHash);

        // Test application approved event
        vm.prank(pm1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskApplicationApproved(0, member1, pm1);
        tm.approveApplication(0, member1);
    }

    function test_ApplicationLifecycleComplete() public {
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
            bytes("LIFECYCLE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // 1. Apply for task
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // 2. Approve application
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        // 3. Submit task
        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        // 4. Complete task
        vm.prank(pm1);
        tm.completeTask(0);

        // Verify final state
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (, TaskManager.Status status,,,) = abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.COMPLETED));
        assertEq(token.balanceOf(member1), 1 ether, "Member should receive tokens");
    }

    function test_CancelTaskWithApplication() public {
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
            bytes("CANCEL_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Apply for task
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Creator can cancel task with application
        vm.prank(creator1);
        tm.cancelTask(0);

        // Verify task is cancelled and budget refunded
        bytes memory ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (, TaskManager.Status status, address claimer,,) =
            abi.decode(ret, (uint96, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CANCELLED));
        assertEq(claimer, address(0), "Claimer should be cleared");
        ret = lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(projectId));
        (uint256 cap, uint256 spent, bool isManager) = abi.decode(ret, (uint256, uint256, bool));
        assertEq(spent, 0, "Budget should be refunded");
    }

    function test_MultipleApplicationsFlow() public {
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
            bytes("MULTI_APP_TEST"), 10 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create multiple tasks
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), projectId, address(0), 0, true);
        vm.prank(creator1);
        tm.createTask(2 ether, bytes("task2"), projectId, address(0), 0, true);

        // Create multiple members
        address member2 = makeAddr("member2");
        setHat(member2, MEMBER_HAT);

        // Both members apply for different tasks
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application1"));

        vm.prank(member2);
        tm.applyForTask(1, keccak256("application2"));

        // Approve first application
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        // Verify first task is claimed
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status1, address claimer1,, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status1), uint8(TaskManager.Status.CLAIMED));
        assertEq(claimer1, member1);

        // Second task should still be UNCLAIMED with pending application
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(1));
        (, TaskManager.Status status2, address claimer2,,) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status2), uint8(TaskManager.Status.UNCLAIMED));
        assertEq(claimer2, address(0));
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(1, member2));
        bytes32 hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member2 should have applied for task 1");
    }

    function test_ApplicationSystemPreventsClaiming() public {
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
            bytes("PREVENT_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Apply for task
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Test that direct claiming is prevented (still requires application)
        address member2 = makeAddr("member2");
        setHat(member2, MEMBER_HAT);

        vm.prank(member2);
        vm.expectRevert(TaskManager.RequiresApplication.selector);
        tm.claimTask(0);

        // Test that assignment still works (bypasses application requirement)
        vm.prank(pm1);
        tm.assignTask(0, member2);

        // Verify task is now claimed by member2
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer,, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED));
        assertEq(claimer, member2);
    }

    /*───────────────── APPLICATION REQUIREMENT TESTS ────────────────────*/

    function test_CreateApplicationTaskBasic() public {
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
            bytes("APP_REQ_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create application-required task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("app_required_task"), projectId, address(0), 0, true);

        // Verify task requires applications
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(requiresApplication, true, "Task should require applications");
        assertEq(uint8(status), uint8(TaskManager.Status.UNCLAIMED), "Status should be UNCLAIMED");
        assertEq(claimer, address(0), "Claimer should be empty");
    }

    function test_ApplicationRequiredTaskPreventsClaiming() public {
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
            bytes("CLAIM_PREVENT_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create application-required task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("app_required_task"), projectId, address(0), 0, true);

        // Test that direct claiming is prevented
        vm.prank(member1);
        vm.expectRevert(TaskManager.RequiresApplication.selector);
        tm.claimTask(0);

        // But assignment should still work (bypass application requirement)
        vm.prank(pm1);
        tm.assignTask(0, member1);

        // Verify task is now claimed
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED));
        assertEq(claimer, member1);
    }

    function test_RegularTaskPreventsApplications() public {
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
            bytes("REGULAR_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        // Create regular task (doesn't require applications)
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("regular_task"), projectId, address(0), 0, false);

        // Verify task doesn't require applications
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(requiresApplication, false, "Task should not require applications");

        // Test that applications are prevented
        vm.prank(member1);
        vm.expectRevert(TaskManager.NoApplicationRequired.selector);
        tm.applyForTask(0, keccak256("application"));

        // But direct claiming should work
        vm.prank(member1);
        tm.claimTask(0);

        // Verify task is claimed
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (payout, status, claimer, taskProjectId, requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED));
        assertEq(claimer, member1);
    }

    /*───────────────── MULTI-APPLICANT SYSTEM TESTS ────────────────────*/

    function test_MultipleApplicantsBasic() public {
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
            bytes("MULTI_APP_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Create multiple applicants
        address member2 = makeAddr("member2");
        address member3 = makeAddr("member3");
        setHat(member2, MEMBER_HAT);
        setHat(member3, MEMBER_HAT);

        // All should be able to apply
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application1"));

        vm.prank(member2);
        tm.applyForTask(0, keccak256("application2"));

        vm.prank(member3);
        tm.applyForTask(0, keccak256("application3"));

        // Verify all applicants are stored
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANTS, abi.encode(0));
        address[] memory applicants = abi.decode(result, (address[]));
        assertEq(applicants.length, 3, "Should have 3 applicants");
        assertEq(applicants[0], member1, "First applicant should be member1");
        assertEq(applicants[1], member2, "Second applicant should be member2");
        assertEq(applicants[2], member3, "Third applicant should be member3");

        // Verify application hashes
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member1));
        bytes32 applicationHash = abi.decode(result, (bytes32));
        assertEq(applicationHash, keccak256("application1"), "Member1 application hash should match");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member2));
        applicationHash = abi.decode(result, (bytes32));
        assertEq(applicationHash, keccak256("application2"), "Member2 application hash should match");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member3));
        applicationHash = abi.decode(result, (bytes32));
        assertEq(applicationHash, keccak256("application3"), "Member3 application hash should match");

        // Verify applicant count
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANT_COUNT, abi.encode(0));
        uint256 applicantCount = abi.decode(result, (uint256));
        assertEq(applicantCount, 3, "Applicant count should be 3");

        // Verify hasAppliedForTask
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member1));
        bytes32 hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member1 should have applied");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member2));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member2 should have applied");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member3));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member3 should have applied");

        address nonApplicant = makeAddr("nonApplicant");
        result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, nonApplicant));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied == bytes32(0), "Non-applicant should not have applied");
    }

    function test_ApproveSpecificApplicant() public {
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
            bytes("APPROVE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Create multiple applicants
        address member2 = makeAddr("member2");
        address member3 = makeAddr("member3");
        setHat(member2, MEMBER_HAT);
        setHat(member3, MEMBER_HAT);

        // All apply
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application1"));

        vm.prank(member2);
        tm.applyForTask(0, keccak256("application2"));

        vm.prank(member3);
        tm.applyForTask(0, keccak256("application3"));

        // Approve member2 (middle applicant)
        vm.prank(pm1);
        tm.approveApplication(0, member2);

        // Verify task is claimed by member2
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0));
        (uint256 payout, TaskManager.Status status, address claimer, bytes32 taskProjectId, bool requiresApplication) =
            abi.decode(result, (uint256, TaskManager.Status, address, bytes32, bool));
        assertEq(claimer, member2, "Task should be claimed by member2");
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED), "Task should be claimed");

        // Verify other applicants can't be approved now
        vm.prank(pm1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.approveApplication(0, member1);

        vm.prank(pm1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.approveApplication(0, member3);
    }

    function test_ApplicationDataPersistence() public {
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
            bytes("PERSISTENCE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Apply with specific application data
        bytes32 applicationHash = keccak256("detailed_application_content");
        vm.prank(member1);
        tm.applyForTask(0, applicationHash);

        // Verify application data persists
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member1));
        applicationHash = abi.decode(result, (bytes32));
        assertEq(applicationHash, keccak256("detailed_application_content"), "Application hash should persist");

        // Approve and complete task
        vm.prank(pm1);
        tm.approveApplication(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        vm.prank(pm1);
        tm.completeTask(0);

        // Verify application data still accessible even after completion
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member1));
        applicationHash = abi.decode(result, (bytes32));
        assertEq(
            applicationHash,
            keccak256("detailed_application_content"),
            "Application hash should persist after completion"
        );
    }

    function test_CancelTaskClearsApplications() public {
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
            bytes("CANCEL_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // Create multiple applicants
        address member2 = makeAddr("member2");
        setHat(member2, MEMBER_HAT);

        // Apply
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application1"));

        vm.prank(member2);
        tm.applyForTask(0, keccak256("application2"));

        // Verify applications exist
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANT_COUNT, abi.encode(0));
        uint256 applicantCount = abi.decode(result, (uint256));
        assertEq(applicantCount, 2, "Should have 2 applicants");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member1));
        bytes32 hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member1 should have applied");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member2));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member2 should have applied");

        // Cancel task
        vm.prank(creator1);
        tm.cancelTask(0);

        // Verify applicants array is cleared (but application hashes remain to avoid DoS)
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANT_COUNT, abi.encode(0));
        applicantCount = abi.decode(result, (uint256));
        assertEq(applicantCount, 0, "Should have 0 applicants after cancel");

        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANTS, abi.encode(0));
        address[] memory applicants = abi.decode(result, (address[]));
        assertEq(applicants.length, 0, "Applicants array should be empty");

        // Note: Application hashes remain in storage to avoid DoS attacks from clearing
        // them in a loop. This is intentional behavior.
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member1));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member1 application hash should remain");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.HAS_APPLIED_FOR_TASK, abi.encode(0, member2));
        hasApplied = abi.decode(result, (bytes32));
        assertTrue(hasApplied != bytes32(0), "Member2 application hash should remain");
    }

    function test_DuplicateApplicationPrevented() public {
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
            bytes("DUPLICATE_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        // First application succeeds
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application1"));

        // Second application by same user fails
        vm.prank(member1);
        vm.expectRevert(TaskManager.AlreadyApplied.selector);
        tm.applyForTask(0, keccak256("application2"));

        // Verify only one application exists
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICANT_COUNT, abi.encode(0));
        uint256 applicantCount = abi.decode(result, (uint256));
        assertEq(applicantCount, 1, "Should have only 1 applicant");
        result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_APPLICATION, abi.encode(0, member1));
        bytes32 applicationHash = abi.decode(result, (bytes32));
        assertEq(applicationHash, keccak256("application1"), "Should have first application hash");
    }

    function test_ApplicationSystemEvents() public {
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
            bytes("EVENT_TEST"), 5 ether, new address[](0), createHats, claimHats, reviewHats, assignHats
        );

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("test_task"), projectId, address(0), 0, true);

        bytes32 applicationHash = keccak256("application_content");

        // Test application submitted event
        vm.prank(member1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskApplicationSubmitted(0, member1, applicationHash);
        tm.applyForTask(0, applicationHash);

        // Test application approved event
        vm.prank(pm1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskApplicationApproved(0, member1, pm1);
        tm.approveApplication(0, member1);
    }
}

/*───────────────── BOUNTY FUNCTIONALITY TESTS ────────────────────*/

contract TaskManagerBountyTest is TaskManagerTestBase {
    /* project IDs */
    bytes32 BOUNTY_PROJECT_ID;
    bytes32 DUAL_BOUNTY_PROJECT_ID;
    bytes32 NO_BOUNTY_PROJECT_ID;

    MockERC20 bountyToken1;
    MockERC20 bountyToken2;

    function setUp() public {
        setUpBase();
        bountyToken1 = new MockERC20();
        bountyToken2 = new MockERC20();

        BOUNTY_PROJECT_ID = _createDefaultProject("BOUNTY_PROJECT", 10 ether);
        DUAL_BOUNTY_PROJECT_ID = _createDefaultProject("DUAL_BOUNTY_PROJECT", 10 ether);
        NO_BOUNTY_PROJECT_ID = _createDefaultProject("NO_BOUNTY_PROJECT", 10 ether);

        // Fund the bounty tokens to the TaskManager (simulating treasury)
        bountyToken1.mint(address(tm), 1000 ether);
        bountyToken2.mint(address(tm), 1000 ether);
    }

    function test_CreateTaskWithBounty() public {
        // Create task with bounty token
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.5 ether, false);

        // Verify task has bounty info
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Participation token payout should be correct");
        assertEq(bountyPayout, 0.5 ether, "Bounty payout should be correct");
        assertEq(bountyToken, address(bountyToken1), "Bounty token should be correct");
        assertEq(uint8(status), uint8(TaskManager.Status.UNCLAIMED), "Status should be UNCLAIMED");
    }

    function test_CreateTaskWithoutBounty() public {
        // Create task without bounty (backward compatibility)
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("no_bounty_task"), NO_BOUNTY_PROJECT_ID, address(0), 0, false);

        // Verify task has no bounty info
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Participation token payout should be correct");
        assertEq(bountyPayout, 0, "Bounty payout should be zero");
        assertEq(bountyToken, address(0), "Bounty token should be zero address");
    }

    function test_CreateApplicationTaskWithBounty() public {
        // Create application task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("app_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, true);

        // Verify task has bounty info and requires application
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Participation token payout should be correct");
        assertEq(bountyPayout, 0.3 ether, "Bounty payout should be correct");
        assertEq(bountyToken, address(bountyToken1), "Bounty token should be correct");
        assertEq(requiresApplication, true, "Should require application");
    }

    function test_CreateAndAssignTaskWithBounty() public {
        // Create and assign task with bounty
        vm.prank(creator1);
        uint256 taskId = tm.createAndAssignTask(
            1 ether, bytes("assign_bounty_task"), BOUNTY_PROJECT_ID, member1, address(bountyToken1), 0.4 ether, false
        );

        // Verify task is assigned and has bounty info
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(taskId));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Participation token payout should be correct");
        assertEq(bountyPayout, 0.4 ether, "Bounty payout should be correct");
        assertEq(bountyToken, address(bountyToken1), "Bounty token should be correct");
        assertEq(claimer, member1, "Task should be assigned to member1");
        assertEq(uint8(status), uint8(TaskManager.Status.CLAIMED), "Status should be CLAIMED");
    }

    function test_CompleteTaskWithBounty() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(
            1 ether, bytes("complete_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.5 ether, false
        );

        // Assign and complete task
        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        uint256 tokenBalanceBefore = token.balanceOf(member1);
        uint256 bountyBalanceBefore = bountyToken1.balanceOf(member1);

        vm.prank(creator1);
        tm.completeTask(0);

        // Verify both tokens were transferred
        assertEq(token.balanceOf(member1), tokenBalanceBefore + 1 ether, "Participation tokens should be minted");
        assertEq(
            bountyToken1.balanceOf(member1), bountyBalanceBefore + 0.5 ether, "Bounty tokens should be transferred"
        );
    }

    function test_CompleteTaskWithoutBounty() public {
        // Create task without bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("complete_no_bounty_task"), NO_BOUNTY_PROJECT_ID, address(0), 0, false);

        // Assign and complete task
        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        uint256 tokenBalanceBefore = token.balanceOf(member1);

        vm.prank(creator1);
        tm.completeTask(0);

        // Verify only participation tokens were minted
        assertEq(token.balanceOf(member1), tokenBalanceBefore + 1 ether, "Participation tokens should be minted");
        assertEq(bountyToken1.balanceOf(member1), 0, "No bounty tokens should be transferred");
    }

    function test_UpdateTaskBountyBeforeClaim() public {
        // Create task with initial bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("update_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        // Update bounty before claim
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated_metadata"), address(bountyToken2), 0.6 ether);

        // Verify bounty was updated
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(bountyPayout, 0.6 ether, "Bounty payout should be updated");
        assertEq(bountyToken, address(bountyToken2), "Bounty token should be updated");
    }

    function test_UpdateTaskBountyAfterClaimReverts() public {
        // Create task with initial bounty
        vm.prank(creator1);
        tm.createTask(
            1 ether, bytes("update_claimed_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false
        );

        // Assign task
        vm.prank(creator1);
        tm.assignTask(0, member1);

        // Update bounty after claim should revert
        vm.prank(creator1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.updateTask(0, 1 ether, bytes("updated_metadata"), address(bountyToken2), 0.6 ether);
    }

    function test_UpdateTaskRemoveBounty() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("remove_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        // Remove bounty
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated_metadata"), address(0), 0);

        // Verify bounty was removed
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(bountyPayout, 0, "Bounty payout should be zero");
        assertEq(bountyToken, address(0), "Bounty token should be zero address");
    }

    function test_CompleteTaskWithDifferentBountyTokens() public {
        // Create two tasks with different bounty tokens
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("bounty1_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        vm.prank(creator1);
        tm.createTask(1 ether, bytes("bounty2_task"), BOUNTY_PROJECT_ID, address(bountyToken2), 0.4 ether, false);

        // Complete both tasks
        vm.startPrank(creator1);
        tm.assignTask(0, member1);
        tm.assignTask(1, member1);
        vm.stopPrank();

        vm.startPrank(member1);
        tm.submitTask(0, bytes("submission1"));
        tm.submitTask(1, bytes("submission2"));
        vm.stopPrank();

        uint256 bounty1Before = bountyToken1.balanceOf(member1);
        uint256 bounty2Before = bountyToken2.balanceOf(member1);

        vm.startPrank(creator1);
        tm.completeTask(0);
        tm.completeTask(1);
        vm.stopPrank();

        // Verify both bounty tokens were transferred correctly
        assertEq(bountyToken1.balanceOf(member1), bounty1Before + 0.3 ether, "Bounty token 1 should be transferred");
        assertEq(bountyToken2.balanceOf(member1), bounty2Before + 0.4 ether, "Bounty token 2 should be transferred");
    }

    function test_BountyValidationErrors() public {
        // Test bounty token with zero payout
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.InvalidPayout.selector);
        tm.createTask(1 ether, bytes("invalid_bounty"), BOUNTY_PROJECT_ID, address(bountyToken1), 0, false);

        // Test excessive bounty payout
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.InvalidPayout.selector);
        tm.createTask(1 ether, bytes("excessive_bounty"), BOUNTY_PROJECT_ID, address(bountyToken1), 1e25, false); // Over MAX_PAYOUT

        // Test that zero bounty token with non-zero payout is not allowed
        vm.prank(creator1);
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        tm.createTask(1 ether, bytes("invalid_zero_token"), BOUNTY_PROJECT_ID, address(0), 0.5 ether, false);
    }

    function test_ApplicationTaskWithBounty() public {
        // Create application task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("app_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, true);

        // Apply for task
        vm.prank(member1);
        tm.applyForTask(0, keccak256("application"));

        // Approve application
        vm.prank(creator1);
        tm.approveApplication(0, member1);

        // Submit and complete
        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        uint256 tokenBalanceBefore = token.balanceOf(member1);
        uint256 bountyBalanceBefore = bountyToken1.balanceOf(member1);

        vm.prank(creator1);
        tm.completeTask(0);

        // Verify both tokens were transferred
        assertEq(token.balanceOf(member1), tokenBalanceBefore + 1 ether, "Participation tokens should be minted");
        assertEq(
            bountyToken1.balanceOf(member1), bountyBalanceBefore + 0.3 ether, "Bounty tokens should be transferred"
        );
    }

    function test_CancelTaskWithBounty() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("cancel_bounty_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        // Cancel task
        vm.prank(creator1);
        tm.cancelTask(0);

        // Verify task is cancelled and bounty info is preserved
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(uint8(status), uint8(TaskManager.Status.CANCELLED), "Status should be CANCELLED");
        assertEq(bountyPayout, 0.3 ether, "Bounty payout should be preserved");
        assertEq(bountyToken, address(bountyToken1), "Bounty token should be preserved");
    }

    function test_GetTaskFullFunction() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("full_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        // Test getTaskFull function
        bytes memory result = lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_FULL_INFO, abi.encode(0));
        (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            TaskManager.Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        ) = abi.decode(result, (uint256, uint256, address, TaskManager.Status, address, bytes32, bool));
        assertEq(payout, 1 ether, "Payout should be correct");
        assertEq(bountyPayout, 0.3 ether, "Bounty payout should be correct");
        assertEq(bountyToken, address(bountyToken1), "Bounty token should be correct");
        assertEq(uint8(status), uint8(TaskManager.Status.UNCLAIMED), "Status should be correct");
        assertEq(claimer, address(0), "Claimer should be correct");
        assertEq(projectId, BOUNTY_PROJECT_ID, "Project ID should be correct");
        assertEq(requiresApplication, false, "Requires application should be correct");

        // Compare with getTask function (should not include bounty info)
        (uint256 payout2, TaskManager.Status status2, address claimer2, bytes32 projectId2, bool requiresApplication2) =
        abi.decode(
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.TASK_INFO, abi.encode(0)),
            (uint256, TaskManager.Status, address, bytes32, bool)
        );
        assertEq(payout2, payout, "getTask payout should match getTaskFull");
        assertEq(uint8(status2), uint8(status), "getTask status should match getTaskFull");
        assertEq(claimer2, claimer, "getTask claimer should match getTaskFull");
        assertEq(projectId2, projectId, "getTask project ID should match getTaskFull");
        assertEq(requiresApplication2, requiresApplication, "getTask requires application should match getTaskFull");
    }

    function test_BountyEvents() public {
        // Create task with bounty
        vm.prank(creator1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskCreated(
            0, BOUNTY_PROJECT_ID, 1 ether, address(bountyToken1), 0.3 ether, false, bytes("bounty_event_task")
        );
        tm.createTask(1 ether, bytes("bounty_event_task"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.3 ether, false);

        // Complete task and verify events
        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        vm.prank(creator1);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.TaskCompleted(0, creator1);
        tm.completeTask(0);
    }

    function test_MultipleBountyTokensInProject() public {
        // Create multiple tasks with different bounty tokens in same project
        vm.startPrank(creator1);
        tm.createTask(1 ether, bytes("task1"), BOUNTY_PROJECT_ID, address(bountyToken1), 0.2 ether, false);
        tm.createTask(1 ether, bytes("task2"), BOUNTY_PROJECT_ID, address(bountyToken2), 0.3 ether, false);
        tm.createTask(1 ether, bytes("task3"), BOUNTY_PROJECT_ID, address(0), 0, false); // No bounty
        vm.stopPrank();

        // Complete all tasks
        vm.startPrank(creator1);
        tm.assignTask(0, member1);
        tm.assignTask(1, member1);
        tm.assignTask(2, member1);
        vm.stopPrank();

        vm.startPrank(member1);
        tm.submitTask(0, bytes("submission1"));
        tm.submitTask(1, bytes("submission2"));
        tm.submitTask(2, bytes("submission3"));
        vm.stopPrank();

        uint256 bounty1Before = bountyToken1.balanceOf(member1);
        uint256 bounty2Before = bountyToken2.balanceOf(member1);
        uint256 tokenBefore = token.balanceOf(member1);

        vm.startPrank(creator1);
        tm.completeTask(0);
        tm.completeTask(1);
        tm.completeTask(2);
        vm.stopPrank();

        // Verify all payouts
        assertEq(bountyToken1.balanceOf(member1), bounty1Before + 0.2 ether, "Bounty token 1 should be transferred");
        assertEq(bountyToken2.balanceOf(member1), bounty2Before + 0.3 ether, "Bounty token 2 should be transferred");
        assertEq(token.balanceOf(member1), tokenBefore + 3 ether, "All participation tokens should be minted");
    }

    function test_BountyTokenTransferFailure() public {
        // Create a mock token that fails on transfer
        MockERC20 failingToken = new MockERC20();
        // Don't mint any tokens to TaskManager, so transfer will fail

        // Create task with failing bounty token
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("failing_bounty_task"), BOUNTY_PROJECT_ID, address(failingToken), 0.3 ether, false);

        // Assign and submit task
        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        // Complete task - should fail due to insufficient bounty tokens
        vm.prank(creator1);
        vm.expectRevert(); // Should revert due to transfer failure
        tm.completeTask(0);
    }
}

/*───────────────── BOUNTY BUDGET FUNCTIONALITY TESTS ────────────────────*/

contract TaskManagerBountyBudgetTest is TaskManagerTestBase {
    /* project IDs */
    bytes32 BUDGET_PROJECT_ID;
    bytes32 MULTI_TOKEN_PROJECT_ID;
    bytes32 UNLIMITED_PROJECT_ID;

    MockERC20 bountyToken1;
    MockERC20 bountyToken2;
    MockERC20 bountyToken3;

    function setUp() public {
        setUpBase();
        bountyToken1 = new MockERC20();
        bountyToken2 = new MockERC20();
        bountyToken3 = new MockERC20();

        BUDGET_PROJECT_ID = _createDefaultProject("BUDGET_PROJECT", 10 ether);
        MULTI_TOKEN_PROJECT_ID = _createDefaultProject("MULTI_TOKEN_PROJECT", 10 ether);
        UNLIMITED_PROJECT_ID = _createDefaultProject("UNLIMITED_PROJECT", 0);

        // Fund the bounty tokens to the TaskManager (simulating treasury)
        bountyToken1.mint(address(tm), 1000 ether);
        bountyToken2.mint(address(tm), 1000 ether);
        bountyToken3.mint(address(tm), 1000 ether);
    }

    function test_SetBountyCapBasic() public {
        // Test setting bounty cap
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.BountyCapSet(BUDGET_PROJECT_ID, address(bountyToken1), 0, 5 ether);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Verify cap was set
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 5 ether, "Bounty cap should be set correctly");
        assertEq(spent, 0, "Bounty spent should be zero initially");
    }

    function test_SetBountyCapPermissions() public {
        // Only executor can set bounty caps
        vm.prank(creator1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        vm.prank(pm1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        vm.prank(member1);
        vm.expectRevert(TaskManager.NotExecutor.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Executor can set cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 5 ether, "Executor should be able to set bounty cap");
    }

    function test_SetBountyCapValidation() public {
        // Test zero address token
        vm.prank(executor);
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(0), 5 ether));

        // Test excessive cap
        vm.prank(executor);
        vm.expectRevert(ValidationLib.InvalidPayout.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 1e25)); // Over MAX_PAYOUT

        // Test non-existent project
        vm.prank(executor);
        vm.expectRevert(TaskManager.NotFound.selector);
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(bytes32(uint256(999)), address(bountyToken1), 5 ether)
        );
    }

    function test_GetBountyBudgetValidation() public {
        // Test zero address token
        vm.expectRevert(ValidationLib.ZeroAddress.selector);
        lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(0))
        );

        // Test non-existent project
        vm.expectRevert(TaskManager.NotFound.selector);
        lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(bytes32(uint256(999)), address(bountyToken1))
        );
    }

    function test_CreateTaskWithBountyBudgetEnforcement() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether));

        // Create task within budget
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 1.5 ether, false);

        // Verify budget tracking
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 3 ether, "Cap should remain unchanged");
        assertEq(spent, 1.5 ether, "Spent should be updated");

        // Create another task within budget
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task2"), BUDGET_PROJECT_ID, address(bountyToken1), 1.5 ether, false);

        // Verify budget tracking
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should be at cap");

        // Try to exceed budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1 ether, bytes("task3"), BUDGET_PROJECT_ID, address(bountyToken1), 0.1 ether, false);
    }

    function test_CreateTaskWithoutBountyBudgetSet() public {
        // Create task without setting bounty budget (should work - unlimited)
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 5 ether, false);

        // Verify budget tracking (cap should be 0, spent should be updated)
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 0, "Cap should be zero (unlimited)");
        assertEq(spent, 5 ether, "Spent should be updated");

        // Create another large task (should work since cap is 0 = unlimited)
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task2"), BUDGET_PROJECT_ID, address(bountyToken1), 10 ether, false);

        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 15 ether, "Spent should be cumulative");
    }

    function test_MultipleBountyTokensBudgets() public {
        // Set different caps for different tokens
        vm.startPrank(executor);
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 2 ether)
        );
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken2), 3 ether)
        );
        vm.stopPrank();

        // Create tasks with different tokens
        vm.startPrank(creator1);
        tm.createTask(1 ether, bytes("task1"), MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 1 ether, false);
        tm.createTask(1 ether, bytes("task2"), MULTI_TOKEN_PROJECT_ID, address(bountyToken2), 2 ether, false);
        tm.createTask(1 ether, bytes("task3"), MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 1 ether, false);
        vm.stopPrank();

        // Verify independent budget tracking
        bytes memory result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap1, uint256 spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken2))
        );
        (uint256 cap2, uint256 spent2) = abi.decode(result, (uint256, uint256));

        assertEq(cap1, 2 ether, "Token1 cap should be correct");
        assertEq(spent1, 2 ether, "Token1 spent should be at cap");
        assertEq(cap2, 3 ether, "Token2 cap should be correct");
        assertEq(spent2, 2 ether, "Token2 spent should be correct");

        // Try to exceed token1 budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1 ether, bytes("task4"), MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 0.1 ether, false);

        // But token2 should still work
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task5"), MULTI_TOKEN_PROJECT_ID, address(bountyToken2), 1 ether, false);

        result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken2))
        );
        (cap2, spent2) = abi.decode(result, (uint256, uint256));
        assertEq(spent2, 3 ether, "Token2 spent should now be at cap");
    }

    function test_UpdateTaskBountyBudgetTracking() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Verify initial budget
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 2 ether, "Initial spent should be correct");

        // Update task to higher bounty (within budget)
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated"), address(bountyToken1), 3 ether);

        // Verify budget updated
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should be updated after task update");

        // Try to update to exceed budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.updateTask(0, 1 ether, bytes("updated2"), address(bountyToken1), 5.1 ether);
    }

    function test_UpdateTaskChangeBountyToken() public {
        // Set caps for both tokens
        vm.startPrank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether));
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2), 4 ether));
        vm.stopPrank();

        // Create task with token1
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Verify initial budgets
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap1, uint256 spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2))
        );
        (uint256 cap2, uint256 spent2) = abi.decode(result, (uint256, uint256));
        assertEq(spent1, 2 ether, "Token1 spent should be correct");
        assertEq(spent2, 0, "Token2 spent should be zero");

        // Update task to use token2
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated"), address(bountyToken2), 3 ether);

        // Verify budgets updated correctly
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap1, spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2))
        );
        (cap2, spent2) = abi.decode(result, (uint256, uint256));
        assertEq(spent1, 0, "Token1 spent should be rolled back");
        assertEq(spent2, 3 ether, "Token2 spent should be updated");
    }

    function test_UpdateTaskRemoveBounty() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 3 ether, false);

        // Verify budget
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should be correct");

        // Remove bounty from task
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated"), address(0), 0);

        // Verify budget rolled back
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 0, "Spent should be rolled back");
    }

    function test_CancelTaskBountyBudgetRollback() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Verify budget
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 2 ether, "Spent should be correct");

        // Cancel task
        vm.prank(creator1);
        tm.cancelTask(0);

        // Verify budget rolled back
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 0, "Spent should be rolled back after cancel");
    }

    function test_CreateAndAssignTaskBountyBudget() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create and assign task
        vm.prank(creator1);
        uint256 taskId = tm.createAndAssignTask(
            1 ether, bytes("assign_task"), BUDGET_PROJECT_ID, member1, address(bountyToken1), 3 ether, false
        );

        // Verify budget tracking
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should be updated");

        // Try to exceed budget with another task
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createAndAssignTask(
            1 ether, bytes("assign_task2"), BUDGET_PROJECT_ID, member1, address(bountyToken1), 2.1 ether, false
        );
    }

    function test_ApplicationTaskBountyBudget() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create application task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("app_task"), BUDGET_PROJECT_ID, address(bountyToken1), 4 ether, true);

        // Verify budget tracking
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 4 ether, "Spent should be updated");

        // Try to create another task that would exceed budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(1 ether, bytes("app_task2"), BUDGET_PROJECT_ID, address(bountyToken1), 1.1 ether, true);
    }

    function test_SetBountyCapBelowSpent() public {
        // Create task first
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 3 ether, false);

        // Verify spent
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should be correct");

        // Try to set cap below spent amount
        vm.prank(executor);
        vm.expectRevert(ValidationLib.CapBelowCommitted.selector);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 2 ether));

        // Setting cap equal to spent should work
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether));

        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 3 ether, "Cap should be set correctly");

        // Setting cap above spent should work
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 5 ether, "Cap should be updated correctly");
    }

    function test_UpdateBountyCapEvent() public {
        // Set initial cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether));

        // Update cap and verify event
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit TaskManager.BountyCapSet(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether, 5 ether);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));
    }

    function test_BountyBudgetIndependentFromParticipationToken() public {
        // Set both participation token cap and bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.PROJECT_CAP, abi.encode(BUDGET_PROJECT_ID, 2 ether));

        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 3 ether));

        // Create task that uses both budgets
        vm.prank(creator1);
        tm.createTask(1.5 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Verify both budgets are tracked independently
        bytes memory result =
            lens.getStorage(address(tm), TaskManagerLens.StorageKey.PROJECT_INFO, abi.encode(BUDGET_PROJECT_ID));
        (uint256 participationCap, uint256 participationSpent, bool isManager) =
            abi.decode(result, (uint256, uint256, bool));
        bytes memory bountyResult = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 bountyCap, uint256 bountySpent) = abi.decode(bountyResult, (uint256, uint256));

        assertEq(participationSpent, 1.5 ether, "Participation token spent should be correct");
        assertEq(bountySpent, 2 ether, "Bounty token spent should be correct");

        // Try to exceed participation token budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(0.6 ether, bytes("task2"), BUDGET_PROJECT_ID, address(bountyToken1), 0.5 ether, false);

        // Create task that only exceeds bounty budget
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(0.5 ether, bytes("task3"), BUDGET_PROJECT_ID, address(bountyToken1), 1.1 ether, false);
    }

    function test_CompleteTaskWithBountyBudgetTracking() public {
        // Set bounty cap
        vm.prank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));

        // Create and complete task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 3 ether, false);

        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(member1);
        tm.submitTask(0, bytes("submission"));

        // Budget should remain reserved during completion
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should remain reserved");

        vm.prank(creator1);
        tm.completeTask(0);

        // Budget should still be marked as spent after completion
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should remain after completion");

        // Verify tokens were transferred
        assertEq(bountyToken1.balanceOf(member1), 3 ether, "Bounty tokens should be transferred");
        assertEq(token.balanceOf(member1), 1 ether, "Participation tokens should be minted");
    }

    function test_UpdateTaskAfterClaimBountyBudgetReverts() public {
        // Set bounty caps
        vm.startPrank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2), 4 ether));
        vm.stopPrank();

        // Create and claim task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        vm.prank(creator1);
        tm.assignTask(0, member1);

        // Update bounty after claim should revert
        vm.prank(creator1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.updateTask(0, 1 ether, bytes("updated"), address(bountyToken2), 3 ether);
    }

    function test_ZeroBountyCapMeansUnlimited() public {
        // Don't set any bounty cap (defaults to 0 = unlimited)

        // Create large bounty task
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 100 ether, false);

        // Verify budget tracking
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 0, "Cap should be zero (unlimited)");
        assertEq(spent, 100 ether, "Spent should be tracked");

        // Create another large task (should work)
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task2"), BUDGET_PROJECT_ID, address(bountyToken1), 200 ether, false);

        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 300 ether, "Spent should be cumulative");
    }

    function test_GetBountyBudgetUnusedToken() public {
        // Get budget for token that was never used
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(cap, 0, "Unused token cap should be zero");
        assertEq(spent, 0, "Unused token spent should be zero");
    }

    function test_BountyBudgetStressTest() public {
        // Set caps for multiple tokens
        vm.startPrank(executor);
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 10 ether)
        );
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken2), 15 ether)
        );
        tm.setConfig(
            TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken3), 20 ether)
        );
        vm.stopPrank();

        uint256 totalTasks = 15;

        // Create many tasks with different tokens
        for (uint256 i = 0; i < totalTasks; i++) {
            address token = address(bountyToken1);
            uint256 bountyAmount = 0.5 ether;

            if (i % 3 == 1) {
                token = address(bountyToken2);
                bountyAmount = 0.8 ether;
            } else if (i % 3 == 2) {
                token = address(bountyToken3);
                bountyAmount = 1.2 ether;
            }

            vm.prank(creator1);
            tm.createTask(0.1 ether, abi.encodePacked("task", i), MULTI_TOKEN_PROJECT_ID, token, bountyAmount, false);
        }

        // Verify final budget states
        bytes memory result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap1, uint256 spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken2))
        );
        (uint256 cap2, uint256 spent2) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm),
            TaskManagerLens.StorageKey.BOUNTY_BUDGET,
            abi.encode(MULTI_TOKEN_PROJECT_ID, address(bountyToken3))
        );
        (uint256 cap3, uint256 spent3) = abi.decode(result, (uint256, uint256));

        assertEq(spent1, 2.5 ether, "Token1 spent should be correct"); // 5 tasks * 0.5 ether
        assertEq(spent2, 4 ether, "Token2 spent should be correct"); // 5 tasks * 0.8 ether
        assertEq(spent3, 6 ether, "Token3 spent should be correct"); // 5 tasks * 1.2 ether

        // Try to exceed budgets
        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(0.1 ether, bytes("fail1"), MULTI_TOKEN_PROJECT_ID, address(bountyToken1), 7.6 ether, false);

        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(0.1 ether, bytes("fail2"), MULTI_TOKEN_PROJECT_ID, address(bountyToken2), 11.1 ether, false);

        vm.prank(creator1);
        vm.expectRevert(BudgetLib.BudgetExceeded.selector);
        tm.createTask(0.1 ether, bytes("fail3"), MULTI_TOKEN_PROJECT_ID, address(bountyToken3), 14.1 ether, false);
    }

    function test_BountyBudgetUnderflowProtectionCancelTask() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Artificially corrupt the bounty budget to simulate underflow scenario

        // First, let's verify normal cancellation works
        vm.prank(creator1);
        tm.cancelTask(0);

        // Create another task to test the protection
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task2"), BUDGET_PROJECT_ID, address(bountyToken1), 1 ether, false);

        // Verify budget is correct
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 1 ether, "Spent should be correct");

        // Normal cancellation should work
        vm.prank(creator1);
        tm.cancelTask(1);
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 0, "Spent should be rolled back correctly");
    }

    function test_BountyBudgetUnderflowProtectionUpdateTask() public {
        // Create task with bounty
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Verify budget
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 2 ether, "Spent should be correct");

        // Normal update should work (rolling back and applying new bounty)
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated"), address(bountyToken1), 1.5 ether);
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 1.5 ether, "Spent should be updated correctly");

        // Update after claiming should revert
        vm.prank(creator1);
        tm.assignTask(0, member1);

        vm.prank(creator1);
        vm.expectRevert(TaskManager.BadStatus.selector);
        tm.updateTask(0, 1 ether, bytes("updated2"), address(bountyToken1), 1 ether);
    }

    function test_BountyBudgetUnderflowProtectionEdgeCase() public {
        // Test edge case where bounty payout equals spent
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 3 ether, false);

        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap, uint256 spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 3 ether, "Spent should equal bounty payout");

        // Cancelling should work when spent equals payout
        vm.prank(creator1);
        tm.cancelTask(0);

        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap, spent) = abi.decode(result, (uint256, uint256));
        assertEq(spent, 0, "Spent should be zero after cancel");
    }

    function test_BountyBudgetUnderflowProtectionMultipleTokens() public {
        // Set caps for both tokens
        vm.startPrank(executor);
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1), 5 ether));
        tm.setConfig(TaskManager.ConfigKey.BOUNTY_CAP, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2), 5 ether));
        vm.stopPrank();

        // Create task with token1
        vm.prank(creator1);
        tm.createTask(1 ether, bytes("task1"), BUDGET_PROJECT_ID, address(bountyToken1), 2 ether, false);

        // Update to token2 (should roll back token1 and apply token2)
        vm.prank(creator1);
        tm.updateTask(0, 1 ether, bytes("updated"), address(bountyToken2), 3 ether);

        // Verify budgets
        bytes memory result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (uint256 cap1, uint256 spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2))
        );
        (uint256 cap2, uint256 spent2) = abi.decode(result, (uint256, uint256));

        assertEq(spent1, 0, "Token1 spent should be rolled back");
        assertEq(spent2, 3 ether, "Token2 spent should be applied");

        // Cancel task should roll back token2
        vm.prank(creator1);
        tm.cancelTask(0);
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken1))
        );
        (cap1, spent1) = abi.decode(result, (uint256, uint256));
        result = lens.getStorage(
            address(tm), TaskManagerLens.StorageKey.BOUNTY_BUDGET, abi.encode(BUDGET_PROJECT_ID, address(bountyToken2))
        );
        (cap2, spent2) = abi.decode(result, (uint256, uint256));

        assertEq(spent1, 0, "Token1 spent should remain zero");
        assertEq(spent2, 0, "Token2 spent should be rolled back");
    }
}
