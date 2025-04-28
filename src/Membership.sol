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

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.membership.storage
    struct Layout {
        /* ─────── Core Storage ─────── */
        uint256 _nextTokenId;
        mapping(bytes32 => string) roleImage; // roleId to baseURI
        mapping(address => bytes32) roleOf; // member to roleId
        mapping(bytes32 => bool) isExecutiveRole;
        mapping(address => uint256) lastExecAction;
        mapping(address => uint256) lastDemotedAt;
        mapping(address => uint256) _tokenOf; // soul‑bound tokenId
        mapping(bytes32 => bool) roleCanVote; // voting flag per role
        /* ─────── Administrative Addresses ─────── */
        address quickJoin; // set once, rotatable by executor
        address electionContract; // set once, rotatable by executor
        address executor; // authoritative DAO / timelock
    }

    // keccak256("poa.membership.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0xee63a658f61e1047aaffc2cd263e58ed6906d1be391d3fb1f8e04e44738846b6;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

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

        Layout storage l = _layout();
        l.executor = executor_;

        __ERC721_init(name_, "MBR");
        __ReentrancyGuard_init();

        /* role meta */
        for (uint256 i; i < roleNames.length; ++i) {
            bytes32 id = keccak256(bytes(roleNames[i]));
            l.roleImage[id] = roleImages[i];
            l.roleCanVote[id] = roleCanVote_[i];
            emit RoleImageSet(id, roleImages[i]);
        }

        /* exec roles */
        for (uint256 i; i < executiveRoles.length; ++i) {
            l.isExecutiveRole[executiveRoles[i]] = true;
        }
        l.isExecutiveRole[EXEC_ROLE] = true;

        // assure DEFAULT_ROLE has a fallback image
        if (bytes(l.roleImage[DEFAULT_ROLE]).length == 0 && roleImages.length > 0) {
            l.roleImage[DEFAULT_ROLE] = roleImages[0];
        }
    }

    /* ─────── Modifiers ─────── */
    modifier onlyExecutor() {
        Layout storage l = _layout();
        if (msg.sender != l.executor) revert Unauthorized();
        _;
    }

    modifier onlyExecutive() {
        Layout storage l = _layout();
        if (msg.sender != l.executor && !l.isExecutiveRole[l.roleOf[msg.sender]]) revert NotExecutive();
        _;
    }

    modifier onlyQuickJoin() {
        Layout storage l = _layout();
        if (msg.sender != l.executor && msg.sender != l.quickJoin) revert NotQuickJoin();
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
        Layout storage l = _layout();
        if (qj == address(0)) revert ZeroAddress();
        if (l.quickJoin != address(0) && msg.sender != l.executor) revert Unauthorized();
        l.quickJoin = qj;
        emit QuickJoinSet(qj);
    }

    function setElectionContract(address el) external {
        Layout storage l = _layout();
        if (el == address(0)) revert ZeroAddress();
        if (l.electionContract != address(0) && msg.sender != l.executor) revert Unauthorized();
        l.electionContract = el;
        emit ElectionSet(el);
    }

    function setRoleImage(bytes32 role, string calldata uri) external onlyExecutor {
        _layout().roleImage[role] = uri;
        emit RoleImageSet(role, uri);
    }

    function setVotingRole(bytes32 role, bool can) external onlyExecutor {
        _layout().roleCanVote[role] = can;
        emit VotingRoleUpdated(role, can);
    }

    /* ─────── Core membership logic ─────── */
    function _issue(address to, bytes32 role) private {
        Layout storage l = _layout();
        if (bytes(l.roleImage[role]).length == 0) revert RoleImageMissing();

        uint256 old = l._tokenOf[to];
        if (old != 0) _burn(old); // replace old token

        uint256 id = ++l._nextTokenId;
        _mint(to, id);

        l.roleOf[to] = role;
        l._tokenOf[to] = id;
        emit Minted(to, role, id);
    }

    function mintOrChange(address member, bytes32 role) external {
        Layout storage l = _layout();
        if (msg.sender != l.executor && !l.isExecutiveRole[l.roleOf[msg.sender]] && msg.sender != l.electionContract) {
            revert NotExecutive();
        }

        _issue(member, role);
        emit RoleChanged(member, role);
    }

    function quickJoinMint(address user) external onlyQuickJoin {
        Layout storage l = _layout();
        if (l.roleOf[user] != bytes32(0)) revert AlreadyMember();
        _issue(user, l._nextTokenId == 0 ? EXEC_ROLE : DEFAULT_ROLE);
    }

    function resign() external {
        Layout storage l = _layout();
        if (l.roleOf[msg.sender] == bytes32(0)) revert NoMember();
        _burn(l._tokenOf[msg.sender]);
        delete l.roleOf[msg.sender];
        delete l._tokenOf[msg.sender];
        emit MemberRemoved(msg.sender);
    }

    function downgradeExecutive(address exec) external onlyExecutive {
        Layout storage l = _layout();
        if (!l.isExecutiveRole[l.roleOf[exec]]) revert NotExecutive();
        if (block.timestamp < l.lastExecAction[msg.sender] + ONE_WEEK) revert Cooldown();
        if (block.timestamp < l.lastDemotedAt[exec] + ONE_WEEK) revert Cooldown();

        _issue(exec, DEFAULT_ROLE);
        l.lastExecAction[msg.sender] = block.timestamp;
        l.lastDemotedAt[exec] = block.timestamp;
        emit ExecutiveDowngraded(exec, msg.sender);
    }

    /* ─────── Views ─────── */
    function isMember(address u) external view returns (bool) {
        return _layout().roleOf[u] != bytes32(0);
    }

    function canVote(address u) external view returns (bool) {
        return _layout().roleCanVote[_layout().roleOf[u]];
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        Layout storage l = _layout();
        if (_ownerOf(id) == address(0)) revert InvalidTokenId();
        string memory uri = l.roleImage[l.roleOf[ownerOf(id)]];
        if (bytes(uri).length == 0) uri = l.roleImage[DEFAULT_ROLE];
        return uri;
    }

    function roleOf(address user) external view returns (bytes32) {
        return _layout().roleOf[user];
    }

    function roleImage(bytes32 role) external view returns (string memory) {
        return _layout().roleImage[role];
    }

    function isExecutiveRole(bytes32 role) external view returns (bool) {
        return _layout().isExecutiveRole[role];
    }

    function lastExecAction(address user) external view returns (uint256) {
        return _layout().lastExecAction[user];
    }

    function lastDemotedAt(address user) external view returns (uint256) {
        return _layout().lastDemotedAt[user];
    }

    function roleCanVote(bytes32 role) external view returns (bool) {
        return _layout().roleCanVote[role];
    }

    function quickJoin() external view returns (address) {
        return _layout().quickJoin;
    }

    function electionContract() external view returns (address) {
        return _layout().electionContract;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }
}
