// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin v5.3 Upgradeables ─────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────────── External membership interface ─────────────*/
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function isExecutiveRole(bytes32 roleId) external view returns (bool);
}

/*──────────────────  Participation Token  ──────────────────*/
contract ParticipationToken is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
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
    error Unauthorized();

    /*──────────── State ───────────*/
    address public taskManager;
    address public educationHub;
    IMembership public membership;
    address public executor;

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
    function initialize(address executor_, string calldata name_, string calldata symbol_, address membershipAddr)
        external
        initializer
    {
        if (membershipAddr == address(0) || executor_ == address(0)) revert InvalidAddress();

        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();

        membership = IMembership(membershipAddr);
        executor = executor_;
    }

    /*────────── Modifiers ─────────*/
    modifier onlyTaskOrEdu() {
        if (_msgSender() != executor && _msgSender() != taskManager && _msgSender() != educationHub) {
            revert NotTaskOrEdu();
        }
        _;
    }

    modifier onlyExec() {
        if (_msgSender() == executor) {
            _;
            return;
        }
        bytes32 role = membership.roleOf(_msgSender());
        if (role == bytes32(0) || !membership.isExecutiveRole(role)) revert NotExecutive();
        _;
    }

    modifier isMember() {
        if (_msgSender() != executor && membership.roleOf(_msgSender()) == bytes32(0)) revert NotMember();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != executor) revert Unauthorized();
        _;
    }

    /*──────── Admin setters ───────*/
    function setTaskManager(address tm) external {
        if (tm == address(0)) revert InvalidAddress();
        if (taskManager == address(0)) {
            taskManager = tm;
            emit TaskManagerSet(tm);
        } else {
            if (_msgSender() != executor) revert Unauthorized();
            taskManager = tm;
            emit TaskManagerSet(tm);
        }
    }

    function setEducationHub(address eh) external {
        if (eh == address(0)) revert InvalidAddress();
        if (educationHub == address(0)) {
            educationHub = eh;
            emit EducationHubSet(eh);
        } else {
            if (_msgSender() != executor) revert Unauthorized();
            educationHub = eh;
            emit EducationHubSet(eh);
        }
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
        if (bytes(ipfsHash).length == 0) revert ZeroAmount();

        requests[++requestCounter] =
            Request({requester: _msgSender(), amount: amount, approved: false, ipfsHash: ipfsHash});

        emit Requested(requestCounter, _msgSender(), amount, ipfsHash);
    }

    /// Execs approve – state change *after* successful mint
    function approveRequest(uint256 id) external nonReentrant onlyExec {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();
        if (r.requester == _msgSender()) revert NotRequester();

        r.approved = true;
        _mint(r.requester, r.amount);

        emit RequestApproved(id, _msgSender());
    }

    /// Cancel unapproved request – requester **or** exec
    function cancelRequest(uint256 id) external nonReentrant {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();

        bool isExec = (_msgSender() == executor) || membership.isExecutiveRole(membership.roleOf(_msgSender()));
        if (_msgSender() != r.requester && !isExec) revert NotExecutive();

        delete requests[id];
        emit RequestCancelled(id, _msgSender());
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

    /// still allow mint / burn internally
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        super._update(from, to, value);
    }

    /*───────── Version helper ─────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    /*──────── Storage gap ────────────*/
    uint256[50] private __gap;
}
