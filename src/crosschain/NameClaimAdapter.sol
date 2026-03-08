// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

/// @notice Minimal interface for reading RegistryRelay's confirmed org names cache.
interface IRegistryRelayReader {
    function confirmedOrgNames(bytes32 nameHash) external view returns (bool);
}

/// @title NameClaimAdapter
/// @notice Satellite-chain adapter that bridges OrgRegistry's synchronous
///         `INameRegistryHubOrgNames` interface to RegistryRelay's async
///         confirmed-names cache.
/// @dev    On the home chain, OrgRegistry calls NameRegistryHub.claimOrgNameLocal()
///         directly (synchronous). On satellites, OrgRegistry points its
///         `nameRegistryHub` at this adapter instead. The adapter checks the
///         RegistryRelay's `confirmedOrgNames` cache (populated after Hyperlane
///         round-trip) and tracks consumption to prevent double-use.
///
///         Deploy behind a BeaconProxy.
contract NameClaimAdapter is Initializable, OwnableUpgradeable {
    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.nameclaimadapter.storage
    struct Layout {
        IRegistryRelayReader relay;
        mapping(bytes32 => bool) consumedOrgNames;
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
    error NameAlreadyConsumed();

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
        _layout().relay = IRegistryRelayReader(_relay);
    }

    /*══════════════════ INameRegistryHubOrgNames ══════════════════*/

    /// @notice Consume a pre-confirmed org name from the relay's cache.
    /// @dev    Called by OrgRegistry.registerOrg() / createOrgBootstrap().
    ///         Reverts if the name was not confirmed by the hub or already consumed.
    function claimOrgNameLocal(bytes32 nameHash) external {
        Layout storage s = _layout();
        if (!s.authorizedCallers[msg.sender]) revert NotAuthorized();
        if (!s.relay.confirmedOrgNames(nameHash)) revert NameNotConfirmed();
        if (s.consumedOrgNames[nameHash]) revert NameAlreadyConsumed();

        s.consumedOrgNames[nameHash] = true;
        emit OrgNameConsumed(nameHash);
    }

    /// @notice Handle org name change: release old name, consume new pre-confirmed name.
    /// @dev    Called by OrgRegistry.updateOrgMeta(). The new name must have been
    ///         pre-claimed via RegistryRelay.claimOrgName() before this call.
    function changeOrgNameLocal(bytes32 oldHash, bytes32 newHash) external {
        Layout storage s = _layout();
        if (!s.authorizedCallers[msg.sender]) revert NotAuthorized();
        if (!s.relay.confirmedOrgNames(newHash)) revert NameNotConfirmed();
        if (s.consumedOrgNames[newHash]) revert NameAlreadyConsumed();

        // Release old name locally (hub still reserves it globally)
        delete s.consumedOrgNames[oldHash];
        s.consumedOrgNames[newHash] = true;

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

    function relay() external view returns (IRegistryRelayReader) {
        return _layout().relay;
    }

    function consumedOrgNames(bytes32 nameHash) external view returns (bool) {
        return _layout().consumedOrgNames[nameHash];
    }

    function authorizedCallers(address caller) external view returns (bool) {
        return _layout().authorizedCallers[caller];
    }
}
