// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*────────────────────────── OpenZeppelin Upgradeables ────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*───────────────────────── Interface minimal stubs ───────────────────────*/
interface IMembership {
    function quickJoinMint(address newUser) external;
}

interface IUniversalAccountRegistry {
    function getUsername(address account) external view returns (string memory);
    function registerAccountQuickJoin(string memory username, address newUser) external;
}

/*──────────────────────────────  Contract  ───────────────────────────────*/
contract QuickJoin is Initializable, ContextUpgradeable, ReentrancyGuardUpgradeable {
    /* ───────── Errors ───────── */
    error InvalidAddress();
    error OnlyMasterDeploy();
    error ZeroUser();
    error UsernameTooLong();
    error NoUsername();
    error Unauthorized();

    /* ───────── Constants ────── */
    uint256 internal constant MAX_USERNAME_LEN = 64;
    bytes4 public constant MODULE_ID = bytes4(keccak256("QuickJoin"));

    /* ───────── Storage ──────── */
    IMembership private membership;
    IUniversalAccountRegistry private accountRegistry;

    address public masterDeployAddress; // set once, but rotatable by executor
    address public executor; // DAO / Timelock – hard‑authority

    /* ───────── Events ───────── */
    event AddressesUpdated(address membership, address registry, address master);
    event ExecutorUpdated(address newExecutor);
    event QuickJoined(address indexed user, bool usernameCreated);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated);

    /* ───────── Initialiser ───── */
    function initialize(address executor_, address membership_, address accountRegistry_, address masterDeploy_)
        external
        initializer
    {
        if (
            executor_ == address(0) || membership_ == address(0) || accountRegistry_ == address(0)
                || masterDeploy_ == address(0)
        ) revert InvalidAddress();

        __Context_init();
        __ReentrancyGuard_init();

        executor = executor_;
        membership = IMembership(membership_);
        accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(membership_, accountRegistry_, masterDeploy_);
        emit ExecutorUpdated(executor_);
    }

    /* ───────── Modifiers ─────── */
    modifier onlyMasterDeploy() {
        if (_msgSender() != executor && _msgSender() != masterDeployAddress) revert OnlyMasterDeploy();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != executor) revert Unauthorized();
        _;
    }

    /* ─────── Admin / DAO setters (executor‑gated) ─────── */
    function updateAddresses(address membership_, address accountRegistry_, address masterDeploy_)
        external
        onlyExecutor
    {
        if (membership_ == address(0) || accountRegistry_ == address(0) || masterDeploy_ == address(0)) {
            revert InvalidAddress();
        }

        membership = IMembership(membership_);
        accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(membership_, accountRegistry_, masterDeploy_);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert InvalidAddress();
        executor = newExec;
        emit ExecutorUpdated(newExec);
    }

    /* ───────── Internal helper ─────── */
    function _quickJoin(address user, string memory username) private nonReentrant {
        if (user == address(0)) revert ZeroUser();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        bool created;
        if (bytes(accountRegistry.getUsername(user)).length == 0) {
            if (bytes(username).length == 0) revert NoUsername(); // require username on first registration
            accountRegistry.registerAccountQuickJoin(username, user);
            created = true;
        }

        membership.quickJoinMint(user);
        emit QuickJoined(user, created);
    }

    /* ───────── Public user paths ─────── */

    /// 1) caller supplies username if they don’t have one yet
    function quickJoinNoUser(string calldata username) external {
        _quickJoin(_msgSender(), username);
    }

    /// 2) caller already registered a username elsewhere
    function quickJoinWithUser() external nonReentrant {
        string memory existing = accountRegistry.getUsername(_msgSender());
        if (bytes(existing).length == 0) revert NoUsername();
        membership.quickJoinMint(_msgSender());
        emit QuickJoined(_msgSender(), false);
    }

    /* ───────── Master‑deploy helper paths ─────── */

    function quickJoinNoUserMasterDeploy(string calldata username, address newUser) external onlyMasterDeploy {
        _quickJoin(newUser, username);
        emit QuickJoinedByMaster(_msgSender(), newUser, bytes(username).length > 0);
    }

    function quickJoinWithUserMasterDeploy(address newUser) external onlyMasterDeploy nonReentrant {
        if (newUser == address(0)) revert ZeroUser();
        string memory existing = accountRegistry.getUsername(newUser);
        if (bytes(existing).length == 0) revert NoUsername();

        membership.quickJoinMint(newUser);
        emit QuickJoinedByMaster(_msgSender(), newUser, false);
    }

    /* ───────── Misc view helpers ─────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[46] private __gap; // storage gap
}
