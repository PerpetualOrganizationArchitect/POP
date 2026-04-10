// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {WebAuthnLib} from "./libs/WebAuthnLib.sol";

/*───────────────────────── Interface stubs ───────────────────────*/
interface IPasskeyFactory {
    function getAddress(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        view
        returns (address);
}

contract UniversalAccountRegistry is Initializable, OwnableUpgradeable {
    /*────────────────────────── Custom Errors ──────────────────────────*/
    error UsernameEmpty();
    error UsernameTooLong();
    error InvalidChars();
    error UsernameTaken();
    error AccountExists();
    error AccountUnknown();
    error ArrayLenMismatch();
    error SignatureExpired();
    error InvalidNonce();
    error InvalidSigner();
    error PasskeyFactoryNotSet();

    /*─────────────────────────── Constants ─────────────────────────────*/
    uint256 private constant MAX_LEN = 64;

    /*──────────────────────── EIP-712 Constants ───────────────────────*/
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("UniversalAccountRegistry");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 private constant _REGISTER_TYPEHASH =
        keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
    bytes32 private constant _REGISTER_PASSKEY_TYPEHASH =
        keccak256("RegisterPasskeyAccount(address user,string username,uint256 nonce,uint256 deadline)");
    bytes32 private constant _SET_PROFILE_TYPEHASH =
        keccak256("SetProfileMetadata(address user,bytes32 metadataHash,uint256 nonce,uint256 deadline)");

    /*──────────────────────── ERC-7201 Storage ──────────────────────────*/
    /// @custom:storage-location erc7201:poa.universalaccountregistry.storage
    struct Layout {
        mapping(address => string) addressToUsername;
        mapping(bytes32 => address) ownerOfUsernameHash;
        mapping(address => uint256) nonces;
        address passkeyFactory;
        // Cached EIP-712 domain separator (recomputed on chain ID change, e.g. hard forks)
        bytes32 cachedDomainSeparator;
        uint256 cachedChainId;
        // Profile metadata (IPFS CID sha256 digest, added in v2)
        mapping(address => bytes32) profileMetadataHash;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.universalaccountregistry.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────────────────────── Events ───────────────────────────────*/
    event UserRegistered(address indexed user, string username);
    event UsernameChanged(address indexed user, string newUsername);
    event UserDeleted(address indexed user, string oldUsername);
    event BatchRegistered(uint256 count);
    event PasskeyFactoryUpdated(address indexed factory);
    event ProfileMetadataUpdated(address indexed user, bytes32 metadataHash);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*────────────────────────── Initializer ────────────────────────────*/
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert InvalidChars();
        __Ownable_init(initialOwner);
        // Domain separator is lazily cached on first use by _domainSeparator()
    }

    /*──────────────────── Admin ──────────────────────────────────────*/
    function setPasskeyFactory(address factory) external onlyOwner {
        _layout().passkeyFactory = factory;
        emit PasskeyFactoryUpdated(factory);
    }

    /*──────────────────── Public Registration API ─────────────────────*/
    function registerAccount(string calldata username) external {
        _register(msg.sender, username);
    }

    /**
     * @notice Register a username for `user` using their EIP-712 ECDSA signature.
     * @dev Allows a third party (org/relayer) to pay gas while the user proves consent.
     * @param user      The EOA address to register the username for.
     * @param username  The desired username.
     * @param deadline  Timestamp after which the signature expires.
     * @param nonce     The user's current nonce (must match stored nonce).
     * @param signature The EIP-712 ECDSA signature from `user`.
     */
    function registerAccountBySig(
        address user,
        string calldata username,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        Layout storage l = _layout();
        if (nonce != l.nonces[user]) revert InvalidNonce();

        bytes32 structHash =
            keccak256(abi.encode(_REGISTER_TYPEHASH, user, keccak256(bytes(username)), nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));

        address signer = ECDSA.recover(digest, signature);
        if (signer != user) revert InvalidSigner();

        l.nonces[user] = nonce + 1;
        _register(user, username);
    }

    /**
     * @notice Register a username for a passkey account using a WebAuthn assertion.
     * @dev The account address is derived from the stored trusted factory + enrollment data.
     *      The WebAuthn signature proves the user controls the passkey private key.
     * @param credentialId The passkey credential ID.
     * @param pubKeyX      The passkey public key X coordinate.
     * @param pubKeyY      The passkey public key Y coordinate.
     * @param salt         The CREATE2 salt for address derivation.
     * @param username     The desired username.
     * @param deadline     Timestamp after which the assertion expires.
     * @param nonce        The account's current nonce (must match stored nonce).
     * @param auth         The WebAuthn assertion data.
     */
    function registerAccountByPasskeySig(
        bytes32 credentialId,
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        uint256 salt,
        string calldata username,
        uint256 deadline,
        uint256 nonce,
        WebAuthnLib.WebAuthnAuth calldata auth
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        Layout storage l = _layout();
        if (l.passkeyFactory == address(0)) revert PasskeyFactoryNotSet();

        // Derive the account address from the trusted stored factory
        address user = IPasskeyFactory(l.passkeyFactory).getAddress(credentialId, pubKeyX, pubKeyY, salt);

        if (nonce != l.nonces[user]) revert InvalidNonce();

        // Build the EIP-712 digest as the challenge for the WebAuthn signature.
        // Uses \x19\x01 + domainSeparator + structHash for proper domain separation,
        // consistent with the ECDSA registration path.
        bytes32 structHash =
            keccak256(abi.encode(_REGISTER_PASSKEY_TYPEHASH, user, keccak256(bytes(username)), nonce, deadline));
        bytes32 challenge = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));

