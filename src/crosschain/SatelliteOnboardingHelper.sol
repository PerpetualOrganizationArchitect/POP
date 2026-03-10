// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @notice Minimal interface for RegistryRelay's onboarding operations.
interface IRegistryRelayOnboarding {
    function registerAccountForUser(address user, string calldata username) external payable;
    function registerAccount(
        address user,
        string calldata username,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external payable;
    function getUsername(address user) external view returns (string memory);
}

/// @notice Minimal interface for QuickJoin's satellite onboarding paths.
interface IQuickJoinSatellite {
    function quickJoinNoUserMasterDeploy(address newUser) external;
    function quickJoinForUser(address user) external;
}

/// @notice Minimal interface for passkey account factory.
interface IPasskeyFactory {
    function createAccount(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        returns (address account);
}

/// @title SatelliteOnboardingHelper
/// @notice Per-org satellite contract that provides single-tx optimistic onboarding.
/// @dev    On satellites, username registration is async (Hyperlane round-trip).
///         This helper uses an optimistic pattern: dispatch the username claim AND
///         join the org immediately in the same tx. The username confirms in the
///         background via Hyperlane. Frontend pre-tx checks prevent collisions.
///
///         Set as QuickJoin's `masterDeployAddress` so it can call join functions.
///         Set as RegistryRelay's authorized caller so it can register on behalf of users.
///         Deploy behind a BeaconProxy.
contract SatelliteOnboardingHelper is Initializable, OwnableUpgradeable {
    /*──────────── Passkey Enrollment Struct ──────────*/
    struct PasskeyEnrollment {
        bytes32 credentialId;
        bytes32 publicKeyX;
        bytes32 publicKeyY;
        uint256 salt;
    }

    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.satelliteonboardinghelper.storage
    struct Layout {
        IRegistryRelayOnboarding relay;
        IQuickJoinSatellite quickJoin;
        IPasskeyFactory passkeyFactory;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.satelliteonboardinghelper.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────── Errors ──────────*/
    error ZeroAddress();
    error CannotRenounce();
    error NoUsername();
    error PasskeyFactoryNotSet();

    /*──────────── Events ──────────*/
    event RegisterAndJoined(address indexed user, string username);
    event RegisterAndJoinedWithPasskey(address indexed account, bytes32 indexed credentialId, string username);
    event JoinCompleted(address indexed user);
    event JoinCompletedWithPasskey(address indexed account, bytes32 indexed credentialId);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    /// @param _passkeyFactory Can be address(0) if passkey support not needed for this org.
    function initialize(address owner, address _relay, address _quickJoin, address _passkeyFactory)
        external
        initializer
    {
        if (owner == address(0) || _relay == address(0) || _quickJoin == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.relay = IRegistryRelayOnboarding(_relay);
        s.quickJoin = IQuickJoinSatellite(_quickJoin);
        if (_passkeyFactory != address(0)) {
            s.passkeyFactory = IPasskeyFactory(_passkeyFactory);
        }
    }

    /*══════════════════ Optimistic Onboarding (single-tx) ══════════════════*/

    /// @notice Register username + join org in one tx (EOA, user calls directly).
    /// @dev    Dispatches username claim optimistically via relay, then joins immediately.
    ///         Caller pays Hyperlane fee via msg.value.
    function registerAndJoin(string calldata username) external payable {
        Layout storage s = _layout();
        s.relay.registerAccountForUser{value: msg.value}(msg.sender, username);
        s.quickJoin.quickJoinNoUserMasterDeploy(msg.sender);
        emit RegisterAndJoined(msg.sender, username);
    }

    /// @notice Register username + join org in one tx (sponsored by relayer/backend).
    /// @dev    Uses RegistryRelay's EIP-712 signature verification — no new relay
    ///         function needed since the sig proves user consent.
    function registerAndJoinSponsored(
        address user,
        string calldata username,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external payable {
        Layout storage s = _layout();
        s.relay.registerAccount{value: msg.value}(user, username, deadline, nonce, signature);
        s.quickJoin.quickJoinNoUserMasterDeploy(user);
        emit RegisterAndJoined(user, username);
    }

    /// @notice Register username + create passkey account + join org in one tx.
    /// @dev    Creates passkey account via factory, dispatches username claim for that
    ///         account address, then joins immediately.
    function registerAndJoinWithPasskey(PasskeyEnrollment calldata passkey, string calldata username)
        external
        payable
        returns (address account)
    {
        Layout storage s = _layout();
        if (address(s.passkeyFactory) == address(0)) revert PasskeyFactoryNotSet();

        account =
            s.passkeyFactory.createAccount(passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);
        s.relay.registerAccountForUser{value: msg.value}(account, username);
        s.quickJoin.quickJoinNoUserMasterDeploy(account);

        emit RegisterAndJoinedWithPasskey(account, passkey.credentialId, username);
    }

    /*══════════════════ Non-Optimistic Onboarding ══════════════════*/

    /// @notice Join org for users who already have a confirmed username.
    /// @dev    No Hyperlane dispatch — just checks relay cache and joins.
    function quickJoinWithUser() external {
        Layout storage s = _layout();
        string memory existing = s.relay.getUsername(msg.sender);
        if (bytes(existing).length == 0) revert NoUsername();

        s.quickJoin.quickJoinForUser(msg.sender);
        emit JoinCompleted(msg.sender);
    }

    /// @notice Join org for passkey users who already have a confirmed username.
    /// @dev    Creates/gets passkey account, checks relay cache, joins.
    function quickJoinWithPasskey(PasskeyEnrollment calldata passkey) external returns (address account) {
        Layout storage s = _layout();
        if (address(s.passkeyFactory) == address(0)) revert PasskeyFactoryNotSet();

        account =
            s.passkeyFactory.createAccount(passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);

        string memory existing = s.relay.getUsername(account);
        if (bytes(existing).length == 0) revert NoUsername();

        s.quickJoin.quickJoinForUser(account);
        emit JoinCompletedWithPasskey(account, passkey.credentialId);
    }

    /*══════════════════ Admin ══════════════════*/

    /// @dev Ownership cannot be renounced.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*══════════════════ Public Getters ══════════════════*/

    function relay() external view returns (IRegistryRelayOnboarding) {
        return _layout().relay;
    }

    function quickJoin() external view returns (IQuickJoinSatellite) {
        return _layout().quickJoin;
    }

    function passkeyFactory() external view returns (IPasskeyFactory) {
        return _layout().passkeyFactory;
    }
}
