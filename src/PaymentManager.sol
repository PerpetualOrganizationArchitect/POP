// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title PaymentManager
 * @notice Accepts payments in ETH or ERC-20 tokens and distributes revenue to eligibility token holders
 * @dev Part of the Perpetual Organization Architect (POA) ecosystem
 */
contract PaymentManager is Ownable, ReentrancyGuard {
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
                                    EVENTS
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice Emitted when a payment is received
    /// @param payer The address that sent the payment
    /// @param amount The amount of the payment
    /// @param token The token address (address(0) for ETH)
    event PaymentReceived(address indexed payer, uint256 amount, address indexed token);

    /// @notice Emitted when revenue is distributed
    /// @param token The token being distributed (address(0) for ETH)
    /// @param amount The total amount distributed
    /// @param processed The number of holders processed
    event RevenueDistributed(address indexed token, uint256 amount, uint256 processed);

    /// @notice Emitted when a user toggles their opt-out status
    /// @param user The address toggling their status
    /// @param optedOut Whether they are opted out
    event OptOutToggled(address indexed user, bool optedOut);

    /// @notice Emitted when the eligibility token is set
    /// @param token The new eligibility token address
    event EligibilityTokenSet(address indexed token);

    /*──────────────────────────────────────────────────────────────────────────
                                    ERRORS
    ──────────────────────────────────────────────────────────────────────────*/

    error ZeroAmount();
    error ZeroAddress();
    error InvalidDistributionParams();
    error NoEligibleHolders();
    error InsufficientFunds();
    error TransferFailed();

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
     * @notice Alternative function to receive ETH payments
     */
    function pay() external payable {
        if (msg.value == 0) revert ZeroAmount();
        emit PaymentReceived(msg.sender, msg.value, address(0));
    }

    /**
     * @notice Receive ERC-20 token payments
     * @param token The ERC-20 token to receive
     * @param amount The amount to receive
     */
    function payERC20(address token, uint256 amount) external nonReentrant {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        emit PaymentReceived(msg.sender, amount, token);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    DISTRIBUTION FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Distribute revenue to eligible token holders
     * @param payoutToken The token to distribute (address(0) for ETH)
     * @param amount The amount to distribute
     * @param holders The list of potential recipients
     */
    function distributeRevenue(
        address payoutToken,
        uint256 amount,
        address[] calldata holders
    ) external onlyOwner nonReentrant {
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
                    (bool success, ) = holder.call{value: share}("");
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
     * @notice Toggle opt-out status for revenue distributions
     * @param _optOut Whether to opt out of distributions
     */
    function optOut(bool _optOut) external {
        _optedOut[msg.sender] = _optOut;
        emit OptOutToggled(msg.sender, _optOut);
    }

    /**
     * @notice Check if an address has opted out
     * @param account The address to check
     * @return Whether the address has opted out
     */
    function isOptedOut(address account) external view returns (bool) {
        return _optedOut[account];
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    ADMIN FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Set the eligibility token
     * @param _eligibilityToken The new eligibility token address
     */
    function setEligibilityToken(address _eligibilityToken) external onlyOwner {
        if (_eligibilityToken == address(0)) revert ZeroAddress();
        eligibilityToken = _eligibilityToken;
        emit EligibilityTokenSet(_eligibilityToken);
    }

    /**
     * @notice Withdraw ERC-20 tokens (admin function)
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Withdraw ETH (admin function)
     * @param amount The amount to withdraw
     */
    function withdrawETH(uint256 amount) external onlyOwner {
        if (amount == 0) revert ZeroAmount();
        if (address(this).balance < amount) revert InsufficientFunds();
        
        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) revert TransferFailed();
    }

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Get total distributed amount for a token
     * @param token The token address (address(0) for ETH)
     * @return The total amount distributed
     */
    function getDistributedTotal(address token) external view returns (uint256) {
        return _distributedTotal[token];
    }
}