// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*────────────────────────── OpenZeppelin Upgradeables ─────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*──────────────────────────── Interface Stubs ─────────────────────────────*/
interface IMembershipNFT {
    function quickJoinMint(address newUser) external;
}

interface IUniversalAccountRegistry {
    function getUsername(address account) external view returns (string memory);
    function registerAccountQuickJoin(string memory username, address newUser) external;
}

contract QuickJoin is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*────────────────────────────── Errors  ───────────────────────────────*/
    error InvalidAddress();
    error OnlyMasterDeploy();
    error ZeroUser();
    error UsernameTooLong();
    error NoUsername();

    /*──────────────────────────── Constants  ──────────────────────────────*/
    uint256 private constant MAX_USERNAME_LEN = 64;
    bytes4 public constant MODULE_ID = bytes4(keccak256("QuickJoin"));

    /*─────────────────────────── State Storage ────────────────────────────*/
    IMembershipNFT private membershipNFT;
    IUniversalAccountRegistry private accountRegistry;
    address public masterDeployAddress;

    /*────────────────────────────── Events  ───────────────────────────────*/
    event AddressesUpdated(address membership, address registry, address master);
    event QuickJoined(address indexed user, bool usernameCreated);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated);
    event UsernameExists(address indexed user);

    /*──────────────────────────── Initialiser ─────────────────────────────*/
    function initialize(address _owner, address _membershipNFT, address _accountRegistry, address _masterDeploy)
        external
        initializer
    {
        if (
            _owner == address(0) || _membershipNFT == address(0) || _accountRegistry == address(0)
                || _masterDeploy == address(0)
        ) revert InvalidAddress();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        membershipNFT = IMembershipNFT(_membershipNFT);
        accountRegistry = IUniversalAccountRegistry(_accountRegistry);
        masterDeployAddress = _masterDeploy;
    }

    /*─────────────────────────── Modifiers  ──────────────────────────────*/
    modifier onlyMasterDeploy() {
        if (msg.sender != masterDeployAddress) revert OnlyMasterDeploy();
        _;
    }

    /*──────────────────────── Address Management  ─────────────────────────*/
    function updateAddresses(address _membershipNFT, address _accountRegistry, address _masterDeploy)
        external
        onlyOwner
    {
        if (_membershipNFT == address(0) || _accountRegistry == address(0) || _masterDeploy == address(0)) {
            revert InvalidAddress();
        }

        membershipNFT = IMembershipNFT(_membershipNFT);
        accountRegistry = IUniversalAccountRegistry(_accountRegistry);
        masterDeployAddress = _masterDeploy;

        emit AddressesUpdated(_membershipNFT, _accountRegistry, _masterDeploy);
    }

    /*──────────────────────── Internal Join Helper ────────────────────────*/
    function _quickJoin(address user, string memory username) private nonReentrant {
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        bool created;
        if (bytes(accountRegistry.getUsername(user)).length == 0) {
            // require non‑empty username if user not yet registered
            if (bytes(username).length == 0) revert NoUsername();
            accountRegistry.registerAccountQuickJoin(username, user);
            created = true;
        }

        membershipNFT.quickJoinMint(user);
        emit QuickJoined(user, created);
    }

    /*────────────────────── Public Quick‑Join Paths ───────────────────────*/
    function quickJoinNoUser(string calldata userName) external {
        _quickJoin(msg.sender, userName);
    }

    function quickJoinWithUser() external nonReentrant {
        string memory existing = accountRegistry.getUsername(msg.sender);
        if (bytes(existing).length == 0) revert NoUsername();
        membershipNFT.quickJoinMint(msg.sender);
        emit QuickJoined(msg.sender, false);
    }

    /*────────────────────── MasterDeploy Quick‑Join  ──────────────────────*/
    function quickJoinNoUserMasterDeploy(string calldata userName, address newUser)
        external
        onlyMasterDeploy
        nonReentrant
    {
        if (newUser == address(0)) revert ZeroUser();
        if (bytes(userName).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        bool created;
        if (bytes(accountRegistry.getUsername(newUser)).length == 0) {
            accountRegistry.registerAccountQuickJoin(userName, newUser);
            created = true;
        }
        membershipNFT.quickJoinMint(newUser);
        emit QuickJoinedByMaster(msg.sender, newUser, created);
    }

    function quickJoinWithUserMasterDeploy(address newUser) external onlyMasterDeploy nonReentrant {
        if (newUser == address(0)) revert ZeroUser();
        string memory existing = accountRegistry.getUsername(newUser);
        if (bytes(existing).length == 0) revert NoUsername();
        membershipNFT.quickJoinMint(newUser);
        emit QuickJoinedByMaster(msg.sender, newUser, false);
    }

    /*──────────────────────── Version Hook & Gap ──────────────────────────*/
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[46] private __gap;
}
