// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

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
