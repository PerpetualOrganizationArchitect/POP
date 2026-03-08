// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @notice Minimal interface for RegistryRelay's username operations.
interface IRegistryRelayOnboarding {
    function registerAccountDirect(string calldata username) external payable;
    function getUsername(address user) external view returns (string memory);
}

/// @notice Minimal interface for QuickJoin's satellite onboarding path.
interface IQuickJoinSatellite {
    function quickJoinForUser(address user) external;
}

/// @title SatelliteOnboardingHelper
/// @notice Per-org satellite contract that coordinates the two-step
///         register-username + join-org flow on satellite chains.
/// @dev    On satellites, username registration is async (Hyperlane round-trip).
///         This helper:
///         1. Dispatches registration via RegistryRelay
///         2. Stores pending join state
///         3. Completes the join after username confirmation arrives
///
///         Set as QuickJoin's `masterDeployAddress` so it can call `quickJoinForUser`.
///         Deploy behind a BeaconProxy.
contract SatelliteOnboardingHelper is Initializable, OwnableUpgradeable {
    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.satelliteonboardinghelper.storage
    struct Layout {
        IRegistryRelayOnboarding relay;
        IQuickJoinSatellite quickJoin;
        mapping(address => bool) pendingJoins;
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
    error NoPendingJoin();
    error UsernameNotConfirmed();
    error NoUsername();

    /*──────────── Events ──────────*/
    event JoinRequested(address indexed user, string username);
    event JoinCompleted(address indexed user);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _relay, address _quickJoin) external initializer {
        if (owner == address(0) || _relay == address(0) || _quickJoin == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.relay = IRegistryRelayOnboarding(_relay);
        s.quickJoin = IQuickJoinSatellite(_quickJoin);
    }

    /*══════════════════ Onboarding Paths ══════════════════*/

    /// @notice Register username via relay AND request org join in one tx.
    /// @dev    Dispatches registration to hub via Hyperlane. The join completes
    ///         after confirmation arrives (call `completePendingJoin`).
    ///         Caller pays Hyperlane fee via msg.value.
    function registerAndRequestJoin(string calldata username) external payable {
        Layout storage s = _layout();
        s.relay.registerAccountDirect{value: msg.value}(username);
        s.pendingJoins[msg.sender] = true;
        emit JoinRequested(msg.sender, username);
    }

    /// @notice Complete a pending join after username confirmation arrives.
    /// @dev    Callable by anyone (relayer-friendly). Checks relay's cache
    ///         for confirmed username, then mints hats via QuickJoin.
    function completePendingJoin(address user) external {
        Layout storage s = _layout();
        if (!s.pendingJoins[user]) revert NoPendingJoin();

        string memory existing = s.relay.getUsername(user);
        if (bytes(existing).length == 0) revert UsernameNotConfirmed();

        delete s.pendingJoins[user];
        s.quickJoin.quickJoinForUser(user);
        emit JoinCompleted(user);
    }

    /// @notice Direct join for users who already registered via relay.
    /// @dev    No pending state needed — just checks relay cache and joins.
    function quickJoinWithUser() external {
        Layout storage s = _layout();
        string memory existing = s.relay.getUsername(msg.sender);
        if (bytes(existing).length == 0) revert NoUsername();

        s.quickJoin.quickJoinForUser(msg.sender);
        emit JoinCompleted(msg.sender);
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

    function pendingJoins(address user) external view returns (bool) {
        return _layout().pendingJoins[user];
    }
}
