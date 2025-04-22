// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────  OpenZeppelin Upgradeables  ──────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract Membership is Initializable, ERC721Upgradeable, ReentrancyGuardUpgradeable {
    /* ─────── Errors ─────── */
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

    /* ─────── Constants ─────── */
    uint256 private constant ONE_WEEK = 1 weeks;
    bytes32 private constant DEFAULT_ROLE = keccak256("DEFAULT");
    bytes32 private constant EXEC_ROLE = keccak256("EXECUTIVE");
    bytes4 public constant MODULE_ID = 0x4d424552; /* "MBER" */

    /* ─────── Storage ─────── */
    uint256 private _nextTokenId;

    mapping(bytes32 => string) public roleImage; // roleId to baseURI
    mapping(address => bytes32) public roleOf; // member to roleId
    mapping(bytes32 => bool) public isExecutiveRole;
    mapping(address => uint256) public lastExecAction;
    mapping(address => uint256) public lastDemotedAt;
    mapping(address => uint256) private _tokenOf; // soul‑bound tokenId
    mapping(bytes32 => bool) public roleCanVote; // voting flag per role

    address public quickJoin; // set once, rotatable by executor
    address public electionContract; // set once, rotatable by executor
    address public executor; // authoritative DAO / timelock

    /* ─────── Events ─────── */
    event Minted(address indexed member, bytes32 role, uint256 tokenId);
    event RoleChanged(address indexed member, bytes32 newRole);
    event MemberRemoved(address indexed member);
    event ExecutiveDowngraded(address indexed exec, address indexed by);
    event QuickJoinSet(address indexed quickJoin);
    event ElectionSet(address indexed election);
    event VotingRoleUpdated(bytes32 indexed role, bool canVote);
    event RoleImageSet(bytes32 indexed role, string uri);

    /* ─────── Initialiser ─────── */
    function initialize(
        address executor_,
        string calldata name_,
        string[] calldata roleNames,
        string[] calldata roleImages,
        bool[] calldata roleCanVote_,
        bytes32[] calldata executiveRoles
    ) external initializer {
        if (roleNames.length != roleImages.length || roleNames.length != roleCanVote_.length) {
            revert ArrayLengthMismatch();
        }
        if (executor_ == address(0)) revert ZeroAddress();
        executor = executor_;

        __ERC721_init(name_, "MBR");
        __ReentrancyGuard_init();

        /* role meta */
        for (uint256 i; i < roleNames.length; ++i) {
            bytes32 id = keccak256(bytes(roleNames[i]));
            roleImage[id] = roleImages[i];
            roleCanVote[id] = roleCanVote_[i];
            emit RoleImageSet(id, roleImages[i]);
        }

        /* exec roles */
        for (uint256 i; i < executiveRoles.length; ++i) {
            isExecutiveRole[executiveRoles[i]] = true;
        }
        isExecutiveRole[EXEC_ROLE] = true;

        // assure DEFAULT_ROLE has a fallback image
        if (bytes(roleImage[DEFAULT_ROLE]).length == 0 && roleImages.length > 0) {
            roleImage[DEFAULT_ROLE] = roleImages[0];
        }
    }

    /* ─────── Modifiers ─────── */
    modifier onlyExecutor() {
        if (msg.sender != executor) revert Unauthorized();
        _;
    }

    modifier onlyExecutive() {
        if (msg.sender != executor && !isExecutiveRole[roleOf[msg.sender]]) revert NotExecutive();
        _;
    }

    modifier onlyQuickJoin() {
        if (msg.sender != executor && msg.sender != quickJoin) revert NotQuickJoin();
        _;
    }

    /* ─────── Soul‑bound overrides ─────── */
    function _update(address to, uint256 id, address auth) internal override returns (address) {
        address from = _ownerOf(id);
        if (from != address(0) && to != address(0)) revert TransfersDisabled(); // no transfers
        return super._update(to, id, auth);
    }

    function setApprovalForAll(address, bool) public pure override {
        revert TransfersDisabled();
    }

    function approve(address, uint256) public pure override {
        revert TransfersDisabled();
    }

    /* ─────── Admin setters ─────── */
    function setQuickJoin(address qj) external {
        if (qj == address(0)) revert ZeroAddress();
        if (quickJoin != address(0) && msg.sender != executor) revert Unauthorized();
        quickJoin = qj;
        emit QuickJoinSet(qj);
    }

    function setElectionContract(address el) external {
        if (el == address(0)) revert ZeroAddress();
        if (electionContract != address(0) && msg.sender != executor) revert Unauthorized();
        electionContract = el;
        emit ElectionSet(el);
    }

    function setRoleImage(bytes32 role, string calldata uri) external onlyExecutor {
        roleImage[role] = uri;
        emit RoleImageSet(role, uri);
    }

    function setVotingRole(bytes32 role, bool can) external onlyExecutor {
        roleCanVote[role] = can;
        emit VotingRoleUpdated(role, can);
    }

    /* ─────── Core membership logic ─────── */
    function _issue(address to, bytes32 role) private {
        if (bytes(roleImage[role]).length == 0) revert RoleImageMissing();

        uint256 old = _tokenOf[to];
        if (old != 0) _burn(old); // replace old token

        uint256 id = ++_nextTokenId;
        _mint(to, id);

        roleOf[to] = role;
        _tokenOf[to] = id;
        emit Minted(to, role, id);
    }

    function mintOrChange(address member, bytes32 role) external {
        if (msg.sender != executor && !isExecutiveRole[roleOf[msg.sender]] && msg.sender != electionContract) {
            revert NotExecutive();
        }

        _issue(member, role);
        emit RoleChanged(member, role);
    }

    function quickJoinMint(address user) external onlyQuickJoin {
        if (roleOf[user] != bytes32(0)) revert AlreadyMember();
        _issue(user, _nextTokenId == 0 ? EXEC_ROLE : DEFAULT_ROLE);
    }

    function resign() external {
        if (roleOf[msg.sender] == bytes32(0)) revert NoMember();
        _burn(_tokenOf[msg.sender]);
        delete roleOf[msg.sender];
        delete _tokenOf[msg.sender];
        emit MemberRemoved(msg.sender);
    }

    function downgradeExecutive(address exec) external onlyExecutive {
        if (!isExecutiveRole[roleOf[exec]]) revert NotExecutive();
        if (block.timestamp < lastExecAction[msg.sender] + ONE_WEEK) revert Cooldown();
        if (block.timestamp < lastDemotedAt[exec] + ONE_WEEK) revert Cooldown();

        _issue(exec, DEFAULT_ROLE);
        lastExecAction[msg.sender] = block.timestamp;
        lastDemotedAt[exec] = block.timestamp;
        emit ExecutiveDowngraded(exec, msg.sender);
    }

    /* ─────── Views ─────── */
    function isMember(address u) external view returns (bool) {
        return roleOf[u] != bytes32(0);
    }

    function canVote(address u) external view returns (bool) {
        return roleCanVote[roleOf[u]];
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf(id) == address(0)) revert InvalidTokenId();
        string memory uri = roleImage[roleOf[ownerOf(id)]];
        if (bytes(uri).length == 0) uri = roleImage[DEFAULT_ROLE];
        return uri;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[40] private __gap;
}
