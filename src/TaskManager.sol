// SPDX‑License‑Identifier: MIT
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
    function setTaskManager(address tm) external;
}

/*───────────────────────  Contract  ───────────────────────*/
contract TaskManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*─────────────── Custom Errors ───────────────*/
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error UnknownTask();
    error NotCreator();
    error NotMember();
    error AlreadyClaimed();
    error AlreadySubmitted();
    error AlreadyCompleted();
    error NotClaimer();
    error MintFailed();

    /*─────────────── Constants ──────────────────*/
    uint256 public constant MAX_PAYOUT = 1e24; // 1 million tokens with 18 dec
    bytes4 public constant MODULE_ID = 0x54534b30; // "TSK0"

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
        string ipfsHash;
    }
    // roleId to allowed   (creator privilege)

    mapping(bytes32 => bool) public isCreatorRole;

    IMembership public membership;
    IParticipationToken public token;

    mapping(uint256 => Task) private _tasks;
    uint256 public nextTaskId;

    /*─────────────── Events ─────────────────────*/
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);
    event TaskCreated(uint256 indexed id, uint256 payout, string ipfsHash, string projectName);
    event TaskUpdated(uint256 indexed id, uint256 payout, string ipfsHash);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskSubmitted(uint256 indexed id, string ipfsHash);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event ProjectCreated(string name);
    event ProjectDeleted(string name);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);

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
        if (!isCreatorRole[membership.roleOf(_msgSender())]) revert NotCreator();
        _;
    }

    modifier onlyMember() {
        if (membership.roleOf(_msgSender()) == bytes32(0)) revert NotMember();
        _;
    }

    /*─────────────────── Core Logic ──────────────────*/
    function createTask(uint256 payout, string calldata ipfsHash, string calldata projectName) external onlyCreator {
        if (payout == 0 || payout > MAX_PAYOUT) revert InvalidPayout();
        if (bytes(ipfsHash).length == 0) revert InvalidString();
        if (bytes(projectName).length == 0) revert InvalidString();

        uint256 id;
        unchecked {
            id = nextTaskId++;
        }
        _tasks[id] = Task({payout: uint248(payout), status: Status.UNCLAIMED, claimer: address(0), ipfsHash: ipfsHash});
        emit TaskCreated(id, payout, ipfsHash, projectName);
    }

    /// @dev Update task before it is CLAIMED; once claimed only `ipfsHash` may change.
    function updateTask(uint256 id, uint256 newPayout, string calldata newIpfsHash) external onlyCreator {
        Task storage t = _task(id);

        if (t.status == Status.CLAIMED || t.status == Status.SUBMITTED) {
            // after claim: only allow ipfsHash bump
            if (bytes(newIpfsHash).length == 0) revert InvalidString();
            t.ipfsHash = newIpfsHash;
        } else if (t.status == Status.UNCLAIMED) {
            // before claim: allow both
            if (newPayout == 0 || newPayout > MAX_PAYOUT) revert InvalidPayout();
            if (bytes(newIpfsHash).length == 0) revert InvalidString();
            t.payout = uint248(newPayout);
            t.ipfsHash = newIpfsHash;
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

    function assignTask(uint256 id, address assignee) external onlyCreator {
        if (assignee == address(0)) revert ZeroAddress();
        if (membership.roleOf(assignee) == bytes32(0)) revert NotMember();

        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();

        t.status  = Status.CLAIMED;
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

    function completeTask(uint256 id) external nonReentrant onlyCreator {
        Task storage t = _task(id);
        if (t.status != Status.SUBMITTED) revert AlreadyCompleted();

        token.mint(t.claimer, t.payout);

        t.status = Status.COMPLETED;
        emit TaskCompleted(id, _msgSender());
    }

    /// @notice Cancel an unclaimed task to claw back storage.
    function cancelTask(uint256 id) external onlyCreator {
        Task storage t = _task(id);
        if (t.status != Status.UNCLAIMED) revert AlreadyClaimed();
        t.status = Status.CANCELLED;
        emit TaskCancelled(id, _msgSender());
    }

    /*──────────── Project signalling ───────────*/
    function createProject(string calldata name) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        emit ProjectCreated(name);
    }

    function deleteProject(string calldata name) external onlyCreator {
        if (bytes(name).length == 0) revert InvalidString();
        emit ProjectDeleted(name);
    }

    /*──────────── Governance Tools ───────────*/
    function setCreatorRole(bytes32 role, bool enable) external onlyOwner {
        isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    /*──────────── View Helpers ───────────*/
    function getTask(uint256 id)
        external
        view
        returns (uint256 payout, Status status, address claimer, string memory ipfs)
    {
        Task storage t = _task(id);
        return (t.payout, t.status, t.claimer, t.ipfsHash);
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
