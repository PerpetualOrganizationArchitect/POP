// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @notice Interface for RegistryRelay — read confirmed names + dispatch claims/releases.
interface IRegistryRelay {
    function confirmedOrgNames(bytes32 nameHash) external view returns (bool);
    function dispatchOrgNameClaim(string calldata orgName) external;
    function dispatchOrgNameRelease(bytes32 nameHash) external;
}

/// @title NameClaimAdapter
/// @notice Satellite-chain adapter that bridges OrgRegistry's synchronous
///         `INameRegistryHubOrgNames` interface to RegistryRelay's async
///         Hyperlane dispatch.
/// @dev    On the home chain, OrgRegistry calls NameRegistryHub.claimOrgNameLocal()
///         directly (synchronous). On satellites, OrgRegistry points its
///         `nameRegistryHub` at this adapter instead.
///
///         On initial claim, the adapter dispatches the claim to the hub
///         optimistically via the relay (using pre-funded relay ETH).
///         On rename, the adapter verifies the new name is pre-confirmed
///         and dispatches a release of the old name to the hub.
///
///         IMPORTANT — Rejection recovery:
///         Initial claims are optimistic: the org deploys before the hub confirms.
///         If the hub rejects the name (e.g. already taken globally), the org exists
///         on the satellite with a locally invalid name. There is no automatic retry.
///         The RegistryRelay emits `OrgNameRejected` — operators/frontend should
///         monitor this event. Recovery requires org governance to call
///         `OrgRegistry.updateOrgMeta()` with a new, pre-confirmed name.
///
///         Deploy behind a BeaconProxy.
contract NameClaimAdapter is Initializable, OwnableUpgradeable {
    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.nameclaimadapter.storage
    struct Layout {
        IRegistryRelay relay;
        mapping(address => bool) authorizedCallers;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.nameclaimadapter.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────── Errors ──────────*/
    error ZeroAddress();
    error CannotRenounce();
    error NotAuthorized();
    error NameNotConfirmed();

    /*──────────── Events ──────────*/
    event OrgNameConsumed(bytes32 indexed nameHash);
    event OrgNameReleased(bytes32 indexed nameHash);
    event AuthorizedCallerSet(address indexed caller, bool authorized);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _relay) external initializer {
        if (owner == address(0) || _relay == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        _layout().relay = IRegistryRelay(_relay);
    }

    /*══════════════════ INameRegistryHubOrgNames ══════════════════*/

    /// @notice Dispatch an optimistic org name claim to the hub via the relay.
    /// @dev    Called by OrgRegistry.registerOrg() / createOrgBootstrap().
    ///         Dispatches the claim immediately — org deploys optimistically
    ///         while the hub confirms/rejects in the background.
    function claimOrgNameLocal(bytes32 nameHash, string calldata orgName) external {
        Layout storage s = _layout();
        if (!s.authorizedCallers[msg.sender]) revert NotAuthorized();

        // Dispatch claim to hub optimistically via pre-funded relay
        s.relay.dispatchOrgNameClaim(orgName);

        emit OrgNameConsumed(nameHash);
    }

    /// @notice Handle org name change: verify new name is confirmed, release old name on hub.
    /// @dev    Called by OrgRegistry.updateOrgMeta(). The new name must have been
    ///         pre-claimed via RegistryRelay.claimOrgName() before this call.
    ///         Automatically dispatches a release of the old name to the hub
    ///         via the relay (using pre-funded relay ETH).
    function changeOrgNameLocal(bytes32 oldHash, bytes32 newHash) external {
        Layout storage s = _layout();
        if (!s.authorizedCallers[msg.sender]) revert NotAuthorized();
        if (!s.relay.confirmedOrgNames(newHash)) revert NameNotConfirmed();

        // Release old name on hub (fire-and-forget via pre-funded relay)
        s.relay.dispatchOrgNameRelease(oldHash);

        emit OrgNameReleased(oldHash);
        emit OrgNameConsumed(newHash);
    }

    /*══════════════════ Admin ══════════════════*/

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        _layout().authorizedCallers[caller] = authorized;
        emit AuthorizedCallerSet(caller, authorized);
    }

    /// @dev Ownership cannot be renounced.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*══════════════════ Public Getters ══════════════════*/

    function relay() external view returns (IRegistryRelay) {
        return _layout().relay;
    }

    function authorizedCallers(address caller) external view returns (bool) {
        return _layout().authorizedCallers[caller];
    }
}
