// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPaymentManager} from "./interfaces/IPaymentManager.sol";
import {ISnapshotToken} from "./interfaces/ISnapshotToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

// Extended interface for tokens with snapshotWithHolders function
interface ISnapshotTokenExtended is ISnapshotToken {
    function snapshotWithHolders(address[] calldata holders) external returns (uint256);
}

/**
 * @title PaymentManagerWithSnapshot
 * @notice Payment manager that uses the token's built-in snapshot functionality
 * @dev Requires the revenue share token to implement ISnapshotToken
 */
contract PaymentManagerWithSnapshot is IPaymentManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*──────────────────────────────────────────────────────────────────────────
                                    CONSTANTS
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice Precision factor for distribution calculations (1e18)
    uint256 private constant PRECISION = 1e18;

    /*──────────────────────────────────────────────────────────────────────────
                                    ERC-7201 STORAGE
    ──────────────────────────────────────────────────────────────────────────*/

    /// @custom:storage-location erc7201:poa.paymentmanagerwithsnapshot.storage
    struct Layout {
        /// @notice The ERC-20 token with snapshot support
        ISnapshotToken revenueShareToken;
        /// @notice Tracks which addresses have opted out of distributions
        mapping(address => bool) optedOut;
    }

    // keccak256("poa.paymentmanagerwithsnapshot.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x5e5fec24aa4dc4e5aee2e025e51e1392c72a2500577559fae9665c6d52bd6a33;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    EVENTS
    ──────────────────────────────────────────────────────────────────────────*/

    event RevenueDistributedWithSnapshot(address indexed payoutToken, uint256 amount, uint256 snapshotId);

    /*──────────────────────────────────────────────────────────────────────────
                                    INITIALIZER
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Initializes the PaymentManagerWithSnapshot
     * @param _owner The address that will own the contract (typically the Executor)
     * @param _revenueShareToken The snapshot-enabled revenue share token address
     */
    function initialize(address _owner, address _revenueShareToken) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        if (_revenueShareToken == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Layout storage s = _layout();
        s.revenueShareToken = ISnapshotToken(_revenueShareToken);
        emit RevenueShareTokenSet(_revenueShareToken);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    SNAPSHOT DISTRIBUTION
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Creates a snapshot on the token with holders
     * @param holders Array of token holders to snapshot
     * @return snapshotId The ID of the created snapshot
     * @dev Only callable by owner (executor)
     */
    function createSnapshot(address[] calldata holders) external onlyOwner returns (uint256 snapshotId) {
        Layout storage s = _layout();
        // Try to call snapshotWithHolders if available
        try ISnapshotTokenExtended(address(s.revenueShareToken)).snapshotWithHolders(holders) returns (uint256 id) {
            snapshotId = id;
        } catch {
            // Fallback to regular snapshot
            snapshotId = s.revenueShareToken.snapshot();
        }
    }

    /**
     * @notice Distributes revenue using a snapshot from the token
     * @param payoutToken The token to distribute (address(0) for ETH)
     * @param amount The total amount to distribute
     * @param snapshotId The snapshot ID to use for distribution
     * @param holders Array of potential token holders to check
     */
    function distributeRevenueWithSnapshot(
        address payoutToken,
        uint256 amount,
        uint256 snapshotId,
        address[] calldata holders
    ) external onlyOwner nonReentrant {
        if (amount == 0 || holders.length == 0) revert InvalidDistributionParams();

        Layout storage s = _layout();
        
        // Get total supply at snapshot
        uint256 totalSupply = s.revenueShareToken.totalSupplyAt(snapshotId);
        if (totalSupply == 0) revert NoEligibleHolders();

        // Check contract has sufficient balance
        if (payoutToken == address(0)) {
            if (address(this).balance < amount) revert InsufficientFunds();
        } else {
            if (IERC20(payoutToken).balanceOf(address(this)) < amount) revert InsufficientFunds();
        }

        uint256 scaledAmount = amount * PRECISION;
        uint256 totalDistributed = 0;
        uint256 totalHoldersBalance = 0;
        bool hasDistributed = false;

        // Distribute based on snapshot balances
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            
            // Get balance at snapshot
            uint256 balance = s.revenueShareToken.balanceOfAt(holder, snapshotId);
            totalHoldersBalance += balance;
            
            // Skip if opted out or no balance
            if (s.optedOut[holder] || balance == 0) continue;
            
            // Calculate share based on snapshot
            uint256 scaledShare = (scaledAmount * balance) / totalSupply;
            uint256 share = scaledShare / PRECISION;
            
            if (share > 0) {
                // Transfer share
                if (payoutToken == address(0)) {
                    (bool success,) = holder.call{value: share}("");
                    if (!success) revert TransferFailed();
                } else {
                    IERC20(payoutToken).safeTransfer(holder, share);
                }
                
                totalDistributed += share;
                hasDistributed = true;
            }
        }

        // Verify all token holders were included
        if (totalHoldersBalance != totalSupply) revert IncompleteHoldersList();

        if (!hasDistributed) revert NoEligibleHolders();

        emit RevenueDistributedWithSnapshot(payoutToken, totalDistributed, snapshotId);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    LEGACY DISTRIBUTION
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     * @notice Legacy function - creates snapshot and distributes immediately
     */
    function distributeRevenue(address payoutToken, uint256 amount, address[] calldata holders)
        external
        override
        onlyOwner
        nonReentrant
    {
        // Create a snapshot
        uint256 snapshotId = _layout().revenueShareToken.snapshot();
        
        // Distribute using the snapshot
        this.distributeRevenueWithSnapshot(payoutToken, amount, snapshotId, holders);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    PAYMENT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Receive ETH payments
     */
    receive() external payable {
        if (msg.value == 0) revert ZeroAmount();
        emit PaymentReceived(msg.sender, msg.value, address(0));
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function pay() external payable override {
        if (msg.value == 0) revert ZeroAmount();
        emit PaymentReceived(msg.sender, msg.value, address(0));
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function payERC20(address token, uint256 amount) external override nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit PaymentReceived(msg.sender, amount, token);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    OPT-OUT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function optOut(bool _optOut) external override {
        Layout storage s = _layout();
        s.optedOut[msg.sender] = _optOut;
        emit OptOutToggled(msg.sender, _optOut);
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function isOptedOut(address account) external view override returns (bool) {
        Layout storage s = _layout();
        return s.optedOut[account];
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    ADMIN FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function setRevenueShareToken(address _revenueShareToken) external override onlyOwner {
        if (_revenueShareToken == address(0)) revert ZeroAddress();
        Layout storage s = _layout();
        s.revenueShareToken = ISnapshotToken(_revenueShareToken);
        emit RevenueShareTokenSet(_revenueShareToken);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function revenueShareToken() external view override returns (address) {
        Layout storage s = _layout();
        return address(s.revenueShareToken);
    }

    /**
     * @notice Gets the current snapshot ID from the token
     * @return The current snapshot ID
     */
    function getCurrentSnapshotId() external view returns (uint256) {
        return _layout().revenueShareToken.currentSnapshotId();
    }
}