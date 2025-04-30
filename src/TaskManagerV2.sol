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
    function roleOf(address user) external view returns (bytes32);
}

interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

/**
 * @title TaskManager V2 (adds `foo` to layout **and** `priority` to Task)
 */
contract TaskManagerV2 is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable {
    /*────────────────── Errors & constants (unchanged) ──────────────────*/
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error UnknownTask();
    error UnknownProject();
    error ProjectExists();
    error NotCreator();
    error NotMember();
    error NotPM();
    error AlreadyClaimed();
    error AlreadySubmitted();
    error AlreadyCompleted();
    error NotClaimer();
    error BudgetExceeded();
    error CapBelowCommitted();
    error NotExecutor();
    error Unauthorized();

    uint256 public constant MAX_PAYOUT = 1e24;
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*──────────────────── Data types ────────────────────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    /// @dev NEW FIELD `priority` appended last ⇒ safe
    struct Task {
        uint128 payout;
        Status status;
        address claimer;
        bytes32 projectId;
        uint64 priority; // <-- new slot 3
    }

    struct Project {
        uint128 cap;
        uint128 spent;
        bool exists;
        mapping(address => bool) managers;
    }

    /*───────────────── ERC-7201 namespaced storage ─────────────────*/
    /// @custom:storage-location erc7201:poa.taskmanager.storage
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IMembership membership;
        IParticipationToken token;
        mapping(bytes32 => bool) isCreatorRole;
        uint256 nextTaskId;
        uint256 nextProjectId;
        address executor;
        uint256 foo;
        mapping(bytes32 => uint8) rolePermGlobal;
        mapping(bytes32 => mapping(bytes32 => uint8)) rolePermProj; // project ⇒ role ⇒ mask
            // from previous upgrade
    }

    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*────────────── Events (unchanged) ────────────*/
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);
    event ProjectCreated(bytes32 indexed id, bytes metadata, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerAdded(bytes32 indexed id, address manager);
    event ProjectManagerRemoved(bytes32 indexed id, address manager);
    event ProjectDeleted(bytes32 indexed id, bytes metadata);
    event TaskCreated(uint256 indexed id, bytes32 indexed pid, uint256 payout, bytes metadata);
    event TaskUpdated(uint256 indexed id, uint256 payout, bytes metadata);
    event TaskSubmitted(uint256 indexed id, bytes metadata);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event ExecutorSet(address indexed newExecutor);
    event ProjectRolePermSet(bytes32 indexed id, bytes32 indexed role, uint8 mask);

    /*────────────── Initializer (unchanged) ─────────────*/
    function initialize(address tokenAddr, address membershipAddr, bytes32[] calldata creatorRoles, address execAddr)
        external
        initializer
    {
        if (tokenAddr == address(0) || membershipAddr == address(0) || execAddr == address(0)) revert ZeroAddress();
        __ReentrancyGuard_init();
        __Context_init();
        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddr);
        l.membership = IMembership(membershipAddr);
        l.executor = execAddr;
        for (uint256 i; i < creatorRoles.length; ++i) {
            l.isCreatorRole[creatorRoles[i]] = true;
            emit CreatorRoleUpdated(creatorRoles[i], true);
        }
        emit ExecutorSet(execAddr);
    }

    /*────────────── Modifiers ─────────────*/
    modifier onlyCreator() {
        Layout storage l = _layout();
        address s = _msgSender();
        if (!l.isCreatorRole[l.membership.roleOf(s)] && s != l.executor) revert NotCreator();
        _;
    }

    modifier onlyMember() {
        Layout storage l = _layout();
        address s = _msgSender();
        if (s != l.executor && l.membership.roleOf(s) == bytes32(0)) revert NotMember();
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

    /*───────────── Project / Task core logic ─────────────*/
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
        l._tasks[id] = Task(uint128(payout), Status.UNCLAIMED, address(0), pid, 0);
        emit TaskCreated(id, pid, payout, meta);
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
        if (l.membership.roleOf(assignee) == bytes32(0)) revert NotMember();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, sender);
    }

    function submitTask(uint256 id, bytes calldata metadata) external onlyMember {
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

    /*───────────── New V2 functionality ─────────────*/
    function setFoo(uint256 value) external onlyExecutor {
        _layout().foo = value;
    }

    function getFoo() external view returns (uint256) {
        return _layout().foo;
    }

    function setTaskPriority(uint256 id, uint64 prio) external onlyExecutor {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        t.priority = prio;
        emit TaskUpdated(id, t.payout, "priority-set");
    }

    function getTaskPriority(uint256 id) external view returns (uint64) {
        return _layout()._tasks[id].priority;
    }

    /*───────────── Permission Management ─────────────*/
    function setRolePerm(bytes32 role, uint8 mask) external onlyExecutor {
        _layout().rolePermGlobal[role] = mask;
    }

    function setProjectRolePerm(bytes32 pid, bytes32 role, uint8 mask) external onlyCreator projectExists(pid) {
        _layout().rolePermProj[pid][role] = mask;
        emit ProjectRolePermSet(pid, role, mask);
    }

    /*───────────── Internal Helpers ─────────────*/
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

    /*───────────── View Helpers ─────────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, bytes32 projectId, uint64 priority)
    {
        Task storage t = _task(_layout(), id);
        return (t.payout, t.status, t.claimer, t.projectId, t.priority);
    }

    function getProjectInfo(bytes32 pid) external view returns (uint256 cap, uint256 spent, bool isManager) {
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();
        return (p.cap, p.spent, p.managers[_msgSender()]);
    }

    /*───────────── Internal Utils ─────────────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert UnknownTask();
        t = l._tasks[id];
    }

    /*───────────── Version Helper ─────────────*/
    function version() external pure returns (string memory) {
        return "v3-with-foo+priority";
    }
}