        // Verify the WebAuthn signature proves the user controls the passkey
        if (!WebAuthnLib.verify(auth, challenge, pubKeyX, pubKeyY, false)) {
            revert InvalidSigner();
        }

        l.nonces[user] = nonce + 1;
        _register(user, username);
    }

    /**
     * @notice Batch onboarding helper (gas-friendlier for DAOs).
     * @dev Arrays must be equal length and <= 100 to stay within block gas.
     */
    function registerBatch(address[] calldata users, string[] calldata names) external onlyOwner {
        uint256 len = users.length;
        if (len != names.length) revert ArrayLenMismatch();
        require(len <= 100, "batch>100");

        for (uint256 i; i < len;) {
            _register(users[i], names[i]);
            unchecked {
                ++i;
            }
        }
        emit BatchRegistered(len);
    }

    /*──────────── Username mutation & voluntary delete ────────────────*/
    function changeUsername(string calldata newUsername) external {
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        (bytes32 newHash, string memory norm) = _validate(newUsername);
        if (l.ownerOfUsernameHash[newHash] != address(0)) revert UsernameTaken();

        // reserve new
        l.ownerOfUsernameHash[newHash] = msg.sender;

        // release old username so it can be claimed by others
        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        delete l.ownerOfUsernameHash[oldHash];

        l.addressToUsername[msg.sender] = norm;
        emit UsernameChanged(msg.sender, norm);
    }

    /**
     * @notice Delete address <-> username link.  The username is released
     *         and can be claimed by others.
     */
    function deleteAccount() external {
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        // release username so it can be re-registered
        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        delete l.ownerOfUsernameHash[oldHash];
        delete l.addressToUsername[msg.sender];
        delete l.profileMetadataHash[msg.sender];

        emit UserDeleted(msg.sender, oldName);
    }

    /*──────────────────── Profile Metadata ─────────────────────────────*/

    /// @notice Set profile metadata (IPFS CID hash) for the caller's account.
    function setProfileMetadata(bytes32 metadataHash) external {
        if (bytes(_layout().addressToUsername[msg.sender]).length == 0) revert AccountUnknown();
        _layout().profileMetadataHash[msg.sender] = metadataHash;
        emit ProfileMetadataUpdated(msg.sender, metadataHash);
    }

    /// @notice Set profile metadata via EIP-712 ECDSA signature (EOA, gas-sponsored).
    function setProfileMetadataBySig(
        address user,
        bytes32 metadataHash,
        uint256 deadline,
        uint256 nonce,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        Layout storage l = _layout();
        if (nonce != l.nonces[user]) revert InvalidNonce();
        if (bytes(l.addressToUsername[user]).length == 0) revert AccountUnknown();

        bytes32 structHash = keccak256(abi.encode(_SET_PROFILE_TYPEHASH, user, metadataHash, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        if (ECDSA.recover(digest, signature) != user) revert InvalidSigner();

        l.nonces[user] = nonce + 1;
        l.profileMetadataHash[user] = metadataHash;
        emit ProfileMetadataUpdated(user, metadataHash);
    }

    /// @notice Set profile metadata via WebAuthn passkey signature (gas-sponsored).
    function setProfileMetadataByPasskeySig(
        bytes32 credentialId,
        bytes32 pubKeyX,
        bytes32 pubKeyY,
        uint256 salt,
        bytes32 metadataHash,
        uint256 deadline,
        uint256 nonce,
        WebAuthnLib.WebAuthnAuth calldata auth
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();
        Layout storage l = _layout();
        if (l.passkeyFactory == address(0)) revert PasskeyFactoryNotSet();

        address user = IPasskeyFactory(l.passkeyFactory).getAddress(credentialId, pubKeyX, pubKeyY, salt);
        if (nonce != l.nonces[user]) revert InvalidNonce();
        if (bytes(l.addressToUsername[user]).length == 0) revert AccountUnknown();

        bytes32 structHash = keccak256(abi.encode(_SET_PROFILE_TYPEHASH, user, metadataHash, nonce, deadline));
        bytes32 challenge = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        if (!WebAuthnLib.verify(auth, challenge, pubKeyX, pubKeyY, false)) revert InvalidSigner();

        l.nonces[user] = nonce + 1;
        l.profileMetadataHash[user] = metadataHash;
        emit ProfileMetadataUpdated(user, metadataHash);
    }

    /// @notice Get profile metadata hash for a user.
    function getProfileMetadata(address user) external view returns (bytes32) {
        return _layout().profileMetadataHash[user];
    }

    /*────────────────────────── View Helpers ──────────────────────────*/
    function addressToUsername(address user) external view returns (string memory) {
        return _layout().addressToUsername[user];
    }

    function ownerOfUsernameHash(bytes32 hash) external view returns (address) {
        return _layout().ownerOfUsernameHash[hash];
    }

    function getUsername(address user) external view returns (string memory) {
        return _layout().addressToUsername[user];
    }

    function getAddressOfUsername(string calldata name) external view returns (address) {
        return _layout().ownerOfUsernameHash[keccak256(bytes(_toLower(name)))];
    }

    /// @notice Returns the current nonce for `user` (for signature construction).
    function nonces(address user) external view returns (uint256) {
        return _layout().nonces[user];
    }

    function passkeyFactory() external view returns (address) {
        return _layout().passkeyFactory;
    }

    /// @notice Returns the EIP-712 domain separator.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _domainSeparatorView();
    }

    /*──────────────────── EIP-712 Helpers ─────────────────────────────*/
    /// @dev Returns the cached domain separator if chain ID hasn't changed, otherwise recomputes.
    function _domainSeparator() internal returns (bytes32) {
        Layout storage l = _layout();
        if (l.cachedChainId == block.chainid && l.cachedDomainSeparator != bytes32(0)) {
            return l.cachedDomainSeparator;
        }
        bytes32 ds = _computeDomainSeparator();
        l.cachedChainId = block.chainid;
        l.cachedDomainSeparator = ds;
        return ds;
    }

    /// @dev View-only domain separator (for DOMAIN_SEPARATOR() getter, cannot update cache).
    function _domainSeparatorView() internal view returns (bytes32) {
        Layout storage l = _layout();
        if (l.cachedChainId == block.chainid && l.cachedDomainSeparator != bytes32(0)) {
            return l.cachedDomainSeparator;
        }
        return _computeDomainSeparator();
    }

    function _computeDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(this)));
    }

    /*──────────────────── Internal Registration ───────────────────────*/
    function _register(address user, string calldata username) internal {
        Layout storage l = _layout();
        if (bytes(l.addressToUsername[user]).length != 0) revert AccountExists();

        (bytes32 hash, string memory norm) = _validate(username);
        if (l.ownerOfUsernameHash[hash] != address(0)) revert UsernameTaken();

        l.ownerOfUsernameHash[hash] = user;
        l.addressToUsername[user] = norm;

        emit UserRegistered(user, norm);
    }

    /*──────────────────── Username Validation ─────────────────────────*/
    function _validate(string calldata raw) internal pure returns (bytes32 hash, string memory normalized) {
        uint256 len = bytes(raw).length;
        if (len == 0) revert UsernameEmpty();
        if (len > MAX_LEN) revert UsernameTooLong();

        bytes memory lower = bytes(raw);
        for (uint256 i; i < len;) {
            uint8 c = uint8(lower[i]);
            if (c >= 65 && c <= 90) c += 32;
            if (
                // a-z
                // 0-9
                !((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || (c == 95) || (c == 45)) // _ or -
            ) revert InvalidChars();
            lower[i] = bytes1(c);
            unchecked {
                ++i;
            }
        }
        normalized = string(lower);
        hash = keccak256(lower);
    }

    function _toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) b[i] = bytes1(c + 32);
        }
        return string(b);
    }
}
