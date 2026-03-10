// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IMailbox, IMessageRecipient} from "./interfaces/IHyperlane.sol";

/// @title RegistryRelay
/// @notice Satellite-chain contract that relays username registration requests
///         to the NameRegistryHub on Arbitrum via Hyperlane, and receives
///         confirmations/rejections back.
/// @dev    Deploy behind a BeaconProxy. Stores confirmed usernames in a local cache
///         for on-chain reads (e.g. QuickJoin checking if a user has a username).
contract RegistryRelay is Initializable, OwnableUpgradeable, IMessageRecipient {
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

    uint256 private constant MAX_LEN = 64;
    uint256 private constant MAX_ORG_NAME_LEN = 256;

    /*──────────── EIP-712 Constants ───────────*/
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("RegistryRelay");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 private constant _REGISTER_TYPEHASH =
        keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");

    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.registryrelay.storage
    struct Layout {
        IMailbox mailbox;
        uint32 hubDomain;
        bytes32 hubAddress;
        bool paused;
        mapping(address => string) confirmedUsernames;
        mapping(bytes32 => address) confirmedOwners;
        mapping(address => uint256) nonces;
        mapping(bytes32 => bool) confirmedOrgNames;
        mapping(address => bool) authorizedCallers;
        uint256 dispatchFee;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.registryrelay.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────── Errors ──────────────*/
    error UnauthorizedMailbox();
    error UnauthorizedOrigin();
    error UnauthorizedSender();
    error UnknownMessageType();
    error ZeroAddress();
    error IsPaused();
    error CannotRenounce();
    error UsernameEmpty();
    error UsernameTooLong();
    error InvalidChars();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();
    error OrgNameEmpty();
    error OrgNameTooLong();
    error UnauthorizedCaller();
    error InsufficientBalance();
    error TransferFailed();

    /*──────────── Events ──────────────*/
    event ClaimDispatched(address indexed user, string username, bytes32 messageId);
    event UsernameConfirmed(address indexed user, string username);
    event UsernameRejected(address indexed user, string username);
    event BurnDispatched(address indexed user, bytes32 messageId);
    event ChangeDispatched(address indexed user, string newUsername, bytes32 messageId);
    event PauseSet(bool paused);
    event OrgNameClaimDispatched(string orgName, bytes32 messageId);
    event OrgNameConfirmed(string orgName);
    event OrgNameRejected(string orgName);
    event AuthorizedCallerSet(address indexed caller, bool authorized);
    event OrgNameReleaseDispatched(bytes32 indexed nameHash, bytes32 messageId);
    event DispatchFeeSet(uint256 fee);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _mailbox, uint32 _hubDomain, address _hubAddress) external initializer {
        if (owner == address(0) || _mailbox == address(0) || _hubAddress == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.mailbox = IMailbox(_mailbox);
        s.hubDomain = _hubDomain;
        s.hubAddress = bytes32(uint256(uint160(_hubAddress)));
    }

    /*══════════════════ Registration ══════════════════*/

    /// @notice Register a username for `user` using their EIP-712 signature.
    /// @dev    Validates format locally, verifies signature, then relays to hub.
    ///         The caller (org/relayer) pays gas + Hyperlane fee via msg.value.
    function registerAccount(
        address user,
        string calldata username,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external payable {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        if (block.timestamp > deadline) revert SignatureExpired();
        if (nonce != s.nonces[user]) revert InvalidNonce();

        // Validate username format locally (saves gas on invalid names)
        _validateUsername(username);

        // Verify EIP-712 signature proves user consent
        bytes32 structHash =
            keccak256(abi.encode(_REGISTER_TYPEHASH, user, keccak256(bytes(username)), nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        address signer = ECDSA.recover(digest, signature);
        if (signer != user) revert InvalidSigner();

        s.nonces[user] = nonce + 1;

        // Dispatch claim to hub
        bytes memory payload = abi.encode(MSG_CLAIM_USERNAME, user, username);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit ClaimDispatched(user, username, msgId);
    }

    /// @notice Direct registration — caller registers their own username.
    function registerAccountDirect(string calldata username) external payable {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        _validateUsername(username);

        bytes memory payload = abi.encode(MSG_CLAIM_USERNAME, msg.sender, username);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit ClaimDispatched(msg.sender, username, msgId);
    }

    /// @notice Register a username on behalf of a user. Authorized callers only.
    /// @dev    Used by SatelliteOnboardingHelper to register users in a single tx.
    function registerAccountForUser(address user, string calldata username) external payable {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        if (!s.authorizedCallers[msg.sender]) revert UnauthorizedCaller();
        if (user == address(0)) revert ZeroAddress();
        _validateUsername(username);

        bytes memory payload = abi.encode(MSG_CLAIM_USERNAME, user, username);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit ClaimDispatched(user, username, msgId);
    }

    /// @notice Change username — caller changes their own username.
    function changeUsername(string calldata newUsername) external payable {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        _validateUsername(newUsername);

        bytes memory payload = abi.encode(MSG_CHANGE_USERNAME, msg.sender, newUsername);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit ChangeDispatched(msg.sender, newUsername, msgId);
    }

    /// @notice Delete account — caller deletes their username (permanently burned).
    function deleteAccount() external payable {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();

        // Clear local cache
        string memory oldName = s.confirmedUsernames[msg.sender];
        if (bytes(oldName).length > 0) {
            bytes32 oldHash = _hashUsername(oldName);
            delete s.confirmedUsernames[msg.sender];
            delete s.confirmedOwners[oldHash];
        }

        bytes memory payload = abi.encode(MSG_BURN_USERNAME, msg.sender);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit BurnDispatched(msg.sender, msgId);
    }

    /*══════════════════ Org Name Registration ══════════════════*/

    /// @notice Dispatch a cross-chain org name claim to the hub.
    /// @dev    Only owner (governance) can claim org names to prevent squatting.
    function claimOrgName(string calldata orgName) external payable onlyOwner {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        _validateOrgName(orgName);

        bytes memory payload = abi.encode(MSG_CLAIM_ORG_NAME, orgName);
        bytes32 msgId = s.mailbox.dispatch{value: msg.value}(s.hubDomain, s.hubAddress, payload);

        emit OrgNameClaimDispatched(orgName, msgId);
    }

    /// @notice Dispatch an optimistic org name claim to the hub.
    /// @dev    Uses pre-funded relay balance for Hyperlane fee. Authorized callers only.
    ///         Called by NameClaimAdapter during org deployment.
    function dispatchOrgNameClaim(string calldata orgName) external {
        if (!_layout().authorizedCallers[msg.sender]) revert UnauthorizedCaller();
        _validateOrgName(orgName);

        bytes32 msgId = _dispatchPreFunded(abi.encode(MSG_CLAIM_ORG_NAME, orgName));
        emit OrgNameClaimDispatched(orgName, msgId);
    }

    /// @notice Release a confirmed org name — clears local cache and dispatches to hub.
    /// @dev    Uses pre-funded relay balance for Hyperlane fee. Authorized callers only.
    function dispatchOrgNameRelease(bytes32 nameHash) external {
        Layout storage s = _layout();
        if (!s.authorizedCallers[msg.sender]) revert UnauthorizedCaller();

        delete s.confirmedOrgNames[nameHash];

        bytes32 msgId = _dispatchPreFunded(abi.encode(MSG_RELEASE_ORG_NAME, nameHash));
        emit OrgNameReleaseDispatched(nameHash, msgId);
    }

    /*══════════════════ Hyperlane Receiver ══════════════════*/

    /// @notice Receives confirm/reject from the NameRegistryHub.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external override {
        Layout storage s = _layout();
        if (msg.sender != address(s.mailbox)) revert UnauthorizedMailbox();
        if (_origin != s.hubDomain) revert UnauthorizedOrigin();
        if (_sender != s.hubAddress) revert UnauthorizedSender();

        uint8 msgType = abi.decode(_body[:32], (uint8));

        if (msgType == MSG_CONFIRM_USERNAME) {
            (, address user, string memory username) = abi.decode(_body, (uint8, address, string));

            // Clear stale cache entry if user had a previous name (e.g. username change)
            string memory oldName = s.confirmedUsernames[user];
            if (bytes(oldName).length > 0) {
                delete s.confirmedOwners[_hashUsername(oldName)];
            }

            // Update local cache
            bytes32 nameHash = _hashUsername(username);
            s.confirmedUsernames[user] = username;
            s.confirmedOwners[nameHash] = user;

            emit UsernameConfirmed(user, username);
        } else if (msgType == MSG_REJECT_USERNAME) {
            (, address user, string memory username) = abi.decode(_body, (uint8, address, string));

            emit UsernameRejected(user, username);
        } else if (msgType == MSG_CONFIRM_ORG_NAME) {
            (, string memory orgName) = abi.decode(_body, (uint8, string));
            s.confirmedOrgNames[_hashUsername(orgName)] = true;
            emit OrgNameConfirmed(orgName);
        } else if (msgType == MSG_REJECT_ORG_NAME) {
            (, string memory orgName) = abi.decode(_body, (uint8, string));
            emit OrgNameRejected(orgName);
        } else {
            revert UnknownMessageType();
        }
    }

    /*══════════════════ Public Getters ══════════════════*/

    function mailbox() external view returns (IMailbox) {
        return _layout().mailbox;
    }

    function hubDomain() external view returns (uint32) {
        return _layout().hubDomain;
    }

    function hubAddress() external view returns (bytes32) {
        return _layout().hubAddress;
    }

    function paused() external view returns (bool) {
        return _layout().paused;
    }

    function nonces(address user) external view returns (uint256) {
        return _layout().nonces[user];
    }

    function confirmedOrgNames(bytes32 nameHash) external view returns (bool) {
        return _layout().confirmedOrgNames[nameHash];
    }

    function authorizedCallers(address caller) external view returns (bool) {
        return _layout().authorizedCallers[caller];
    }

    function dispatchFee() external view returns (uint256) {
        return _layout().dispatchFee;
    }

    /*══════════════════ View Helpers ══════════════════*/

    /// @notice Get a user's confirmed username (from local cache).
    function getUsername(address user) external view returns (string memory) {
        return _layout().confirmedUsernames[user];
    }

    /// @notice Check if a name is taken in the local cache.
    /// @dev    This is NOT authoritative — the hub is the source of truth.
    ///         A name may be taken on the hub but not yet synced to this cache.
    function getAddressOfUsername(string calldata name) external view returns (address) {
        return _layout().confirmedOwners[_hashUsername(name)];
    }

    /// @notice Check if an org name is confirmed in the local cache.
    /// @dev    This is NOT authoritative — the hub is the source of truth.
    function isOrgNameConfirmed(string calldata orgName) external view returns (bool) {
        return _layout().confirmedOrgNames[_hashUsername(orgName)];
    }

    /// @notice EIP-712 domain separator for this relay.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparator();
    }

    /*══════════════════ Admin ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        _layout().paused = _paused;
        emit PauseSet(_paused);
    }

    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        if (caller == address(0)) revert ZeroAddress();
        _layout().authorizedCallers[caller] = authorized;
        emit AuthorizedCallerSet(caller, authorized);
    }

    function setDispatchFee(uint256 _fee) external onlyOwner {
        _layout().dispatchFee = _fee;
        emit DispatchFeeSet(_fee);
    }

    function withdrawETH(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = to.call{value: balance}("");
        if (!ok) revert TransferFailed();
    }

    /// @dev Ownership cannot be renounced.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /// @dev Accept ETH for pre-funded dispatches (claims + releases).
    receive() external payable {}

    /*══════════════════ Internal ══════════════════*/

    /// @dev Dispatch a message to the hub using pre-funded relay balance.
    function _dispatchPreFunded(bytes memory payload) internal returns (bytes32) {
        Layout storage s = _layout();
        uint256 fee = s.dispatchFee;
        if (fee > 0 && address(this).balance < fee) revert InsufficientBalance();
        return s.mailbox.dispatch{value: fee}(s.hubDomain, s.hubAddress, payload);
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }

    function _validateUsername(string calldata raw) internal pure {
        uint256 len = bytes(raw).length;
        if (len == 0) revert UsernameEmpty();
        if (len > MAX_LEN) revert UsernameTooLong();

        bytes memory b = bytes(raw);
        for (uint256 i; i < len;) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) c += 32; // to lowercase
            if (!((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || (c == 95) || (c == 45))) {
                revert InvalidChars();
            }
            unchecked {
                ++i;
            }
        }
    }

    function _validateOrgName(string calldata raw) internal pure {
        uint256 len = bytes(raw).length;
        if (len == 0) revert OrgNameEmpty();
        if (len > MAX_ORG_NAME_LEN) revert OrgNameTooLong();
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
