// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IMailbox, IMessageRecipient} from "./interfaces/IHyperlane.sol";

/// @notice Minimal interface for UAR cross-chain registration.
interface IAccountRegistryCrossChain {
    function registerAccountCrossChain(address user, string calldata username) external;
    function changeUsernameCrossChain(address user, string calldata newUsername) external;
    function deleteAccountCrossChain(address user) external;
}

/// @title NameRegistryHub
/// @notice Home-chain (Arbitrum) hub for globally unique username and org name registration.
///         Receives claims from satellite relays via Hyperlane, registers on the
///         canonical UniversalAccountRegistry (usernames) or reserves globally (org names),
///         and dispatches confirm/reject back.
/// @dev    Deploy behind a BeaconProxy. Bidirectional: implements IMessageRecipient
///         (receives from satellites) AND dispatches responses back through the same Mailbox.
///         The confirm/reject dispatch happens in the same tx as handle().
contract NameRegistryHub is Initializable, OwnableUpgradeable, IMessageRecipient {
    /*──────────── Types ───────────*/
    struct SatelliteConfig {
        uint32 domain;
        bytes32 satellite;
        bool active;
    }

    /*──────────── Constants ───────────*/
    uint8 internal constant MSG_CLAIM_USERNAME = 0x01;
    uint8 internal constant MSG_CONFIRM_USERNAME = 0x02;
    uint8 internal constant MSG_REJECT_USERNAME = 0x03;
    uint8 internal constant MSG_BURN_USERNAME = 0x04;
    uint8 internal constant MSG_CHANGE_USERNAME = 0x05;
    uint8 internal constant MSG_CLAIM_ORG_NAME = 0x06;
    uint8 internal constant MSG_CONFIRM_ORG_NAME = 0x07;
    uint8 internal constant MSG_REJECT_ORG_NAME = 0x08;
    uint8 internal constant MSG_RELEASE_ORG_NAME = 0x09;

    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.nameregistryhub.storage
    struct Layout {
        IAccountRegistryCrossChain accountRegistry;
        IMailbox mailbox;
        SatelliteConfig[] satellites;
        bool paused;
        mapping(bytes32 => bool) reserved;
        mapping(bytes32 => bool) reservedOrgNames;
        mapping(address => bool) authorizedOrgRegistries;
        uint256 returnFee;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.nameregistryhub.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────── Errors ──────────────*/
    error IsPaused();
    error ZeroAddress();
    error CannotRenounce();
    error TransferFailed();
    error DuplicateDomain(uint32 domain);
    error UnauthorizedMailbox();
    error NotAccountRegistry();
    error UnauthorizedSatellite();
    error UnknownMessageType();
    error NameTaken();
    error NameNotReserved();
    error OrgNameTaken();
    error NotOrgRegistry();
    error InsufficientBalance();

    /*──────────── Events ──────────────*/
    event UsernameReserved(bytes32 indexed nameHash, uint32 indexed originDomain, address user);
    event UsernameRejected(bytes32 indexed nameHash, uint32 indexed originDomain, address user);
    event UsernameBurned(bytes32 indexed nameHash, uint32 indexed originDomain, address user);
    event UsernameChanged(
        bytes32 indexed oldNameHash, bytes32 indexed newNameHash, uint32 indexed originDomain, address user
    );
    event OrgNameReserved(bytes32 indexed nameHash, uint32 indexed originDomain);
    event OrgNameRejected(bytes32 indexed nameHash, uint32 indexed originDomain);

    event OrgNameBurned(bytes32 indexed nameHash);
    event OrgNameReleased(bytes32 indexed nameHash, uint32 indexed originDomain);
    event OrgRegistryAuthorized(address indexed registry, bool authorized);
    event SatelliteRegistered(uint32 indexed domain, address satellite);
    event SatelliteRemoved(uint32 indexed domain);
    event PauseSet(bool paused);
    event ReturnFeeSet(uint256 fee);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _accountRegistry, address _mailbox) external initializer {
        if (owner == address(0) || _accountRegistry == address(0) || _mailbox == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.accountRegistry = IAccountRegistryCrossChain(_accountRegistry);
        s.mailbox = IMailbox(_mailbox);
    }

    /*══════════════════ Hyperlane Receiver ══════════════════*/

    /// @notice Called by the Hyperlane Mailbox when a message arrives from a satellite relay.
    /// @dev    Validates origin + sender against registered satellites, then processes
    ///         the claim and dispatches confirm/reject back in the same transaction.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external override {
        Layout storage s = _layout();
        if (msg.sender != address(s.mailbox)) revert UnauthorizedMailbox();
        if (s.paused) revert IsPaused();
        if (!_isRegisteredSatellite(s, _origin, _sender)) revert UnauthorizedSatellite();

        uint8 msgType = abi.decode(_body[:32], (uint8));

        if (msgType == MSG_CLAIM_USERNAME) {
            _handleClaimUsername(s, _origin, _sender, _body);
        } else if (msgType == MSG_BURN_USERNAME) {
            _handleBurnUsername(s, _origin, _body);
        } else if (msgType == MSG_CHANGE_USERNAME) {
            _handleChangeUsername(s, _origin, _sender, _body);
        } else if (msgType == MSG_CLAIM_ORG_NAME) {
            _handleClaimOrgName(s, _origin, _sender, _body);
        } else if (msgType == MSG_RELEASE_ORG_NAME) {
            _handleReleaseOrgName(s, _origin, _body);
        } else {
            revert UnknownMessageType();
        }
    }

    /*══════════════════ Home-Chain Shortcut ══════════════════*/

    /// @notice Called by the home-chain UniversalAccountRegistry during local registration.
    /// @dev    Synchronous — reverts if name is taken, no Hyperlane involved.
    function claimUsernameLocal(bytes32 nameHash) external {
        Layout storage s = _layout();
        if (msg.sender != address(s.accountRegistry)) revert NotAccountRegistry();
        if (s.reserved[nameHash]) revert NameTaken();
        s.reserved[nameHash] = true;
    }

    /// @notice Called by the home-chain UAR during local username change.
    function changeUsernameLocal(bytes32, bytes32 newHash) external {
        Layout storage s = _layout();
        if (msg.sender != address(s.accountRegistry)) revert NotAccountRegistry();
        if (s.reserved[newHash]) revert NameTaken();
        s.reserved[newHash] = true;
        // Old name stays reserved (burned) — cannot be reclaimed
    }

    /// @notice Called by the home-chain UAR during local username delete.
    function burnUsernameLocal(bytes32) external view {
        Layout storage s = _layout();
        if (msg.sender != address(s.accountRegistry)) revert NotAccountRegistry();
        // Name stays reserved — burned names can never be reclaimed (POP invariant)
    }

    /*══════════════════ Home-Chain Shortcut: Org Names ══════════════════*/

    /// @notice Called by the home-chain OrgRegistry during local org creation.
    /// @dev    Synchronous — reverts if name is taken, no Hyperlane involved.
    ///         The orgName param is unused on home chain (hash is sufficient).
    function claimOrgNameLocal(bytes32 nameHash, string calldata) external {
        Layout storage s = _layout();
        if (!s.authorizedOrgRegistries[msg.sender]) revert NotOrgRegistry();
        if (s.reservedOrgNames[nameHash]) revert OrgNameTaken();
        s.reservedOrgNames[nameHash] = true;
    }

    /// @notice Called by the home-chain OrgRegistry during org name change.
    /// @dev    Old name is released (unlike usernames, org names CAN be reclaimed after rename).
    function changeOrgNameLocal(bytes32 oldHash, bytes32 newHash) external {
        Layout storage s = _layout();
        if (!s.authorizedOrgRegistries[msg.sender]) revert NotOrgRegistry();
        if (s.reservedOrgNames[newHash]) revert OrgNameTaken();
        delete s.reservedOrgNames[oldHash];
        s.reservedOrgNames[newHash] = true;
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function registerSatellite(uint32 domain, address satellite) external onlyOwner {
        if (satellite == address(0)) revert ZeroAddress();
        Layout storage s = _layout();

        uint256 len = s.satellites.length;
        for (uint256 i; i < len;) {
            if (s.satellites[i].domain == domain && s.satellites[i].active) {
                revert DuplicateDomain(domain);
            }
            unchecked {
                ++i;
            }
        }

        s.satellites
            .push(SatelliteConfig({domain: domain, satellite: bytes32(uint256(uint160(satellite))), active: true}));
        emit SatelliteRegistered(domain, satellite);
    }

    function removeSatellite(uint256 index) external onlyOwner {
        Layout storage s = _layout();
        uint32 domain = s.satellites[index].domain;
        s.satellites[index].active = false;
        emit SatelliteRemoved(domain);
    }

    function satelliteCount() external view returns (uint256) {
        return _layout().satellites.length;
    }

    /*══════════════════ Public Getters ══════════════════*/

    function accountRegistry() external view returns (IAccountRegistryCrossChain) {
        return _layout().accountRegistry;
    }

    function mailbox() external view returns (IMailbox) {
        return _layout().mailbox;
    }

    function satellites(uint256 index) external view returns (uint32 domain, bytes32 satellite, bool active) {
        Layout storage s = _layout();
        SatelliteConfig storage sat = s.satellites[index];
        return (sat.domain, sat.satellite, sat.active);
    }

    function paused() external view returns (bool) {
        return _layout().paused;
    }

    function reserved(bytes32 nameHash) external view returns (bool) {
        return _layout().reserved[nameHash];
    }

    function reservedOrgNames(bytes32 nameHash) external view returns (bool) {
        return _layout().reservedOrgNames[nameHash];
    }

    function authorizedOrgRegistries(address registry) external view returns (bool) {
        return _layout().authorizedOrgRegistries[registry];
    }

    function returnFee() external view returns (uint256) {
        return _layout().returnFee;
    }

    /*══════════════════ Admin ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        _layout().paused = _paused;
        emit PauseSet(_paused);
    }

    function setReturnFee(uint256 _fee) external onlyOwner {
        _layout().returnFee = _fee;
        emit ReturnFeeSet(_fee);
    }

    /// @dev Ownership cannot be renounced — losing it bricks the Hub permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /// @notice Rescue ETH stuck in this contract.
    function withdrawETH(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = to.call{value: balance}("");
        if (!ok) revert TransferFailed();
    }

    /// @notice Admin burn: permanently reserve a username (e.g. to block offensive names).
    function adminBurn(bytes32 nameHash) external onlyOwner {
        _layout().reserved[nameHash] = true;
    }

    /// @notice Admin burn: permanently reserve an org name.
    function adminBurnOrgName(bytes32 nameHash) external onlyOwner {
        _layout().reservedOrgNames[nameHash] = true;
        emit OrgNameBurned(nameHash);
    }

    /// @notice Authorize an OrgRegistry to call *OrgNameLocal functions.
    function setAuthorizedOrgRegistry(address registry, bool authorized) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        _layout().authorizedOrgRegistries[registry] = authorized;
        emit OrgRegistryAuthorized(registry, authorized);
    }

    /// @dev Accept ETH for return-dispatch fees.
    receive() external payable {}

    /*══════════════════ Internal: Message Handlers ══════════════════*/

    function _handleClaimUsername(Layout storage s, uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, address user, string memory username) = abi.decode(_body, (uint8, address, string));
        bytes32 nameHash = _hashUsername(username);

        // Pre-check: reject if name is already reserved (e.g. admin burn, prior claim)
        if (s.reserved[nameHash]) {
            emit UsernameRejected(nameHash, _origin, user);
            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, username);
            _dispatchToSatellite(s, _origin, _sender, reject);
            return;
        }

        // Try to register on canonical UAR
        try s.accountRegistry.registerAccountCrossChain(user, username) {
            s.reserved[nameHash] = true;
            emit UsernameReserved(nameHash, _origin, user);

            bytes memory confirm = abi.encode(MSG_CONFIRM_USERNAME, user, username);
            _dispatchToSatellite(s, _origin, _sender, confirm);
        } catch {
            emit UsernameRejected(nameHash, _origin, user);

            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, username);
            _dispatchToSatellite(s, _origin, _sender, reject);
        }
    }

    function _handleBurnUsername(Layout storage s, uint32, bytes calldata _body) internal {
        (, address user) = abi.decode(_body, (uint8, address));

        // Fire-and-forget: delete on canonical UAR. Name stays reserved.
        try s.accountRegistry.deleteAccountCrossChain(user) {} catch {}

        // No response needed — burn is permanent regardless
    }

    function _handleChangeUsername(Layout storage s, uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, address user, string memory newUsername) = abi.decode(_body, (uint8, address, string));
        bytes32 newHash = _hashUsername(newUsername);

        // Check global reservation first (catches admin-burned names).
        // changeUsernameCrossChain on UAR doesn't call back to claimUsernameLocal
        // (unlike _register), so we must check reserved here explicitly.
        if (s.reserved[newHash]) {
            emit UsernameRejected(newHash, _origin, user);
            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, newUsername);
            _dispatchToSatellite(s, _origin, _sender, reject);
            return;
        }

        // Atomic: try change on UAR (it burns old + claims new internally)
        try s.accountRegistry.changeUsernameCrossChain(user, newUsername) {
            s.reserved[newHash] = true;
            emit UsernameChanged(bytes32(0), newHash, _origin, user);

            bytes memory confirm = abi.encode(MSG_CONFIRM_USERNAME, user, newUsername);
            _dispatchToSatellite(s, _origin, _sender, confirm);
        } catch {
            emit UsernameRejected(newHash, _origin, user);

            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, newUsername);
            _dispatchToSatellite(s, _origin, _sender, reject);
        }
    }

    /*══════════════════ Internal: Org Name Handlers ══════════════════*/

    function _handleClaimOrgName(Layout storage s, uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, string memory orgName) = abi.decode(_body, (uint8, string));
        bytes32 nameHash = _hashUsername(orgName);

        if (s.reservedOrgNames[nameHash]) {
            emit OrgNameRejected(nameHash, _origin);
            bytes memory reject = abi.encode(MSG_REJECT_ORG_NAME, orgName);
            _dispatchToSatellite(s, _origin, _sender, reject);
        } else {
            s.reservedOrgNames[nameHash] = true;
            emit OrgNameReserved(nameHash, _origin);
            bytes memory confirm = abi.encode(MSG_CONFIRM_ORG_NAME, orgName);
            _dispatchToSatellite(s, _origin, _sender, confirm);
        }
    }

    function _handleReleaseOrgName(Layout storage s, uint32 _origin, bytes calldata _body) internal {
        (, bytes32 nameHash) = abi.decode(_body, (uint8, bytes32));
        delete s.reservedOrgNames[nameHash];
        emit OrgNameReleased(nameHash, _origin);
    }

    /*══════════════════ Internal: Helpers ══════════════════*/

    function _isRegisteredSatellite(Layout storage s, uint32 domain, bytes32 sender) internal view returns (bool) {
        uint256 len = s.satellites.length;
        for (uint256 i; i < len;) {
            if (s.satellites[i].active && s.satellites[i].domain == domain && s.satellites[i].satellite == sender) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function _dispatchToSatellite(Layout storage s, uint32 domain, bytes32 satellite, bytes memory payload) internal {
        uint256 fee = s.returnFee;
        if (fee > 0 && address(this).balance < fee) revert InsufficientBalance();
        s.mailbox.dispatch{value: fee}(domain, satellite, payload);
    }

    function _hashUsername(string memory username) internal pure returns (bytes32) {
        bytes memory b = bytes(username);
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) b[i] = bytes1(c + 32);
        }
        return keccak256(b);
    }
}
