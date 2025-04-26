// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*───────────  OpenZeppelin v5.3 Upgradeables  ──────────*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";

/*────────── External Interfaces ──────────*/
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
}

interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

/*───────────────────────  Contract  ───────────────────────*/
contract TaskManager is Initializable, ReentrancyGuardUpgradeable, ContextUpgradeable {
    /*─────────────── Custom Errors ───────────────*/
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

    /*─────────────── Constants ──────────────────*/
    uint256 public constant MAX_PAYOUT = 1e24; // 1,000,000 tokens (18 decimals)
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*─────────────── Data Types ─────────────────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    /// @dev packed into 3 storage slots (payout+status, claimer, projectId)
    struct Task {
        uint128 payout; // fits MAX_PAYOUT
        Status status; // stored as uint8
        address claimer;
        bytes32 projectId;
    }

    struct Project {
        uint128 cap; // 0 ⇒ unlimited
        uint128 spent; // always tracked (even if cap==0)
        bool exists;
        mapping(address => bool) managers;
    }

    /*─────────────── Storage ─────────────────────*/
    mapping(bytes32 => Project) private _projects;
    mapping(uint256 => Task) private _tasks;

    IMembership public membership;
    IParticipationToken public token;

    mapping(bytes32 => bool) public isCreatorRole;
    uint256 public nextTaskId;
    uint256 public nextProjectId;

    address public executor;

    /*─────────────── Events ─────────────────────*/
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

    /*──────────────── Initialiser ───────────────*/
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

        token = IParticipationToken(tokenAddress);
        membership = IMembership(membershipAddress);
        executor = executorAddress;

        for (uint256 i; i < creatorRoleIds.length;) {
            isCreatorRole[creatorRoleIds[i]] = true;
            emit CreatorRoleUpdated(creatorRoleIds[i], true);
            unchecked {
                ++i;
            }
        }

        emit ExecutorSet(executorAddress);
    }

    /*──────────────── Modifiers ─────────────────*/
    modifier onlyCreator() {
        address sender = _msgSender();
        if (!isCreatorRole[membership.roleOf(sender)] && sender != executor) revert NotCreator();
        _;
    }

    modifier onlyMember() {
        address sender = _msgSender();
        if (sender != executor && membership.roleOf(sender) == bytes32(0)) revert NotMember();
        _;
    }

    modifier onlyPM(bytes32 pid) {
        address sender = _msgSender();
        if (sender != executor && !_projects[pid].managers[sender]) revert NotPM();
        _;
    }

    modifier projectExists(bytes32 pid) {
        if (!_projects[pid].exists) revert UnknownProject();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != executor) revert NotExecutor();
        _;
    }

    /*─────────────────── Project Logic ──────────────────*/
    function createProject(
        bytes calldata metadata,
        uint256 cap, // 0 to unlimited
        address[] calldata managers
    ) external onlyCreator returns (bytes32 projectId) {
        if (metadata.length == 0) revert InvalidString();
        if (cap > MAX_PAYOUT) revert InvalidPayout();

        projectId = bytes32(nextProjectId);
        unchecked {
            ++nextProjectId;
        }

        Project storage p = _projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        address sender = _msgSender();
        p.managers[sender] = true;
        emit ProjectManagerAdded(projectId, sender);

        for (uint256 i; i < managers.length;) {
            address m = managers[i];
            if (m == address(0)) revert ZeroAddress();
            p.managers[m] = true;
            emit ProjectManagerAdded(projectId, m);
            unchecked {
                ++i;
            }
        }

        emit ProjectCreated(projectId, metadata, cap);
    }

    function updateProjectCap(bytes32 projectId, uint256 newCap) external onlyCreator projectExists(projectId) {
        if (newCap > MAX_PAYOUT) revert InvalidPayout();

        Project storage p = _projects[projectId];
        if (newCap != 0 && newCap < p.spent) revert CapBelowCommitted();

        uint256 old = p.cap;
        p.cap = uint128(newCap);
        emit ProjectCapUpdated(projectId, old, newCap);
    }

    function addProjectManager(bytes32 projectId, address manager) external onlyCreator projectExists(projectId) {
        if (manager == address(0)) revert ZeroAddress();
        _projects[projectId].managers[manager] = true;
        emit ProjectManagerAdded(projectId, manager);
    }

    function removeProjectManager(bytes32 projectId, address manager) external onlyCreator projectExists(projectId) {
        _projects[projectId].managers[manager] = false;
        emit ProjectManagerRemoved(projectId, manager);
    }

    function deleteProject(bytes32 projectId, bytes calldata metadata) external onlyCreator {
        if (metadata.length == 0) revert InvalidString();
        Project storage p = _projects[projectId];
        if (!p.exists) revert UnknownProject();
        if (p.cap != 0 && p.spent != p.cap) revert CapBelowCommitted();

        delete _projects[projectId]; // mapped struct & its storage pointers
        emit ProjectDeleted(projectId, metadata);
    }

    /*─────────────────── Task Logic ──────────────────*/
    function createTask(
        uint256 payout,
        bytes calldata metadata, // compressed bytes
        bytes32 projectId
    ) external onlyMember {
        if (payout == 0 || payout > MAX_PAYOUT) revert InvalidPayout();
        if (metadata.length == 0) revert InvalidString();
        if (payout > type(uint128).max) revert InvalidPayout();

        Project storage p = _projects[projectId];
        if (!p.exists) revert UnknownProject();

        address sender = _msgSender();
        if (sender != executor && !isCreatorRole[membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetExceeded();
        p.spent = uint128(newSpent);

        uint256 id = nextTaskId;
        unchecked {
            ++nextTaskId;
        }

        _tasks[id] =
            Task({payout: uint128(payout), status: Status.UNCLAIMED, claimer: address(0), projectId: projectId});

        emit TaskCreated(id, projectId, payout, metadata);
    }

    function updateTask(uint256 id, uint256 newPayout, bytes calldata newMetadata) external {
        require(newPayout <= type(uint128).max, "Overflw");
        Task storage t = _task(id);
        bytes32 pid = t.projectId;
        Project storage p = _projects[pid];

        address sender = _msgSender();
        if (sender != executor && !isCreatorRole[membership.roleOf(sender)] && !p.managers[sender]) {
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
        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external {
        if (assignee == address(0)) revert ZeroAddress();
        if (membership.roleOf(assignee) == bytes32(0)) revert NotMember();

        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        bytes32 pid = t.projectId;
        address sender = _msgSender();
        if (sender != executor && !isCreatorRole[membership.roleOf(sender)] && !_projects[pid].managers[sender]) {
            revert NotPM();
        }

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, sender);
    }

    function submitTask(uint256 id, bytes calldata metadata) external onlyMember {
        Task storage t = _task(id);
        if (t.status != Status.CLAIMED) revert AlreadySubmitted();
        if (t.claimer != _msgSender()) revert NotClaimer();
        if (metadata.length == 0) revert InvalidString();

        t.status = Status.SUBMITTED;
        emit TaskSubmitted(id, metadata);
    }

    function completeTask(uint256 id) external nonReentrant {
        Task storage t = _task(id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        bytes32 pid = t.projectId;
        if (!_projects[pid].exists) revert UnknownProject();
        address sender = _msgSender();
        if (sender != executor && !isCreatorRole[membership.roleOf(sender)] && !_projects[pid].managers[sender]) {
            revert NotPM();
        }

        t.status = Status.COMPLETED;
        token.mint(t.claimer, uint256(t.payout));
        emit TaskCompleted(id, sender);
    }

    function cancelTask(uint256 id) external {
        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        bytes32 pid = t.projectId;
        Project storage p = _projects[pid];

        address sender = _msgSender();
        if (sender != executor && !isCreatorRole[membership.roleOf(sender)] && !p.managers[sender]) {
            revert NotPM();
        }

        p.spent -= t.payout;
        t.status = Status.CANCELLED;
        emit TaskCancelled(id, sender);
    }

    /*──────────── Governance Tools ───────────*/
    function setCreatorRole(bytes32 role, bool enable) external onlyExecutor {
        isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    function setExecutor(address newExecutor) external onlyExecutor {
        if (newExecutor == address(0)) revert ZeroAddress();
        executor = newExecutor;
        emit ExecutorSet(newExecutor);
    }

    /*──────────── View Helpers ───────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, bytes32 projectId)
    {
        Task storage t = _task(id);
        return (t.payout, t.status, t.claimer, t.projectId);
    }

    function getProjectInfo(bytes32 projectId) external view returns (uint256 cap, uint256 spent, bool isManager) {
        Project storage p = _projects[projectId];
        if (!p.exists) revert UnknownProject();
        return (p.cap, p.spent, p.managers[_msgSender()]);
    }

    /*──────────── Internal Utils ───────────*/
    function _task(uint256 id) internal view returns (Task storage t) {
        if (id >= nextTaskId) revert UnknownTask();
        t = _tasks[id];
    }

    /*──────────── Version & Gap ───────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[99] private __gap;
}
