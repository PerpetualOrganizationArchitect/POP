// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPaymentManager} from "./interfaces/IPaymentManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title PaymentManager
 * @notice Accepts payments in ETH or ERC-20 tokens and distributes revenue to eligibility token holders
 * @dev Implements IPaymentManager interface with ERC-7201 storage pattern, part of the Perpetual Organization Architect (POA) ecosystem
 */
contract PaymentManager is IPaymentManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*──────────────────────────────────────────────────────────────────────────
                                    CONSTANTS
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice Precision factor for distribution calculations (1e18)
    uint256 private constant PRECISION = 1e18;

    /*──────────────────────────────────────────────────────────────────────────
                                    ERC-7201 STORAGE
    ──────────────────────────────────────────────────────────────────────────*/

    /// @custom:storage-location erc7201:poa.paymentmanager.storage
    struct Layout {
        /// @notice The ERC-20 token used to determine distribution weights
        address eligibilityToken;
        /// @notice Tracks which addresses have opted out of distributions
        mapping(address => bool) optedOut;
    }

    // keccak256("poa.paymentmanager.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x3e5fec24aa4dc4e5aee2e025e51e1392c72a2500577559fae9665c6d52bd6a31;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    INITIALIZER
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Initializes the PaymentManager
     * @param _owner The address that will own the contract (typically the Executor)
     * @param _eligibilityToken The initial eligibility token address
     */
    function initialize(address _owner, address _eligibilityToken) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        if (_eligibilityToken == address(0)) revert ZeroAddress();
        
        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        
        Layout storage s = _layout();
        s.eligibilityToken = _eligibilityToken;
        emit EligibilityTokenSet(_eligibilityToken);
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
                                    DISTRIBUTION FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     * @notice Access restricted to owner only (Executor)
     */
    function distributeRevenue(address payoutToken, uint256 amount, address[] calldata holders)
        external
        override
        onlyOwner
        nonReentrant
    {
        if (amount == 0 || holders.length == 0) revert InvalidDistributionParams();

        // Check contract has sufficient balance
        if (payoutToken == address(0)) {
            if (address(this).balance < amount) revert InsufficientFunds();
        } else {
            if (IERC20(payoutToken).balanceOf(address(this)) < amount) revert InsufficientFunds();
        }

        Layout storage s = _layout();
        
        // Get total weight from eligibility token
        uint256 totalWeight = IERC20(s.eligibilityToken).totalSupply();
        if (totalWeight == 0) revert NoEligibleHolders();

        uint256 scaledAmount = amount * PRECISION;
        uint256 processed = 0;
        uint256 totalDistributed = 0;

        // Single pass distribution
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];

            // Skip if opted out
            if (s.optedOut[holder]) continue;

            // Get holder's balance
            uint256 balance = IERC20(s.eligibilityToken).balanceOf(holder);
            if (balance == 0) continue;

            // Calculate share
            uint256 scaledShare = (scaledAmount * balance) / totalWeight;
            uint256 share = scaledShare / PRECISION;

            if (share > 0) {
                // Transfer share
                if (payoutToken == address(0)) {
                    // Transfer ETH
                    (bool success,) = holder.call{value: share}("");
                    if (!success) revert TransferFailed();
                } else {
                    // Transfer ERC-20
                    IERC20(payoutToken).safeTransfer(holder, share);
                }

                totalDistributed += share;
                processed++;
            }
        }

        if (processed == 0) revert NoEligibleHolders();

        emit RevenueDistributed(payoutToken, totalDistributed, processed);
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
    function setEligibilityToken(address _eligibilityToken) external override onlyOwner {
        if (_eligibilityToken == address(0)) revert ZeroAddress();
        Layout storage s = _layout();
        s.eligibilityToken = _eligibilityToken;
        emit EligibilityTokenSet(_eligibilityToken);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function eligibilityToken() external view override returns (address) {
        Layout storage s = _layout();
        return s.eligibilityToken;
    }
}