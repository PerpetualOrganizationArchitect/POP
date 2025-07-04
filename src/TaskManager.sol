// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
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
contract TaskManager is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable {
    using SafeERC20 for IERC20;
    using BudgetLib for BudgetLib.Budget;
    using ValidationLib for address;
    using ValidationLib for bytes;

    /*──────── Errors ───────*/
    error UnknownTask();
    error UnknownProject();
    error NotCreator();
    error AlreadyClaimed();
    error AlreadySubmitted();
    error AlreadyCompleted();
    error NotClaimer();
    error NotExecutor();
    error Unauthorized();
    error NotApplicant();
    error AlreadyApplied();
    error RequiresApplication();
    error NoApplicationRequired();

    /*──────── Constants ─────*/
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

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
        uint128 cap; // slot 1: 16 bytes (participation token cap)
        uint128 spent; // slot 1: 16 bytes (participation token spent)
        bool exists; // slot 2: 1 byte (separate slot for cleaner access)
        mapping(address => BudgetLib.Budget) bountyBudgets; // slot 2: rest of slot & beyond
    }

    /*──────── Storage (ERC-7201) ───────*/
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IHats hats;
        IParticipationToken token;
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint48 nextTaskId;
        uint48 nextProjectId;
        address executor; // 20 bytes + 2*6 bytes = 32 bytes (one slot)
        mapping(uint256 => uint8) rolePermGlobal; // hat ID => permission mask
        mapping(bytes32 => mapping(uint256 => uint8)) rolePermProj; // project => hat ID => permission mask
        uint256[] permissionHatIds; // enumeration array for hats with permissions
        mapping(uint256 => address[]) taskApplicants; // task ID => array of applicants
        mapping(uint256 => mapping(address => bytes32)) taskApplications; // task ID => applicant => application hash
    }

    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────── Events ───────*/
    event CreatorHatSet(uint256 indexed hat, bool allowed);
    event ProjectCreated(bytes32 indexed id, bytes metadata, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerAdded(bytes32 indexed id, address indexed manager);
    event ProjectManagerRemoved(bytes32 indexed id, address indexed manager);
    event ProjectDeleted(bytes32 indexed id, bytes metadata);
    event ProjectRolePermSet(bytes32 indexed id, uint256 indexed hatId, uint8 mask);
    event BountyCapSet(bytes32 indexed projectId, address indexed token, uint256 oldCap, uint256 newCap);

    event TaskCreated(
        uint256 indexed id,
        bytes32 indexed project,
        uint256 payout,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication,
        bytes metadata
    );
    event TaskUpdated(uint256 indexed id, uint256 payout, address bountyToken, uint256 bountyPayout, bytes metadata);
    event TaskSubmitted(uint256 indexed id, bytes metadata);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event TaskApplicationSubmitted(uint256 indexed id, address indexed applicant, bytes32 applicationHash);
    event TaskApplicationApproved(uint256 indexed id, address indexed applicant, address indexed approver);
    event ExecutorSet(address indexed newExecutor);

    /*──────── Initialiser ───────*/
    function initialize(
        address tokenAddress,
        address hatsAddress,
        uint256[] calldata creatorHats,
        address executorAddress
    ) external initializer {
        tokenAddress.requireNonZeroAddress();
        hatsAddress.requireNonZeroAddress();
        executorAddress.requireNonZeroAddress();

        __ReentrancyGuard_init();
        __Context_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddress);
        l.hats = IHats(hatsAddress);
        l.executor = executorAddress;

        // Initialize creator hat arrays using HatManager
        for (uint256 i; i < creatorHats.length;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHats[i], true);
            emit CreatorHatSet(creatorHats[i], true);
            unchecked {
                ++i;
            }
        }

        emit ExecutorSet(executorAddress);
    }

    /*──────── Hat Management ─────*/
    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.creatorHatIds, h, ok);
        emit CreatorHatSet(h, ok);
    }

    /*──────── Modifiers ─────*/
    modifier onlyCreator() {
        Layout storage l = _layout();
        address s = _msgSender();
        if (!_hasCreatorHat(s) && s != l.executor) revert NotCreator();
        _;
    }

    modifier projectExists(bytes32 pid) {
        if (!_layout()._projects[pid].exists) revert UnknownProject();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != _layout().executor) revert NotExecutor();
        _;
    }

    modifier canCreate(bytes32 pid) {
        _checkPerm(pid, TaskPerm.CREATE);
        _;
    }

    modifier canClaim(uint256 tid) {
        Layout storage l = _layout();
        _checkPerm(l._tasks[tid].projectId, TaskPerm.CLAIM);
        _;
    }

    modifier canReview(bytes32 pid) {
        _checkPerm(pid, TaskPerm.REVIEW);
        _;
    }

    modifier canAssign(bytes32 pid) {
        _checkPerm(pid, TaskPerm.ASSIGN);
        _;
    }

    /*──────── Project Logic ─────*/
    /**
     * @param managers        initial manager addresses (auto-adds msg.sender)
     * @param createHats      hat IDs allowed to CREATE tasks in this project
     * @param claimHats       hat IDs allowed to CLAIM
     * @param reviewHats      hat IDs allowed to REVIEW / COMPLETE / UPDATE
     * @param assignHats      hat IDs allowed to ASSIGN tasks
     */
    function createProject(
        bytes calldata metadata,
        uint256 cap,
        address[] calldata managers,
        uint256[] calldata createHats,
        uint256[] calldata claimHats,
        uint256[] calldata reviewHats,
        uint256[] calldata assignHats
    ) external onlyCreator returns (bytes32 projectId) {
        ValidationLib.requireValidProjectParams(metadata, cap);

        Layout storage l = _layout();
        projectId = bytes32(uint256(l.nextProjectId++));
        Project storage p = l._projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        /* managers */
        p.managers[_msgSender()] = true;
        emit ProjectManagerAdded(projectId, _msgSender());
        for (uint256 i; i < managers.length;) {
            managers[i].requireNonZeroAddress();
            p.managers[managers[i]] = true;
            emit ProjectManagerAdded(projectId, managers[i]);
            unchecked {
                ++i;
            }
        }

        /* hat-permission matrix */
        _setBatchHatPerm(projectId, createHats, TaskPerm.CREATE);
        _setBatchHatPerm(projectId, claimHats, TaskPerm.CLAIM);
        _setBatchHatPerm(projectId, reviewHats, TaskPerm.REVIEW);
        _setBatchHatPerm(projectId, assignHats, TaskPerm.ASSIGN);

        emit ProjectCreated(projectId, metadata, cap);
    }

    function updateProjectCap(bytes32 pid, uint256 newCap) external onlyExecutor projectExists(pid) {
        ValidationLib.requireValidCapAmount(newCap);

        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        ValidationLib.requireValidCap(newCap, p.spent);

        uint256 old = p.cap;
        p.cap = uint128(newCap);
        emit ProjectCapUpdated(pid, old, newCap);
    }

    function addProjectManager(bytes32 pid, address mgr) external onlyExecutor projectExists(pid) {
        mgr.requireNonZeroAddress();
        Layout storage l = _layout();
        l._projects[pid].managers[mgr] = true;
        emit ProjectManagerAdded(pid, mgr);
    }

    function removeProjectManager(bytes32 pid, address mgr) external onlyExecutor projectExists(pid) {
        Layout storage l = _layout();
        l._projects[pid].managers[mgr] = false;
        emit ProjectManagerRemoved(pid, mgr);
    }

    function deleteProject(bytes32 pid, bytes calldata metadata) external onlyCreator {
        metadata.requireNonEmptyBytes();
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();

        delete l._projects[pid];
        emit ProjectDeleted(pid, metadata);
    }

    /*──────── Task Logic ───────*/
    function createTask(uint256 payout, bytes calldata meta, bytes32 pid, address bountyToken, uint256 bountyPayout)
        external
        canCreate(pid)
    {
        _createTask(payout, meta, pid, false, bountyToken, bountyPayout);
    }

    function createApplicationTask(
        uint256 payout,
        bytes calldata meta,
        bytes32 pid,
        address bountyToken,
        uint256 bountyPayout
    ) external canCreate(pid) {
        _createTask(payout, meta, pid, true, bountyToken, bountyPayout);
    }

    function _createTask(
        uint256 payout,
        bytes calldata meta,
        bytes32 pid,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal {
        Layout storage l = _layout();
        ValidationLib.requireValidTaskParams(payout, meta, bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();

        // Update participation token budget
        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check and update bounty budget if applicable
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        uint48 id = l.nextTaskId++;
        l._tasks[id] = Task(
            pid, uint96(payout), address(0), uint96(bountyPayout), requiresApplication, Status.UNCLAIMED, bountyToken
        );
        emit TaskCreated(id, pid, payout, bountyToken, bountyPayout, requiresApplication, meta);
    }

    function updateTask(
        uint256 id,
        uint256 newPayout,
        bytes calldata newMetadata,
        address newBountyToken,
        uint256 newBountyPayout
    ) external canCreate(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        ValidationLib.requireValidTaskParams(newPayout, newMetadata, newBountyToken, newBountyPayout);

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];

        // Update participation token budget
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

        emit TaskUpdated(id, newPayout, newBountyToken, newBountyPayout, newMetadata);
    }

    function claimTask(uint256 id) external canClaim(id) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();
        if (t.requiresApplication) revert RequiresApplication();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external canAssign(_layout()._tasks[id].projectId) {
        assignee.requireNonZeroAddress();
        Layout storage l = _layout();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, _msgSender());
    }

    function submitTask(uint256 id, bytes calldata metadata) external {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.CLAIMED) revert AlreadySubmitted();
        if (t.claimer != _msgSender()) revert NotClaimer();
        metadata.requireNonEmptyBytes();

        t.status = Status.SUBMITTED;
        emit TaskSubmitted(id, metadata);
    }

    function completeTask(uint256 id) external nonReentrant canReview(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        t.status = Status.COMPLETED;
        l.token.mint(t.claimer, uint256(t.payout));

        // Transfer bounty token if set
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            IERC20(t.bountyToken).safeTransfer(t.claimer, uint256(t.bountyPayout));
        }

        emit TaskCompleted(id, _msgSender());
    }

    function cancelTask(uint256 id) external canCreate(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

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
    function applyForTask(uint256 id, bytes32 applicationHash) external canClaim(id) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();
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
    function approveApplication(uint256 id, address applicant) external canAssign(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();
        if (l.taskApplications[id][applicant] == bytes32(0)) revert NotApplicant();

        t.status = Status.CLAIMED;
        t.claimer = applicant;
        delete l.taskApplicants[id];
        emit TaskApplicationApproved(id, applicant, _msgSender());
    }

    /**
     * @dev Creates a task and immediately assigns it to the specified assignee in a single transaction.
     * @param payout The payout amount for the task
     * @param meta Task metadata
     * @param pid Project ID
     * @param assignee Address to assign the task to
     * @return taskId The ID of the created task
     */
    function createAndAssignTask(
        uint256 payout,
        bytes calldata meta,
        bytes32 pid,
        address assignee,
        address bountyToken,
        uint256 bountyPayout
    ) external returns (uint256 taskId) {
        return _createAndAssignTask(payout, meta, pid, assignee, false, bountyToken, bountyPayout);
    }

    function createAndAssignApplicationTask(
        uint256 payout,
        bytes calldata meta,
        bytes32 pid,
        address assignee,
        address bountyToken,
        uint256 bountyPayout
    ) external returns (uint256 taskId) {
        return _createAndAssignTask(payout, meta, pid, assignee, true, bountyToken, bountyPayout);
    }

    function _createAndAssignTask(
        uint256 payout,
        bytes calldata meta,
        bytes32 pid,
        address assignee,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal returns (uint256 taskId) {
        assignee.requireNonZeroAddress();

        Layout storage l = _layout();
        address sender = _msgSender();

        // Check permissions - user must have both CREATE and ASSIGN permissions, or be a project manager
        uint8 userPerms = _permMask(sender, pid);
        bool hasCreateAndAssign = TaskPerm.has(userPerms, TaskPerm.CREATE) && TaskPerm.has(userPerms, TaskPerm.ASSIGN);
        if (!hasCreateAndAssign && !_isPM(pid, sender)) {
            revert Unauthorized();
        }

        // Validation
        ValidationLib.requireValidTaskParams(payout, meta, bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();

        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check and update bounty budget if applicable
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        // Create and assign task in one go
        taskId = l.nextTaskId++;
        l._tasks[taskId] =
            Task(pid, uint96(payout), assignee, uint96(bountyPayout), requiresApplication, Status.CLAIMED, bountyToken);

        // Emit events
        emit TaskCreated(taskId, pid, payout, bountyToken, bountyPayout, requiresApplication, meta);
        emit TaskAssigned(taskId, assignee, sender);
    }

    /*────────── View Helpers ─────────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, bytes32 projectId, bool requiresApplication)
    {
        Task storage t = _task(_layout(), id);
        return (t.payout, t.status, t.claimer, t.projectId, t.requiresApplication);
    }

    function getTaskFull(uint256 id)
        external
        view
        returns (
            uint256 payout,
            uint256 bountyPayout,
            address bountyToken,
            Status status,
            address claimer,
            bytes32 projectId,
            bool requiresApplication
        )
    {
        Task storage t = _task(_layout(), id);
        return (t.payout, t.bountyPayout, t.bountyToken, t.status, t.claimer, t.projectId, t.requiresApplication);
    }

    function getProjectInfo(bytes32 pid) external view returns (uint256 cap, uint256 spent, bool isManager) {
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();
        return (p.cap, p.spent, p.managers[_msgSender()]);
    }

    function getTaskApplicants(uint256 id) external view returns (address[] memory) {
        return _layout().taskApplicants[id];
    }

    function getTaskApplication(uint256 id, address applicant) external view returns (bytes32) {
        return _layout().taskApplications[id][applicant];
    }

    function getTaskApplicantCount(uint256 id) external view returns (uint256) {
        return _layout().taskApplicants[id].length;
    }

    function hasAppliedForTask(uint256 id, address applicant) external view returns (bool) {
        return _layout().taskApplications[id][applicant] != bytes32(0);
    }

    /*──────── Governance / Admin ─────*/
    function setRolePerm(uint256 hatId, uint8 mask) external onlyExecutor {
        Layout storage l = _layout();
        l.rolePermGlobal[hatId] = mask;

        // Track that this hat has permissions
        if (mask != 0) {
            HatManager.setHatInArray(l.permissionHatIds, hatId, true);
        } else {
            HatManager.setHatInArray(l.permissionHatIds, hatId, false);
        }
    }

    function setProjectRolePerm(bytes32 pid, uint256 hatId, uint8 mask) external onlyCreator projectExists(pid) {
        Layout storage l = _layout();
        l.rolePermProj[pid][hatId] = mask;

        // Track that this hat has permissions (project-specific permissions count too)
        if (mask != 0) {
            HatManager.setHatInArray(l.permissionHatIds, hatId, true);
        } else {
            HatManager.setHatInArray(l.permissionHatIds, hatId, false);
        }

        emit ProjectRolePermSet(pid, hatId, mask);
    }

    function setExecutor(address newExec) external onlyExecutor {
        newExec.requireNonZeroAddress();
        _layout().executor = newExec;
        emit ExecutorSet(newExec);
    }

    function setBountyCap(bytes32 pid, address token, uint256 newCap) external onlyExecutor projectExists(pid) {
        token.requireNonZeroAddress();
        ValidationLib.requireValidCapAmount(newCap);

        Layout storage l = _layout();
        BudgetLib.Budget storage b = l._projects[pid].bountyBudgets[token];
        ValidationLib.requireValidCap(newCap, b.spent);

        uint256 oldCap = b.cap;
        b.cap = uint128(newCap);

        emit BountyCapSet(pid, token, oldCap, newCap);
    }

    function getBountyBudget(bytes32 pid, address token)
        external
        view
        projectExists(pid)
        returns (uint256 cap, uint256 spent)
    {
        token.requireNonZeroAddress();
        BudgetLib.Budget storage b = _layout()._projects[pid].bountyBudgets[token];
        return (b.cap, b.spent);
    }

    /*──────── Public getters for storage variables ─────────── */
    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function creatorHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().creatorHatIds);
    }

    /*──────── Internal Perm helpers ─────*/
    function _permMask(address user, bytes32 pid) internal view returns (uint8 m) {
        Layout storage l = _layout();
        uint256 len = l.permissionHatIds.length;
        if (len == 0) return 0;

        // one call instead of N
        address[] memory wearers = new address[](len);
        uint256[] memory hats_ = new uint256[](len);
        for (uint256 i; i < len;) {
            wearers[i] = user;
            hats_[i] = l.permissionHatIds[i];
            unchecked {
                ++i;
            }
        }
        uint256[] memory bal = l.hats.balanceOfBatch(wearers, hats_);

        for (uint256 i; i < len;) {
            if (bal[i] == 0) {
                unchecked {
                    ++i;
                }
                continue; // user doesn't wear it
            }
            uint256 h = hats_[i];
            uint8 mask = l.rolePermProj[pid][h];
            m |= mask == 0 ? l.rolePermGlobal[h] : mask; // project overrides global
            unchecked {
                ++i;
            }
        }
    }

    function _isPM(bytes32 pid, address who) internal view returns (bool) {
        Layout storage l = _layout();
        return (who == l.executor) || l._projects[pid].managers[who];
    }

    function _checkPerm(bytes32 pid, uint8 flag) internal view {
        address s = _msgSender();
        if (!TaskPerm.has(_permMask(s, pid), flag) && !_isPM(pid, s)) revert Unauthorized();
    }

    function _setBatchHatPerm(bytes32 pid, uint256[] calldata hatIds, uint8 flag) internal {
        Layout storage l = _layout();
        for (uint256 i; i < hatIds.length;) {
            uint256 hatId = hatIds[i];
            uint8 newMask = l.rolePermProj[pid][hatId] | flag;
            l.rolePermProj[pid][hatId] = newMask;

            // Track that this hat has permissions
            HatManager.setHatInArray(l.permissionHatIds, hatId, true);

            emit ProjectRolePermSet(pid, hatId, newMask);
            unchecked {
                ++i;
            }
        }
    }

    /*──────── Internal Helper Functions ─────────── */
    /// @dev Returns true if `user` wears *any* creator hat.
    function _hasCreatorHat(address user) internal view returns (bool) {
        Layout storage l = _layout();
        return HatManager.hasAnyHat(l.hats, l.creatorHatIds, user);
    }

    /*──────── Utils / View ────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert UnknownTask();
        t = l._tasks[id];
    }

    /*──────── Hat Management View Functions ─────────── */
    function creatorHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().creatorHatIds);
    }

    function permissionHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().permissionHatIds);
    }

    function isCreatorHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().creatorHatIds, hatId);
    }

    function isPermissionHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().permissionHatIds, hatId);
    }

    function version() external pure returns (string memory) {
        return "v1";
    }
}
