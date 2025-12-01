// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* OpenZeppelin v5.3 Upgradeables */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";

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
        IHats hats; // Hats Protocol interface
        mapping(address => bool) authorizedHatMinters; // contracts authorized to request hat minting
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
    event HatsSet(address indexed hats);
    event HatMinterAuthorized(address indexed minter, bool authorized);
    event HatsMinted(address indexed user, uint256[] hatIds);

    /* ─────────── Initialiser ─────────── */
    function initialize(address owner_, address hats_) external initializer {
        if (owner_ == address(0) || hats_ == address(0)) revert ZeroAddress();
        __Ownable_init(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        emit HatsSet(hats_);
    }

    /* ─────────── Governor management ─────────── */
    function setCaller(address newCaller) external {
        if (newCaller == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        if (l.allowedCaller != address(0)) {
            // After first set, only current caller or owner can change
            if (msg.sender != l.allowedCaller && msg.sender != owner()) revert UnauthorizedCaller();
        }
        l.allowedCaller = newCaller;
        emit CallerSet(newCaller);
    }

    /* ─────────── Hat minting management ─────────── */
    function setHatMinterAuthorization(address minter, bool authorized) external {
        if (minter == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        // Only owner or allowed caller can set authorizations
        if (msg.sender != owner() && msg.sender != l.allowedCaller) revert UnauthorizedCaller();
        l.authorizedHatMinters[minter] = authorized;
        emit HatMinterAuthorized(minter, authorized);
    }

    function mintHatsForUser(address user, uint256[] calldata hatIds) external {
        Layout storage l = _layout();
        if (!l.authorizedHatMinters[msg.sender]) revert UnauthorizedCaller();
        if (user == address(0)) revert ZeroAddress();

        // Mint each hat to the user
        for (uint256 i = 0; i < hatIds.length; i++) {
            l.hats.mintHat(hatIds[i], user);
        }

        emit HatsMinted(user, hatIds);
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

    /* ─────────── Module Configuration ─────────── */
    /**
     * @notice Configure vouching on EligibilityModule during initial setup
     * @dev Only callable by owner before renouncing ownership
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatId Hat ID to configure vouching for
     * @param quorum Number of vouches required
     * @param membershipHatId Hat ID whose wearers can vouch
     * @param combineWithHierarchy Whether to combine with parent hat eligibility
     */
    function configureVouching(
        address eligibilityModule,
        uint256 hatId,
        uint32 quorum,
        uint256 membershipHatId,
        bool combineWithHierarchy
    ) external onlyOwner {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature(
                "configureVouching(uint256,uint32,uint256,bool)", hatId, quorum, membershipHatId, combineWithHierarchy
            )
        );
        require(success, "configureVouching failed");
    }

    /**
     * @notice Batch configure vouching for multiple hats during initial setup
     * @dev Only callable by owner before renouncing ownership - gas optimized for org deployment
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatIds Array of hat IDs to configure
     * @param quorums Array of quorum values
     * @param membershipHatIds Array of membership hat IDs
     * @param combineWithHierarchyFlags Array of combine flags
     */
    function batchConfigureVouching(
        address eligibilityModule,
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external onlyOwner {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature(
                "batchConfigureVouching(uint256[],uint32[],uint256[],bool[])",
                hatIds, quorums, membershipHatIds, combineWithHierarchyFlags
            )
        );
        require(success, "batchConfigureVouching failed");
    }

    /**
     * @notice Set default eligibility for a hat during initial setup
     * @dev Only callable by owner before renouncing ownership
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatId Hat ID to set default eligibility for
     * @param eligible Whether wearers are eligible by default
     * @param standing Whether wearers have good standing by default
     */
    function setDefaultEligibility(address eligibilityModule, uint256 hatId, bool eligible, bool standing)
        external
        onlyOwner
    {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature("setDefaultEligibility(uint256,bool,bool)", hatId, eligible, standing)
        );
        require(success, "setDefaultEligibility failed");
    }

    /* ─────────── View Helpers ─────────── */
    function allowedCaller() external view returns (address) {
        return _layout().allowedCaller;
    }

    /* accept ETH for payable calls within a batch */
    receive() external payable {}
}
