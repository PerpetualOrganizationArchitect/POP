// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/*──────── OpenZeppelin Upgradeables ────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*────────── Internal Libraries ──────────*/
import {TaskPerm} from "./libs/TaskPerm.sol";
import {BudgetLib} from "./libs/BudgetLib.sol";
import {ValidationLib} from "./libs/ValidationLib.sol";

/*────────── External Hats interface ──────────*/
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";

/*────────── External Interfaces ──────────*/
interface IParticipationToken is IERC20 {
    function mint(address, uint256) external;
}

/*────────────────────── Contract ───────────────────────*/
contract TaskManager is Initializable, ContextUpgradeable {
    using SafeERC20 for IERC20;
    using BudgetLib for BudgetLib.Budget;
    using ValidationLib for address;
    using ValidationLib for bytes;

    /*──────── Errors ───────*/
    error NotFound();
    error BadStatus();
    error NotCreator();
    error NotClaimer();
    error NotExecutor();
    error NotDeployer();
    error Unauthorized();
    error NotApplicant();
    error AlreadyApplied();
    error RequiresApplication();
    error NoApplicationRequired();
    error InvalidIndex();
    error SelfReviewNotAllowed();
    error ArrayLengthMismatch();
    error EmptyBatch();
    error InvalidCapMask();

    /*──────── Constants ─────*/
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*──────── Enums ─────*/
    enum HatType {
        CREATOR
    }

    enum ConfigKey {
        EXECUTOR,
        CREATOR_HAT_ALLOWED,
        ROLE_PERM,
        PROJECT_ROLE_PERM,
        BOUNTY_CAP,
        PROJECT_MANAGER,
        PROJECT_CAP
    }

    /*──────── Data Types ────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    struct Task {
        bytes32 projectId; // slot 1: full 32 bytes
        uint96 payout; // slot 2: 12 bytes (supports up to 7e28, well over 1e24 cap), voting token payout
        address claimer; // slot 2: 20 bytes (total 32 bytes in slot 2)
        uint96 bountyPayout; // slot 3: 12 bytes, additional payout in bounty currency
        bool requiresApplication; // slot 3: 1 byte
        Status status; // slot 3: 1 byte (enum fits in 1 byte)
        address bountyToken; // slot 4: 20 bytes (optimized packing: small fields grouped together)
    }

    struct Project {
        mapping(address => bool) managers; // slot 0: mapping (full slot)
        uint128 cap; // slot 1: 16 bytes — PT cap (0 = unlimited, minted tokens)
        uint128 spent; // slot 1: 16 bytes — PT committed spend
        bool exists; // slot 2: 1 byte (separate slot for cleaner access)
        // Bounty budgets use BudgetLib semantics: cap 0 = DISABLED, UNLIMITED = no limit
        mapping(address => BudgetLib.Budget) bountyBudgets; // per-token ERC-20 budget
    }

    /*──────── Bootstrap Config Structs ───────*/
    struct BootstrapProjectConfig {
        bytes title;
        bytes32 metadataHash;
        uint256 cap;
        address[] managers;
        // Per-project capability hat overrides. A value of 0 means "use the global capability hat".
        // The Hats-native model is one capability hat per gate (CREATE/CLAIM/REVIEW/ASSIGN); a project
        // can override the global hat for any of these by setting a non-zero hat ID here.
        uint256 createHat;
        uint256 claimHat;
        uint256 reviewHat;
        uint256 assignHat;
        address[] bountyTokens;
        uint256[] bountyCaps;
    }

    struct BootstrapTaskConfig {
        uint8 projectIndex; // References project in same batch (0 for first project)
        uint256 payout;
        bytes title;
        bytes32 metadataHash;
        address bountyToken;
        uint256 bountyPayout;
        bool requiresApplication;
    }

    struct CreateTaskInput {
        uint256 payout;
        bytes title;
        bytes32 metadataHash;
        address bountyToken;
        uint256 bountyPayout;
        bool requiresApplication;
    }

    /*──────── Storage (ERC-7201) ───────*/
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IHats hats;
        IParticipationToken token;
        uint256[] creatorHatIds; // DEPRECATED: dead state, kept for ERC-7201 append-only rules
        uint48 nextTaskId;
        uint48 nextProjectId;
        address executor; // 20 bytes + 2*6 bytes = 32 bytes (one slot)
        mapping(uint256 => uint8) rolePermGlobal; // DEPRECATED: dead state (old bitmask model)
        mapping(bytes32 => mapping(uint256 => uint8)) rolePermProj; // DEPRECATED: dead state
        uint256[] permissionHatIds; // DEPRECATED: dead state
        mapping(uint256 => address[]) taskApplicants; // task ID => array of applicants
        mapping(uint256 => mapping(address => bytes32)) taskApplications; // task ID => applicant => application hash
        address deployer; // OrgDeployer address for bootstrap operations
        mapping(uint256 => uint256) projectPermHatRefCount; // DEPRECATED: dead state
        // ─── Hats-native capability hats (one per gate) ───
        uint256 projectCreatorHat; // capability hat gating createProject / updateTask / cancelTask
        uint256 createHat; // global capability hat gating createTask
        uint256 claimHat; // global capability hat gating claimTask / applyForTask
        uint256 reviewHat; // global capability hat gating completeTask / rejectTask
        uint256 assignHat; // global capability hat gating assignTask / approveApplication
        uint256 selfReviewHat; // capability hat allowing a claimer to complete their own task
        // Per-project capability overrides: 0 means "use the global capability hat"
        mapping(bytes32 => mapping(uint8 => uint256)) projectCapHat; // pid => TaskPerm flag => hatId
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.taskmanager.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────── Events ───────*/
    event HatSet(HatType hatType, uint256 hat, bool allowed);
    event ProjectCreated(bytes32 indexed id, bytes title, bytes32 metadataHash, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerUpdated(bytes32 indexed id, address indexed manager, bool isManager);
    event ProjectDeleted(bytes32 indexed id);
    event ProjectRolePermSet(bytes32 indexed id, uint256 indexed hatId, uint8 mask);
    event BountyCapSet(bytes32 indexed projectId, address indexed token, uint256 oldCap, uint256 newCap);

    event TaskCreated(
        uint256 indexed id,
        bytes32 indexed project,
        uint256 payout,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication,
        bytes title,
        bytes32 metadataHash
    );
    event TaskUpdated(
        uint256 indexed id, uint256 payout, address bountyToken, uint256 bountyPayout, bytes title, bytes32 metadataHash
    );
    event TaskSubmitted(uint256 indexed id, bytes32 submissionHash);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event TaskRejected(uint256 indexed id, address indexed rejector, bytes32 rejectionHash);
    event TaskApplicationSubmitted(uint256 indexed id, address indexed applicant, bytes32 applicationHash);
    event TaskApplicationApproved(uint256 indexed id, address indexed applicant, address indexed approver);
    event ExecutorUpdated(address newExecutor);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────── Initialiser ───────*/
    /// @param tokenAddress ParticipationToken address
    /// @param hatsAddress Hats Protocol address
    /// @param projectCreatorHat_ Capability hat gating createProject
    /// @param executorAddress Org's Executor
    /// @param deployerAddress OrgDeployer (for bootstrap; address(0) skips)
    function initialize(
        address tokenAddress,
        address hatsAddress,
        uint256 projectCreatorHat_,
        address executorAddress,
        address deployerAddress
    ) external initializer {
        tokenAddress.requireNonZeroAddress();
        hatsAddress.requireNonZeroAddress();
        executorAddress.requireNonZeroAddress();

        __Context_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddress);
        l.hats = IHats(hatsAddress);
        l.executor = executorAddress;
        l.deployer = deployerAddress; // Can be address(0) if bootstrap not needed
        l.projectCreatorHat = projectCreatorHat_;

        emit HatSet(HatType.CREATOR, projectCreatorHat_, true);
        emit ExecutorUpdated(executorAddress);
    }

    /*──────── Internal Check Functions ─────*/
    function _requireCreator() internal view {
        Layout storage l = _layout();
        address s = _msgSender();
        if (!_hasCreatorHat(s) && s != l.executor) revert NotCreator();
    }

    function _requireProjectExists(bytes32 pid) internal view {
        if (!_layout()._projects[pid].exists) revert NotFound();
    }

    function _requireExecutor() internal view {
        if (_msgSender() != _layout().executor) revert NotExecutor();
    }

    function _requireCanCreate(bytes32 pid) internal view {
        _checkPerm(pid, TaskPerm.CREATE);
    }

    function _requireCanClaim(uint256 tid) internal view {
        _checkPerm(_layout()._tasks[tid].projectId, TaskPerm.CLAIM);
    }

    function _requireCanAssign(bytes32 pid) internal view {
        _checkPerm(pid, TaskPerm.ASSIGN);
    }

    /*──────── Project Logic ─────*/

    /**
     * @notice Create a new project
     * @dev Uses BootstrapProjectConfig struct to avoid stack-too-deep with 10+ calldata arrays.
     *      The caller (msg.sender) is automatically added as a project manager.
     * @param p  Project configuration (title, metadataHash, cap, managers, hat arrays, bounty budgets)
     */
    function createProject(BootstrapProjectConfig calldata p) external returns (bytes32 projectId) {
        _requireCreator();
        projectId = _createProjectCore(
            p.title, p.metadataHash, p.cap, p.managers, p.createHat, p.claimHat, p.reviewHat, p.assignHat, _msgSender()
        );
        _initBountyBudgets(projectId, p.bountyTokens, p.bountyCaps);
    }

    function _createProjectCore(
        bytes calldata title,
        bytes32 metadataHash,
        uint256 cap,
        address[] calldata managers,
        uint256 createHat_,
        uint256 claimHat_,
        uint256 reviewHat_,
        uint256 assignHat_,
        address defaultManager
    ) internal returns (bytes32 projectId) {
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidCapAmount(cap);

        Layout storage l = _layout();
        projectId = bytes32(uint256(l.nextProjectId++));
        Project storage p = l._projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        emit ProjectCreated(projectId, title, metadataHash, cap);

        /* managers */
        if (defaultManager != address(0)) {
            p.managers[defaultManager] = true;
            emit ProjectManagerUpdated(projectId, defaultManager, true);
        }
        for (uint256 i; i < managers.length;) {
            managers[i].requireNonZeroAddress();
            p.managers[managers[i]] = true;
            emit ProjectManagerUpdated(projectId, managers[i], true);
            unchecked {
                ++i;
            }
        }

        /* per-project capability hat overrides (0 = use global) */
        if (createHat_ != 0) {
            l.projectCapHat[projectId][TaskPerm.CREATE] = createHat_;
            emit ProjectRolePermSet(projectId, createHat_, TaskPerm.CREATE);
        }
        if (claimHat_ != 0) {
            l.projectCapHat[projectId][TaskPerm.CLAIM] = claimHat_;
            emit ProjectRolePermSet(projectId, claimHat_, TaskPerm.CLAIM);
        }
        if (reviewHat_ != 0) {
            l.projectCapHat[projectId][TaskPerm.REVIEW] = reviewHat_;
            emit ProjectRolePermSet(projectId, reviewHat_, TaskPerm.REVIEW);
        }
        if (assignHat_ != 0) {
            l.projectCapHat[projectId][TaskPerm.ASSIGN] = assignHat_;
            emit ProjectRolePermSet(projectId, assignHat_, TaskPerm.ASSIGN);
        }
    }

    function _initBountyBudgets(bytes32 projectId, address[] calldata bountyTokens, uint256[] calldata bountyCaps)
        internal
    {
        if (bountyTokens.length != bountyCaps.length) revert ArrayLengthMismatch();
        if (bountyTokens.length == 0) return;

        Project storage p = _layout()._projects[projectId];
        for (uint256 i; i < bountyTokens.length;) {
            bountyTokens[i].requireNonZeroAddress();
            ValidationLib.requireValidCapAmount(bountyCaps[i]);
            p.bountyBudgets[bountyTokens[i]].cap = uint128(bountyCaps[i]);
            emit BountyCapSet(projectId, bountyTokens[i], 0, bountyCaps[i]);
            unchecked {
                ++i;
            }
        }
    }

    function deleteProject(bytes32 pid) external {
        _requireCreator();
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        // Clear per-project capability hat overrides
        delete l.projectCapHat[pid][TaskPerm.CREATE];
        delete l.projectCapHat[pid][TaskPerm.CLAIM];
        delete l.projectCapHat[pid][TaskPerm.REVIEW];
        delete l.projectCapHat[pid][TaskPerm.ASSIGN];
        delete l.projectCapHat[pid][TaskPerm.SELF_REVIEW];

        delete l._projects[pid];
        emit ProjectDeleted(pid);
    }

    /**
     * @notice Bootstrap initial projects and tasks during org deployment
     * @dev Only callable by deployer (OrgDeployer) during bootstrap phase
     * @param projects Array of project configurations to create
     * @param tasks Array of task configurations (reference projects by index)
     * @return projectIds Array of created project IDs
     */
    function bootstrapProjectsAndTasks(BootstrapProjectConfig[] calldata projects, BootstrapTaskConfig[] calldata tasks)
        external
        returns (bytes32[] memory projectIds)
    {
        Layout storage l = _layout();
        if (_msgSender() != l.deployer) revert NotDeployer();

        projectIds = new bytes32[](projects.length);

        // Create all projects (executor is not auto-added as manager, use managers array)
        for (uint256 i; i < projects.length;) {
            projectIds[i] = _createProjectCore(
                projects[i].title,
                projects[i].metadataHash,
                projects[i].cap,
                projects[i].managers,
                projects[i].createHat,
                projects[i].claimHat,
                projects[i].reviewHat,
                projects[i].assignHat,
                address(0) // No default manager - use explicit managers array
            );
            _initBountyBudgets(projectIds[i], projects[i].bountyTokens, projects[i].bountyCaps);
            unchecked {
                ++i;
            }
        }

        // Create all tasks referencing projects by index
        for (uint256 i; i < tasks.length;) {
            if (tasks[i].projectIndex >= projects.length) revert InvalidIndex();
            bytes32 pid = projectIds[tasks[i].projectIndex];
            _createTask(
                tasks[i].payout,
                tasks[i].title,
                tasks[i].metadataHash,
                pid,
                tasks[i].requiresApplication,
                tasks[i].bountyToken,
                tasks[i].bountyPayout
            );
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Clear the deployer address after bootstrap phase is complete
     * @dev Only callable by deployer. Prevents future bootstrap calls for defense-in-depth.
     *      Should be called by OrgDeployer at the end of org deployment.
     */
    function clearDeployer() external {
        Layout storage l = _layout();
        if (_msgSender() != l.deployer) revert NotDeployer();
        l.deployer = address(0);
    }

    /*──────── Task Logic ───────*/
    function createTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication
    ) external {
        _requireCanCreate(pid);
        _createTask(payout, title, metadataHash, pid, requiresApplication, bountyToken, bountyPayout);
    }

    /**
     * @notice Create multiple tasks in a single project in one transaction.
     * @dev Permission is checked once for the whole batch; project existence and
     *      per-task validation still run inside `_createTask`. All-or-nothing:
     *      any failure reverts the entire call.
     * @param pid    Project ID all tasks will be created under.
     * @param tasks  Array of task configurations, in the order they should be created.
     * @return taskIds IDs of the newly-created tasks, in the same order as `tasks`.
     */
    function createTasksBatch(bytes32 pid, CreateTaskInput[] calldata tasks)
        external
        returns (uint256[] memory taskIds)
    {
        if (tasks.length == 0) revert EmptyBatch();
        _requireCanCreate(pid);

        uint256 len = tasks.length;
        taskIds = new uint256[](len);

        for (uint256 i; i < len;) {
            CreateTaskInput calldata t = tasks[i];
            taskIds[i] = _createTask(
                t.payout, t.title, t.metadataHash, pid, t.requiresApplication, t.bountyToken, t.bountyPayout
            );
            unchecked {
                ++i;
            }
        }
    }

    function _createTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal returns (uint48 id) {
        Layout storage l = _layout();
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidPayout96(payout);
        ValidationLib.requireValidBountyConfig(bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        // Update participation token budget (PT cap: 0 = unlimited, since PT is minted)
        uint256 newSpent = p.spent + payout;
        if (newSpent > type(uint128).max) revert BudgetLib.BudgetExceeded();
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check bounty budget (BudgetLib: cap 0 = DISABLED, must be explicitly enabled)
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        id = l.nextTaskId++;
        l._tasks[id] = Task(
            pid, uint96(payout), address(0), uint96(bountyPayout), requiresApplication, Status.UNCLAIMED, bountyToken
        );
        emit TaskCreated(id, pid, payout, bountyToken, bountyPayout, requiresApplication, title, metadataHash);
    }

    function updateTask(
        uint256 id,
        uint256 newPayout,
        bytes calldata newTitle,
        bytes32 newMetadataHash,
        address newBountyToken,
        uint256 newBountyPayout
    ) external {
        _requireCanCreate(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        ValidationLib.requireValidTitle(newTitle);
        ValidationLib.requireValidPayout96(newPayout);
        ValidationLib.requireValidBountyConfig(newBountyToken, newBountyPayout);

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        Project storage p = l._projects[t.projectId];

        // Update participation token budget
        // PT cap: 0 = unlimited (minted tokens)
        uint256 tentative = p.spent - t.payout + newPayout;
        if (p.cap != 0 && tentative > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(tentative);

        // Update bounty budgets
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            BudgetLib.Budget storage oldB = p.bountyBudgets[t.bountyToken];
            oldB.subtractSpent(t.bountyPayout);
        }

        if (newBountyToken != address(0) && newBountyPayout > 0) {
            BudgetLib.Budget storage newB = p.bountyBudgets[newBountyToken];
            newB.addSpent(newBountyPayout);
        }

        // Update task
        t.payout = uint96(newPayout);
        t.bountyToken = newBountyToken;
        t.bountyPayout = uint96(newBountyPayout);

        emit TaskUpdated(id, newPayout, newBountyToken, newBountyPayout, newTitle, newMetadataHash);
    }

    function claimTask(uint256 id) external {
        _requireCanClaim(id);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        if (t.requiresApplication) revert RequiresApplication();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external {
        _requireCanAssign(_layout()._tasks[id].projectId);
        assignee.requireNonZeroAddress();
        Layout storage l = _layout();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, _msgSender());
    }

    function submitTask(uint256 id, bytes32 submissionHash) external {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.CLAIMED) revert BadStatus();
        if (t.claimer != _msgSender()) revert NotClaimer();
        if (submissionHash == bytes32(0)) revert ValidationLib.InvalidString();

        t.status = Status.SUBMITTED;
        emit TaskSubmitted(id, submissionHash);
    }

    function completeTask(uint256 id) external {
        Layout storage l = _layout();
        bytes32 pid = l._tasks[id].projectId;
        _checkPerm(pid, TaskPerm.REVIEW);
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert BadStatus();

        // Self-review: if caller is the claimer, require SELF_REVIEW permission or PM/executor
        address sender = _msgSender();
        if (t.claimer == sender && !_isPM(pid, sender)) {
            if (!_hasCap(sender, pid, TaskPerm.SELF_REVIEW)) {
                revert SelfReviewNotAllowed();
            }
        }

        t.status = Status.COMPLETED;
        l.token.mint(t.claimer, uint256(t.payout));

        // Transfer bounty token if set
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            IERC20(t.bountyToken).safeTransfer(t.claimer, uint256(t.bountyPayout));
        }

        emit TaskCompleted(id, _msgSender());
    }

    function rejectTask(uint256 id, bytes32 rejectionHash) external {
        Layout storage l = _layout();
        _checkPerm(l._tasks[id].projectId, TaskPerm.REVIEW);
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert BadStatus();
        if (rejectionHash == bytes32(0)) revert ValidationLib.InvalidString();

        t.status = Status.CLAIMED;
        emit TaskRejected(id, _msgSender(), rejectionHash);
    }

    function cancelTask(uint256 id) external {
        _requireCanCreate(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        Project storage p = l._projects[t.projectId];
        if (p.spent < t.payout) revert BudgetLib.SpentUnderflow();
        unchecked {
            p.spent -= t.payout;
        }

        // Roll back bounty budget if applicable
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[t.bountyToken];
            bb.subtractSpent(t.bountyPayout);
        }

        t.status = Status.CANCELLED;
        t.claimer = address(0);

        // Clear all applications - zero out the mapping and delete applicants array
        delete l.taskApplicants[id];

        emit TaskCancelled(id, _msgSender());
    }

    /*──────── Application System ─────*/
    /**
     * @dev Submit application for a task with IPFS hash containing submission
     * @param id Task ID to apply for
     * @param applicationHash IPFS hash of the application/submission
     */
    function applyForTask(uint256 id, bytes32 applicationHash) external {
        _requireCanClaim(id);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        ValidationLib.requireValidApplicationHash(applicationHash);
        if (!t.requiresApplication) revert NoApplicationRequired();

        address applicant = _msgSender();

        // Check if user has already applied
        if (l.taskApplications[id][applicant] != bytes32(0)) revert AlreadyApplied();

        // Add applicant to the list
        l.taskApplicants[id].push(applicant);
        l.taskApplications[id][applicant] = applicationHash;

        emit TaskApplicationSubmitted(id, applicant, applicationHash);
    }

    /**
     * @dev Approve an application, moving task to CLAIMED status
     * @param id Task ID
     * @param applicant Address of the applicant to approve
     */
    function approveApplication(uint256 id, address applicant) external {
        _requireCanAssign(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        if (l.taskApplications[id][applicant] == bytes32(0)) revert NotApplicant();

        t.status = Status.CLAIMED;
        t.claimer = applicant;
        delete l.taskApplicants[id];
        emit TaskApplicationApproved(id, applicant, _msgSender());
    }

    /**
     * @dev Creates a task and immediately assigns it to the specified assignee in a single transaction.
     * @param payout The payout amount for the task
     * @param title Task title (required, raw UTF-8)
     * @param metadataHash IPFS CID sha256 digest (optional, bytes32(0) valid)
     * @param pid Project ID
     * @param assignee Address to assign the task to
     * @return taskId The ID of the created task
     */
    function createAndAssignTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address assignee,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication
    ) external returns (uint256 taskId) {
        return _createAndAssignTask(
            payout, title, metadataHash, pid, assignee, requiresApplication, bountyToken, bountyPayout
        );
    }

    function _createAndAssignTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address assignee,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal returns (uint256 taskId) {
        assignee.requireNonZeroAddress();

        Layout storage l = _layout();
        address sender = _msgSender();

        // Check permissions - user must have both CREATE and ASSIGN capability hats, or be a project manager
        bool hasCreateAndAssign = _hasCap(sender, pid, TaskPerm.CREATE) && _hasCap(sender, pid, TaskPerm.ASSIGN);
        if (!hasCreateAndAssign && !_isPM(pid, sender)) {
            revert Unauthorized();
        }

        // Validation
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidPayout96(payout);
        ValidationLib.requireValidBountyConfig(bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        // PT cap: 0 = unlimited (minted tokens)
        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check bounty budget (BudgetLib: cap 0 = DISABLED, must be explicitly enabled)
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        // Create and assign task in one go
        taskId = l.nextTaskId++;
        l._tasks[taskId] =
            Task(pid, uint96(payout), assignee, uint96(bountyPayout), requiresApplication, Status.CLAIMED, bountyToken);

        // Emit events
        emit TaskCreated(taskId, pid, payout, bountyToken, bountyPayout, requiresApplication, title, metadataHash);
        emit TaskAssigned(taskId, assignee, sender);
    }

    /*──────── Config Setter (Optimized) ─────── */
    function setConfig(ConfigKey key, bytes calldata value) external {
        _requireExecutor();
        Layout storage l = _layout();

        if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            newExecutor.requireNonZeroAddress();
            l.executor = newExecutor;
            emit ExecutorUpdated(newExecutor);
            return;
        }

        if (key == ConfigKey.CREATOR_HAT_ALLOWED) {
            // Repurposed: sets the single projectCreatorHat. `allowed` is ignored — pass hat=0 to clear.
            (uint256 hat,) = abi.decode(value, (uint256, bool));
            l.projectCreatorHat = hat;
            emit HatSet(HatType.CREATOR, hat, true);
            return;
        }

        if (key == ConfigKey.ROLE_PERM) {
            // Repurposed: ROLE_PERM now sets a global capability hat. `mask` is the TaskPerm flag,
            // hatId is the capability hat. Pass hat=0 to clear.
            (uint256 hatId, uint8 mask) = abi.decode(value, (uint256, uint8));
            if (mask == TaskPerm.CREATE) {
                l.createHat = hatId;
            } else if (mask == TaskPerm.CLAIM) {
                l.claimHat = hatId;
            } else if (mask == TaskPerm.REVIEW) {
                l.reviewHat = hatId;
            } else if (mask == TaskPerm.ASSIGN) {
                l.assignHat = hatId;
            } else if (mask == TaskPerm.SELF_REVIEW) {
                l.selfReviewHat = hatId;
            } else {
                revert InvalidCapMask();
            }
            emit ProjectRolePermSet(bytes32(0), hatId, mask);
            return;
        }

        // Project-related configs - consolidate common logic
        bytes32 pid;
        if (key >= ConfigKey.BOUNTY_CAP) {
            pid = abi.decode(value, (bytes32));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();

            if (key == ConfigKey.BOUNTY_CAP) {
                (, address token, uint256 newCap) = abi.decode(value, (bytes32, address, uint256));
                token.requireNonZeroAddress();
                ValidationLib.requireValidCapAmount(newCap);
                BudgetLib.Budget storage b = p.bountyBudgets[token];
                ValidationLib.requireValidCap(newCap, b.spent);
                uint256 oldCap = b.cap;
                b.cap = uint128(newCap);
                emit BountyCapSet(pid, token, oldCap, newCap);
            } else if (key == ConfigKey.PROJECT_MANAGER) {
                (, address mgr, bool isManager) = abi.decode(value, (bytes32, address, bool));
                mgr.requireNonZeroAddress();
                p.managers[mgr] = isManager;
                emit ProjectManagerUpdated(pid, mgr, isManager);
            } else if (key == ConfigKey.PROJECT_CAP) {
                (, uint256 newCap) = abi.decode(value, (bytes32, uint256));
                ValidationLib.requireValidCapAmount(newCap);
                ValidationLib.requireValidCap(newCap, p.spent);
                uint256 old = p.cap;
                p.cap = uint128(newCap);
                emit ProjectCapUpdated(pid, old, newCap);
            }
        }
    }

    /// @notice Override a project's capability hat for a specific TaskPerm flag.
    ///         Pass hatId=0 to clear and fall back to the global capability hat.
    /// @dev `mask` MUST be exactly one of the single-bit TaskPerm constants
    ///      (CREATE, CLAIM, REVIEW, ASSIGN, SELF_REVIEW). OR-combined masks would
    ///      write to an unused slot in `projectCapHat` and silently no-op, since
    ///      `_capHat` only queries by single-flag keys.
    function setProjectRolePerm(bytes32 pid, uint256 hatId, uint8 mask) external {
        _requireCreator();
        _requireProjectExists(pid);
        if (
            mask != TaskPerm.CREATE && mask != TaskPerm.CLAIM && mask != TaskPerm.REVIEW && mask != TaskPerm.ASSIGN
                && mask != TaskPerm.SELF_REVIEW
        ) revert InvalidCapMask();
        _layout().projectCapHat[pid][mask] = hatId;
        emit ProjectRolePermSet(pid, hatId, mask);
    }

    /*──────── Internal Perm helpers ─────*/

    /// @dev Looks up the effective capability hat for `(pid, cap)`: project override if set,
    ///      otherwise the global capability hat.
    function _capHat(bytes32 pid, uint8 cap) internal view returns (uint256) {
        Layout storage l = _layout();
        uint256 hat = l.projectCapHat[pid][cap];
        if (hat != 0) return hat;
        if (cap == TaskPerm.CREATE) return l.createHat;
        if (cap == TaskPerm.CLAIM) return l.claimHat;
        if (cap == TaskPerm.REVIEW) return l.reviewHat;
        if (cap == TaskPerm.ASSIGN) return l.assignHat;
        if (cap == TaskPerm.SELF_REVIEW) return l.selfReviewHat;
        return 0;
    }

    function _hasCap(address user, bytes32 pid, uint8 cap) internal view returns (bool) {
        uint256 hat = _capHat(pid, cap);
        if (hat == 0) return false;
        return _layout().hats.isWearerOfHat(user, hat);
    }

    function _isPM(bytes32 pid, address who) internal view returns (bool) {
        Layout storage l = _layout();
        return (who == l.executor) || l._projects[pid].managers[who];
    }

    function _checkPerm(bytes32 pid, uint8 flag) internal view {
        address s = _msgSender();
        if (!_hasCap(s, pid, flag) && !_isPM(pid, s)) revert Unauthorized();
    }

    /*──────── Internal Helper Functions ─────────── */
    /// @dev Returns true if `user` wears the project-creator capability hat.
    function _hasCreatorHat(address user) internal view returns (bool) {
        Layout storage l = _layout();
        uint256 hat = l.projectCreatorHat;
        if (hat == 0) return false;
        return l.hats.isWearerOfHat(user, hat);
    }

    /*──────── Utils / View ────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert NotFound();
        t = l._tasks[id];
    }

    /*──────── Minimal External Getters for Lens ─────── */
    function getLensData(uint8 t, bytes calldata d) external view returns (bytes memory) {
        Layout storage l = _layout();
        if (t == 1) {
            // Task
            uint256 id = abi.decode(d, (uint256));
            if (id >= l.nextTaskId) revert NotFound();
            Task storage task = l._tasks[id];
            return abi.encode(
                task.projectId,
                task.payout,
                task.claimer,
                task.bountyPayout,
                task.requiresApplication,
                task.status,
                task.bountyToken
            );
        } else if (t == 2) {
            // Project
            bytes32 pid = abi.decode(d, (bytes32));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();
            return abi.encode(p.cap, p.spent, p.exists);
        } else if (t == 3) {
            // Hats
            return abi.encode(address(l.hats));
        } else if (t == 4) {
            // Executor
            return abi.encode(l.executor);
        } else if (t == 5) {
            // CreatorHats — single capability hat (returned as single-element array for compat)
            uint256[] memory arr = new uint256[](1);
            arr[0] = l.projectCreatorHat;
            return abi.encode(arr);
        } else if (t == 6) {
            // PermissionHats — global capability hats per gate (returned as 5-element array)
            uint256[] memory arr = new uint256[](5);
            arr[0] = l.createHat;
            arr[1] = l.claimHat;
            arr[2] = l.reviewHat;
            arr[3] = l.assignHat;
            arr[4] = l.selfReviewHat;
            return abi.encode(arr);
        } else if (t == 7) {
            // TaskApplicants
            uint256 id = abi.decode(d, (uint256));
            return abi.encode(l.taskApplicants[id]);
        } else if (t == 8) {
            // TaskApplication
            (uint256 id, address applicant) = abi.decode(d, (uint256, address));
            return abi.encode(l.taskApplications[id][applicant]);
        } else if (t == 9) {
            // BountyBudget
            (bytes32 pid, address token) = abi.decode(d, (bytes32, address));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();
            BudgetLib.Budget storage b = p.bountyBudgets[token];
            return abi.encode(b.cap, b.spent);
        }
        revert NotFound();
    }
}
