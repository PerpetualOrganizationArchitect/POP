    // SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* OpenZeppelin v5.3 Upgradeables */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

interface IExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function execute(uint256 proposalId, Call[] calldata batch) external;
}

/**
 * @title Executor
 * @notice Batch‑executor behind an UpgradeableBeacon.
 *         Exactly **one** governor address is authorised to trigger `execute`.
 */
contract Executor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IExecutor {
    /* ─────────── Errors ─────────── */
    error UnauthorizedCaller();
    error CallFailed(uint256 index, bytes lowLevelData);
    error EmptyBatch();
    error TooManyCalls();
    error TargetSelf();
    error ZeroAddress();

    /* ─────────── Constants ─────────── */
    uint8 public constant MAX_CALLS_PER_BATCH = 20;

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.executor.storage
    struct Layout {
        address allowedCaller; // sole authorised governor
    }

    // keccak256("poa.executor.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x4a2328a3c3b056def98e04ebb0cc7ccc084886f7998dd0a6d16fd24be55ffa5d;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────────── Events ─────────── */
    event CallerSet(address indexed caller);
    event BatchExecuted(uint256 indexed proposalId, uint256 calls);
    event CallExecuted(uint256 indexed proposalId, uint256 indexed index, address target, uint256 value);
    event Swept(address indexed to, uint256 amount);

    /* ─────────── Initialiser ─────────── */
    function initialize(address owner_) external initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        __Ownable_init(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /* ─────────── Governor management ─────────── */
    function setCaller(address newCaller) external {
        if (newCaller == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        if (l.allowedCaller != address(0)) {
            // After first set, only current caller can change
            if (msg.sender != l.allowedCaller) revert UnauthorizedCaller();
        }
        l.allowedCaller = newCaller;
        emit CallerSet(newCaller);
    }

    /* ─────────── Batch execution ─────────── */
    function execute(uint256 proposalId, Call[] calldata batch) external override whenNotPaused nonReentrant {
        if (msg.sender != _layout().allowedCaller) revert UnauthorizedCaller();
        uint256 len = batch.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_CALLS_PER_BATCH) revert TooManyCalls();

        for (uint256 i; i < len;) {
            if (batch[i].target == address(this)) revert TargetSelf();

            (bool ok, bytes memory ret) = batch[i].target.call{value: batch[i].value}(batch[i].data);
            if (!ok) revert CallFailed(i, ret);

            emit CallExecuted(proposalId, i, batch[i].target, batch[i].value);
            unchecked {
                ++i;
            }
        }
        emit BatchExecuted(proposalId, len);
    }

    /* ─────────── Guardian helpers ─────────── */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ─────────── ETH recovery ─────────── */
    function sweep(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = address(this).balance;
        to.transfer(bal);
        emit Swept(to, bal);
    }

    /* ─────────── View Helpers ─────────── */
    function allowedCaller() external view returns (address) {
        return _layout().allowedCaller;
    }

    /* accept ETH for payable calls within a batch */
    receive() external payable {}

    /* ───────────── Version ───────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
