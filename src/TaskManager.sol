// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TaskPerm} from "./libs/TaskPerm.sol";

/*────────── External Interfaces ──────────*/
interface IMembership {
    function roleOf(address) external view returns (bytes32);
}

interface IParticipationToken is IERC20 {
    function mint(address, uint256) external;
}

/*────────────────────── Contract ───────────────────────*/
contract TaskManager is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable {
    /*──────── Errors ───────*/
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error UnknownTask();
    error UnknownProject();
    error NotCreator();
    error AlreadyClaimed();
    error AlreadySubmitted();
    error AlreadyCompleted();
    error NotClaimer();
    error BudgetExceeded();
    error CapBelowCommitted();
    error NotExecutor();
    error Unauthorized();

    /*──────── Constants ─────*/
    uint256 public constant MAX_PAYOUT = 1e24; // 1 000 000 tokens (18 dec)
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
        uint128 payout;
        Status status;
        address claimer;
        bytes32 projectId;
    }

    struct Project {
        uint128 cap;
        uint128 spent;
        bool exists;
        mapping(address => bool) managers;
    }

    /*──────── Storage (ERC-7201) ───────*/
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IMembership membership;
        IParticipationToken token;
        mapping(bytes32 => bool) isCreatorRole;
        uint256 nextTaskId;
        uint256 nextProjectId;
        address executor;
        mapping(bytes32 => uint8) rolePermGlobal;
        mapping(bytes32 => mapping(bytes32 => uint8)) rolePermProj; // project ⇒ role ⇒ mask
    }

    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────── Events ───────*/
    event CreatorRoleUpdated(bytes32 role, bool enabled);
    event ProjectCreated(bytes32 id, bytes metadata, uint256 cap);
    event ProjectCapUpdated(bytes32 id, uint256 oldCap, uint256 newCap);
    event ProjectManagerAdded(bytes32 id, address manager);
    event ProjectManagerRemoved(bytes32 id, address manager);
    event ProjectDeleted(bytes32 id, bytes metadata);
    event ProjectRolePermSet(bytes32 id, bytes32 role, uint8 mask);

    event TaskCreated(uint256 id, bytes32 project, uint256 payout, bytes metadata);
    event TaskUpdated(uint256 id, uint256 payout, bytes metadata);
    event TaskSubmitted(uint256 id, bytes metadata);
    event TaskClaimed(uint256 id, address claimer);
    event TaskAssigned(uint256 id, address assignee, address assigner);
    event TaskCompleted(uint256 id, address completer);
    event TaskCancelled(uint256 id, address canceller);
    event ExecutorSet(address newExecutor);

    /*──────── Initialiser ───────*/
    function initialize(
        address tokenAddress,
        address membershipAddress,
        bytes32[] calldata creatorRoles,
        address executorAddress
    ) external initializer {
        if (tokenAddress == address(0) || membershipAddress == address(0) || executorAddress == address(0)) {
            revert ZeroAddress();
        }

        __ReentrancyGuard_init();
        __Context_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddress);
        l.membership = IMembership(membershipAddress);
        l.executor = executorAddress;

        for (uint256 i; i < creatorRoles.length; ++i) {
            l.isCreatorRole[creatorRoles[i]] = true;
            emit CreatorRoleUpdated(creatorRoles[i], true);
        }
        emit ExecutorSet(executorAddress);
    }

    /*──────── Modifiers ─────*/
    modifier onlyCreator() {
        Layout storage l = _layout();
        address s = _msgSender();
        if (!l.isCreatorRole[l.membership.roleOf(s)] && s != l.executor) revert NotCreator();
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
     * @param createRoles     roles allowed to CREATE tasks in this project
     * @param claimRoles      roles allowed to CLAIM
     * @param reviewRoles     roles allowed to REVIEW / COMPLETE / UPDATE
     * @param assignRoles     roles allowed to ASSIGN tasks
     */
    function createProject(
        bytes calldata metadata,
        uint256 cap,
        address[] calldata managers,
        bytes32[] calldata createRoles,
        bytes32[] calldata claimRoles,
        bytes32[] calldata reviewRoles,
        bytes32[] calldata assignRoles
    ) external onlyCreator returns (bytes32 projectId) {
        if (metadata.length == 0) revert InvalidString();
        if (cap > MAX_PAYOUT) revert InvalidPayout();

        Layout storage l = _layout();
        projectId = bytes32(l.nextProjectId++);
        Project storage p = l._projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        /* managers */
        p.managers[_msgSender()] = true;
        emit ProjectManagerAdded(projectId, _msgSender());
        for (uint256 i; i < managers.length; ++i) {
            if (managers[i] == address(0)) revert ZeroAddress();
            p.managers[managers[i]] = true;
            emit ProjectManagerAdded(projectId, managers[i]);
        }

        /* role-permission matrix */
        _setBatchRolePerm(projectId, createRoles, TaskPerm.CREATE);
        _setBatchRolePerm(projectId, claimRoles, TaskPerm.CLAIM);
        _setBatchRolePerm(projectId, reviewRoles, TaskPerm.REVIEW);
        _setBatchRolePerm(projectId, assignRoles, TaskPerm.ASSIGN);

        emit ProjectCreated(projectId, metadata, cap);
    }

    function updateProjectCap(bytes32 pid, uint256 newCap) external onlyExecutor projectExists(pid) {
        if (newCap > MAX_PAYOUT) revert InvalidPayout();

        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (newCap != 0 && newCap < p.spent) revert CapBelowCommitted();

        uint256 old = p.cap;
        p.cap = uint128(newCap);
        emit ProjectCapUpdated(pid, old, newCap);
    }

    function addProjectManager(bytes32 pid, address mgr) external onlyExecutor projectExists(pid) {
        if (mgr == address(0)) revert ZeroAddress();
        _layout()._projects[pid].managers[mgr] = true;
        emit ProjectManagerAdded(pid, mgr);
    }

    function removeProjectManager(bytes32 pid, address mgr) external onlyExecutor projectExists(pid) {
        _layout()._projects[pid].managers[mgr] = false;
        emit ProjectManagerRemoved(pid, mgr);
    }

    function deleteProject(bytes32 pid, bytes calldata metadata) external onlyCreator {
        if (metadata.length == 0) revert InvalidString();
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();
        if (p.cap != 0 && p.spent != p.cap) revert CapBelowCommitted();

        delete l._projects[pid];
        emit ProjectDeleted(pid, metadata);
    }

    /*──────── Task Logic (unchanged except old PM checks removed) ───────*/
    function createTask(uint256 payout, bytes calldata meta, bytes32 pid) external canCreate(pid) {
        Layout storage l = _layout();
        if (payout == 0 || payout > MAX_PAYOUT || payout > type(uint128).max) revert InvalidPayout();
        if (meta.length == 0) revert InvalidString();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();

        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetExceeded();
        p.spent = uint128(newSpent);

        uint256 id = l.nextTaskId++;
        l._tasks[id] = Task(uint128(payout), Status.UNCLAIMED, address(0), pid);
        emit TaskCreated(id, pid, payout, meta);
    }

    function updateTask(uint256 id, uint256 newPayout, bytes calldata newMetadata)
        external
        canCreate(_layout()._tasks[id].projectId)
    {
        Layout storage l = _layout();
        if (newPayout > type(uint128).max) revert InvalidPayout();

        Task storage t = _task(l, id);
        Project storage p = l._projects[t.projectId];

        if (t.status == Status.CLAIMED || t.status == Status.SUBMITTED) {
            if (newMetadata.length == 0) revert InvalidString();
        } else if (t.status == Status.UNCLAIMED) {
            if (newPayout == 0 || newPayout > MAX_PAYOUT) revert InvalidPayout();
            uint256 tentative = p.spent - t.payout + newPayout;
            if (p.cap != 0 && tentative > p.cap) revert BudgetExceeded();
            p.spent = uint128(tentative);
            t.payout = uint128(newPayout);
        } else {
            revert AlreadyCompleted();
        }

        emit TaskUpdated(id, newPayout, newMetadata);
    }

    function claimTask(uint256 id) external canClaim(id) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external canAssign(_layout()._tasks[id].projectId) {
        if (assignee == address(0)) revert ZeroAddress();
        Layout storage l = _layout();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, sender);
    }

    function submitTask(uint256 id, bytes calldata metadata) external {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.CLAIMED) revert AlreadySubmitted();
        if (t.claimer != _msgSender()) revert NotClaimer();
        if (metadata.length == 0) revert InvalidString();

        t.status = Status.SUBMITTED;
        emit TaskSubmitted(id, metadata);
    }

    function completeTask(uint256 id) external nonReentrant canReview(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();

        t.status = Status.COMPLETED;
        l.token.mint(t.claimer, uint256(t.payout));
        emit TaskCompleted(id, sender);
    }

    function cancelTask(uint256 id) external canCreate(_layout()._tasks[id].projectId) {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();

        p.spent -= t.payout;
        t.status = Status.CANCELLED;
        emit TaskCancelled(id, sender);
    }

    /*────────── View Helpers ─────────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, bytes32 projectId)
    {
        Task storage t = _task(_layout(), id);
        return (t.payout, t.status, t.claimer, t.projectId);
    }

    function getProjectInfo(bytes32 pid) external view returns (uint256 cap, uint256 spent, bool isManager) {
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();
        return (p.cap, p.spent, p.managers[_msgSender()]);
    }

    /*──────── Governance / Admin ─────*/
    function setRolePerm(bytes32 role, uint8 mask) external onlyExecutor {
        _layout().rolePermGlobal[role] = mask;
    }

    function setProjectRolePerm(bytes32 pid, bytes32 role, uint8 mask) external onlyCreator projectExists(pid) {
        _layout().rolePermProj[pid][role] = mask;
        emit ProjectRolePermSet(pid, role, mask);
    }

    function setCreatorRole(bytes32 role, bool enable) external onlyExecutor {
        _layout().isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert ZeroAddress();
        _layout().executor = newExec;
        emit ExecutorSet(newExec);
    }

    /*──────── Internal Perm helpers ─────*/
    function _permMask(address user, bytes32 pid) internal view returns (uint8 m) {
        Layout storage l = _layout();
        bytes32 r = l.membership.roleOf(user);
        m = l.rolePermProj[pid][r];
        if (m == 0) m = l.rolePermGlobal[r];
    }

    function _isPM(bytes32 pid, address who) internal view returns (bool) {
        Layout storage l = _layout();
        return (who == l.executor) || l._projects[pid].managers[who];
    }

    function _checkPerm(bytes32 pid, uint8 flag) internal view {
        address s = _msgSender();
        if (!TaskPerm.has(_permMask(s, pid), flag) && !_isPM(pid, s)) revert Unauthorized();
    }

    function _setBatchRolePerm(bytes32 pid, bytes32[] calldata roles, uint8 flag) internal {
        Layout storage l = _layout();
        for (uint256 i; i < roles.length; ++i) {
            bytes32 r = roles[i];
            uint8 newMask = l.rolePermProj[pid][r] | flag;
            l.rolePermProj[pid][r] = newMask;
            emit ProjectRolePermSet(pid, r, newMask);
        }
    }

    /*──────── Utils / View (unchanged) ────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert UnknownTask();
        t = l._tasks[id];
    }

    function version() external pure returns (string memory) {
        return "v1";
    }
}
