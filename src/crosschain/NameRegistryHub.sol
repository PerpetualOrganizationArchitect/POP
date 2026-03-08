// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
/// @dev    Bidirectional: implements IMessageRecipient (receives from satellites)
///         AND dispatches responses back through the same Mailbox.
///         The confirm/reject dispatch happens in the same tx as handle().
contract NameRegistryHub is Ownable(msg.sender), IMessageRecipient {
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

    /*──────────── Immutables ──────────*/
    IAccountRegistryCrossChain public immutable accountRegistry;
    IMailbox public immutable mailbox;

    /*──────────── Storage ─────────────*/
    SatelliteConfig[] public satellites;
    bool public paused;

    /// @dev Global reservation map for usernames. A name is taken iff reserved[nameHash] == true.
    ///      This is the single source of truth for cross-chain username uniqueness.
    mapping(bytes32 => bool) public reserved;

    /// @dev Global reservation map for org names. Separate namespace from usernames.
    mapping(bytes32 => bool) public reservedOrgNames;

    /// @dev Addresses authorized to call the *OrgNameLocal functions (home-chain OrgRegistry).
    mapping(address => bool) public authorizedOrgRegistries;

    /// @dev Fee to use per return dispatch. Owner-configurable to adapt to gas price changes.
    uint256 public returnFee;

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
    event OrgRegistryAuthorized(address indexed registry, bool authorized);
    event SatelliteRegistered(uint32 indexed domain, address satellite);
    event SatelliteRemoved(uint32 indexed domain);
    event PauseSet(bool paused);
    event ReturnFeeSet(uint256 fee);

    /*──────────── Constructor ─────────*/
    constructor(address _accountRegistry, address _mailbox) {
        if (_accountRegistry == address(0) || _mailbox == address(0)) revert ZeroAddress();
        accountRegistry = IAccountRegistryCrossChain(_accountRegistry);
        mailbox = IMailbox(_mailbox);
    }

    /*══════════════════ Hyperlane Receiver ══════════════════*/

    /// @notice Called by the Hyperlane Mailbox when a message arrives from a satellite relay.
    /// @dev    Validates origin + sender against registered satellites, then processes
    ///         the claim and dispatches confirm/reject back in the same transaction.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external override {
        if (msg.sender != address(mailbox)) revert UnauthorizedMailbox();
        if (paused) revert IsPaused();
        if (!_isRegisteredSatellite(_origin, _sender)) revert UnauthorizedSatellite();

        uint8 msgType = abi.decode(_body[:32], (uint8));

        if (msgType == MSG_CLAIM_USERNAME) {
            _handleClaimUsername(_origin, _sender, _body);
        } else if (msgType == MSG_BURN_USERNAME) {
            _handleBurnUsername(_origin, _body);
        } else if (msgType == MSG_CHANGE_USERNAME) {
            _handleChangeUsername(_origin, _sender, _body);
        } else if (msgType == MSG_CLAIM_ORG_NAME) {
            _handleClaimOrgName(_origin, _sender, _body);
        } else {
            revert UnknownMessageType();
        }
    }

    /*══════════════════ Home-Chain Shortcut ══════════════════*/

    /// @notice Called by the home-chain UniversalAccountRegistry during local registration.
    /// @dev    Synchronous — reverts if name is taken, no Hyperlane involved.
    function claimUsernameLocal(bytes32 nameHash) external {
        if (msg.sender != address(accountRegistry)) revert NotAccountRegistry();
        if (reserved[nameHash]) revert NameTaken();
        reserved[nameHash] = true;
    }

    /// @notice Called by the home-chain UAR during local username change.
    function changeUsernameLocal(bytes32, bytes32 newHash) external {
        if (msg.sender != address(accountRegistry)) revert NotAccountRegistry();
        if (reserved[newHash]) revert NameTaken();
        reserved[newHash] = true;
        // Old name stays reserved (burned) — cannot be reclaimed
    }

    /// @notice Called by the home-chain UAR during local username delete.
    function burnUsernameLocal(bytes32) external view {
        if (msg.sender != address(accountRegistry)) revert NotAccountRegistry();
        // Name stays reserved — burned names can never be reclaimed (POP invariant)
    }

    /*══════════════════ Home-Chain Shortcut: Org Names ══════════════════*/

    /// @notice Called by the home-chain OrgRegistry during local org creation.
    /// @dev    Synchronous — reverts if name is taken, no Hyperlane involved.
    function claimOrgNameLocal(bytes32 nameHash) external {
        if (!authorizedOrgRegistries[msg.sender]) revert NotOrgRegistry();
        if (reservedOrgNames[nameHash]) revert OrgNameTaken();
        reservedOrgNames[nameHash] = true;
    }

    /// @notice Called by the home-chain OrgRegistry during org name change.
    /// @dev    Old name is released (unlike usernames, org names CAN be reclaimed after rename).
    function changeOrgNameLocal(bytes32 oldHash, bytes32 newHash) external {
        if (!authorizedOrgRegistries[msg.sender]) revert NotOrgRegistry();
        if (reservedOrgNames[newHash]) revert OrgNameTaken();
        delete reservedOrgNames[oldHash];
        reservedOrgNames[newHash] = true;
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function registerSatellite(uint32 domain, address satellite) external onlyOwner {
        if (satellite == address(0)) revert ZeroAddress();

        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            if (satellites[i].domain == domain && satellites[i].active) {
                revert DuplicateDomain(domain);
            }
            unchecked {
                ++i;
            }
        }

        satellites.push(
            SatelliteConfig({domain: domain, satellite: bytes32(uint256(uint160(satellite))), active: true})
        );
        emit SatelliteRegistered(domain, satellite);
    }

    function removeSatellite(uint256 index) external onlyOwner {
        uint32 domain = satellites[index].domain;
        satellites[index].active = false;
        emit SatelliteRemoved(domain);
    }

    function satelliteCount() external view returns (uint256) {
        return satellites.length;
    }

    /*══════════════════ Admin ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseSet(_paused);
    }

    function setReturnFee(uint256 _fee) external onlyOwner {
        returnFee = _fee;
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
        reserved[nameHash] = true;
    }

    /// @notice Admin burn: permanently reserve an org name.
    function adminBurnOrgName(bytes32 nameHash) external onlyOwner {
        reservedOrgNames[nameHash] = true;
        emit OrgNameBurned(nameHash);
    }

    /// @notice Authorize an OrgRegistry to call *OrgNameLocal functions.
    function setAuthorizedOrgRegistry(address registry, bool authorized) external onlyOwner {
        if (registry == address(0)) revert ZeroAddress();
        authorizedOrgRegistries[registry] = authorized;
        emit OrgRegistryAuthorized(registry, authorized);
    }

    /// @dev Accept ETH for return-dispatch fees.
    receive() external payable {}

    /*══════════════════ Internal: Message Handlers ══════════════════*/

    function _handleClaimUsername(uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, address user, string memory username) = abi.decode(_body, (uint8, address, string));
        bytes32 nameHash = _hashUsername(username);

        // Try to register on canonical UAR
        try accountRegistry.registerAccountCrossChain(user, username) {
            reserved[nameHash] = true;
            emit UsernameReserved(nameHash, _origin, user);

            bytes memory confirm = abi.encode(MSG_CONFIRM_USERNAME, user, username);
            _dispatchToSatellite(_origin, _sender, confirm);
        } catch {
            emit UsernameRejected(nameHash, _origin, user);

            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, username);
            _dispatchToSatellite(_origin, _sender, reject);
        }
    }

    function _handleBurnUsername(uint32, bytes calldata _body) internal {
        (, address user) = abi.decode(_body, (uint8, address));

        // Fire-and-forget: delete on canonical UAR. Name stays reserved.
        try accountRegistry.deleteAccountCrossChain(user) {} catch {}

        // No response needed — burn is permanent regardless
    }

    function _handleChangeUsername(uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, address user, string memory newUsername) = abi.decode(_body, (uint8, address, string));
        bytes32 newHash = _hashUsername(newUsername);

        // Check global reservation first (catches admin-burned names).
        // changeUsernameCrossChain on UAR doesn't call back to claimUsernameLocal
        // (unlike _register), so we must check reserved here explicitly.
        if (reserved[newHash]) {
            emit UsernameRejected(newHash, _origin, user);
            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, newUsername);
            _dispatchToSatellite(_origin, _sender, reject);
            return;
        }

        // Atomic: try change on UAR (it burns old + claims new internally)
        try accountRegistry.changeUsernameCrossChain(user, newUsername) {
            reserved[newHash] = true;
            emit UsernameChanged(bytes32(0), newHash, _origin, user);

            bytes memory confirm = abi.encode(MSG_CONFIRM_USERNAME, user, newUsername);
            _dispatchToSatellite(_origin, _sender, confirm);
        } catch {
            emit UsernameRejected(newHash, _origin, user);

            bytes memory reject = abi.encode(MSG_REJECT_USERNAME, user, newUsername);
            _dispatchToSatellite(_origin, _sender, reject);
        }
    }

    /*══════════════════ Internal: Org Name Handlers ══════════════════*/

    function _handleClaimOrgName(uint32 _origin, bytes32 _sender, bytes calldata _body) internal {
        (, string memory orgName) = abi.decode(_body, (uint8, string));
        bytes32 nameHash = _hashUsername(orgName);

        if (reservedOrgNames[nameHash]) {
            emit OrgNameRejected(nameHash, _origin);
            bytes memory reject = abi.encode(MSG_REJECT_ORG_NAME, orgName);
            _dispatchToSatellite(_origin, _sender, reject);
        } else {
            reservedOrgNames[nameHash] = true;
            emit OrgNameReserved(nameHash, _origin);
            bytes memory confirm = abi.encode(MSG_CONFIRM_ORG_NAME, orgName);
            _dispatchToSatellite(_origin, _sender, confirm);
        }
    }

    /*══════════════════ Internal: Helpers ══════════════════*/

    function _isRegisteredSatellite(uint32 domain, bytes32 sender) internal view returns (bool) {
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            if (satellites[i].active && satellites[i].domain == domain && satellites[i].satellite == sender) {
                return true;
            }
            unchecked {
                ++i;
            }
        }
        return false;
    }

    function _dispatchToSatellite(uint32 domain, bytes32 satellite, bytes memory payload) internal {
        uint256 fee = returnFee;
        if (fee > 0 && address(this).balance < fee) revert InsufficientBalance();
        mailbox.dispatch{value: fee}(domain, satellite, payload);
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
