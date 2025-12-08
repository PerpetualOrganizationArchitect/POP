// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*──────────────────── OpenZeppelin ────────────────────────────────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

/*──────────────────── Local Imports ────────────────────────────────────*/
import {PasskeyAccount} from "./PasskeyAccount.sol";

/**
 * @title PasskeyAccountFactory
 * @author POA Team
 * @notice Factory for deploying PasskeyAccount smart wallets
 * @dev Features:
 *      - CREATE2 deterministic deployment
 *      - Per-org configuration (max credentials, guardian, recovery delay)
 *      - Counterfactual address computation
 *      - Integration with ERC-4337 EntryPoint
 *
 *      Architecture:
 *      - Uses ERC-7201 namespaced storage for upgrade safety
 *      - Deployed via BeaconProxy for upgradeability
 *      - Creates PasskeyAccount instances as BeaconProxy
 */
contract PasskeyAccountFactory is Initializable {
    /*──────────────────────────── Structs ──────────────────────────────*/

    /**
     * @notice Per-organization configuration
     * @param maxCredentialsPerAccount Maximum passkeys per account for this org
     * @param defaultGuardian Default recovery guardian for accounts
     * @param recoveryDelay Recovery delay in seconds
     * @param enabled Whether this org can create accounts
     */
    struct OrgConfig {
        uint8 maxCredentialsPerAccount;
        address defaultGuardian;
        uint48 recoveryDelay;
        bool enabled;
    }

    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice Default max credentials per account
    uint8 public constant DEFAULT_MAX_CREDENTIALS = 5;

    /// @notice Default recovery delay (7 days)
    uint48 public constant DEFAULT_RECOVERY_DELAY = 7 days;

    /// @notice Module identifier
    bytes4 public constant MODULE_ID = bytes4(keccak256("PasskeyAccountFactory"));

    /*──────────────────────── ERC-7201 Storage ──────────────────────────*/

    /// @custom:storage-location erc7201:poa.passkeyaccountfactory.storage
    struct Layout {
        // The beacon for PasskeyAccount proxies
        address accountBeacon;
        // The executor/owner that can register orgs
        address executor;
        // Per-org configurations
        mapping(bytes32 => OrgConfig) orgConfigs;
        // Track deployed accounts
        mapping(address => bool) deployedAccounts;
    }

    // keccak256("poa.passkeyaccountfactory.storage")
    bytes32 private constant _STORAGE_SLOT = 0x827e9908968f666e42b67f932c7b1de44a3c55e267a1f6ed05a8d68576716a25;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────── Events ───────────────────────────────*/

    /// @notice Emitted when a new account is created
    event AccountCreated(address indexed account, bytes32 indexed orgId, bytes32 credentialId, address indexed owner);

    /// @notice Emitted when an org is registered
    event OrgRegistered(bytes32 indexed orgId, uint8 maxCredentials, address guardian, uint48 recoveryDelay);

    /// @notice Emitted when org config is updated
    event OrgConfigUpdated(bytes32 indexed orgId);

    /// @notice Emitted when executor is updated
    event ExecutorUpdated(address indexed oldExecutor, address indexed newExecutor);

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when caller is not authorized
    error Unauthorized();

    /// @notice Thrown when org is not registered or disabled
    error OrgNotEnabled();

    /// @notice Thrown when account already exists
    error AccountExists();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when beacon is not set
    error BeaconNotSet();

    /*──────────────────────────── Modifiers ────────────────────────────*/

    /// @notice Restrict to executor only
    modifier onlyExecutor() {
        if (msg.sender != _layout().executor) revert Unauthorized();
        _;
    }

    /*──────────────────────────── Constructor ──────────────────────────*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────────────────────── Initializer ──────────────────────────*/

    /**
     * @notice Initialize the factory
     * @param executor_ The executor/owner address
     * @param accountBeacon_ The beacon for PasskeyAccount proxies
     */
    function initialize(address executor_, address accountBeacon_) external initializer {
        if (executor_ == address(0)) revert ZeroAddress();
        if (accountBeacon_ == address(0)) revert ZeroAddress();

        Layout storage l = _layout();
        l.executor = executor_;
        l.accountBeacon = accountBeacon_;

        emit ExecutorUpdated(address(0), executor_);
    }

    /*──────────────────────────── Org Management ──────────────────────*/

    /**
     * @notice Register a new organization
     * @param orgId Organization identifier
     * @param maxCredentials Maximum credentials per account
     * @param guardian Default recovery guardian
     * @param recoveryDelay Recovery delay in seconds
     */
    function registerOrg(bytes32 orgId, uint8 maxCredentials, address guardian, uint48 recoveryDelay)
        external
        onlyExecutor
    {
        Layout storage l = _layout();

        l.orgConfigs[orgId] = OrgConfig({
            maxCredentialsPerAccount: maxCredentials > 0 ? maxCredentials : DEFAULT_MAX_CREDENTIALS,
            defaultGuardian: guardian,
            recoveryDelay: recoveryDelay > 0 ? recoveryDelay : DEFAULT_RECOVERY_DELAY,
            enabled: true
        });

        emit OrgRegistered(orgId, maxCredentials, guardian, recoveryDelay);
    }

    /**
     * @notice Update org configuration
     * @param orgId Organization identifier
     * @param maxCredentials New max credentials (0 to keep existing)
     * @param guardian New guardian (address(0) to keep existing)
     * @param recoveryDelay New recovery delay (0 to keep existing)
     */
    function updateOrgConfig(bytes32 orgId, uint8 maxCredentials, address guardian, uint48 recoveryDelay)
        external
        onlyExecutor
    {
        Layout storage l = _layout();
        OrgConfig storage config = l.orgConfigs[orgId];

        if (maxCredentials > 0) {
            config.maxCredentialsPerAccount = maxCredentials;
        }
        if (guardian != address(0)) {
            config.defaultGuardian = guardian;
        }
        if (recoveryDelay > 0) {
            config.recoveryDelay = recoveryDelay;
        }

        emit OrgConfigUpdated(orgId);
    }

    /**
     * @notice Enable or disable an org
     * @param orgId Organization identifier
     * @param enabled Whether the org is enabled
     */
    function setOrgEnabled(bytes32 orgId, bool enabled) external onlyExecutor {
        _layout().orgConfigs[orgId].enabled = enabled;
        emit OrgConfigUpdated(orgId);
    }

    /**
     * @notice Update the executor
     * @param newExecutor New executor address
     */
    function setExecutor(address newExecutor) external onlyExecutor {
        if (newExecutor == address(0)) revert ZeroAddress();

        Layout storage l = _layout();
        address oldExecutor = l.executor;
        l.executor = newExecutor;

        emit ExecutorUpdated(oldExecutor, newExecutor);
    }

    /*──────────────────────────── Account Creation ────────────────────*/

    /**
     * @notice Create a new PasskeyAccount
     * @param orgId Organization this account belongs to
     * @param credentialId Initial credential ID
     * @param pubKeyX Credential public key X coordinate
     * @param pubKeyY Credential public key Y coordinate
     * @param salt Additional salt for CREATE2
     * @return account The deployed account address
     */
    function createAccount(bytes32 orgId, bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        returns (address account)
    {
        Layout storage l = _layout();

        // Verify org is enabled
        OrgConfig storage config = l.orgConfigs[orgId];
        if (!config.enabled) revert OrgNotEnabled();

        // Verify beacon is set
        if (l.accountBeacon == address(0)) revert BeaconNotSet();

        // Compute deterministic address
        account = getAddress(orgId, credentialId, pubKeyX, pubKeyY, salt);

        // Return existing if already deployed
        if (account.code.length > 0) {
            return account;
        }

        // Build initialization data
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector,
            address(this), // factory
            credentialId,
            pubKeyX,
            pubKeyY,
            orgId,
            config.defaultGuardian,
            config.recoveryDelay
        );

        // Deploy via CREATE2
        bytes32 create2Salt = _computeSalt(orgId, credentialId, pubKeyX, pubKeyY, salt);

        account = address(new BeaconProxy{salt: create2Salt}(l.accountBeacon, initData));

        // Track deployment
        l.deployedAccounts[account] = true;

        emit AccountCreated(account, orgId, credentialId, msg.sender);
    }

    /**
     * @notice Compute the counterfactual address for an account
     * @param orgId Organization this account belongs to
     * @param credentialId Initial credential ID
     * @param pubKeyX Credential public key X coordinate
     * @param pubKeyY Credential public key Y coordinate
     * @param salt Additional salt for CREATE2
     * @return account The predicted account address
     */
    function getAddress(bytes32 orgId, bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        public
        view
        returns (address account)
    {
        Layout storage l = _layout();

        // Get org config for initialization params
        OrgConfig storage config = l.orgConfigs[orgId];

        // Build initialization data
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector,
            address(this), // factory
            credentialId,
            pubKeyX,
            pubKeyY,
            orgId,
            config.defaultGuardian,
            config.recoveryDelay
        );

        // Compute bytecode hash
        bytes memory proxyBytecode =
            abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(l.accountBeacon, initData));

        bytes32 create2Salt = _computeSalt(orgId, credentialId, pubKeyX, pubKeyY, salt);

        return Create2.computeAddress(create2Salt, keccak256(proxyBytecode));
    }

    /*──────────────────────────── View Functions ──────────────────────*/

    /**
     * @notice Get org configuration
     * @param orgId Organization identifier
     * @return config The org configuration
     */
    function getOrgConfig(bytes32 orgId) external view returns (OrgConfig memory config) {
        return _layout().orgConfigs[orgId];
    }

    /**
     * @notice Get max credentials per org for an account
     * @param orgId Organization identifier
     * @return maxCredentials Maximum credentials allowed
     */
    function getMaxCredentialsPerOrg(bytes32 orgId) external view returns (uint8 maxCredentials) {
        OrgConfig storage config = _layout().orgConfigs[orgId];
        return config.maxCredentialsPerAccount > 0 ? config.maxCredentialsPerAccount : DEFAULT_MAX_CREDENTIALS;
    }

    /**
     * @notice Check if an address is a deployed account
     * @param account Address to check
     * @return deployed True if this factory deployed the account
     */
    function isDeployedAccount(address account) external view returns (bool deployed) {
        return _layout().deployedAccounts[account];
    }

    /**
     * @notice Get the account beacon address
     * @return beacon The beacon address
     */
    function accountBeacon() external view returns (address beacon) {
        return _layout().accountBeacon;
    }

    /**
     * @notice Get the executor address
     * @return executor The executor address
     */
    function executor() external view returns (address) {
        return _layout().executor;
    }

    /*──────────────────────────── Internal Helpers ────────────────────*/

    /**
     * @notice Compute CREATE2 salt
     * @param orgId Organization identifier
     * @param credentialId Credential identifier
     * @param pubKeyX Public key X coordinate
     * @param pubKeyY Public key Y coordinate
     * @param salt Additional salt
     * @return The computed salt
     */
    function _computeSalt(bytes32 orgId, bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(orgId, credentialId, pubKeyX, pubKeyY, salt));
    }
}
