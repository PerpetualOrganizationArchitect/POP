// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin v5.3 Upgradeables ─────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────────── External membership interface ─────────────*/
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function isExecutiveRole(bytes32 roleId) external view returns (bool);
}

/*──────────────────  Participation Token  ──────────────────*/
contract ParticipationToken is Initializable, ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*──────────── Errors ───────────*/
    error NotTaskOrEdu();
    error NotExecutive();
    error NotMember();
    error NotRequester();
    error RequestUnknown();
    error AlreadyApproved();
    error AlreadySet();
    error InvalidAddress();
    error ZeroAmount();
    error TransfersDisabled();

    /*──────────── State ───────────*/
    address public taskManager;
    address public educationHub;
    IMembership public membership;

    uint256 public requestCounter;

    struct Request {
        address requester;
        uint96 amount;
        bool approved;
        string ipfsHash;
    }

    mapping(uint256 => Request) public requests;

    /*──────────── Events ──────────*/
    event TaskManagerSet(address indexed taskManager);
    event EducationHubSet(address indexed educationHub);
    event Requested(uint256 indexed id, address indexed requester, uint96 amount, string ipfsHash);
    event RequestApproved(uint256 indexed id, address indexed approver);
    event RequestCancelled(uint256 indexed id, address indexed caller);

    /*─────────── Initialiser ──────*/
    function initialize(string calldata name_, string calldata symbol_, address membershipAddr) external initializer {
        if (membershipAddr == address(0)) revert InvalidAddress();
        __ERC20_init(name_, symbol_);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        membership = IMembership(membershipAddr);
    }

    /*────────── Modifiers ─────────*/
    modifier onlyTaskOrEdu() {
        if (msg.sender != taskManager && msg.sender != educationHub) revert NotTaskOrEdu();
        _;
    }

    modifier onlyExec() {
        bytes32 role = membership.roleOf(msg.sender);
        if (role == bytes32(0) || !membership.isExecutiveRole(role)) revert NotExecutive();
        _;
    }

    modifier isMember() {
        if (membership.roleOf(msg.sender) == bytes32(0)) revert NotMember();
        _;
    }

    /*──────── Admin setters ───────*/
    function setTaskManager(address tm) external onlyOwner {
        if (taskManager != address(0)) revert AlreadySet();
        if (tm == address(0)) revert InvalidAddress();
        taskManager = tm;
        emit TaskManagerSet(tm);
    }

    function setEducationHub(address eh) external onlyOwner {
        if (educationHub != address(0)) revert AlreadySet();
        if (eh == address(0)) revert InvalidAddress();
        educationHub = eh;
        emit EducationHubSet(eh);
    }

    /*────── Mint by authorised modules ─────*/
    function mint(address to, uint256 amount) external nonReentrant onlyTaskOrEdu {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }

    /*────────── Request flow ─────────*/
    function requestTokens(uint96 amount, string calldata ipfsHash) external isMember {
        if (amount == 0) revert ZeroAmount();
        if (bytes(ipfsHash).length == 0) revert InvalidAddress();

        unchecked {
            ++requestCounter;
        }
        requests[requestCounter] = Request({requester: msg.sender, amount: amount, approved: false, ipfsHash: ipfsHash});
        emit Requested(requestCounter, msg.sender, amount, ipfsHash);
    }

    /// Execs approve – _state change after_ successful mint
    function approveRequest(uint256 id) external nonReentrant onlyExec {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();
        if (r.requester == msg.sender) revert NotRequester();

        _mint(r.requester, r.amount); // ← external effect first
        r.approved = true;
        emit RequestApproved(id, msg.sender);
    }

    /// Optional: allow requester or exec to cancel unapproved request & free storage
    function cancelRequest(uint256 id) external nonReentrant {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();
        if (msg.sender != r.requester && !membership.isExecutiveRole(membership.roleOf(msg.sender))) {
            revert NotExecutive();
        }

        delete requests[id];
        emit RequestCancelled(id, msg.sender);
    }

    /*────── Complete transfer lockdown ─────*/
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }
    // still allow mint/burn via `_update`

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        super._update(from, to, value);
    }

    /*───────── Version helper ─────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    /*──────── Storage gap (50 left) ───*/
    uint256[50] private __gap;
}
