// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {ContextUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*────────── External Interfaces ──────────*/
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
}

interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

/*────────────────────── Contract ───────────────────────*/
/**
 * @title TaskManager (v5-upgradeable, namespaced-storage)
 * @custom:module-id 0x54534b32 ("TSK2")
 */
contract TaskManager is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable {
    /*────────────── Custom Errors ──────────────*/
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

    /*────────────── Constants ─────────────────*/
    uint256 public constant MAX_PAYOUT = 1e24; // 1,000,000 tokens (18 dec)
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*────────────── Data Types ────────────────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    /// @dev packed into 3 slots
    struct Task {
        uint128 payout; // fits MAX_PAYOUT
        Status status; // stored as uint8
        address claimer;
        bytes32 projectId;
    }

    struct Project {
        uint128 cap; // 0 to unlimited
        uint128 spent;
        bool exists;
        mapping(address => bool) managers;
    }

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.taskmanager.storage
    struct Layout {
        /* core mappings */
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        /* external refs */
        IMembership membership;
        IParticipationToken token;
        /* misc state */
        mapping(bytes32 => bool) isCreatorRole;
        uint256 nextTaskId;
        uint256 nextProjectId;
        address executor;
    }

    // keccak256("poa.taskmanager.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*────────────── Events ───────────────────*/
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);

    // ── Project
    event ProjectCreated(bytes32 indexed id, bytes metadata, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerAdded(bytes32 indexed id, address manager);
    event ProjectManagerRemoved(bytes32 indexed id, address manager);
    event ProjectDeleted(bytes32 indexed id, bytes metadata);

    // ── Task
    event TaskCreated(uint256 indexed id, bytes32 indexed projectId, uint256 payout, bytes metadata);
    event TaskUpdated(uint256 indexed id, uint256 payout, bytes metadata);
    event TaskSubmitted(uint256 indexed id, bytes metadata);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event ExecutorSet(address indexed newExecutor);

    /*────────────── Initializer ──────────────*/
    function initialize(
        address tokenAddress,
        address membershipAddress,
        bytes32[] calldata creatorRoleIds,
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

        for (uint256 i; i < creatorRoleIds.length; ++i) {
            l.isCreatorRole[creatorRoleIds[i]] = true;
            emit CreatorRoleUpdated(creatorRoleIds[i], true);
        }

        emit ExecutorSet(executorAddress);
    }

    /*────────────── Modifiers ────────────────*/
    modifier onlyCreator() {
        Layout storage l = _layout();
        address sender = _msgSender();
        if (!l.isCreatorRole[l.membership.roleOf(sender)] && sender != l.executor) revert NotCreator();
        _;
    }

    modifier onlyMember() {
        Layout storage l = _layout();
        address sender = _msgSender();
        if (sender != l.executor && l.membership.roleOf(sender) == bytes32(0)) revert NotMember();
        _;
    }

    modifier onlyPM(bytes32 pid) {
        Layout storage l = _layout();
        address sender = _msgSender();
        if (sender != l.executor && !l._projects[pid].managers[sender]) revert NotPM();
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

    /*───────────── Project Logic ─────────────*/
    function createProject(bytes calldata metadata, uint256 cap, address[] calldata managers)
        external
        onlyCreator
        returns (bytes32 projectId)
    {
        Layout storage l = _layout();
        if (metadata.length == 0) revert InvalidString();
        if (cap > MAX_PAYOUT) revert InvalidPayout();

        projectId = bytes32(l.nextProjectId++);
        Project storage p = l._projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        address sender = _msgSender();
        p.managers[sender] = true;
        emit ProjectManagerAdded(projectId, sender);

        for (uint256 i; i < managers.length; ++i) {
            address m = managers[i];
            if (m == address(0)) revert ZeroAddress();
            p.managers[m] = true;
            emit ProjectManagerAdded(projectId, m);
        }

        emit ProjectCreated(projectId, metadata, cap);
    }

    function updateProjectCap(bytes32 pid, uint256 newCap) external onlyCreator projectExists(pid) {
        if (newCap > MAX_PAYOUT) revert InvalidPayout();

        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (newCap != 0 && newCap < p.spent) revert CapBelowCommitted();

        uint256 old = p.cap;
        p.cap = uint128(newCap);
        emit ProjectCapUpdated(pid, old, newCap);
    }

    function addProjectManager(bytes32 pid, address mgr) external onlyCreator projectExists(pid) {
        if (mgr == address(0)) revert ZeroAddress();
        _layout()._projects[pid].managers[mgr] = true;
        emit ProjectManagerAdded(pid, mgr);
    }

    function removeProjectManager(bytes32 pid, address mgr) external onlyCreator projectExists(pid) {
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

    /*────────────── Task Logic ───────────────*/
    function createTask(uint256 payout, bytes calldata metadata, bytes32 pid) external onlyMember {
        Layout storage l = _layout();
        if (payout == 0 || payout > MAX_PAYOUT || payout > type(uint128).max) revert InvalidPayout();
        if (metadata.length == 0) revert InvalidString();

        Project storage p = l._projects[pid];
        if (!p.exists) revert UnknownProject();

        address sender = _msgSender();
        if (sender != l.executor && !l.isCreatorRole[l.membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetExceeded();
        p.spent = uint128(newSpent);

        uint256 id = l.nextTaskId++;
        l._tasks[id] = Task({payout: uint128(payout), status: Status.UNCLAIMED, claimer: address(0), projectId: pid});
        emit TaskCreated(id, pid, payout, metadata);
    }

    function updateTask(uint256 id, uint256 newPayout, bytes calldata newMetadata) external {
        Layout storage l = _layout();
        if (newPayout > type(uint128).max) revert InvalidPayout();

        Task storage t = _task(l, id);
        Project storage p = l._projects[t.projectId];

        address sender = _msgSender();
        if (sender != l.executor && !l.isCreatorRole[l.membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

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

    function claimTask(uint256 id) external onlyMember {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external {
        if (assignee == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        if (l.membership.roleOf(assignee) == bytes32(0)) revert NotMember();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();
        if (sender != l.executor && !l.isCreatorRole[l.membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

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

    function completeTask(uint256 id) external nonReentrant {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();
        if (sender != l.executor && !l.isCreatorRole[l.membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

        t.status = Status.COMPLETED;
        l.token.mint(t.claimer, uint256(t.payout));
        emit TaskCompleted(id, sender);
    }

    function cancelTask(uint256 id) external {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        Project storage p = l._projects[t.projectId];
        address sender = _msgSender();
        if (sender != l.executor && !l.isCreatorRole[l.membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

        p.spent -= t.payout;
        t.status = Status.CANCELLED;
        emit TaskCancelled(id, sender);
    }

    /*────────── Governance Tools ──────────*/
    function setCreatorRole(bytes32 role, bool enable) external onlyExecutor {
        _layout().isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert ZeroAddress();
        _layout().executor = newExec;
        emit ExecutorSet(newExec);
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

    /*────────── Internal Utils ───────────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert UnknownTask();
        t = l._tasks[id];
    }

    /*────────── Version Helper ───────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }
}
