// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/*──────────────────── Interfaces ────────────────────────────────────*/
import {IAccount} from "./interfaces/IAccount.sol";
import {IPasskeyAccount} from "./interfaces/IPasskeyAccount.sol";
import {PackedUserOperation} from "./interfaces/PackedUserOperation.sol";

/*──────────────────── Libraries ────────────────────────────────────*/
import {WebAuthnLib} from "./libs/WebAuthnLib.sol";

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
