// SPDX-License-Identifier: MIT
pragma solidity >=0.4.11 >=0.4.16 ^0.8.20 ^0.8.21 ^0.8.22 ^0.8.24;

// lib/openzeppelin-contracts/contracts/utils/Errors.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

// lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts (last updated v5.4.0) (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1967.sol)

/**
 * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
 */
interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
}

// src/interfaces/IPasskeyAccount.sol

/**
 * @title IPasskeyAccount
 * @notice Interface for PasskeyAccount smart contract wallet
 * @dev Defines credential management and recovery functions for passkey-based accounts
 */
interface IPasskeyAccount {
    /*──────────────────────────── Structs ──────────────────────────────*/

    /**
     * @notice Passkey credential information
     * @param publicKeyX P256 public key X coordinate
     * @param publicKeyY P256 public key Y coordinate
     * @param createdAt Timestamp when credential was registered
     * @param signCount Last known signature count (anti-replay)
     * @param orgId Organization ID this credential was created for
     * @param active Whether this credential is currently active
     */
    struct PasskeyCredential {
        bytes32 publicKeyX;
        bytes32 publicKeyY;
        uint64 createdAt;
        uint32 signCount;
        bytes32 orgId;
        bool active;
    }

    /**
     * @notice Recovery request information
     * @param credentialId ID of the new credential to add
     * @param pubKeyX New credential public key X
     * @param pubKeyY New credential public key Y
     * @param executeAfter Timestamp when recovery can be completed
     * @param cancelled Whether the request was cancelled
     */
    struct RecoveryRequest {
        bytes32 credentialId;
        bytes32 pubKeyX;
        bytes32 pubKeyY;
        uint48 executeAfter;
        bool cancelled;
    }

    /*──────────────────────────── Events ───────────────────────────────*/

    /// @notice Emitted when a new credential is added
    event CredentialAdded(bytes32 indexed credentialId, bytes32 orgId, uint64 createdAt);

    /// @notice Emitted when a credential is removed
    event CredentialRemoved(bytes32 indexed credentialId);

    /// @notice Emitted when a credential is activated/deactivated
    event CredentialStatusChanged(bytes32 indexed credentialId, bool active);

    /// @notice Emitted when guardian is updated
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);

    /// @notice Emitted when recovery delay is updated
    event RecoveryDelayUpdated(uint48 oldDelay, uint48 newDelay);

    /// @notice Emitted when recovery is initiated
    event RecoveryInitiated(
        bytes32 indexed recoveryId, bytes32 credentialId, address indexed initiator, uint48 executeAfter
    );

    /// @notice Emitted when recovery is completed
    event RecoveryCompleted(bytes32 indexed recoveryId, bytes32 indexed credentialId);

    /// @notice Emitted when recovery is cancelled
    event RecoveryCancelled(bytes32 indexed recoveryId);

    /// @notice Emitted when a transaction is executed
    event Executed(address indexed target, uint256 value, bytes data, bytes result);

    /// @notice Emitted when batch transactions are executed
    event BatchExecuted(uint256 count);

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when caller is not the EntryPoint
    error OnlyEntryPoint();

    /// @notice Thrown when caller is not the account itself
    error OnlySelf();

    /// @notice Thrown when caller is not the guardian
    error OnlyGuardian();

    /// @notice Thrown when caller is not the guardian or account
    error OnlyGuardianOrSelf();

    /// @notice Thrown when credential already exists
    error CredentialExists();

    /// @notice Thrown when credential does not exist
    error CredentialNotFound();

    /// @notice Thrown when credential is not active
    error CredentialNotActive();

    /// @notice Thrown when max credentials per org is reached
    error MaxCredentialsReached();

    /// @notice Thrown when trying to remove the last credential
    error CannotRemoveLastCredential();

    /// @notice Thrown when recovery is already pending
    error RecoveryAlreadyPending();

    /// @notice Thrown when recovery is not pending
    error RecoveryNotPending();

    /// @notice Thrown when recovery delay hasn't passed
    error RecoveryDelayNotPassed();

    /// @notice Thrown when call execution fails
    error ExecutionFailed();

    /// @notice Thrown when array lengths mismatch
    error ArrayLengthMismatch();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when signature is invalid
    error InvalidSignature();

    /*──────────────────────────── View Functions ──────────────────────*/

    /**
     * @notice Get credential information
     * @param credentialId The credential ID to query
     * @return credential The credential information
     */
    function getCredential(bytes32 credentialId) external view returns (PasskeyCredential memory credential);

    /**
     * @notice Get all credential IDs for this account
     * @return credentialIds Array of credential IDs
     */
    function getCredentialIds() external view returns (bytes32[] memory credentialIds);

    /**
     * @notice Get the number of credentials for an org
     * @param orgId The organization ID
     * @return count Number of credentials for this org
     */
    function getOrgCredentialCount(bytes32 orgId) external view returns (uint8 count);

    /**
     * @notice Get the guardian address
     * @return guardian The guardian address
     */
    function guardian() external view returns (address guardian);

    /**
     * @notice Get the recovery delay
     * @return delay Recovery delay in seconds
     */
    function recoveryDelay() external view returns (uint48 delay);

    /**
     * @notice Get a pending recovery request
     * @param recoveryId The recovery request ID
     * @return request The recovery request
     */
    function getRecoveryRequest(bytes32 recoveryId) external view returns (RecoveryRequest memory request);

    /**
     * @notice Get the factory that created this account
     * @return factory The factory address
     */
    function factory() external view returns (address factory);

    /*──────────────────────────── Credential Management ───────────────*/

    /**
     * @notice Add a new passkey credential
     * @param credentialId Unique identifier for the credential (hash of WebAuthn credentialId)
     * @param pubKeyX P256 public key X coordinate
     * @param pubKeyY P256 public key Y coordinate
     * @param orgId Organization this credential is for
     * @dev Only callable via UserOp (self-call through EntryPoint)
     */
    function addCredential(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, bytes32 orgId) external;

    /**
     * @notice Remove a passkey credential
     * @param credentialId The credential to remove
     * @dev Only callable via UserOp, cannot remove last credential
     */
    function removeCredential(bytes32 credentialId) external;

    /**
     * @notice Set credential active status
     * @param credentialId The credential to update
     * @param active Whether the credential should be active
     */
    function setCredentialActive(bytes32 credentialId, bool active) external;

    /*──────────────────────────── Guardian Management ─────────────────*/

    /**
     * @notice Update the guardian address
     * @param newGuardian The new guardian address
     * @dev Only callable via UserOp
     */
    function setGuardian(address newGuardian) external;

    /**
     * @notice Update the recovery delay
     * @param newDelay The new recovery delay in seconds
     * @dev Only callable via UserOp
     */
    function setRecoveryDelay(uint48 newDelay) external;

    /*──────────────────────────── Recovery Functions ──────────────────*/

    /**
     * @notice Initiate account recovery with a new credential
     * @param credentialId ID for the new credential
     * @param pubKeyX New credential public key X
     * @param pubKeyY New credential public key Y
     * @dev Only callable by guardian, starts recovery delay timer
     */
    function initiateRecovery(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY) external;

    /**
     * @notice Complete a pending recovery
     * @param recoveryId The recovery request ID to complete
     * @dev Anyone can call after delay passes.
     *
     *      IMPORTANT: Recovery credentials are added with orgId = bytes32(0) and do NOT
     *      count toward the per-org credential limit. This is intentional behavior to ensure
     *      recovery always succeeds regardless of org credential limits. The credential can
     *      later be associated with an org by the account owner if needed.
     */
    function completeRecovery(bytes32 recoveryId) external;

    /**
     * @notice Cancel a pending recovery
     * @param recoveryId The recovery request ID to cancel
     * @dev Callable by guardian or account owner
     */
    function cancelRecovery(bytes32 recoveryId) external;

    /*──────────────────────────── Execution Functions ─────────────────*/

    /**
     * @notice Execute a single transaction
     * @param target Target address
     * @param value ETH value to send
     * @param data Calldata
     * @return result Return data from the call
     */
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result);

    /**
     * @notice Execute multiple transactions
     * @param targets Target addresses
     * @param values ETH values to send
     * @param datas Calldatas
     */
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external;
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
        }
    }
}

