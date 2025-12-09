// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*────────────────────────── OpenZeppelin v5.3 Upgradeables ────────────────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ContextUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*───────────────────────── Interface minimal stubs ───────────────────────*/
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";

interface IUniversalAccountRegistry {
    function getUsername(address account) external view returns (string memory);
    function registerAccountQuickJoin(string memory username, address newUser) external;
}

interface IExecutorHatMinter {
    function mintHatsForUser(address user, uint256[] calldata hatIds) external;
}

interface IUniversalPasskeyAccountFactory {
    function createAccount(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        returns (address account);
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
    error PasskeyFactoryNotSet();
    error AccountAlreadyRegistered();

    /* ───────── Constants ────── */
    uint256 internal constant MAX_USERNAME_LEN = 64;
    bytes4 public constant MODULE_ID = bytes4(keccak256("QuickJoin"));

    /* ───────── ERC-7201 Storage ──────── */
    /// @custom:storage-location erc7201:poa.quickjoin.storage
    struct Layout {
        IHats hats;
        IUniversalAccountRegistry accountRegistry;
        address masterDeployAddress;
        address executor;
        uint256[] memberHatIds; // hat IDs to mint when users join
        IUniversalPasskeyAccountFactory universalFactory; // Universal factory for passkey accounts
    }

    /* ───────── Passkey Enrollment Struct ──────── */
    struct PasskeyEnrollment {
        bytes32 credentialId;
        bytes32 publicKeyX;
        bytes32 publicKeyY;
        uint256 salt;
    }

    // keccak256("poa.quickjoin.storage")
    bytes32 private constant _STORAGE_SLOT = 0x566f0545117c69d7a3001f74fa210927792975a5c779e9cbf2876fbc68ef7fa2;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───────── Events ───────── */
    event AddressesUpdated(address hats, address registry, address master);
    event ExecutorUpdated(address newExecutor);
    event MemberHatIdsUpdated(uint256[] hatIds);
    event QuickJoined(address indexed user, bool usernameCreated, uint256[] hatIds);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated, uint256[] hatIds);
    event UniversalFactoryUpdated(address indexed universalFactory);
    event QuickJoinedWithPasskey(
        address indexed account, string username, bytes32 indexed credentialId, uint256[] hatIds
    );
    event QuickJoinedWithPasskeyByMaster(
        address indexed master, address indexed account, string username, bytes32 indexed credentialId, uint256[] hatIds
    );

    /* ───────── Initialiser ───── */
    function initialize(
        address executor_,
        address hats_,
        address accountRegistry_,
        address masterDeploy_,
        uint256[] calldata memberHatIds_
    ) external initializer {
        if (
            executor_ == address(0) || hats_ == address(0) || accountRegistry_ == address(0)
                || masterDeploy_ == address(0)
        ) revert InvalidAddress();

        __Context_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.executor = executor_;
        l.hats = IHats(hats_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        // Set member hat IDs using HatManager
        for (uint256 i = 0; i < memberHatIds_.length; i++) {
            HatManager.setHatInArray(l.memberHatIds, memberHatIds_[i], true);
        }

        emit AddressesUpdated(hats_, accountRegistry_, masterDeploy_);
        emit ExecutorUpdated(executor_);
        emit MemberHatIdsUpdated(memberHatIds_);
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
    function updateAddresses(address hats_, address accountRegistry_, address masterDeploy_) external onlyExecutor {
        if (hats_ == address(0) || accountRegistry_ == address(0) || masterDeploy_ == address(0)) {
            revert InvalidAddress();
        }

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(hats_, accountRegistry_, masterDeploy_);
    }

    function updateMemberHatIds(uint256[] calldata memberHatIds_) external onlyExecutor {
        Layout storage l = _layout();

        // Clear existing hat IDs using HatManager
        HatManager.clearHatArray(l.memberHatIds);

        // Set new hat IDs using HatManager
        for (uint256 i = 0; i < memberHatIds_.length; i++) {
            HatManager.setHatInArray(l.memberHatIds, memberHatIds_[i], true);
        }

        emit MemberHatIdsUpdated(memberHatIds_);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert InvalidAddress();
        _layout().executor = newExec;
        emit ExecutorUpdated(newExec);
    }

    function setUniversalFactory(address factory) external onlyExecutor {
        _layout().universalFactory = IUniversalPasskeyAccountFactory(factory);
        emit UniversalFactoryUpdated(factory);
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

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(user, l.memberHatIds);
        }

        emit QuickJoined(user, created, l.memberHatIds);
    }

    /* ───────── Public user paths ─────── */

    /// 1) caller supplies username if they don't have one yet
    function quickJoinNoUser(string calldata username) external {
        _quickJoin(_msgSender(), username);
    }

    /// 2) caller already registered a username elsewhere
    function quickJoinWithUser() external nonReentrant {
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(_msgSender());
        if (bytes(existing).length == 0) revert NoUsername();

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(_msgSender(), l.memberHatIds);
        }

        emit QuickJoined(_msgSender(), false, l.memberHatIds);
    }

