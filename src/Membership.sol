// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────  OpenZeppelin Upgradeables  ──────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract Membership is Initializable, ERC721Upgradeable, ContextUpgradeable, ReentrancyGuardUpgradeable {
    /*────────────────────────────   Errors   ───────────────────────────────*/
    error NotExecutive();
    error NotQuickJoin();
    error RoleImageMissing();
    error AlreadyMember();
    error NoMember();
    error Cooldown();
    error TransfersDisabled();
    error ArrayLengthMismatch();
    error ZeroAddress();
    error InvalidTokenId();
    error Unauthorized();

    /*────────────────────────────  Constants  ──────────────────────────────*/
    uint256 private constant ONE_WEEK = 1 weeks;
    bytes32 private constant DEFAULT_ROLE = keccak256("DEFAULT");
    bytes32 private constant EXEC_ROLE = keccak256("EXECUTIVE");
    bytes4 public constant MODULE_ID = 0x4d424552; /* "MBER" */

    /*────────────────────────────  State Vars  ─────────────────────────────*/
    uint256 private _nextTokenId;

    mapping(bytes32 => string) public roleImage; // roleId ⇒ baseURI
    mapping(address => bytes32) public roleOf; // member ⇒ roleId
    mapping(bytes32 => bool) public isExecutiveRole;
    mapping(address => uint256) public lastExecAction;
    mapping(address => uint256) public lastDemotedAt;
    mapping(address => uint256) private _tokenOf; // soul‑bound token
    mapping(bytes32 => bool) public roleCanVote; // voting flag per role

    address public quickJoin; // immutable once set
    address public electionContract; // up‑gradable
    address public executor; // immutable once set

    /*──────────────────────────────  Events  ───────────────────────────────*/
    event Minted(address indexed member, bytes32 role, uint256 tokenId);
    event RoleChanged(address indexed member, bytes32 newRole);
    event MemberRemoved(address indexed member);
    event ExecutiveDowngraded(address indexed executive, address indexed downgrader);
    event QuickJoinSet(address indexed quickJoin);
    event ElectionSet(address indexed election);
    event VotingRoleUpdated(bytes32 indexed role, bool canVote);
    event RoleImageSet(bytes32 indexed role, string uri);

    /*──────────────────────────── Initialiser ──────────────────────────────*/
    function initialize(
        address _executor,
        string calldata _name,
        string[] calldata _roleNames,
        string[] calldata _roleImages,
        bool[] calldata _roleCanVote,
        bytes32[] calldata _executiveRoles
    ) external initializer {
        if (_roleNames.length != _roleImages.length || _roleNames.length != _roleCanVote.length) {
            revert ArrayLengthMismatch();
        }
        if (_executor == address(0)) revert ZeroAddress();
        executor = _executor;

        __ERC721_init(_name, "MBR");
        __Context_init();
        __ReentrancyGuard_init();

        /* store role images & voting flags */
        for (uint256 i; i < _roleNames.length;) {
            bytes32 roleId = keccak256(bytes(_roleNames[i]));
            roleImage[roleId] = _roleImages[i];
            roleCanVote[roleId] = _roleCanVote[i];
            emit RoleImageSet(roleId, _roleImages[i]);
            unchecked {
                ++i;
            }
        }

        /* executive roles */
        for (uint256 i; i < _executiveRoles.length;) {
            isExecutiveRole[_executiveRoles[i]] = true;
            unchecked {
                ++i;
            }
        }
        isExecutiveRole[EXEC_ROLE] = true;

        // guarantee DEFAULT_ROLE has an image
        if (bytes(roleImage[DEFAULT_ROLE]).length == 0 && _roleImages.length > 0) {
            roleImage[DEFAULT_ROLE] = _roleImages[0];
        }
    }

    /*──────────────────────── Modifiers / Checks ──────────────────────────*/
    modifier onlyExecutive() {
        if (_msgSender() != executor && !isExecutiveRole[roleOf[_msgSender()]]) revert NotExecutive();
        _;
    }

    modifier onlyQuickJoin() {
        if (_msgSender() != executor && _msgSender() != quickJoin) revert NotQuickJoin();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != executor) revert Unauthorized();
        _;
    }

    /*─────────────────── Soul‑bound Transfer Overrides ────────────────────*/
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        return super._update(to, tokenId, auth);
    }

    function setApprovalForAll(address, bool) public pure override {
        revert TransfersDisabled();
    }

    function approve(address, uint256) public pure override {
        revert TransfersDisabled();
    }

    /*──────────────────────────  Admin Setters  ───────────────────────────*/
    function setQuickJoin(address _quickJoin) external {
        if (_quickJoin == address(0)) revert ZeroAddress();
        if (quickJoin != address(0) && _msgSender() != executor) revert Unauthorized();
        quickJoin = _quickJoin;
        emit QuickJoinSet(_quickJoin);
    }

    function setElectionContract(address _election) external {
        if (_election == address(0)) revert ZeroAddress();
        if (electionContract != address(0) && _msgSender() != executor) revert Unauthorized();
        electionContract = _election;
        emit ElectionSet(_election);
    }

    function setRoleImage(bytes32 roleId, string calldata uri) external onlyExecutor {
        roleImage[roleId] = uri;
        emit RoleImageSet(roleId, uri);
    }

    function setVotingRole(bytes32 role, bool can) external onlyExecutor {
        roleCanVote[role] = can;
        emit VotingRoleUpdated(role, can);
    }

    /*──────────────────────────  Membership Logic  ─────────────────────────*/
    function _issue(address to, bytes32 roleId) private nonReentrant {
        if (bytes(roleImage[roleId]).length == 0) revert RoleImageMissing();

        // burn previous token if exists
        uint256 old = _tokenOf[to];
        if (old != 0) _burn(old);

        uint256 tokenId;
        unchecked {
            tokenId = ++_nextTokenId;
        }
        _mint(to, tokenId);

        roleOf[to] = roleId;
        _tokenOf[to] = tokenId;

        emit Minted(to, roleId, tokenId);
    }

    function mintOrChange(address member, bytes32 roleId) external {
        if (_msgSender() != executor && !isExecutiveRole[roleOf[_msgSender()]] && _msgSender() != electionContract) {
            revert NotExecutive();
        }

        _issue(member, roleId);
        emit RoleChanged(member, roleId);
    }

    function quickJoinMint(address newUser) external onlyQuickJoin {
        if (roleOf[newUser] != bytes32(0)) revert AlreadyMember();
        bytes32 role = (_nextTokenId == 0) ? EXEC_ROLE : DEFAULT_ROLE;
        _issue(newUser, role);
    }

    function resign() external {
        if (roleOf[_msgSender()] == bytes32(0)) revert NoMember();
        _burn(_tokenOf[_msgSender()]);
        delete roleOf[_msgSender()];
        delete _tokenOf[_msgSender()];
        emit MemberRemoved(_msgSender());
    }

    function downgradeExecutive(address exec) external onlyExecutive {
        /* target *must* currently be an executive */
        if (!isExecutiveRole[roleOf[exec]]) revert NotExecutive();
        if (block.timestamp < lastExecAction[_msgSender()] + ONE_WEEK) revert Cooldown();
        if (block.timestamp < lastDemotedAt[exec] + ONE_WEEK) revert Cooldown();

        _issue(exec, DEFAULT_ROLE);
        lastExecAction[_msgSender()] = block.timestamp;
        lastDemotedAt[exec] = block.timestamp;
        emit ExecutiveDowngraded(exec, _msgSender());
    }

    /*────────────────────────────  Read Helpers  ───────────────────────────*/
    function isMember(address user) external view returns (bool) {
        return roleOf[user] != bytes32(0);
    }

    function canVote(address user) external view returns (bool) {
        return roleCanVote[roleOf[user]];
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        if (_ownerOf(tokenId) == address(0)) revert InvalidTokenId();
        address holder = ownerOf(tokenId);
        string memory uri = roleImage[roleOf[holder]];
        if (bytes(uri).length == 0) uri = roleImage[DEFAULT_ROLE];
        return uri;
    }

    /*──────────────────────  Version & Storage gap  ───────────────────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[40] private __gap;
}