// src/libs/P256Verifier.sol

/**
 * @title P256Verifier
 * @author POA Team
 * @notice Library for secp256r1 (P-256) signature verification using EIP-7951 precompile
 * @dev This library provides gas-efficient P256 signature verification by:
 *      1. First attempting the EIP-7951 precompile at address 0x100
 *      2. Falling back to daimo-eth's deterministic verifier contract if precompile unavailable
 *
 *      EIP-7951 Specification (Fusaka upgrade, live Dec 3 2025):
 *      - Address: 0x100
 *      - Gas cost: 6900 gas (fixed, regardless of result)
 *      - Input: 160 bytes (messageHash || r || s || x || y)
 *      - Output valid: 32 bytes with value 1
 *      - Output invalid/error: empty bytes (NOT zero!)
 *
 *      EIP-7951 supersedes RIP-7212 with critical security fixes:
 *      - Point-at-infinity check (prevents non-deterministic behavior)
 *      - Modular comparison: r' ≡ r (mod n) for proper x-coordinate handling
 *
 *      Gas costs:
 *      - EIP-7951 precompile (L1): 6,900 gas
 *      - RIP-7212 precompile (L2s): 3,450 gas
 *      - Fallback contract: ~330,000 gas
 *
 *      L2 Support (RIP-7212 - ALREADY LIVE):
 *      These chains have native P256 precompile at 0x100 TODAY:
 *      - Arbitrum One/Nova
 *      - Optimism
 *      - Base
 *      - zkSync Era
 *      - Polygon PoS
 *      - Scroll
 *      - Linea
 *
 *      L1 Support (EIP-7951 - Fusaka upgrade):
 *      - Ethereum mainnet: December 3, 2025
 *
 *      Gas Optimization:
 *      For optimal gas, cache `isPrecompileAvailable()` at deployment and use
 *      `verifyWithHint()` with the cached value. This avoids:
 *      - Failed precompile calls on chains without precompile
 *      - Redundant fallback calls when precompile exists but signature is invalid
 *
 *      Example:
 *      ```solidity
 *      bool public immutable hasP256Precompile = P256Verifier.isPrecompileAvailable();
 *
 *      function validateSignature(...) internal view {
 *          return P256Verifier.verifyWithHint(hash, r, s, x, y, hasP256Precompile);
 *      }
 *      ```
 */
