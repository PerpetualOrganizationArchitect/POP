// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

contract UniversalAccountRegistry is Initializable, OwnableUpgradeable {
    /*────────────────────────── Custom Errors ──────────────────────────*/
    error UsernameEmpty();
    error UsernameTooLong();
    error InvalidChars();
    error UsernameTaken();
    error AccountExists();
    error AccountUnknown();
    error ArrayLenMismatch();

    /*─────────────────────────── Constants ─────────────────────────────*/
    uint256 private constant MAX_LEN = 64;
    address private constant BURN_ADDRESS = address(0xdead);

    /*──────────────────────────── Storage ──────────────────────────────*/
    mapping(address => string) public addressToUsername;
    mapping(bytes32 => address) public ownerOfUsernameHash;

    /*──────────────────────────── Events ───────────────────────────────*/
    event UserRegistered(address indexed user, string username);
    event UsernameChanged(address indexed user, string newUsername);
    event UserDeleted(address indexed user, string oldUsername);
    event BatchRegistered(uint256 count);

    /*────────────────────────── Initializer ────────────────────────────*/
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert InvalidChars();
        __Ownable_init(initialOwner);
    }

    /*──────────────────── Public Registration API ─────────────────────*/
    function registerAccount(string calldata username) external {
        _register(msg.sender, username);
    }

    /**
     * @notice Permission‑less QuickJoin path. Anyone can call but the
     *         `newUser` must NOT already have a username and the handle
     *         must still be free.
     */
    function registerAccountQuickJoin(string calldata username, address newUser) external {
        _register(newUser, username);
    }

    /**
     * @notice Batch onboarding helper (gas‑friendlier for DAOs).
     * @dev Arrays must be equal length and ≤ 100 to stay within block gas.
     */
    function registerBatch(address[] calldata users, string[] calldata names) external {
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
        string storage oldName = addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        (bytes32 newHash, string memory norm) = _validate(newUsername);
        if (ownerOfUsernameHash[newHash] != address(0)) revert UsernameTaken();

        // reserve new
        ownerOfUsernameHash[newHash] = msg.sender;

        // keep old reserved forever by burning ownership
        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        ownerOfUsernameHash[oldHash] = BURN_ADDRESS;

        addressToUsername[msg.sender] = norm;
        emit UsernameChanged(msg.sender, norm);
    }

    /**
     * @notice Delete address ↔ username link.  Name remains permanently
     *         reserved (cannot be claimed by others).
     */
    function deleteAccount() external {
        string storage oldName = addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        ownerOfUsernameHash[oldHash] = BURN_ADDRESS;
        delete addressToUsername[msg.sender];

        emit UserDeleted(msg.sender, oldName);
    }

    /*────────────────────────── View Helpers ──────────────────────────*/
    function getUsername(address user) external view returns (string memory) {
        return addressToUsername[user];
    }

    function getAddressOfUsername(string calldata name) external view returns (address) {
        return ownerOfUsernameHash[keccak256(bytes(_toLower(name)))];
    }

    /*────────────────────────── Version Hook ──────────────────────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    /*──────────────────── Internal Registration ───────────────────────*/
    function _register(address user, string calldata username) internal {
        if (bytes(addressToUsername[user]).length != 0) revert AccountExists();

        (bytes32 hash, string memory norm) = _validate(username);
        if (ownerOfUsernameHash[hash] != address(0)) revert UsernameTaken();

        ownerOfUsernameHash[hash] = user;
        addressToUsername[user] = norm;

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
                // a‑z
                // 0‑9
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

    /*───────────── Upgrade storage gap ─────────────*/
    uint256[45] private __gap;
}
