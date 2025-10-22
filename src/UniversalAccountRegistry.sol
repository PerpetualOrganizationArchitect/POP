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
    error NotAuthorizedRecoveryCaller();
    error NoUsername();
    error SameAddress();
    error AddressAlreadyHasUsername();

    /*─────────────────────────── Constants ─────────────────────────────*/
    uint256 private constant MAX_LEN = 64;
    address private constant BURN_ADDRESS = address(0xdead);

    /*──────────────────────── ERC-7201 Storage ──────────────────────────*/
    /// @custom:storage-location erc7201:poa.universalaccountregistry.storage
    struct Layout {
        mapping(address => string) addressToUsername;
        mapping(bytes32 => address) ownerOfUsernameHash;
        address recoveryCaller; // Contract authorized to perform recoverAccount
        address orgApprover; // Optional: org-level approver for recovery
    }

    // keccak256("poa.universalaccountregistry.storage") to unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x7930448747c45b59575e0d27c83e46a902e6071fea71aa7dda420fff16e39ee5;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────── Events ───────────────────────────────*/
    event UserRegistered(address indexed user, string username);
    event UsernameChanged(address indexed user, string newUsername);
    event UserDeleted(address indexed user, string oldUsername);
    event BatchRegistered(uint256 count);
    event RecoveryCallerChanged(address indexed oldCaller, address indexed newCaller);
    event OrgApproverChanged(address indexed oldApprover, address indexed newApprover);
    event AccountRecovered(address indexed from, address indexed to, string username);

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
     * @dev Arrays must be equal length and ≤ 100 to stay within block gas.
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
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        (bytes32 newHash, string memory norm) = _validate(newUsername);
        if (l.ownerOfUsernameHash[newHash] != address(0)) revert UsernameTaken();

        // reserve new
        l.ownerOfUsernameHash[newHash] = msg.sender;

        // keep old reserved forever by burning ownership
        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        l.ownerOfUsernameHash[oldHash] = BURN_ADDRESS;

        l.addressToUsername[msg.sender] = norm;
        emit UsernameChanged(msg.sender, norm);
    }

    /**
     * @notice Delete address ↔ username link.  Name remains permanently
     *         reserved (cannot be claimed by others).
     */
    function deleteAccount() external {
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        l.ownerOfUsernameHash[oldHash] = BURN_ADDRESS;
        delete l.addressToUsername[msg.sender];

        emit UserDeleted(msg.sender, oldName);
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

    /*──────────────────── Recovery Management ─────────────────────────*/
    /**
     * @notice Set the authorized recovery caller (typically DeviceWrapRegistry)
     * @param newCaller Address authorized to call recoverAccount
     */
    function setRecoveryCaller(address newCaller) external onlyOwner {
        Layout storage l = _layout();
        address old = l.recoveryCaller;
        l.recoveryCaller = newCaller;
        emit RecoveryCallerChanged(old, newCaller);
    }

    /**
     * @notice Set org-level approver for recovery (optional)
     * @param newApprover Address authorized to approve recoveries
     */
    function setOrgApprover(address newApprover) external onlyOwner {
        Layout storage l = _layout();
        address old = l.orgApprover;
        l.orgApprover = newApprover;
        emit OrgApproverChanged(old, newApprover);
    }

    /**
     * @notice Recover account from one address to another
     * @dev Can only be called by authorized recovery caller or org approver
     * @param from Current address holding the username
     * @param to New address to receive the username
     */
    function recoverAccount(address from, address to) external {
        Layout storage l = _layout();

        // Authorization check
        if (msg.sender != l.recoveryCaller && msg.sender != l.orgApprover) {
            revert NotAuthorizedRecoveryCaller();
        }

        string storage uname = l.addressToUsername[from];
        if (bytes(uname).length == 0) revert NoUsername();
        if (from == to) revert SameAddress();
        if (bytes(l.addressToUsername[to]).length != 0) revert AddressAlreadyHasUsername();

        // Transfer username to new address
        l.addressToUsername[to] = uname;
        delete l.addressToUsername[from];

        bytes32 h = keccak256(bytes(_toLower(uname)));
        l.ownerOfUsernameHash[h] = to;

        emit AccountRecovered(from, to, uname);
        emit UsernameChanged(to, uname);
    }

    /**
     * @notice Get the current recovery caller address
     */
    function getRecoveryCaller() external view returns (address) {
        return _layout().recoveryCaller;
    }

    /**
     * @notice Get the current org approver address
     */
    function getOrgApprover() external view returns (address) {
        return _layout().orgApprover;
    }
}
