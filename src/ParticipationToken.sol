// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/**  
 * @dev External membership interface. 
 *      Interface to interact with Membership contract.
 */
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function isExecutiveRole(bytes32 roleId) external view returns (bool);
    function canVote(address user) external view returns (bool);
}

contract ParticipationToken is Initializable, ERC20Upgradeable, OwnableUpgradeable {
    /*──────────────────────────── Errors ───────────────────────────*/
    error NotTaskOrEdu();
    error NotExecutive();
    error NotMember();
    error NotRequester();
    error RequestUnknown();
    error AlreadyApproved();
    error AlreadySet();
    error InvalidAddress();
    error TransfersDisabled();
    /*──────────────────────────── Constants ─────────────────────────*/
    bytes32 private constant EXEC_ROLE = keccak256("EXECUTIVE");

    /*──────────────────────────── State Vars ─────────────────────────*/
    address public taskManager;
    address public educationHub;
    IMembership public membership;

    uint256 public requestCounter;

    struct Request {
        address requester;
        uint256 amount;
        string ipfsHash;
        bool approved;
    }
    mapping(uint256 => Request) public requests;

    /*────────────────────────────── Events ───────────────────────────*/
    event TaskManagerSet(address indexed taskManager);
    event EducationHubSet(address indexed educationHub);
    event Minted(address indexed to, uint256 amount);
    event Requested(uint256 indexed id, address indexed requester, uint256 amount, string ipfsHash);
    event RequestApproved(uint256 indexed id, address indexed approver);

    /*────────────────────────── Initializer ──────────────────────────*/
    function initialize(
        string calldata name_,
        string calldata symbol_,
        address membershipAddress
    ) external initializer {
        if (membershipAddress == address(0)) revert InvalidAddress();
        __ERC20_init(name_, symbol_);
        __Ownable_init(msg.sender);

        membership = IMembership(membershipAddress);
        // taskManager & educationHub remain zero until set by owner
    }

    /*──────────────────────── Modifiers ─────────────────────────────*/
    modifier onlyTaskOrEdu() {
        if (msg.sender != taskManager && msg.sender != educationHub) revert NotTaskOrEdu();
        _;
    }
    modifier onlyExec() {
        bytes32 role = membership.roleOf(msg.sender);
        if (!membership.isExecutiveRole(role)) revert NotExecutive();
        _;
    }
    modifier isMember() {
        bytes32 role = membership.roleOf(msg.sender);
        if (role == bytes32(0)) revert NotMember();
        _;
    }

    /*──────────────────────── Admin Setters ─────────────────────────*/
    /// @notice Can only be set once by owner
    function setTaskManager(address tm) external onlyOwner {
        if (taskManager != address(0)) revert AlreadySet();
        if (tm == address(0)) revert InvalidAddress();
        taskManager = tm;
        emit TaskManagerSet(tm);
    }

    /// @notice Can only be set once by owner
    function setEducationHub(address eh) external onlyOwner {
        if (educationHub != address(0)) revert AlreadySet();
        if (eh == address(0)) revert InvalidAddress();
        educationHub = eh;
        emit EducationHubSet(eh);
    }

    /*────────────────────────── Minting Logic ───────────────────────*/
    /// @notice Only the Task Manager or Education Hub may mint arbitrarily
    function mint(address to, uint256 amount) external onlyTaskOrEdu {
        _mint(to, amount);
        emit Minted(to, amount);
    }

    /*────────────────────────── Request Flow ─────────────────────────*/
    /// @notice Members may request tokens, providing an IPFS proof
    function requestTokens(uint256 amount, string calldata ipfsHash) external isMember {
        unchecked { requestCounter++; }
        requests[requestCounter] = Request({
            requester: msg.sender,
            amount:    amount,
            ipfsHash:  ipfsHash,
            approved:  false
        });
        emit Requested(requestCounter, msg.sender, amount, ipfsHash);
    }

    /// @notice Only executives may approve others' requests
    function approveRequest(uint256 id) external onlyExec {
        Request storage r = requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved)            revert AlreadyApproved();
        if (r.requester == msg.sender) revert NotRequester();

        r.approved = true;
        _mint(r.requester, r.amount);
        emit RequestApproved(id, msg.sender);
    }

    /*──────────────────────── Disable Transfers ─────────────────────*/
    function _update(address from, address to, uint256 value) internal virtual override {
        // allow mint (from=0) and burn (to=0)
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        super._update(from, to, value);
    }

    /*──────────────────────── Storage Gap ───────────────────────────*/
    uint256[49] private __gap;
}