library P256Verifier {
    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice EIP-7951/RIP-7212 precompile address
    /// @dev Same address on L1 and all supported L2s
    address internal constant PRECOMPILE = address(0x100);

    /// @notice daimo-eth P256 verifier at deterministic CREATE2 address
    /// @dev Deployed at same address on all EVM chains via Safe Singleton Factory
    /// @dev See: https://github.com/daimo-eth/p256-verifier
    address internal constant FALLBACK_VERIFIER = 0xc2b78104907F722DABAc4C69f826a522B2754De4;

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when public key coordinates are invalid (zero)
    error InvalidPublicKey();

    /// @notice Thrown when signature components are invalid (zero or >= n)
    error InvalidSignatureComponents();

    /*──────────────────────────── Main Functions ──────────────────────*/

    /**
     * @notice Verify a secp256r1 signature
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Attempts precompile first, falls back to contract verifier
     */
    function verify(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        // Pack input for precompile (160 bytes total)
        // Format: messageHash(32) || r(32) || s(32) || x(32) || y(32)
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);

        // Try EIP-7951 precompile first (at 0x100)
        // Per EIP-7951: returns 32 bytes with value 1 if valid, empty bytes if invalid
        (bool success, bytes memory result) = PRECOMPILE.staticcall(input);

        if (success && result.length == 32) {
            // Only returns 32 bytes for valid signatures (value will be 1)
            // Invalid signatures return empty bytes, not 0
            return abi.decode(result, (uint256)) == 1;
        }

        // Precompile returned empty (invalid sig OR precompile doesn't exist)
        // Try daimo-eth fallback verifier for chains without native precompile
        (success, result) = FALLBACK_VERIFIER.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }

        // Both methods returned empty - signature is invalid
        return false;
    }

    /**
     * @notice Verify a signature and revert if invalid
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @dev Reverts with InvalidSignature if verification fails
     */
    function verifyOrRevert(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y) internal view {
        if (!verify(messageHash, r, s, x, y)) {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Verify using precompile only (no fallback)
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this when you know the precompile is available (e.g., cached at deployment).
     *      Saves ~330k gas on invalid signatures by not trying fallback.
     *      Returns false if precompile is unavailable OR signature is invalid.
     */
    function verifyWithPrecompile(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);
        (bool success, bytes memory result) = PRECOMPILE.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Verify using fallback verifier only (no precompile)
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this on chains without precompile to save the failed precompile call gas.
     *      The daimo-eth verifier costs ~330k gas regardless of result.
     */
    function verifyWithFallback(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);
        (bool success, bytes memory result) = FALLBACK_VERIFIER.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Verify using cached precompile availability hint
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @param hasPrecompile Whether the precompile is known to be available
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this with a cached `isPrecompileAvailable()` result for optimal gas.
     *      Example: cache the result in an immutable at deployment time.
     */
    function verifyWithHint(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y, bool hasPrecompile)
        internal
        view
        returns (bool valid)
    {
        if (hasPrecompile) {
            return verifyWithPrecompile(messageHash, r, s, x, y);
        }
        return verifyWithFallback(messageHash, r, s, x, y);
    }

    /**
     * @notice Check if the P256 precompile is available on this chain
     * @return available True if the precompile is available
     * @dev Useful for gas estimation and debugging
     */
    function isPrecompileAvailable() internal view returns (bool available) {
        // The osaka P256 precompile only returns 32 bytes for VALID signatures
        // It returns empty for invalid signatures (unlike the EIP spec which says return 0)
        // So we must use a known valid NIST P-256 test vector to detect availability

        // NIST P-256 test vector (valid signature)
        bytes memory testInput = abi.encodePacked(
            bytes32(0x44acf6b7e36c1342c2c5897204fe09504e1e2efb1a900377dbc4e7a6a133ec56), // messageHash
            bytes32(0xf3ac8061b514795b8843e3d6629527ed2afd6b1f6a555a7acabb5e6f79c8c2ac), // r
            bytes32(0x8bf77819ca05a6b2786c76262bf7371cef97b218e96f175a3ccdda2acc058903), // s
            bytes32(0x1ccbe91c075fc7f4f033bfa248db8fccd3565de94bbfb12f3c59ff46c271bf83), // x
            bytes32(0xce4014c68811f9a21a1fdb2c0e6113e06db7ca93b7404e78dc7ccd5ca89a4ca9) // y
        );

        (bool success, bytes memory result) = PRECOMPILE.staticcall(testInput);

        // Precompile exists if call succeeded, returned 32 bytes, and value is 1 (valid)
        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Estimate gas cost for P256 verification on current chain
     * @return gasCost Estimated gas cost for verify()
     * @dev Returns costs per specification:
     *      - 6900 for L1 precompile (EIP-7951, Fusaka+)
     *      - 3450 for L2 precompile (RIP-7212)
     *      - 350000 for fallback contract (daimo-eth)
     */
    function estimateVerificationGas() internal view returns (uint256 gasCost) {
        if (isPrecompileAvailable()) {
            // Precompile available - check if L1 or L2 based on chain ID
            // L1 mainnet = 1, L2s have higher chain IDs
            if (block.chainid == 1) {
                return 6900; // EIP-7951 exact gas cost
            }
            return 3450; // RIP-7212 exact gas cost (L2s)
        }
        return 350000; // Fallback contract gas cost
    }

    /*──────────────────────────── Validation Helpers ──────────────────*/

    /**
     * @notice Validate public key coordinates
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @return valid True if the public key is valid (non-zero)
     * @dev Note: This only checks for zero values. Full curve validation
     *      is performed by the verifier itself.
     */
    function isValidPublicKey(bytes32 x, bytes32 y) internal pure returns (bool valid) {
        return x != bytes32(0) && y != bytes32(0);
    }

    /**
     * @notice Validate signature components
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @return valid True if the signature components are valid (non-zero)
     * @dev Note: This only checks for zero values. Full range validation
     *      is performed by the verifier itself.
     */
    function isValidSignature(bytes32 r, bytes32 s) internal pure returns (bool valid) {
        return r != bytes32(0) && s != bytes32(0);
    }
}

// src/interfaces/PackedUserOperation.sol

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    bytes paymasterAndData;
    bytes signature;
}

library UserOpLib {
    function unpackAccountGasLimits(bytes32 accountGasLimits)
        internal
        pure
        returns (uint128 verificationGasLimit, uint128 callGasLimit)
    {
        verificationGasLimit = uint128(uint256(accountGasLimits));
        callGasLimit = uint128(uint256(accountGasLimits >> 128));
    }

    function packAccountGasLimits(uint128 verificationGasLimit, uint128 callGasLimit) internal pure returns (bytes32) {
        return bytes32(uint256(verificationGasLimit) | (uint256(callGasLimit) << 128));
    }
}

// lib/openzeppelin-contracts/contracts/proxy/Proxy.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/Proxy.sol)

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overridden so it returns the address to which the fallback
     * function and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
    }
}

// lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, bytes memory returndata) = recipient.call{value: amount}("");
        if (!success) {
            _revert(returndata);
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        } else {
            revert Errors.FailedCall();
        }
    }
}

// lib/openzeppelin-contracts/contracts/utils/Create2.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Create2.sol)

/**
 * @dev Helper to make usage of the `CREATE2` EVM opcode easier and safer.
 * `CREATE2` can be used to compute in advance the address where a smart
 * contract will be deployed, which allows for interesting new mechanisms known
 * as 'counterfactual interactions'.
 *
 * See the https://eips.ethereum.org/EIPS/eip-1014#motivation[EIP] for more
 * information.
 */
library Create2 {
    /**
     * @dev There's no code to deploy.
     */
    error Create2EmptyBytecode();

    /**
     * @dev Deploys a contract using `CREATE2`. The address where the contract
     * will be deployed can be known in advance via {computeAddress}.
     *
     * The bytecode for a contract can be obtained from Solidity with
     * `type(contractName).creationCode`.
     *
     * Requirements:
     *
     * - `bytecode` must not be empty.
     * - `salt` must have not been used for `bytecode` already.
     * - the factory must have a balance of at least `amount`.
     * - if `amount` is non-zero, `bytecode` must have a `payable` constructor.
     */
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) internal returns (address addr) {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }
        if (bytecode.length == 0) {
            revert Create2EmptyBytecode();
        }
        assembly ("memory-safe") {
            addr := create2(amount, add(bytecode, 0x20), mload(bytecode), salt)
            // if no address was created, and returndata is not empty, bubble revert
            if and(iszero(addr), not(iszero(returndatasize()))) {
                let p := mload(0x40)
                returndatacopy(p, 0, returndatasize())
                revert(p, returndatasize())
            }
        }
        if (addr == address(0)) {
            revert Errors.FailedDeployment();
        }
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy}. Any change in the
     * `bytecodeHash` or `salt` will result in a new destination address.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) internal view returns (address) {
        return computeAddress(salt, bytecodeHash, address(this));
    }

    /**
     * @dev Returns the address where a contract will be stored if deployed via {deploy} from a contract located at
     * `deployer`. If `deployer` is this contract's address, returns the same value as {computeAddress}.
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer) internal pure returns (address addr) {
        assembly ("memory-safe") {
            let ptr := mload(0x40) // Get free memory pointer

            // |                   | ↓ ptr ...  ↓ ptr + 0x0B (start) ...  ↓ ptr + 0x20 ...  ↓ ptr + 0x40 ...   |
            // |-------------------|---------------------------------------------------------------------------|
            // | bytecodeHash      |                                                        CCCCCCCCCCCCC...CC |
            // | salt              |                                      BBBBBBBBBBBBB...BB                   |
            // | deployer          | 000000...0000AAAAAAAAAAAAAAAAAAA...AA                                     |
            // | 0xFF              |            FF                                                             |
            // |-------------------|---------------------------------------------------------------------------|
            // | memory            | 000000...00FFAAAAAAAAAAAAAAAAAAA...AABBBBBBBBBBBBB...BBCCCCCCCCCCCCC...CC |
            // | keccak(start, 85) |            ↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑↑ |

            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer) // Right-aligned with 12 preceding garbage bytes
            let start := add(ptr, 0x0b) // The hashed data starts at the final garbage byte which we will set to 0xff
            mstore8(start, 0xff)
            addr := and(keccak256(start, 85), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }
}

// src/interfaces/IAccount.sol

/**
 * @title IAccount
 * @notice ERC-4337 Account interface
 * @dev Required interface for smart contract wallets in the ERC-4337 account abstraction system
 *
 *      The account's validateUserOp function is called by the EntryPoint to validate
 *      a UserOperation before execution. The account must verify the signature and
 *      may perform additional authorization checks.
 *
 *      Return Values for validationData:
 *      - 0: Signature is valid
 *      - 1: Signature validation failed (SIG_VALIDATION_FAILED)
 *      - Packed value: (authorizer address, validUntil, validAfter)
 *        - authorizer: Address to call for additional validation (0 for none)
 *        - validUntil: Timestamp until which the signature is valid (0 for infinite)
 *        - validAfter: Timestamp from which the signature is valid (0 for immediate)
 */
