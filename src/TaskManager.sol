// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*───────────  OpenZeppelin v5.3 Upgradeables  ──────────*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────── External Interfaces ──────────*/
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
}

interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
}

/*───────────────────────  Contract  ───────────────────────*/
contract TaskManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
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
    uint256 public constant MAX_PAYOUT = 1e24; // 1,000,000 tokens (18 dec)
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*─────────────── Data Types ─────────────────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    struct Task {
        uint248 payout;
        Status status;
        address claimer;
        bytes32 projectId;
        string ipfsHash;
    }

    struct Project {
        uint128 cap; // 0 ⇒ unlimited
        uint128 spent; // always tracked (even if cap==0)
        bool exists;
        mapping(address => bool) managers;
    }

    /*─────────────── Storage ─────────────────────*/
    mapping(bytes32 => Project) private _projects;
    mapping(uint256 => bytes32) private _taskProject;
    mapping(uint256 => Task) private _tasks;

    IMembership public membership;
    IParticipationToken public token;

    mapping(bytes32 => bool) public isCreatorRole;
    uint256 public nextTaskId;

    address public executor;

    /*─────────────── Events ─────────────────────*/
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);

    // ── Project
    event ProjectCreated(bytes32 indexed id, string name, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerAdded(bytes32 indexed id, address manager);
    event ProjectManagerRemoved(bytes32 indexed id, address manager);
    event ProjectDeleted(bytes32 indexed id, string name);

    // ── Task
    event TaskCreated(uint256 indexed id, bytes32 indexed projectId, uint256 payout, string ipfsHash);
    event TaskUpdated(uint256 indexed id, uint256 payout, string ipfsHash);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskSubmitted(uint256 indexed id, string ipfsHash);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event ExecutorSet(address indexed newExecutor);
    /*──────────────── Initialiser ───────────────*/

    function initialize(address tokenAddress, address membershipAddress, bytes32[] calldata creatorRoleIds)
        external
        initializer
    {
        if (tokenAddress == address(0) || membershipAddress == address(0)) revert ZeroAddress();
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();

        token = IParticipationToken(tokenAddress);
        membership = IMembership(membershipAddress);

        for (uint256 i; i < creatorRoleIds.length; ++i) {
            isCreatorRole[creatorRoleIds[i]] = true;
            emit CreatorRoleUpdated(creatorRoleIds[i], true);
        }
    }

    /*──────────────── Modifiers ─────────────────*/
    modifier onlyCreator() {
        if (!isCreatorRole[membership.roleOf(_msgSender())] && _msgSender() != executor) revert NotCreator();
        _;
    }

    modifier onlyMember() {
        if (_msgSender() != executor && membership.roleOf(_msgSender()) == bytes32(0)) {
            revert NotMember();
        }
        _;
    }

    modifier onlyPM(bytes32 pid) {
        if (_msgSender() != executor && !_projects[pid].managers[_msgSender()]) revert NotPM();
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
    function _pid(string calldata name) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(name));
    }

    function createProject(
        string calldata name,
        uint256 cap, // 0 ⇒ unlimited
        address[] calldata managers
    ) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        if (cap > MAX_PAYOUT) revert InvalidPayout();

        bytes32 pid = _pid(name);
        if (_projects[pid].exists) revert ProjectExists();

        Project storage p = _projects[pid];
        p.cap = uint128(cap);
        p.exists = true;

        // auto‑add caller as PM (remove later if you want zero managers)
        p.managers[_msgSender()] = true;
        emit ProjectManagerAdded(pid, _msgSender());

        for (uint256 i; i < managers.length; ++i) {
            address m = managers[i];
            if (m == address(0)) revert ZeroAddress();
            p.managers[m] = true;
            emit ProjectManagerAdded(pid, m);
        }

        emit ProjectCreated(pid, name, cap);
    }

    function updateProjectCap(string calldata name, uint256 newCap) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        if (newCap > MAX_PAYOUT) revert InvalidPayout();

        bytes32 pid = _pid(name);
        Project storage p = _projects[pid];
        if (!p.exists) revert UnknownProject();
        if (newCap != 0 && newCap < p.spent) revert CapBelowCommitted();

        uint256 old = p.cap;
        p.cap = uint128(newCap);
        emit ProjectCapUpdated(pid, old, newCap);
    }

    function addProjectManager(string calldata name, address manager) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        if (manager == address(0)) revert ZeroAddress();
        bytes32 pid = _pid(name);
        Project storage p = _projects[pid];
        if (!p.exists) revert UnknownProject();
        p.managers[manager] = true;
        emit ProjectManagerAdded(pid, manager);
    }

    function removeProjectManager(string calldata name, address manager) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        bytes32 pid = _pid(name);
        Project storage p = _projects[pid];
        if (!p.exists) revert UnknownProject();
        p.managers[manager] = false;
        emit ProjectManagerRemoved(pid, manager);
    }

    function deleteProject(string calldata name) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        bytes32 pid = _pid(name);
        Project storage p = _projects[pid];
        if (!p.exists) revert UnknownProject();
        if (p.cap != 0 && p.spent != p.cap) revert CapBelowCommitted();
        delete _projects[pid];
        emit ProjectDeleted(pid, name);
    }

    /*─────────────────── Task Logic ──────────────────*/
    function createTask(uint256 payout, string calldata ipfsHash, string calldata projectName) external onlyMember {
        if (payout == 0 || payout > MAX_PAYOUT) revert InvalidPayout();
        if (bytes(ipfsHash).length == 0) revert InvalidString();

        bytes32 pid = _pid(projectName);
        Project storage p = _projects[pid];
        if (!p.exists) revert UnknownProject();

        // auth
        if (_msgSender() != executor && !isCreatorRole[membership.roleOf(_msgSender())] && !p.managers[_msgSender()]) {
            revert NotPM();
        }

        // always track spent; enforce only when capped
        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetExceeded();
        p.spent = uint128(newSpent);

        uint256 id = nextTaskId++;
        _tasks[id] = Task({
            payout: uint248(payout),
            status: Status.UNCLAIMED,
            claimer: address(0),
            projectId: pid,
            ipfsHash: ipfsHash
        });
        _taskProject[id] = pid;

        emit TaskCreated(id, pid, payout, ipfsHash);
    }

    function updateTask(uint256 id, uint256 newPayout, string calldata newIpfsHash) external {
        Task storage t = _task(id);
        bytes32 pid = _taskProject[id];
        Project storage p = _projects[pid];

        if (_msgSender() != executor && !isCreatorRole[membership.roleOf(_msgSender())] && !p.managers[_msgSender()]) {
            revert NotPM();
        }

        if (t.status == Status.CLAIMED || t.status == Status.SUBMITTED) {
            if (bytes(newIpfsHash).length == 0) revert InvalidString();
            t.ipfsHash = newIpfsHash;
        } else if (t.status == Status.UNCLAIMED) {
            uint256 oldPayout = t.payout;
            if (newPayout == 0 || newPayout > MAX_PAYOUT) revert InvalidPayout();

            uint256 tentative = p.spent - oldPayout + newPayout;
            if (p.cap != 0 && tentative > p.cap) revert BudgetExceeded();
            p.spent = uint128(tentative);

            t.payout = uint248(newPayout);
            if (bytes(newIpfsHash).length != 0) t.ipfsHash = newIpfsHash;
        } else {
            revert AlreadyCompleted();
        }

        emit TaskUpdated(id, newPayout, newIpfsHash);
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

        bytes32 pid = _taskProject[id];
        if (
            _msgSender() != executor && !isCreatorRole[membership.roleOf(_msgSender())]
                && !_projects[pid].managers[_msgSender()]
        ) {
            revert NotPM();
        }

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, _msgSender());
    }

    function submitTask(uint256 id, string calldata ipfsHash) external onlyMember {
        Task storage t = _task(id);
        if (t.status != Status.CLAIMED) revert AlreadySubmitted();
        if (t.claimer != _msgSender()) revert NotClaimer();
        if (bytes(ipfsHash).length == 0) revert InvalidString();

        t.status = Status.SUBMITTED;
        t.ipfsHash = ipfsHash;
        emit TaskSubmitted(id, ipfsHash);
    }

    function completeTask(uint256 id) external nonReentrant {
        Task storage t = _task(id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        bytes32 pid = _taskProject[id];
        if (
            _msgSender() != executor && !isCreatorRole[membership.roleOf(_msgSender())]
                && !_projects[pid].managers[_msgSender()]
        ) {
            revert NotPM();
        }

        token.mint(t.claimer, t.payout);
        t.status = Status.COMPLETED;
        emit TaskCompleted(id, _msgSender());
    }

    function cancelTask(uint256 id) external {
        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        bytes32 pid = _taskProject[id];
        Project storage p = _projects[pid];
        if (_msgSender() != executor && !isCreatorRole[membership.roleOf(_msgSender())] && !p.managers[_msgSender()]) {
            revert NotPM();
        }

        // always refund
        p.spent -= uint128(t.payout);

        t.status = Status.CANCELLED;
        emit TaskCancelled(id, _msgSender());
    }

    /*──────────── Governance Tools ───────────*/
    function setCreatorRole(bytes32 role, bool enable) external onlyExecutor {
        isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    function setExecutor(address newExecutor) external {
        if (newExecutor == address(0)) revert ZeroAddress();
        if (executor != address(0)) {
            // After first set, only executor can update
            if (msg.sender != executor) revert Unauthorized();
        }
        executor = newExecutor;
        emit ExecutorSet(newExecutor);
    }

    /*──────────── View Helpers ───────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, bytes32 projectId, string memory ipfs)
    {
        Task storage t = _task(id);
        return (t.payout, t.status, t.claimer, t.projectId, t.ipfsHash);
    }

    function getProjectInfo(string calldata name) external view returns (uint256 cap, uint256 spent, bool isManager) {
        bytes32 pid = _pid(name);
        Project storage p = _projects[pid];
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

    uint256[100] private __gap;
}
