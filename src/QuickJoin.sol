// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*────────────────────────── OpenZeppelin v5.3 Upgradeables ────────────────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

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

    /* ───────── ERC-7201 Storage ──────── */
    /// @custom:storage-location erc7201:poa.quickjoin.storage
    struct Layout {
        IMembership membership;
        IUniversalAccountRegistry accountRegistry;
        address masterDeployAddress;
        address executor;
    }

    // keccak256("poa.quickjoin.storage")
    bytes32 private constant _STORAGE_SLOT = 0x566f0545117c69d7a3001f74fa210927792975a5c779e9cbf2876fbc68ef7fa2;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

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

        Layout storage l = _layout();
        l.executor = executor_;
        l.membership = IMembership(membership_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(membership_, accountRegistry_, masterDeploy_);
        emit ExecutorUpdated(executor_);
    }

    /* ───────── Modifiers ─────── */
    modifier onlyMasterDeploy() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && _msgSender() != l.masterDeployAddress) revert OnlyMasterDeploy();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != _layout().executor) revert Unauthorized();
        _;
    }

    /* ─────── Admin / DAO setters (executor-gated) ─────── */
    function updateAddresses(address membership_, address accountRegistry_, address masterDeploy_)
        external
        onlyExecutor
    {
        if (membership_ == address(0) || accountRegistry_ == address(0) || masterDeploy_ == address(0)) {
            revert InvalidAddress();
        }

        Layout storage l = _layout();
        l.membership = IMembership(membership_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(membership_, accountRegistry_, masterDeploy_);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert InvalidAddress();
        _layout().executor = newExec;
        emit ExecutorUpdated(newExec);
    }

    /* ───────── Internal helper ─────── */
    function _quickJoin(address user, string memory username) private nonReentrant {
        if (user == address(0)) revert ZeroUser();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        Layout storage l = _layout();
        bool created;

        if (bytes(l.accountRegistry.getUsername(user)).length == 0) {
            if (bytes(username).length == 0) revert NoUsername();
            l.accountRegistry.registerAccountQuickJoin(username, user);
            created = true;
        }

        l.membership.quickJoinMint(user);
        emit QuickJoined(user, created);
    }

    /* ───────── Public user paths ─────── */

    /// 1) caller supplies username if they don’t have one yet
    function quickJoinNoUser(string calldata username) external {
        _quickJoin(_msgSender(), username);
    }

    /// 2) caller already registered a username elsewhere
    function quickJoinWithUser() external nonReentrant {
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(_msgSender());
        if (bytes(existing).length == 0) revert NoUsername();
        l.membership.quickJoinMint(_msgSender());
        emit QuickJoined(_msgSender(), false);
    }

    /* ───────── Master-deploy helper paths ─────── */

    function quickJoinNoUserMasterDeploy(string calldata username, address newUser) external onlyMasterDeploy {
        _quickJoin(newUser, username);
        emit QuickJoinedByMaster(_msgSender(), newUser, bytes(username).length > 0);
    }

    function quickJoinWithUserMasterDeploy(address newUser) external onlyMasterDeploy nonReentrant {
        if (newUser == address(0)) revert ZeroUser();
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(newUser);
        if (bytes(existing).length == 0) revert NoUsername();
        l.membership.quickJoinMint(newUser);
        emit QuickJoinedByMaster(_msgSender(), newUser, false);
    }

    /* ───────── Misc view helpers ─────── */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
