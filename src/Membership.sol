// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────  OpenZeppelin Upgradeables  ──────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract Membership is Initializable, ERC721Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*────────────────────────────   Errors   ───────────────────────────────*/
    error NotExecutive();
    error NotQuickJoin();
    error RoleImageMissing();
    error AlreadyMember();
    error NoMember();
    error Cooldown();
    error TransfersDisabled();
    error ArrayLengthMismatch();
    error NotOwner();

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
    address public electionContract; // upgradable

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
        address _owner,
        string calldata _name,
        string[] calldata _roleNames,
        string[] calldata _roleImages,
        bool[] calldata _roleCanVote,
        bytes32[] calldata _executiveRoles
    ) external initializer {
        require(_owner != address(0), "owner=0");
        if (_roleNames.length != _roleImages.length || _roleNames.length != _roleCanVote.length) {
            revert ArrayLengthMismatch();
        }

        __ERC721_init(_name, "MBR");
        __Ownable_init(_owner);
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

        /* exec roles */
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
        if (!isExecutiveRole[roleOf[msg.sender]]) revert NotExecutive();
        _;
    }

    modifier onlyQuickJoin() {
        if (msg.sender != quickJoin) revert NotQuickJoin();
        _;
    }

    /*─────────────────── Soul‑bound Transfer Overrides ────────────────────*/
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert TransfersDisabled();
        }
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
        if (quickJoin != address(0)) {
            // After first set, only owner can change
            if (msg.sender != owner()) revert NotOwner();
        }
        quickJoin = _quickJoin;
        emit QuickJoinSet(_quickJoin);
    }

    function setElectionContract(address _election) external {
        if (electionContract != address(0)) {
            // After first set, only owner can change
            if (msg.sender != owner()) revert NotOwner();
        }
        electionContract = _election;
        emit ElectionSet(_election);
    }

    function setRoleImage(bytes32 roleId, string calldata uri) external onlyOwner {
        roleImage[roleId] = uri;
        emit RoleImageSet(roleId, uri);
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
        } // (A‑3 gas)
        _mint(to, tokenId);

        roleOf[to] = roleId;
        _tokenOf[to] = tokenId;

        emit Minted(to, roleId, tokenId);
    }

    function mintOrChange(address member, bytes32 roleId) external {
        if (!isExecutiveRole[roleOf[msg.sender]] && msg.sender != electionContract) revert NotExecutive();

        _issue(member, roleId);
        emit RoleChanged(member, roleId);
    }

    function quickJoinMint(address newUser) external onlyQuickJoin {
        if (roleOf[newUser] != bytes32(0)) revert AlreadyMember();
        bytes32 role = _nextTokenId == 0 ? EXEC_ROLE : DEFAULT_ROLE;
        _issue(newUser, role);
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

    function setVotingRole(bytes32 role, bool can) external onlyOwner {
        roleCanVote[role] = can;
        emit VotingRoleUpdated(role, can);
    }

    /*────────────────────────────  Read Helpers  ───────────────────────────*/
    function isMember(address user) external view returns (bool) {
        return roleOf[user] != bytes32(0);
    }

    function canVote(address user) external view returns (bool) {
        return roleCanVote[roleOf[user]];
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "invalid id");
        address holder = ownerOf(tokenId);
        string memory uri = roleImage[roleOf[holder]];
        if (bytes(uri).length == 0) uri = roleImage[DEFAULT_ROLE];
        return uri;
    }

    /* Upgrade beacon test hook */
    function version() external pure returns (string memory) {
        return "v1";
    }

    /* storage gap for future variables */
    uint256[40] private __gap;
}
