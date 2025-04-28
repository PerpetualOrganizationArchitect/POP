// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*──────── External interfaces ────────*/
interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function setEducationHub(address eh) external;
}

interface IMembership {
    function isMember(address user) external view returns (bool);
    function roleOf(address user) external view returns (bytes32);
}

/*────────────────── EducationHub ─────────────────*/
/// @title EducationHub – on‑chain learning modules that reward participation tokens
/// @notice Metadata is emitted in events as compressed bytes rather than stored on‑chain
contract EducationHub is Initializable, ContextUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /*────────── Constants ─────────*/
    bytes4 public constant MODULE_ID = 0x45445548; /* "EDUH" */

    /*────────── Errors ─────────*/
    error ZeroAddress();
    error InvalidBytes();
    error InvalidPayout();
    error InvalidAnswer();
    error NotMember();
    error NotCreator();
    error NotExecutor();
    error ModuleExists();
    error ModuleUnknown();
    error AlreadyCompleted();

    /*────────── Types ─────────*/
    struct Module {
        bytes32 answerHash;
        uint128 payout;
        bool exists;
    }

    /*────────── ERC-7201 Storage ─────────*/
    /// @custom:storage-location erc7201:poa.educationhub.storage
    struct Layout {
        mapping(uint256 => Module) _modules;
        mapping(address => mapping(uint256 => uint256)) _progress;
        uint256 nextModuleId;
        mapping(bytes32 => bool) isCreatorRole;
        IParticipationToken token;
        IMembership membership;
        address executor; // DAO / Timelock / Governor
    }

    // keccak256("poa.educationhub.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x5dc09eed2545e1c49e29265cd02140e8b217f2e2a19c33f42e35fa06d63dcb0a;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*────────── Events ─────────*/
    event ModuleCreated(uint256 indexed id, uint256 payout, bytes metadata);
    event ModuleUpdated(uint256 indexed id, uint256 payout, bytes metadata);
    event ModuleRemoved(uint256 indexed id);
    event ModuleCompleted(uint256 indexed id, address indexed learner);
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);

    event ExecutorSet(address indexed newExecutor);
    event TokenSet(address indexed newToken);
    event MembershipSet(address indexed newMembership);

    /*────────── Initialiser ────────*/
    function initialize(
        address tokenAddr,
        address membershipAddr,
        address executorAddr,
        bytes32[] calldata creatorRoleIds
    ) external initializer {
        if (tokenAddr == address(0) || membershipAddr == address(0) || executorAddr == address(0)) revert ZeroAddress();

        __Context_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddr);
        l.membership = IMembership(membershipAddr);
        l.executor = executorAddr;

        emit TokenSet(tokenAddr);
        emit MembershipSet(membershipAddr);
        emit ExecutorSet(executorAddr);

        for (uint256 i; i < creatorRoleIds.length;) {
            l.isCreatorRole[creatorRoleIds[i]] = true;
            emit CreatorRoleUpdated(creatorRoleIds[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /*────────── Modifiers ─────────*/
    modifier onlyMember() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !l.membership.isMember(_msgSender())) revert NotMember();
        _;
    }

    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !l.isCreatorRole[l.membership.roleOf(_msgSender())]) revert NotCreator();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != _layout().executor) revert NotExecutor();
        _;
    }

    /*────────── DAO / Admin Setters ───────*/
    function setExecutor(address newExec) external {
        Layout storage l = _layout();
        if (newExec == address(0)) revert ZeroAddress();
        if (_msgSender() != l.executor) revert NotExecutor();
        l.executor = newExec;
        emit ExecutorSet(newExec);
    }

    function setToken(address newToken) external onlyExecutor {
        if (newToken == address(0)) revert ZeroAddress();
        _layout().token = IParticipationToken(newToken);
        emit TokenSet(newToken);
    }

    function setMembership(address newMembership) external onlyExecutor {
        if (newMembership == address(0)) revert ZeroAddress();
        _layout().membership = IMembership(newMembership);
        emit MembershipSet(newMembership);
    }

    function setCreatorRole(bytes32 role, bool enable) external onlyExecutor {
        _layout().isCreatorRole[role] = enable;
        emit CreatorRoleUpdated(role, enable);
    }

    /*────────── Pause Control (executor) ───────*/
    function pause() external {
        if (_msgSender() != _layout().executor) revert NotExecutor();
        _pause();
    }

    function unpause() external {
        if (_msgSender() != _layout().executor) revert NotExecutor();
        _unpause();
    }

    /*────────── Module CRUD ────────*/
    function createModule(bytes calldata metadata, uint256 payout, uint8 correctAnswer)
        external
        onlyCreator
        whenNotPaused
    {
        if (metadata.length == 0) revert InvalidBytes();
        if (payout == 0 || payout > type(uint128).max) revert InvalidPayout();

        Layout storage l = _layout();
        uint256 id = l.nextModuleId;
        unchecked {
            ++l.nextModuleId;
        }

        l._modules[id] =
            Module({answerHash: keccak256(abi.encodePacked(correctAnswer)), payout: uint128(payout), exists: true});

        emit ModuleCreated(id, payout, metadata);
    }

    function updateModule(uint256 id, bytes calldata newMetadata, uint256 newPayout)
        external
        onlyCreator
        whenNotPaused
    {
        Module storage m = _module(id);
        if (newMetadata.length == 0) revert InvalidBytes();
        if (newPayout == 0 || newPayout > type(uint128).max) revert InvalidPayout();

        m.payout = uint128(newPayout);
        emit ModuleUpdated(id, newPayout, newMetadata);
    }

    function removeModule(uint256 id) external onlyCreator whenNotPaused {
        _module(id); // existence check
        delete _layout()._modules[id];
        emit ModuleRemoved(id);
    }

    /*────────── Learner path ───────*/
    function completeModule(uint256 id, uint8 answer) external nonReentrant onlyMember whenNotPaused {
        Module storage m = _module(id);
        if (_isCompleted(_msgSender(), id)) revert AlreadyCompleted();
        if (keccak256(abi.encodePacked(answer)) != m.answerHash) revert InvalidAnswer();

        Layout storage l = _layout();
        l.token.mint(_msgSender(), m.payout);
        _setCompleted(_msgSender(), id);

        emit ModuleCompleted(id, _msgSender());
    }

    /*────────── View helpers ───────*/
    function getModule(uint256 id) external view returns (uint256 payout, bool exists) {
        Module storage m = _module(id);
        return (m.payout, m.exists);
    }

    function hasCompleted(address learner, uint256 id) external view returns (bool) {
        return _isCompleted(learner, id);
    }

    /*────────── Internal utils ───────*/
    function _module(uint256 id) internal view returns (Module storage m) {
        Layout storage l = _layout();
        m = l._modules[id];
        if (!m.exists) revert ModuleUnknown();
    }

    function _isCompleted(address user, uint256 id) internal view returns (bool) {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        return _layout()._progress[user][word] & bit != 0;
    }

    function _setCompleted(address user, uint256 id) internal {
        Layout storage l = _layout();
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        unchecked {
            l._progress[user][word] |= bit;
        }
    }

    /*────────── Public getters for storage variables ─────────*/
    function nextModuleId() external view returns (uint256) {
        return _layout().nextModuleId;
    }

    function isCreatorRole(bytes32 role) external view returns (bool) {
        return _layout().isCreatorRole[role];
    }

    function token() external view returns (IParticipationToken) {
        return _layout().token;
    }

    function membership() external view returns (IMembership) {
        return _layout().membership;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    /*────────── Version ───────*/
    function version() external pure returns (string memory) {
        return "v1";
    }
}
