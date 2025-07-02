// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin v5.3 Upgradeables ─────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────────── External Hats interface ─────────────*/
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

/*──────────────────  Participation Token  ──────────────────*/
contract ParticipationToken is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    /*──────────── Errors ───────────*/
    error NotTaskOrEdu();
    error NotApprover();
    error NotMember();
    error NotRequester();
    error RequestUnknown();
    error AlreadyApproved();
    error AlreadySet();
    error InvalidAddress();
    error ZeroAmount();
    error TransfersDisabled();
    error Unauthorized();

    /*──────────── Types ───────────*/
    struct Request {
        address requester;
        uint96 amount;
        bool approved;
        string ipfsHash;
    }

    /*──────────── Hat Type Enum ───────────*/
    enum HatType { MEMBER, APPROVER }

    /*──────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.participationtoken.storage
    struct Layout {
        address taskManager;
        address educationHub;
        IHats hats;
        address executor;
        uint256 requestCounter;
        mapping(uint256 => Request) requests;
        uint256[] memberHatIds; // enumeration array for member hats
        uint256[] approverHatIds; // enumeration array for approver hats
    }

    // keccak256("poa.participationtoken.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0xc49c4cc718f2f9e8d168c340989dd4f66bf6674fc7217665b075b167908f4ee1;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────── Events ──────────*/
    event TaskManagerSet(address indexed taskManager);
    event EducationHubSet(address indexed educationHub);
    event Requested(uint256 indexed id, address indexed requester, uint96 amount, string ipfsHash);
    event RequestApproved(uint256 indexed id, address indexed approver);
    event RequestCancelled(uint256 indexed id, address indexed caller);
    event MemberHatSet(uint256 hat, bool allowed);
    event ApproverHatSet(uint256 hat, bool allowed);

    /*─────────── Initialiser ──────*/
    function initialize(
        address executor_, 
        string calldata name_, 
        string calldata symbol_, 
        address hatsAddr,
        uint256[] calldata initialMemberHats,
        uint256[] calldata initialApproverHats
    ) external initializer {
        if (hatsAddr == address(0) || executor_ == address(0)) revert InvalidAddress();

        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hatsAddr);
        l.executor = executor_;

        // Set initial member hats
        for (uint256 i; i < initialMemberHats.length;) {
            _setHatAllowed(initialMemberHats[i], true, HatType.MEMBER);
            unchecked {
                ++i;
            }
        }

        // Set initial approver hats
        for (uint256 i; i < initialApproverHats.length;) {
            _setHatAllowed(initialApproverHats[i], true, HatType.APPROVER);
            unchecked {
                ++i;
            }
        }
    }

    /*────────── Modifiers ─────────*/
    modifier onlyTaskOrEdu() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && _msgSender() != l.taskManager && _msgSender() != l.educationHub) {
            revert NotTaskOrEdu();
        }
        _;
    }

    modifier onlyApprover() {
        Layout storage l = _layout();
        if (_msgSender() == l.executor) {
            _;
            return;
        }
        if (!_hasHat(_msgSender(), HatType.APPROVER)) revert NotApprover();
        _;
    }

    modifier isMember() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !_hasHat(_msgSender(), HatType.MEMBER)) revert NotMember();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != _layout().executor) revert Unauthorized();
        _;
    }

    /*──────── Admin setters ───────*/
    function setTaskManager(address tm) external {
        if (tm == address(0)) revert InvalidAddress();
        Layout storage l = _layout();
        if (l.taskManager == address(0)) {
            l.taskManager = tm;
            emit TaskManagerSet(tm);
        } else {
            if (_msgSender() != l.executor) revert Unauthorized();
            l.taskManager = tm;
            emit TaskManagerSet(tm);
        }
    }

    function setEducationHub(address eh) external {
        if (eh == address(0)) revert InvalidAddress();
        Layout storage l = _layout();
        if (l.educationHub == address(0)) {
            l.educationHub = eh;
            emit EducationHubSet(eh);
        } else {
            if (_msgSender() != l.executor) revert Unauthorized();
            l.educationHub = eh;
            emit EducationHubSet(eh);
        }
    }

    function setMemberHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.MEMBER);
    }

    function setApproverHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.APPROVER);
    }

    function _setHatAllowed(uint256 h, bool ok, HatType hatType) internal {
        Layout storage l = _layout();
        
        if (hatType == HatType.MEMBER) {
            // Find if hat already exists
            uint256 existingIndex = type(uint256).max;
            for (uint256 i = 0; i < l.memberHatIds.length; i++) {
                if (l.memberHatIds[i] == h) {
                    existingIndex = i;
                    break;
                }
            }
            
            if (ok && existingIndex == type(uint256).max) {
                // Adding new hat (not found)
                l.memberHatIds.push(h);
                emit MemberHatSet(h, true);
            } else if (!ok && existingIndex != type(uint256).max) {
                // Removing hat (found at existingIndex)
                l.memberHatIds[existingIndex] = l.memberHatIds[l.memberHatIds.length - 1];
                l.memberHatIds.pop();
                emit MemberHatSet(h, false);
            }
        } else {
            // Find if hat already exists
            uint256 existingIndex = type(uint256).max;
            for (uint256 i = 0; i < l.approverHatIds.length; i++) {
                if (l.approverHatIds[i] == h) {
                    existingIndex = i;
                    break;
                }
            }
            
            if (ok && existingIndex == type(uint256).max) {
                // Adding new hat (not found)
                l.approverHatIds.push(h);
                emit ApproverHatSet(h, true);
            } else if (!ok && existingIndex != type(uint256).max) {
                // Removing hat (found at existingIndex)
                l.approverHatIds[existingIndex] = l.approverHatIds[l.approverHatIds.length - 1];
                l.approverHatIds.pop();
                emit ApproverHatSet(h, false);
            }
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

        Layout storage l = _layout();
        uint256 requestId = ++l.requestCounter;
        l.requests[requestId] = Request({requester: _msgSender(), amount: amount, approved: false, ipfsHash: ipfsHash});

        emit Requested(requestId, _msgSender(), amount, ipfsHash);
    }

    /// Approvers approve – state change *after* successful mint
    function approveRequest(uint256 id) external nonReentrant onlyApprover {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();
        if (r.requester == _msgSender()) revert NotRequester();

        r.approved = true;
        _mint(r.requester, r.amount);

        emit RequestApproved(id, _msgSender());
    }

    /// Cancel unapproved request – requester **or** approver
    function cancelRequest(uint256 id) external nonReentrant {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();

        bool isApprover = (_msgSender() == l.executor) || _hasHat(_msgSender(), HatType.APPROVER);
        if (_msgSender() != r.requester && !isApprover) revert NotApprover();

        delete l.requests[id];
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

    /*───────── Internal Helper Functions ─────────*/
    /// @dev Returns true if `user` wears *any* hat of the requested type.
    function _hasHat(address user, HatType hatType) internal view returns (bool) {
        Layout storage l = _layout();
        uint256[] storage ids = hatType == HatType.MEMBER ? l.memberHatIds : l.approverHatIds;
        
        uint256 len = ids.length;
        if (len == 0) return false;
        if (len == 1) return l.hats.isWearerOfHat(user, ids[0]); // micro-optimise 1-ID case

        // Build calldata in memory (cheap because ≤ 3)
        address[] memory wearers = new address[](len);
        uint256[] memory hatIds = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            wearers[i] = user;
            hatIds[i] = ids[i];
        }
        uint256[] memory balances = l.hats.balanceOfBatch(wearers, hatIds);
        for (uint256 i; i < balances.length; ++i) {
            if (balances[i] > 0) return true;
        }
        return false;
    }

    /*───────── View helpers ─────────*/
    function requests(uint256 id)
        external
        view
        returns (address requester, uint96 amount, bool approved, string memory ipfsHash)
    {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        return (r.requester, r.amount, r.approved, r.ipfsHash);
    }

    function taskManager() external view returns (address) {
        return _layout().taskManager;
    }

    function educationHub() external view returns (address) {
        return _layout().educationHub;
    }

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function requestCounter() external view returns (uint256) {
        return _layout().requestCounter;
    }

    function memberHatIds() external view returns (uint256[] memory) {
        return _layout().memberHatIds;
    }

    function approverHatIds() external view returns (uint256[] memory) {
        return _layout().approverHatIds;
    }

    /*───────── Version helper ─────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }
}