interface IAccount {
    /**
     * @notice Validate a UserOperation
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation (excluding signature)
     * @param missingAccountFunds Amount the account needs to pay to EntryPoint for gas
     * @return validationData 0 for success, 1 for signature failure, or packed validation data
     * @dev The account MUST pay `missingAccountFunds` to the EntryPoint (msg.sender)
     *      if it has sufficient balance. This payment happens before execution.
     *      The account may receive partial or full refund after execution via postOp.
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}

/**
 * @title IAccountExecute
 * @notice Optional interface for accounts that support direct execution
 * @dev This interface allows the EntryPoint to call execute directly
 */
interface IAccountExecute {
    /**
     * @notice Execute a transaction from the account
     * @param target The target address to call
     * @param value The ETH value to send
     * @param data The calldata to send
     * @return result The return data from the call
     */
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result);

    /**
     * @notice Execute multiple transactions from the account
     * @param targets The target addresses to call
     * @param values The ETH values to send
     * @param datas The calldatas to send
     */
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external;
}

// src/libs/WebAuthnLib.sol

/**
 * @title WebAuthnLib
 * @author POA Team
 * @notice Library for WebAuthn/Passkey signature parsing and verification
 * @dev Implements WebAuthn assertion verification for ERC-4337 account abstraction
 *
 *      WebAuthn Signature Flow:
 *      1. Authenticator signs: sha256(authenticatorData || sha256(clientDataJSON))
 *      2. clientDataJSON contains base64url-encoded challenge (the userOpHash)
 *      3. authenticatorData contains rpIdHash, flags, and signCount
 *
 *      This library verifies:
 *      - The challenge in clientDataJSON matches the expected value
 *      - The authenticator flags indicate user presence/verification
 *      - The P256 signature over the constructed message is valid
 *
 *      References:
 *      - WebAuthn spec: https://www.w3.org/TR/webauthn-2/
 *      - FIDO2 CTAP: https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-client-to-authenticator-protocol-v2.0-rd-20180702.html
 */
