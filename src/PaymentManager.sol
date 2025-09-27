// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPaymentManager} from "./interfaces/IPaymentManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PaymentManager
 * @notice Accepts payments in ETH or ERC-20 tokens and distributes revenue to eligibility token holders
 * @dev Implements IPaymentManager interface, part of the Perpetual Organization Architect (POA) ecosystem
 */
contract PaymentManager is IPaymentManager, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*──────────────────────────────────────────────────────────────────────────
                                    CONSTANTS
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice Precision factor for distribution calculations (1e18)
    uint256 private constant PRECISION = 1e18;

    /*──────────────────────────────────────────────────────────────────────────
                                    STATE VARIABLES
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice The ERC-20 token used to determine distribution weights
    address public eligibilityToken;

    /// @notice Tracks which addresses have opted out of distributions
    mapping(address => bool) private _optedOut;

    /// @notice Tracks total amount distributed per token
    mapping(address => uint256) private _distributedTotal;

    /*──────────────────────────────────────────────────────────────────────────
                                    CONSTRUCTOR
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Initializes the PaymentManager
     * @param _owner The address that will own the contract (typically the Executor)
     * @param _eligibilityToken The initial eligibility token address
     */
    constructor(address _owner, address _eligibilityToken) Ownable(_owner) {
        if (_eligibilityToken == address(0)) revert ZeroAddress();
        eligibilityToken = _eligibilityToken;
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

        // Get total weight from eligibility token
        uint256 totalWeight = IERC20(eligibilityToken).totalSupply();
        if (totalWeight == 0) revert NoEligibleHolders();

        uint256 scaledAmount = amount * PRECISION;
        uint256 processed = 0;
        uint256 totalDistributed = 0;

        // Single pass distribution
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];

            // Skip if opted out
            if (_optedOut[holder]) continue;

            // Get holder's balance
            uint256 balance = IERC20(eligibilityToken).balanceOf(holder);
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

        _distributedTotal[payoutToken] += totalDistributed;
        emit RevenueDistributed(payoutToken, totalDistributed, processed);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    OPT-OUT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function optOut(bool _optOut) external override {
        _optedOut[msg.sender] = _optOut;
        emit OptOutToggled(msg.sender, _optOut);
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function isOptedOut(address account) external view override returns (bool) {
        return _optedOut[account];
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    ADMIN FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function setEligibilityToken(address _eligibilityToken) external override onlyOwner {
        if (_eligibilityToken == address(0)) revert ZeroAddress();
        eligibilityToken = _eligibilityToken;
        emit EligibilityTokenSet(_eligibilityToken);
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function withdraw(address token, uint256 amount) external override onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function withdrawETH(uint256 amount) external override onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientFunds();

        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @inheritdoc IPaymentManager
     */
    function getDistributedTotal(address token) external view override returns (uint256) {
        return _distributedTotal[token];
    }
}

