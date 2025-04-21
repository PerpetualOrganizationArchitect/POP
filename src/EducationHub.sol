// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
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
contract EducationHub is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /*────────── Constants ─────────*/
    bytes4 public constant MODULE_ID = 0x45445548; /* "EDUH" */

    /*────────── Errors ─────────*/
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error InvalidAnswer();
    error NotMember();
    error NotExecutive();
    error ModuleExists();
    error ModuleUnknown();
    error AlreadyCompleted();

    /*────────── Types / Storage ─────────*/
    struct Module {
        bytes32 answerHash;
        uint256 payout;
        string ipfsHash;
        bool exists;
    }

    mapping(uint256 => Module) private _modules;
    mapping(address => mapping(uint256 => uint256)) private _progress;
    uint256 public nextModuleId;

    // roleId to allowed (creator privilege)
    mapping(bytes32 => bool) public isCreatorRole;

    IParticipationToken public token;
    IMembership public membership;

    /*────────── Events ─────────*/
    event ModuleCreated(uint256 indexed id, string ipfsHash, uint256 payout);
    event ModuleUpdated(uint256 indexed id, string ipfsHash, uint256 payout);
    event ModuleRemoved(uint256 indexed id);
    event ModuleCompleted(uint256 indexed id, address indexed learner);
    event CreatorRoleUpdated(bytes32 indexed role, bool enabled);

    /*────────── Initialiser ────────*/
    function initialize(address tokenAddr, address membershipAddr, bytes32[] calldata creatorRoleIds)
        external
        initializer
    {
        if (tokenAddr == address(0) || membershipAddr == address(0)) revert ZeroAddress();
        __Ownable_init(_msgSender());
        __ReentrancyGuard_init();
        __Pausable_init();

        token = IParticipationToken(tokenAddr);
        membership = IMembership(membershipAddr);

        for (uint256 i; i < creatorRoleIds.length; ++i) {
            isCreatorRole[creatorRoleIds[i]] = true;
            emit CreatorRoleUpdated(creatorRoleIds[i], true);
        }
    }

    /*────────── Modifiers ─────────*/
    modifier onlyMember() {
        if (!membership.isMember(_msgSender())) revert NotMember();
        _;
    }

    modifier onlyCreator() {
        if (!isCreatorRole[membership.roleOf(_msgSender())]) revert NotExecutive();
        _;
    }

    /*────────── Module CRUD ────────*/
    function createModule(string calldata ipfsHash, uint256 payout, uint8 correctAnswer)
        external
        onlyCreator
        whenNotPaused
    {
        if (bytes(ipfsHash).length == 0) revert InvalidString();
        if (payout == 0) revert InvalidPayout();

        uint256 id;
        unchecked {
            id = nextModuleId++;
        }

        _modules[id] = Module({
            answerHash: keccak256(abi.encodePacked(correctAnswer)),
            payout: payout,
            ipfsHash: ipfsHash,
            exists: true
        });

        emit ModuleCreated(id, ipfsHash, payout);
    }

    function updateModule(uint256 id, string calldata newIpfsHash, uint256 newPayout)
        external
        onlyCreator
        whenNotPaused
    {
        Module storage m = _module(id);
        if (bytes(newIpfsHash).length == 0) revert InvalidString();
        if (newPayout == 0) revert InvalidPayout();

        m.ipfsHash = newIpfsHash;
        m.payout = newPayout;

        emit ModuleUpdated(id, newIpfsHash, newPayout);
    }

    function removeModule(uint256 id) external onlyCreator whenNotPaused {
        _module(id);
        delete _modules[id];
        emit ModuleRemoved(id);
    }

    /*────────── Learner path ───────*/
    function completeModule(uint256 id, uint8 answer) external nonReentrant onlyMember whenNotPaused {
        Module storage m = _module(id);
        if (_isCompleted(_msgSender(), id)) revert AlreadyCompleted();
        if (keccak256(abi.encodePacked(answer)) != m.answerHash) revert InvalidAnswer();

        token.mint(_msgSender(), m.payout);

        _setCompleted(_msgSender(), id);
        emit ModuleCompleted(id, _msgSender());
    }

    /*────────── View helpers ───────*/
    function getModule(uint256 id) external view returns (uint256 payout, string memory ipfsHash, bool exists) {
        Module storage m = _module(id);
        return (m.payout, m.ipfsHash, m.exists);
    }

    function hasCompleted(address learner, uint256 id) external view returns (bool) {
        return _isCompleted(learner, id);
    }

    /*────────── Admin Guard rails ─────────*/
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /*────────── Creator Role Management ───────*/
    function setCreatorRole(bytes32 role, bool enabled) external onlyOwner {
        isCreatorRole[role] = enabled;
        emit CreatorRoleUpdated(role, enabled);
    }

    /*────────── Internal utils ───────*/
    function _module(uint256 id) internal view returns (Module storage m) {
        m = _modules[id];
        if (!m.exists) revert ModuleUnknown();
    }

    function _isCompleted(address user, uint256 id) internal view returns (bool) {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        return _progress[user][word] & bit != 0;
    }

    function _setCompleted(address user, uint256 id) internal {
        uint256 word = id >> 8;
        uint256 bit = 1 << (id & 0xff);
        unchecked {
            _progress[user][word] |= bit;
        }
    }

    /*────────── Version / Gap ───────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[42] private __gap;
}
