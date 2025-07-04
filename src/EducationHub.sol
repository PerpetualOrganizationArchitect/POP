// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/*──────── External interfaces ────────*/
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";

interface IParticipationToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function setEducationHub(address eh) external;
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
        uint48 nextModuleId; // packed with executor address
        address executor; // 20 bytes + 6 bytes = 26 bytes (fits in one slot)
        IHats hats;
        IParticipationToken token;
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint256[] memberHatIds; // enumeration array for member hats
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
    event CreatorHatSet(uint256 indexed hatId, bool enabled);
    event MemberHatSet(uint256 indexed hatId, bool enabled);

    event ExecutorSet(address indexed newExecutor);
    event TokenSet(address indexed newToken);
    event HatsSet(address indexed newHats);

    /*────────── Initialiser ────────*/
    function initialize(
        address tokenAddr,
        address hatsAddr,
        address executorAddr,
        uint256[] calldata creatorHatIds,
        uint256[] calldata memberHatIds
    ) external initializer {
        if (tokenAddr == address(0) || hatsAddr == address(0) || executorAddr == address(0)) revert ZeroAddress();

        __Context_init();
        __ReentrancyGuard_init();
        __Pausable_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddr);
        l.hats = IHats(hatsAddr);
        l.executor = executorAddr;

        emit TokenSet(tokenAddr);
        emit HatsSet(hatsAddr);
        emit ExecutorSet(executorAddr);

        // Initialize creator hats using HatManager
        for (uint256 i; i < creatorHatIds.length;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHatIds[i], true);
            emit CreatorHatSet(creatorHatIds[i], true);
            unchecked {
                ++i;
            }
        }

        // Initialize member hats using HatManager
        for (uint256 i; i < memberHatIds.length;) {
            HatManager.setHatInArray(l.memberHatIds, memberHatIds[i], true);
            emit MemberHatSet(memberHatIds[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /*────────── Hat Management ─────*/
    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.creatorHatIds, h, ok);
        emit CreatorHatSet(h, ok);
    }

    function setMemberHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.memberHatIds, h, ok);
        emit MemberHatSet(h, ok);
    }

    /*────────── Modifiers ─────────*/
    modifier onlyMember() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !_hasMemberHat(_msgSender())) revert NotMember();
        _;
    }

    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !_hasCreatorHat(_msgSender())) revert NotCreator();
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

    function setHats(address newHats) external onlyExecutor {
        if (newHats == address(0)) revert ZeroAddress();
        _layout().hats = IHats(newHats);
        emit HatsSet(newHats);
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
        uint48 id = l.nextModuleId;
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
        Layout storage l = _layout();
        Module storage m = _module(l, id);
        if (newMetadata.length == 0) revert InvalidBytes();
        if (newPayout == 0 || newPayout > type(uint128).max) revert InvalidPayout();

        m.payout = uint128(newPayout);
        emit ModuleUpdated(id, newPayout, newMetadata);
    }

    function removeModule(uint256 id) external onlyCreator whenNotPaused {
        Layout storage l = _layout();
        _module(l, id); // existence check
        delete l._modules[id];
        emit ModuleRemoved(id);
    }

    /*────────── Learner path ───────*/
    function completeModule(uint256 id, uint8 answer) external nonReentrant onlyMember whenNotPaused {
        Layout storage l = _layout();
        Module storage m = _module(l, id);
        if (_isCompleted(l, _msgSender(), id)) revert AlreadyCompleted();
        if (keccak256(abi.encodePacked(answer)) != m.answerHash) revert InvalidAnswer();

        l.token.mint(_msgSender(), m.payout);
        _setCompleted(l, _msgSender(), id);

        emit ModuleCompleted(id, _msgSender());
    }

    /*────────── View helpers ───────*/
    function getModule(uint256 id) external view returns (uint256 payout, bool exists) {
        Layout storage l = _layout();
        Module storage m = _module(l, id);
        return (m.payout, m.exists);
    }

    function hasCompleted(address learner, uint256 id) external view returns (bool) {
        Layout storage l = _layout();
        return _isCompleted(l, learner, id);
    }

    /*────────── Internal utils ───────*/
    function _module(Layout storage l, uint256 id) internal view returns (Module storage m) {
        m = l._modules[id];
        if (!m.exists) revert ModuleUnknown();
    }

    function _isCompleted(Layout storage l, address user, uint256 id) internal view returns (bool) {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        return l._progress[user][word] & bit != 0;
    }

    function _setCompleted(Layout storage l, address user, uint256 id) internal {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        unchecked {
            l._progress[user][word] |= bit;
        }
    }

    /*────────── Internal Helper Functions ─────────── */
    /// @dev Returns true if `user` wears *any* creator hat.
    function _hasCreatorHat(address user) internal view returns (bool) {
        Layout storage l = _layout();
        return HatManager.hasAnyHat(l.hats, l.creatorHatIds, user);
    }

    /// @dev Returns true if `user` wears *any* member hat.
    function _hasMemberHat(address user) internal view returns (bool) {
        Layout storage l = _layout();
        return HatManager.hasAnyHat(l.hats, l.memberHatIds, user);
    }

    /*────────── Public getters for storage variables ─────────*/
    function nextModuleId() external view returns (uint256) {
        return _layout().nextModuleId;
    }

    function creatorHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().creatorHatIds);
    }

    function memberHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().memberHatIds);
    }

    function token() external view returns (IParticipationToken) {
        return _layout().token;
    }

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    /*────────── Hat Management View Functions ─────────── */
    function creatorHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().creatorHatIds);
    }

    function memberHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().memberHatIds);
    }

    function isCreatorHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().creatorHatIds, hatId);
    }

    function isMemberHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().memberHatIds, hatId);
    }

    /*────────── Version ───────*/
    function version() external pure returns (string memory) {
        return "v1";
    }
}
