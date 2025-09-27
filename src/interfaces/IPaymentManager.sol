// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IPaymentManager
 * @notice Interface for the PaymentManager contract that accepts payments and distributes revenue
 * @dev Part of the Perpetual Organization Architect (POA) ecosystem
 */
interface IPaymentManager {
    /*──────────────────────────────────────────────────────────────────────────
                                    EVENTS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Emitted when a payment is received by the contract
     * @param payer The address that sent the payment
     * @param amount The amount of the payment in the smallest unit
     * @param token The token address (address(0) for native ETH)
     */
    event PaymentReceived(address indexed payer, uint256 amount, address indexed token);

    /**
     * @notice Emitted when revenue is distributed to eligible holders
     * @param token The token being distributed (address(0) for native ETH)
     * @param amount The total amount distributed in the smallest unit
     * @param processed The number of holders that received distributions
     */
    event RevenueDistributed(address indexed token, uint256 amount, uint256 processed);

    /**
     * @notice Emitted when a user changes their opt-out status
     * @param user The address toggling their distribution participation
     * @param optedOut True if the user is opting out, false if opting back in
     */
    event OptOutToggled(address indexed user, bool optedOut);

    /**
     * @notice Emitted when the eligibility token is changed
     * @param token The new eligibility token address
     */
    event EligibilityTokenSet(address indexed token);

    /*──────────────────────────────────────────────────────────────────────────
                                    ERRORS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Thrown when attempting to process a zero amount
     * @dev Prevents wasted gas on operations with no value
     */
    error ZeroAmount();

    /**
     * @notice Thrown when a zero address is provided where not allowed
     * @dev Prevents setting critical addresses to the zero address
     */
    error ZeroAddress();

    /**
     * @notice Thrown when distribution parameters are invalid
     * @dev Ensures distribution has valid amount and recipient list
     */
    error InvalidDistributionParams();

    /**
     * @notice Thrown when no eligible holders exist for distribution
     * @dev Prevents distribution when all holders are opted out or have zero balance
     */
    error NoEligibleHolders();

    /**
     * @notice Thrown when the contract lacks sufficient funds for an operation
     * @dev Ensures contract has enough balance before attempting transfers
     */
    error InsufficientFunds();

    /**
     * @notice Thrown when a transfer operation fails
     * @dev Indicates ETH transfer failure during distribution or withdrawal
     */
    error TransferFailed();

    /*──────────────────────────────────────────────────────────────────────────
                                    PAYMENT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Alternative function to receive ETH payments
     * @dev Emits PaymentReceived event with sender and amount
     */
    function pay() external payable;

    /**
     * @notice Receive ERC-20 token payments
     * @dev Requires prior approval from the sender
     * @param token The ERC-20 token contract address
     * @param amount The amount to receive in the token's smallest unit
     */
    function payERC20(address token, uint256 amount) external;

    /*──────────────────────────────────────────────────────────────────────────
                                    DISTRIBUTION FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Distribute revenue to eligible token holders
     * @dev Only callable by owner, uses totalSupply for weight calculation
     * @param payoutToken The token to distribute (address(0) for ETH)
     * @param amount The total amount to distribute
     * @param holders Array of addresses to consider for distribution
     */
    function distributeRevenue(address payoutToken, uint256 amount, address[] calldata holders) external;

    /*──────────────────────────────────────────────────────────────────────────
                                    OPT-OUT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Toggle opt-out status for revenue distributions
     * @dev Allows users to exclude themselves from future distributions
     * @param optOut True to opt out of distributions, false to opt back in
     */
    function optOut(bool optOut) external;

    /**
     * @notice Check if an address has opted out of distributions
     * @param account The address to check
     * @return True if the address has opted out, false otherwise
     */
    function isOptedOut(address account) external view returns (bool);

    /*──────────────────────────────────────────────────────────────────────────
                                    ADMIN FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Set the token used to determine distribution eligibility
     * @dev Only callable by owner, must be a valid ERC-20 token
     * @param eligibilityToken The new eligibility token address
     */
    function setEligibilityToken(address eligibilityToken) external;

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Get the current eligibility token address
     * @return The address of the token used for distribution weights
     */
    function eligibilityToken() external view returns (address);

    /**
     * @notice Get the total amount distributed for a specific token
     * @param token The token address to query (address(0) for ETH)
     * @return The cumulative amount distributed
     */
    function getDistributedTotal(address token) external view returns (uint256);
}

