// SPDX-License-Identifier: AGPL-3.0-only
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
     * @notice Emitted when a user changes their opt-out status
     * @param user The address toggling their distribution participation
     * @param optedOut True if the user is opting out, false if opting back in
     */
    event OptOutToggled(address indexed user, bool optedOut);

    /**
     * @notice Emitted when the revenue share token is changed
     * @param token The new revenue share token address
     */
    event RevenueShareTokenSet(address indexed token);

    /**
     * @notice Emitted when a new merkle-based distribution is created
     * @param distributionId The unique ID of the distribution
     * @param token The token being distributed (address(0) for ETH)
     * @param amount The total amount to distribute
     * @param checkpointBlock The block number used for balance snapshot
     * @param merkleRoot The merkle root for claim verification
     */
    event DistributionCreated(
        uint256 indexed distributionId,
        address indexed token,
        uint256 amount,
        uint256 checkpointBlock,
        bytes32 merkleRoot
    );

    /**
     * @notice Emitted when a user claims from a distribution
     * @param distributionId The distribution being claimed from
     * @param claimer The address claiming
     * @param amount The amount claimed
     */
    event DistributionClaimed(uint256 indexed distributionId, address indexed claimer, uint256 amount);

    /**
     * @notice Emitted when a distribution is finalized
     * @param distributionId The distribution being finalized
     * @param unclaimedAmount The amount returned to owner
     */
    event DistributionFinalized(uint256 indexed distributionId, uint256 unclaimedAmount);

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
     * @notice Thrown when the contract lacks sufficient funds for an operation
     * @dev Ensures contract has enough balance before attempting transfers
     */
    error InsufficientFunds();

    /**
     * @notice Thrown when a transfer operation fails
     * @dev Indicates ETH transfer failure during distribution or withdrawal
     */
    error TransferFailed();

    /**
     * @notice Thrown when merkle root is invalid (zero)
     * @dev Ensures valid merkle tree for distribution
     */
    error InvalidMerkleRoot();

    /**
     * @notice Thrown when checkpoint block is invalid
     * @dev Checkpoint must be in the past
     */
    error InvalidCheckpoint();

    /**
     * @notice Thrown when distribution is not found
     * @dev Distribution ID does not exist
     */
    error DistributionNotFound();

    /**
     * @notice Thrown when trying to claim from finalized distribution
     * @dev Distribution has been closed
     */
    error DistributionAlreadyFinalized();

    /**
     * @notice Thrown when user already claimed from distribution
     * @dev Prevents double claiming
     */
    error AlreadyClaimed();

    /**
     * @notice Thrown when opted-out user tries to claim
     * @dev User must opt back in to claim
     */
    error OptedOut();

    /**
     * @notice Thrown when merkle proof is invalid
     * @dev Proof does not verify against merkle root
     */
    error InvalidProof();

    /**
     * @notice Thrown when distribution is already finalized
     * @dev Cannot finalize twice
     */
    error AlreadyFinalized();

    /**
     * @notice Thrown when claim period has not expired
     * @dev Must wait minimum period before finalizing
     */
    error ClaimPeriodNotExpired();

    /**
     * @notice Thrown when array lengths don't match
     * @dev For batch operations
     */
    error ArrayLengthMismatch();

    /*──────────────────────────────────────────────────────────────────────────
                                    PAYMENT FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────────*/

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
     * @notice Creates a new merkle-based distribution
     * @dev Only callable by owner (Executor). Checkpoint must be in the past.
     * @param payoutToken The token to distribute (address(0) for ETH)
     * @param amount The total amount to distribute
     * @param merkleRoot The merkle root of the distribution tree
     * @param checkpointBlock The block number for balance snapshot
     * @return distributionId The ID of the created distribution
     */
    function createDistribution(address payoutToken, uint256 amount, bytes32 merkleRoot, uint256 checkpointBlock)
        external
        returns (uint256 distributionId);

    /**
     * @notice Claims a distribution for the caller
     * @dev Verifies merkle proof and transfers funds
     * @param distributionId The distribution to claim from
     * @param claimAmount The amount being claimed
     * @param merkleProof The merkle proof for verification
     */
    function claimDistribution(uint256 distributionId, uint256 claimAmount, bytes32[] calldata merkleProof) external;

    /**
     * @notice Claims multiple distributions in a single transaction
     * @dev Gas optimization for users with multiple pending claims
     * @param distributionIds Array of distribution IDs to claim from
     * @param amounts Array of amounts to claim
     * @param proofs Array of merkle proofs
     */
    function claimMultiple(uint256[] calldata distributionIds, uint256[] calldata amounts, bytes32[][] calldata proofs)
        external;

    /**
     * @notice Finalizes a distribution and returns unclaimed funds
     * @dev Only callable by owner after minimum claim period
     * @param distributionId The distribution to finalize
     * @param minClaimPeriodBlocks Minimum blocks that must pass since checkpoint
     */
    function finalizeDistribution(uint256 distributionId, uint256 minClaimPeriodBlocks) external;

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
     * @notice Set the token used to determine revenue share distribution
     * @dev Only callable by owner, must be a valid ERC-20 token
     * @param revenueShareToken The new revenue share token address
     */
    function setRevenueShareToken(address revenueShareToken) external;

    /*──────────────────────────────────────────────────────────────────────────
                                    VIEW FUNCTIONS
    ──────────────────────────────────────────────────────────────────────────*/

    /**
     * @notice Get the current revenue share token address
     * @return The address of the token used for distribution weights
     */
    function revenueShareToken() external view returns (address);

    /**
     * @notice Get distribution details
     * @param distributionId The distribution ID
     * @return payoutToken The token being distributed
     * @return totalAmount The total distribution amount
     * @return checkpointBlock The checkpoint block number
     * @return merkleRoot The merkle root
     * @return totalClaimed The amount claimed so far
     * @return finalized Whether distribution is finalized
     */
    function getDistribution(uint256 distributionId)
        external
        view
        returns (
            address payoutToken,
            uint256 totalAmount,
            uint256 checkpointBlock,
            bytes32 merkleRoot,
            uint256 totalClaimed,
            bool finalized
        );

    /**
     * @notice Check if an address has claimed from a distribution
     * @param distributionId The distribution ID
     * @param account The address to check
     * @return True if the address has claimed
     */
    function hasClaimed(uint256 distributionId, address account) external view returns (bool);

    /**
     * @notice Get the total number of distributions created
     * @return The distribution counter
     */
    function distributionCounter() external view returns (uint256);
}