library WebAuthnLib {
    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice Authenticator data flag: User Present (UP)
    uint8 internal constant FLAG_USER_PRESENT = 0x01;

    /// @notice Authenticator data flag: User Verified (UV)
    uint8 internal constant FLAG_USER_VERIFIED = 0x04;

    /// @notice Authenticator data flag: Attested credential data included
    uint8 internal constant FLAG_ATTESTED_CREDENTIAL = 0x40;

    /// @notice Authenticator data flag: Extension data included
    uint8 internal constant FLAG_EXTENSION_DATA = 0x80;

    /// @notice Minimum authenticator data length (rpIdHash + flags + signCount)
    uint256 internal constant MIN_AUTH_DATA_LENGTH = 37;

    /// @notice Base64URL alphabet for decoding challenge
    bytes internal constant BASE64URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when authenticator data is too short
    error AuthDataTooShort();

    /// @notice Thrown when user presence flag is not set
    error UserNotPresent();

    /// @notice Thrown when the challenge doesn't match expected value
    error ChallengeMismatch();

    /// @notice Thrown when clientDataJSON is malformed
    error MalformedClientData();

    /// @notice Thrown when the signature is invalid
    error InvalidWebAuthnSignature();

    /// @notice Thrown when signCount indicates replay attack
    error SignCountTooLow();

    /*──────────────────────────── Structs ──────────────────────────────*/

    /**
     * @notice WebAuthn signature data structure
     * @param authenticatorData Raw authenticator data bytes
     * @param clientDataJSON Raw client data JSON string as bytes
     * @param challengeIndex Index where "challenge":"<value>" starts in clientDataJSON
     * @param typeIndex Index where "type":"webauthn.get" starts in clientDataJSON
     * @param r P256 signature r component
     * @param s P256 signature s component
     */
    struct WebAuthnAuth {
        bytes authenticatorData;
        bytes clientDataJSON;
        uint256 challengeIndex;
        uint256 typeIndex;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Parsed authenticator data
     * @param rpIdHash SHA-256 hash of the relying party ID
     * @param flags Authenticator flags byte
     * @param signCount Signature counter (anti-replay)
     */
    struct AuthenticatorData {
        bytes32 rpIdHash;
        uint8 flags;
        uint32 signCount;
    }

    /*──────────────────────────── Main Functions ──────────────────────*/

    /**
     * @notice Verify a WebAuthn signature
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge (typically userOpHash)
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag to be set
     * @return valid True if the signature is valid
     */
    function verify(WebAuthnAuth memory auth, bytes32 challenge, bytes32 x, bytes32 y, bool requireUserVerification)
        internal
        view
        returns (bool valid)
    {
        // 1. Validate authenticator data length
        if (auth.authenticatorData.length < MIN_AUTH_DATA_LENGTH) {
            return false;
        }

        // 2. Parse and validate authenticator flags
        uint8 flags = uint8(auth.authenticatorData[32]);

        // User presence is always required
        if ((flags & FLAG_USER_PRESENT) == 0) {
            return false;
        }

        // User verification may be required
        if (requireUserVerification && (flags & FLAG_USER_VERIFIED) == 0) {
            return false;
        }

        // 3. Verify challenge in clientDataJSON
        if (!_verifyChallenge(auth.clientDataJSON, auth.challengeIndex, challenge)) {
            return false;
        }

        // 4. Verify type is "webauthn.get"
        if (!_verifyType(auth.clientDataJSON, auth.typeIndex)) {
            return false;
        }

        // 5. Compute the message hash
        // message = sha256(authenticatorData || sha256(clientDataJSON))
        bytes32 clientDataHash = sha256(auth.clientDataJSON);
        bytes32 messageHash = sha256(abi.encodePacked(auth.authenticatorData, clientDataHash));

        // 6. Verify P256 signature
        return P256Verifier.verify(messageHash, auth.r, auth.s, x, y);
    }

    /**
     * @notice Verify a WebAuthn signature and revert if invalid
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag
     */
    function verifyOrRevert(
        WebAuthnAuth memory auth,
        bytes32 challenge,
        bytes32 x,
        bytes32 y,
        bool requireUserVerification
    ) internal view {
        if (!verify(auth, challenge, x, y, requireUserVerification)) {
            revert InvalidWebAuthnSignature();
        }
    }

    /**
     * @notice Verify signature with signCount anti-replay check
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag
     * @param lastSignCount The last known signCount for this credential
     * @return valid True if valid
     * @return newSignCount The new signCount from this authentication
     */
    function verifyWithSignCount(
        WebAuthnAuth memory auth,
        bytes32 challenge,
        bytes32 x,
        bytes32 y,
        bool requireUserVerification,
        uint32 lastSignCount
    ) internal view returns (bool valid, uint32 newSignCount) {
        // Parse signCount from authenticator data (bytes 33-36, big-endian)
        if (auth.authenticatorData.length < MIN_AUTH_DATA_LENGTH) {
            return (false, 0);
        }

        newSignCount = uint32(
            bytes4(
                abi.encodePacked(
                    auth.authenticatorData[33],
                    auth.authenticatorData[34],
                    auth.authenticatorData[35],
                    auth.authenticatorData[36]
                )
            )
        );

        // SignCount anti-replay check: new count must be greater than last known value
        // Edge cases handled:
        //   - lastSignCount=0, newSignCount=0: PASSES (authenticator doesn't support counters)
        //   - lastSignCount=0, newSignCount>0: PASSES (first use after counter-enabled auth)
        //   - lastSignCount>0, newSignCount=0: PASSES (new authenticator without counters)
        //   - lastSignCount>0, newSignCount<=last: FAILS (replay attack or cloned key)
        // NOTE: Authenticators that don't support counters (e.g., some security keys) always
        // return 0. We intentionally allow this to maximize compatibility.
        if (lastSignCount > 0 && newSignCount > 0 && newSignCount <= lastSignCount) {
            return (false, newSignCount);
        }

        valid = verify(auth, challenge, x, y, requireUserVerification);
        return (valid, newSignCount);
    }

    /*──────────────────────────── Parsing Functions ───────────────────*/

    /**
     * @notice Parse authenticator data
     * @param authData Raw authenticator data bytes
     * @return parsed Parsed authenticator data struct
     */
    function parseAuthenticatorData(bytes calldata authData) internal pure returns (AuthenticatorData memory parsed) {
        if (authData.length < MIN_AUTH_DATA_LENGTH) {
            revert AuthDataTooShort();
        }

        // rpIdHash: bytes 0-31
        parsed.rpIdHash = bytes32(authData[0:32]);

        // flags: byte 32
        parsed.flags = uint8(authData[32]);

        // signCount: bytes 33-36 (big-endian uint32)
        parsed.signCount = uint32(bytes4(authData[33:37]));
    }

    /**
     * @notice Extract the challenge from clientDataJSON
     * @param clientDataJSON The client data JSON bytes
     * @param challengeIndex Index where challenge value starts
     * @return challenge The decoded challenge bytes32
     * @dev The challenge in clientDataJSON is base64url-encoded
     */
    function extractChallenge(bytes calldata clientDataJSON, uint256 challengeIndex)
        internal
        pure
        returns (bytes32 challenge)
    {
        // Find the end quote of the challenge value
        uint256 i = challengeIndex;
        while (i < clientDataJSON.length && clientDataJSON[i] != '"') {
            i++;
        }

        // Extract and decode the base64url challenge
        bytes memory encoded = clientDataJSON[challengeIndex:i];
        bytes memory decoded = _base64UrlDecode(encoded);

        if (decoded.length != 32) {
            revert ChallengeMismatch();
        }

        challenge = bytes32(decoded);
    }

    /*──────────────────────────── Internal Functions ──────────────────*/

    /**
     * @notice Verify the challenge in clientDataJSON matches expected value
     * @param clientDataJSON The client data JSON bytes
     * @param challengeIndex Index where challenge value starts (after "challenge":")
     * @param expectedChallenge The expected challenge value
     * @return valid True if challenge matches
     */
    function _verifyChallenge(bytes memory clientDataJSON, uint256 challengeIndex, bytes32 expectedChallenge)
        private
        pure
        returns (bool valid)
    {
        // The challenge in clientDataJSON is base64url-encoded
        // We need to decode it and compare with expected

        // Find the end of the challenge string (look for closing quote)
        uint256 endIndex = challengeIndex;
        while (endIndex < clientDataJSON.length && clientDataJSON[endIndex] != '"') {
            endIndex++;
        }

        if (endIndex >= clientDataJSON.length) {
            return false;
        }

        // Extract the base64url-encoded challenge (manual copy since memory doesn't support slices)
        uint256 challengeLen = endIndex - challengeIndex;
        bytes memory encodedChallenge = new bytes(challengeLen);
        for (uint256 i = 0; i < challengeLen; i++) {
            encodedChallenge[i] = clientDataJSON[challengeIndex + i];
        }

        // Decode and compare
        bytes memory decodedChallenge = _base64UrlDecode(encodedChallenge);

        if (decodedChallenge.length != 32) {
            return false;
        }

        return bytes32(decodedChallenge) == expectedChallenge;
    }

    /**
     * @notice Verify the type in clientDataJSON is "webauthn.get"
     * @param clientDataJSON The client data JSON bytes
     * @param typeIndex Index where type value starts (after "type":")
     * @return valid True if type is "webauthn.get"
     */
    function _verifyType(bytes memory clientDataJSON, uint256 typeIndex) private pure returns (bool valid) {
        // Expected: "webauthn.get"
        bytes memory expected = bytes("webauthn.get");

        if (typeIndex + expected.length > clientDataJSON.length) {
            return false;
        }

        for (uint256 i = 0; i < expected.length; i++) {
            if (clientDataJSON[typeIndex + i] != expected[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Decode a base64url-encoded string
     * @param encoded The base64url-encoded bytes
     * @return decoded The decoded bytes
     * @dev Base64url uses '-' and '_' instead of '+' and '/', and no padding
     */
    function _base64UrlDecode(bytes memory encoded) private pure returns (bytes memory decoded) {
        if (encoded.length == 0) {
            return new bytes(0);
        }

        // Calculate output length (account for missing padding)
        uint256 paddedLength = encoded.length;
        if (paddedLength % 4 != 0) {
            paddedLength += 4 - (paddedLength % 4);
        }

        uint256 decodedLength = (paddedLength * 3) / 4;

        // Adjust for actual padding that would be needed
        uint256 missingPadding = paddedLength - encoded.length;
        if (missingPadding > 0) {
            decodedLength -= missingPadding;
        }

        decoded = new bytes(decodedLength);

        uint256 outIdx = 0;
        uint256 buffer = 0;
        uint256 bitsCollected = 0;

        for (uint256 i = 0; i < encoded.length; i++) {
            uint8 char = uint8(encoded[i]);
            uint8 value;

            // Decode base64url character
            if (char >= 65 && char <= 90) {
                // A-Z
                value = char - 65;
            } else if (char >= 97 && char <= 122) {
                // a-z
                value = char - 97 + 26;
            } else if (char >= 48 && char <= 57) {
                // 0-9
                value = char - 48 + 52;
            } else if (char == 45) {
                // '-' (base64url)
                value = 62;
            } else if (char == 95) {
                // '_' (base64url)
                value = 63;
            } else {
                continue; // Skip invalid characters
            }

            buffer = (buffer << 6) | value;
            bitsCollected += 6;

            if (bitsCollected >= 8) {
                bitsCollected -= 8;
                if (outIdx < decodedLength) {
                    decoded[outIdx++] = bytes1(uint8(buffer >> bitsCollected));
                }
                buffer &= (1 << bitsCollected) - 1;
            }
        }
    }
}

// lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol

// OpenZeppelin Contracts (last updated v5.4.0) (proxy/ERC1967/ERC1967Utils.sol)

/**
 * @dev This library provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
 */
library ERC1967Utils {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by ERC-1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the ERC-1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}

// src/PasskeyAccount.sol

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/

/*──────────────────── Interfaces ────────────────────────────────────*/

/*──────────────────── Libraries ────────────────────────────────────*/

/**
 * @title PasskeyAccount
 * @author POA Team
 * @notice ERC-4337 smart contract wallet with WebAuthn/Passkey authentication
 * @dev Features:
 *      - Multi-passkey support (up to maxCredentials per org)
 *      - Guardian-assisted recovery with time delay
 *      - Per-org credential tracking to prevent account selling
 *      - EIP-7951 native P256 signature verification
 *
 *      Architecture:
 *      - Uses ERC-7201 namespaced storage for upgrade safety
 *      - Deployed via BeaconProxy for upgradeability
 *      - Integrates with ERC-4337 EntryPoint v0.7
 */
contract PasskeyAccount is Initializable, IAccount, IPasskeyAccount {
    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice ERC-4337 EntryPoint v0.7 address (same on all chains)
    address public constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice Signature validation failed return value
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /// @notice Maximum number of credentials per account (global limit)
    uint8 internal constant MAX_CREDENTIALS = 10;

    /// @notice Minimum recovery delay (1 day)
    uint48 internal constant MIN_RECOVERY_DELAY = 1 days;

    /// @notice Module identifier
    bytes4 public constant MODULE_ID = bytes4(keccak256("PasskeyAccount"));

    /*──────────────────────── ERC-7201 Storage ──────────────────────────*/

    /// @custom:storage-location erc7201:poa.passkeyaccount.storage
    struct Layout {
        // Factory that created this account
        address factory;
        // Passkey credentials
        mapping(bytes32 => PasskeyCredential) credentials;
        bytes32[] credentialIds;
        // Per-org credential counts
        mapping(bytes32 => uint8) orgCredentialCount;
        // Guardian recovery
        address guardian;
        uint48 recoveryDelay;
        mapping(bytes32 => RecoveryRequest) recoveryRequests;
        bytes32[] pendingRecoveryIds;
    }

    // keccak256("poa.passkeyaccount.storage")
    bytes32 private constant _STORAGE_SLOT = 0x7cfc8294c1be3fa32b08d50f0668cc2726e1306f195499e2d5283b8967b03fef;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────── Modifiers ────────────────────────────*/

    /// @notice Restrict to EntryPoint only
    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();
        _;
    }

    /// @notice Restrict to self-calls (via EntryPoint execution)
    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelf();
        _;
    }

    /// @notice Restrict to guardian only
    modifier onlyGuardian() {
        if (msg.sender != _layout().guardian) revert OnlyGuardian();
        _;
    }

    /// @notice Restrict to guardian or self
    modifier onlyGuardianOrSelf() {
        Layout storage l = _layout();
        if (msg.sender != l.guardian && msg.sender != address(this)) {
            revert OnlyGuardianOrSelf();
        }
        _;
    }

    /*──────────────────────────── Constructor ──────────────────────────*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────────────────────── Initializer ──────────────────────────*/

    /**
     * @notice Initialize the passkey account
     * @param factory_ The factory that created this account
     * @param credentialId Initial credential ID
     * @param pubKeyX Initial credential public key X
     * @param pubKeyY Initial credential public key Y
     * @param orgId Organization this account is for
     * @param guardian_ Recovery guardian address
     * @param recoveryDelay_ Recovery delay in seconds
     */
    function initialize(
        address factory_,
        bytes32 credentialId,
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        bytes32 orgId,
        address guardian_,
        uint48 recoveryDelay_
    ) external initializer {
        if (factory_ == address(0)) revert ZeroAddress();
        if (pubKeyX == bytes32(0) || pubKeyY == bytes32(0)) revert InvalidSignature();

        Layout storage l = _layout();

        l.factory = factory_;
        l.guardian = guardian_;
        l.recoveryDelay = recoveryDelay_ < MIN_RECOVERY_DELAY ? MIN_RECOVERY_DELAY : recoveryDelay_;

        // Register initial credential
        l.credentials[credentialId] = PasskeyCredential({
            publicKeyX: pubKeyX,
            publicKeyY: pubKeyY,
            createdAt: uint64(block.timestamp),
            signCount: 0,
            orgId: orgId,
            active: true
        });
        l.credentialIds.push(credentialId);
        l.orgCredentialCount[orgId] = 1;

        emit CredentialAdded(credentialId, orgId, uint64(block.timestamp));
        if (guardian_ != address(0)) {
            emit GuardianUpdated(address(0), guardian_);
        }
    }

    /*──────────────────────────── ERC-4337 IAccount ────────────────────*/

    /**
     * @notice Validate a UserOperation signature
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation
     * @param missingAccountFunds Amount to pay to EntryPoint
     * @return validationData 0 for success, 1 for failure
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        onlyEntryPoint
        returns (uint256 validationData)
    {
        // Verify the WebAuthn signature
        validationData = _validateSignature(userOp.signature, userOpHash);

        // Pay prefund to EntryPoint
        if (missingAccountFunds > 0) {
            // solhint-disable-next-line no-unused-vars
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            // Return value intentionally ignored - EntryPoint validates the deposit
        }
    }

    /**
     * @notice Validate the WebAuthn signature
     * @param signature Encoded WebAuthn signature
     * @param userOpHash The challenge (userOpHash)
     * @return validationData 0 for success, 1 for failure
     */
    function _validateSignature(bytes calldata signature, bytes32 userOpHash)
        internal
        returns (uint256 validationData)
    {
        // Decode the signature
        // Format: credentialId(32) || WebAuthnAuth
        if (signature.length < 32) {
            return SIG_VALIDATION_FAILED;
        }

        bytes32 credentialId = bytes32(signature[0:32]);
        Layout storage l = _layout();

        // Get the credential
        PasskeyCredential storage cred = l.credentials[credentialId];
        if (!cred.active) {
            return SIG_VALIDATION_FAILED;
        }

        // Decode WebAuthn auth data
        WebAuthnLib.WebAuthnAuth memory auth = abi.decode(signature[32:], (WebAuthnLib.WebAuthnAuth));

        // Verify with signCount check
        (bool valid, uint32 newSignCount) = WebAuthnLib.verifyWithSignCount(
            auth,
            userOpHash,
            cred.publicKeyX,
            cred.publicKeyY,
            false, // Don't require user verification (UP is enough)
            cred.signCount
        );

        if (!valid) {
            return SIG_VALIDATION_FAILED;
        }

        // Update signCount
        cred.signCount = newSignCount;

        return 0;
    }

    /*──────────────────────────── Credential Management ───────────────*/

    /// @inheritdoc IPasskeyAccount
    function addCredential(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, bytes32 orgId)
        external
        override
        onlySelf
    {
        Layout storage l = _layout();

        // Check if credential already exists
        if (l.credentials[credentialId].createdAt != 0) {
            revert CredentialExists();
        }

        // Check global limit
        if (l.credentialIds.length >= MAX_CREDENTIALS) {
            revert MaxCredentialsReached();
        }

        // Check per-org limit from factory
        uint8 maxPerOrg = _getMaxCredentialsPerOrg(orgId);
        if (l.orgCredentialCount[orgId] >= maxPerOrg) {
            revert MaxCredentialsReached();
        }

        // Add credential
        l.credentials[credentialId] = PasskeyCredential({
            publicKeyX: pubKeyX,
            publicKeyY: pubKeyY,
            createdAt: uint64(block.timestamp),
            signCount: 0,
            orgId: orgId,
            active: true
        });
        l.credentialIds.push(credentialId);
        l.orgCredentialCount[orgId]++;

        emit CredentialAdded(credentialId, orgId, uint64(block.timestamp));
    }

    /// @inheritdoc IPasskeyAccount
    function removeCredential(bytes32 credentialId) external override onlySelf {
        Layout storage l = _layout();

        // Cannot remove last credential
        if (l.credentialIds.length <= 1) {
            revert CannotRemoveLastCredential();
        }

        PasskeyCredential storage cred = l.credentials[credentialId];
        if (cred.createdAt == 0) {
            revert CredentialNotFound();
        }

        // Decrement org count
        l.orgCredentialCount[cred.orgId]--;

        // Remove from array
        _removeCredentialFromArray(credentialId);

        // Delete credential
        delete l.credentials[credentialId];

        emit CredentialRemoved(credentialId);
    }

    /// @inheritdoc IPasskeyAccount
    function setCredentialActive(bytes32 credentialId, bool active) external override onlySelf {
        Layout storage l = _layout();
        PasskeyCredential storage cred = l.credentials[credentialId];

        if (cred.createdAt == 0) {
            revert CredentialNotFound();
        }

        cred.active = active;
        emit CredentialStatusChanged(credentialId, active);
    }

    /*──────────────────────────── Guardian Management ─────────────────*/

    /// @inheritdoc IPasskeyAccount
    function setGuardian(address newGuardian) external override onlySelf {
        Layout storage l = _layout();
        address oldGuardian = l.guardian;
        l.guardian = newGuardian;
        emit GuardianUpdated(oldGuardian, newGuardian);
    }

    /// @inheritdoc IPasskeyAccount
    function setRecoveryDelay(uint48 newDelay) external override onlySelf {
        Layout storage l = _layout();
        uint48 oldDelay = l.recoveryDelay;

        // Enforce minimum delay
        l.recoveryDelay = newDelay < MIN_RECOVERY_DELAY ? MIN_RECOVERY_DELAY : newDelay;

        emit RecoveryDelayUpdated(oldDelay, l.recoveryDelay);
    }

    /*──────────────────────────── Recovery Functions ──────────────────*/

    /// @inheritdoc IPasskeyAccount
    function initiateRecovery(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY) external override onlyGuardian {
        Layout storage l = _layout();

        // Generate recovery ID
        bytes32 recoveryId = keccak256(abi.encodePacked(credentialId, block.timestamp, msg.sender));

        // Check if recovery already pending for this credential
        if (l.recoveryRequests[recoveryId].executeAfter != 0) {
            revert RecoveryAlreadyPending();
        }

        // Check credential doesn't already exist
        if (l.credentials[credentialId].createdAt != 0) {
            revert CredentialExists();
        }

        uint48 executeAfter = uint48(block.timestamp) + l.recoveryDelay;

        l.recoveryRequests[recoveryId] = RecoveryRequest({
            credentialId: credentialId, pubKeyX: pubKeyX, pubKeyY: pubKeyY, executeAfter: executeAfter, cancelled: false
        });
        l.pendingRecoveryIds.push(recoveryId);

        emit RecoveryInitiated(recoveryId, credentialId, msg.sender, executeAfter);
    }

    /// @inheritdoc IPasskeyAccount
    function completeRecovery(bytes32 recoveryId) external override {
        Layout storage l = _layout();
        RecoveryRequest storage request = l.recoveryRequests[recoveryId];

        if (request.executeAfter == 0) {
            revert RecoveryNotPending();
        }

        if (request.cancelled) {
            revert RecoveryNotPending();
        }

        if (block.timestamp < request.executeAfter) {
            revert RecoveryDelayNotPassed();
        }

        // Add the new credential (use default org - can be updated later)
        bytes32 credentialId = request.credentialId;

        l.credentials[credentialId] = PasskeyCredential({
            publicKeyX: request.pubKeyX,
            publicKeyY: request.pubKeyY,
            createdAt: uint64(block.timestamp),
            signCount: 0,
            orgId: bytes32(0), // Recovery credentials have no org binding
            active: true
        });
        l.credentialIds.push(credentialId);

        // Mark recovery as completed by setting executeAfter to 0
        request.executeAfter = 0;

        emit RecoveryCompleted(recoveryId, credentialId);
        emit CredentialAdded(credentialId, bytes32(0), uint64(block.timestamp));
    }

    /// @inheritdoc IPasskeyAccount
    function cancelRecovery(bytes32 recoveryId) external override onlyGuardianOrSelf {
        Layout storage l = _layout();
        RecoveryRequest storage request = l.recoveryRequests[recoveryId];

        if (request.executeAfter == 0 || request.cancelled) {
            revert RecoveryNotPending();
        }

        request.cancelled = true;
        emit RecoveryCancelled(recoveryId);
    }

    /*──────────────────────────── Execution Functions ─────────────────*/

    /// @inheritdoc IPasskeyAccount
    function execute(address target, uint256 value, bytes calldata data)
        external
        override
        returns (bytes memory result)
    {
        // Can be called by EntryPoint or self
        if (msg.sender != ENTRY_POINT && msg.sender != address(this)) {
            revert OnlySelf();
        }

        bool success;
        (success, result) = target.call{value: value}(data);

        if (!success) {
            // Bubble up revert reason
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit Executed(target, value, data, result);
    }

    /// @inheritdoc IPasskeyAccount
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas)
        external
        override
    {
        // Can be called by EntryPoint or self
        if (msg.sender != ENTRY_POINT && msg.sender != address(this)) {
            revert OnlySelf();
        }

        if (targets.length != values.length || targets.length != datas.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(datas[i]);

            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }

        emit BatchExecuted(targets.length);
    }

    /*──────────────────────────── View Functions ──────────────────────*/

    /// @inheritdoc IPasskeyAccount
    function getCredential(bytes32 credentialId) external view override returns (PasskeyCredential memory credential) {
        return _layout().credentials[credentialId];
    }

    /// @inheritdoc IPasskeyAccount
    function getCredentialIds() external view override returns (bytes32[] memory) {
        return _layout().credentialIds;
    }

    /// @inheritdoc IPasskeyAccount
    function getOrgCredentialCount(bytes32 orgId) external view override returns (uint8) {
        return _layout().orgCredentialCount[orgId];
    }

    /// @inheritdoc IPasskeyAccount
    function guardian() external view override returns (address) {
        return _layout().guardian;
    }

    /// @inheritdoc IPasskeyAccount
    function recoveryDelay() external view override returns (uint48) {
        return _layout().recoveryDelay;
    }

    /// @inheritdoc IPasskeyAccount
    function getRecoveryRequest(bytes32 recoveryId) external view override returns (RecoveryRequest memory) {
        return _layout().recoveryRequests[recoveryId];
    }

    /// @inheritdoc IPasskeyAccount
    function factory() external view override returns (address) {
        return _layout().factory;
    }

    /*──────────────────────────── Internal Helpers ────────────────────*/

    /**
     * @notice Get max credentials per org from factory
     * @param orgId The organization ID
     * @return maxCredentials Maximum credentials allowed for this org
     */
    function _getMaxCredentialsPerOrg(bytes32 orgId) internal view returns (uint8) {
        // Try to get from factory, default to 5 if not set
        address factoryAddr = _layout().factory;
        if (factoryAddr == address(0)) {
            return 5;
        }

        // Call factory to get org config
        try IPasskeyAccountFactory(factoryAddr).getMaxCredentialsPerOrg(orgId) returns (uint8 max) {
            return max > 0 ? max : 5;
        } catch {
            return 5;
        }
    }

    /**
     * @notice Remove a credential ID from the array
     * @param credentialId The credential ID to remove
     */
    function _removeCredentialFromArray(bytes32 credentialId) internal {
        Layout storage l = _layout();
        uint256 length = l.credentialIds.length;

        for (uint256 i = 0; i < length; i++) {
            if (l.credentialIds[i] == credentialId) {
                // Swap with last element and pop
                l.credentialIds[i] = l.credentialIds[length - 1];
                l.credentialIds.pop();
                break;
            }
        }
    }

    /*──────────────────────────── Receive ETH ─────────────────────────*/

    receive() external payable {}
}

/**
 * @notice Interface for PasskeyAccountFactory (used internally)
 */
interface IPasskeyAccountFactory {
    function getMaxCredentialsPerOrg(bytes32 orgId) external view returns (uint8);
}

// lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol

// OpenZeppelin Contracts (last updated v5.2.0) (proxy/beacon/BeaconProxy.sol)

/**
 * @dev This contract implements a proxy that gets the implementation address for each call from an {UpgradeableBeacon}.
 *
 * The beacon address can only be set once during construction, and cannot be changed afterwards. It is stored in an
 * immutable variable to avoid unnecessary storage reads, and also in the beacon storage slot specified by
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] so that it can be accessed externally.
 *
 * CAUTION: Since the beacon address can never be changed, you must ensure that you either control the beacon, or trust
 * the beacon to not upgrade the implementation maliciously.
 *
 * IMPORTANT: Do not use the implementation logic to modify the beacon storage slot. Doing so would leave the proxy in
 * an inconsistent state where the beacon storage slot does not match the beacon address.
 */
contract BeaconProxy is Proxy {
    // An immutable address for the beacon to avoid unnecessary SLOADs before each delegate call.
    address private immutable _beacon;

    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     * - If `data` is empty, `msg.value` must be zero.
     */
    constructor(address beacon, bytes memory data) payable {
        ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
        _beacon = beacon;
    }

    /**
     * @dev Returns the current implementation address of the associated beacon.
     */
    function _implementation() internal view virtual override returns (address) {
        return IBeacon(_getBeacon()).implementation();
    }

    /**
     * @dev Returns the beacon.
     */
    function _getBeacon() internal view virtual returns (address) {
        return _beacon;
    }
}

// src/PasskeyAccountFactory.sol

/*──────────────────── OpenZeppelin ────────────────────────────────────*/

/*──────────────────── Local Imports ────────────────────────────────────*/

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