    /* ───────── Passkey join paths ─────── */

    /// @notice Join org with a new passkey account
    /// @param username Username to register
    /// @param passkey Passkey enrollment data
    /// @return account The created passkey account address
    /// @dev Reverts if the passkey already has a registered account with a username
    function quickJoinWithPasskey(string calldata username, PasskeyEnrollment calldata passkey)
        external
        nonReentrant
        returns (address account)
    {
        Layout storage l = _layout();
        if (address(l.universalFactory) == address(0)) revert PasskeyFactoryNotSet();
        if (bytes(username).length == 0) revert NoUsername();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        // 1. Create PasskeyAccount via universal factory (returns existing if already deployed)
        account = l.universalFactory
            .createAccount(passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);

        // 2. Register username to the account
        // Revert if account already has a username (prevents duplicate enrollment attempts)
        if (bytes(l.accountRegistry.getUsername(account)).length != 0) {
            revert AccountAlreadyRegistered();
        }
        l.accountRegistry.registerAccountQuickJoin(username, account);

        // 3. Mint member hats to the account
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(account, l.memberHatIds);
        }

        emit QuickJoinedWithPasskey(account, username, passkey.credentialId, l.memberHatIds);
    }

    /// @notice Master-deploy path for passkey onboarding
    /// @param username Username to register
    /// @param passkey Passkey enrollment data
    /// @return account The created passkey account address
    /// @dev Reverts if the passkey already has a registered account with a username
    function quickJoinWithPasskeyMasterDeploy(string calldata username, PasskeyEnrollment calldata passkey)
        external
        onlyMasterDeploy
        nonReentrant
        returns (address account)
    {
        Layout storage l = _layout();
        if (address(l.universalFactory) == address(0)) revert PasskeyFactoryNotSet();
        if (bytes(username).length == 0) revert NoUsername();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        // 1. Create PasskeyAccount via universal factory (returns existing if already deployed)
        account = l.universalFactory
            .createAccount(passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);

        // 2. Register username to the account
        // Revert if account already has a username (prevents duplicate enrollment attempts)
        if (bytes(l.accountRegistry.getUsername(account)).length != 0) {
            revert AccountAlreadyRegistered();
        }
        l.accountRegistry.registerAccountQuickJoin(username, account);

        // 3. Mint member hats to the account
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(account, l.memberHatIds);
        }

        emit QuickJoinedWithPasskeyByMaster(_msgSender(), account, username, passkey.credentialId, l.memberHatIds);
    }

    /* ───────── Master-deploy helper paths ─────── */

    function quickJoinNoUserMasterDeploy(string calldata username, address newUser) external onlyMasterDeploy {
        _quickJoin(newUser, username);
        emit QuickJoinedByMaster(_msgSender(), newUser, bytes(username).length > 0, _layout().memberHatIds);
    }

    function quickJoinWithUserMasterDeploy(address newUser) external onlyMasterDeploy nonReentrant {
        if (newUser == address(0)) revert ZeroUser();
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(newUser);
        if (bytes(existing).length == 0) revert NoUsername();

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(newUser, l.memberHatIds);
        }

        emit QuickJoinedByMaster(_msgSender(), newUser, false, l.memberHatIds);
    }

    /* ───────── Misc view helpers ─────── */
    function memberHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().memberHatIds);
    }

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function accountRegistry() external view returns (IUniversalAccountRegistry) {
        return _layout().accountRegistry;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function masterDeployAddress() external view returns (address) {
        return _layout().masterDeployAddress;
    }

    /* ───────── Hat Management View Functions ─────────── */
    function memberHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().memberHatIds);
    }

    function isMemberHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().memberHatIds, hatId);
    }

    function universalFactory() external view returns (IUniversalPasskeyAccountFactory) {
        return _layout().universalFactory;
    }
}
