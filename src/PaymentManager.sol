// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPaymentManager} from "./interfaces/IPaymentManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title PaymentManager
 * @notice Accepts payments in ETH or ERC-20 tokens and distributes revenue to revenue share token holders
 * @dev Implements IPaymentManager interface with ERC-7201 storage pattern, part of the Perpetual Organization Architect (POA) ecosystem
 */
contract PaymentManager is IPaymentManager, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    /*──────────────────────────────────────────────────────────────────────────
                                    CONSTANTS
    ──────────────────────────────────────────────────────────────────────────*/

    /*──────────────────────────────────────────────────────────────────────────
                                    ERC-7201 STORAGE
    ──────────────────────────────────────────────────────────────────────────*/

    /// @notice Merkle-based distribution data
    struct Distribution {
        address payoutToken;        // Token to distribute (address(0) = ETH)
        uint256 totalAmount;        // Total amount to distribute
        uint256 checkpointBlock;    // Block number for balance snapshot
        bytes32 merkleRoot;         // Root of merkle tree with (address, amount) pairs
        uint256 totalClaimed;       // Running total of claims
        bool finalized;             // Whether distribution is closed
        mapping(address => bool) claimed;  // Track who has claimed
    }

    /// @custom:storage-location erc7201:poa.paymentmanager.storage
    struct Layout {
        /// @notice The ERC-20 token used to determine distribution weights
        address revenueShareToken;
        /// @notice Tracks which addresses have opted out of distributions
        mapping(address => bool) optedOut;
        /// @notice Merkle-based distributions
        mapping(uint256 => Distribution) distributions;
        /// @notice Distribution counter
        uint256 distributionCounter;
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
     * @param _revenueShareToken The initial revenue share token address
     */
    function initialize(address _owner, address _revenueShareToken) external initializer {
        if (_owner == address(0)) revert ZeroAddress();
        if (_revenueShareToken == address(0)) revert ZeroAddress();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        Layout storage s = _layout();
        s.revenueShareToken = _revenueShareToken;
        emit RevenueShareTokenSet(_revenueShareToken);
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
     * @notice Creates a new merkle-based distribution
     * @dev Only callable by owner (Executor). Checkpoint must be in the past.
     */
    function createDistribution(
        address payoutToken,
        uint256 amount,
        bytes32 merkleRoot,
        uint256 checkpointBlock
    ) external override onlyOwner nonReentrant returns (uint256 distributionId) {
        if (amount == 0) revert ZeroAmount();
        if (merkleRoot == bytes32(0)) revert InvalidMerkleRoot();
        if (checkpointBlock >= block.number) revert InvalidCheckpoint();

        // Check contract has sufficient balance
        if (payoutToken == address(0)) {
            if (address(this).balance < amount) revert InsufficientFunds();
        } else {
            if (IERC20(payoutToken).balanceOf(address(this)) < amount) revert InsufficientFunds();
        }

        Layout storage s = _layout();
        distributionId = ++s.distributionCounter;
        Distribution storage dist = s.distributions[distributionId];

        dist.payoutToken = payoutToken;
        dist.totalAmount = amount;
        dist.checkpointBlock = checkpointBlock;
        dist.merkleRoot = merkleRoot;
        dist.finalized = false;

        emit DistributionCreated(distributionId, payoutToken, amount, checkpointBlock, merkleRoot);
    }

    /**
     * @inheritdoc IPaymentManager
     * @notice Claims a distribution for the caller
     * @dev Verifies merkle proof and transfers funds
     */
    function claimDistribution(
        uint256 distributionId,
        uint256 claimAmount,
        bytes32[] calldata merkleProof
    ) external override nonReentrant {
        Layout storage s = _layout();
        Distribution storage dist = s.distributions[distributionId];

        if (dist.totalAmount == 0) revert DistributionNotFound();
        if (dist.finalized) revert DistributionAlreadyFinalized();
        if (dist.claimed[msg.sender]) revert AlreadyClaimed();
        if (s.optedOut[msg.sender]) revert OptedOut();

        // Verify merkle proof
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, claimAmount))));
        if (!MerkleProof.verify(merkleProof, dist.merkleRoot, leaf)) {
            revert InvalidProof();
        }

        // Mark as claimed
        dist.claimed[msg.sender] = true;
        dist.totalClaimed += claimAmount;

        // Transfer funds
        if (dist.payoutToken == address(0)) {
            (bool success,) = msg.sender.call{value: claimAmount}("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(dist.payoutToken).safeTransfer(msg.sender, claimAmount);
        }

        emit DistributionClaimed(distributionId, msg.sender, claimAmount);
    }

    /**
     * @inheritdoc IPaymentManager
     * @notice Claims multiple distributions in a single transaction
     * @dev Gas optimization for users with multiple pending claims
     */
    function claimMultiple(
        uint256[] calldata distributionIds,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    ) external override nonReentrant {
        if (distributionIds.length != amounts.length || distributionIds.length != proofs.length) {
            revert ArrayLengthMismatch();
        }

        Layout storage s = _layout();

        for (uint256 i = 0; i < distributionIds.length; i++) {
            uint256 distributionId = distributionIds[i];
            uint256 claimAmount = amounts[i];
            bytes32[] calldata merkleProof = proofs[i];

            Distribution storage dist = s.distributions[distributionId];

            if (dist.totalAmount == 0) revert DistributionNotFound();
            if (dist.finalized) revert DistributionAlreadyFinalized();
            if (dist.claimed[msg.sender]) revert AlreadyClaimed();
            if (s.optedOut[msg.sender]) revert OptedOut();

            // Verify merkle proof
            bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, claimAmount))));
            if (!MerkleProof.verify(merkleProof, dist.merkleRoot, leaf)) {
                revert InvalidProof();
            }

            // Mark as claimed
            dist.claimed[msg.sender] = true;
            dist.totalClaimed += claimAmount;

            // Transfer funds
            if (dist.payoutToken == address(0)) {
                (bool success,) = msg.sender.call{value: claimAmount}("");
                if (!success) revert TransferFailed();
            } else {
                IERC20(dist.payoutToken).safeTransfer(msg.sender, claimAmount);
            }

            emit DistributionClaimed(distributionId, msg.sender, claimAmount);
        }
    }

    /**
     * @inheritdoc IPaymentManager
     * @notice Finalizes a distribution and returns unclaimed funds
     * @dev Only callable by owner after minimum claim period
     */
    function finalizeDistribution(uint256 distributionId, uint256 minClaimPeriodBlocks)
        external
        override
        onlyOwner
    {
        Layout storage s = _layout();
        Distribution storage dist = s.distributions[distributionId];

        if (dist.totalAmount == 0) revert DistributionNotFound();
        if (dist.finalized) revert AlreadyFinalized();
        if (block.number < dist.checkpointBlock + minClaimPeriodBlocks) {
            revert ClaimPeriodNotExpired();
        }

        dist.finalized = true;
        uint256 unclaimed = dist.totalAmount - dist.totalClaimed;

        // Return unclaimed funds to owner (executor)
        if (unclaimed > 0) {
            if (dist.payoutToken == address(0)) {
                (bool success,) = owner().call{value: unclaimed}("");
                if (!success) revert TransferFailed();
            } else {
                IERC20(dist.payoutToken).safeTransfer(owner(), unclaimed);
            }
        }

        emit DistributionFinalized(distributionId, unclaimed);
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
        s.revenueShareToken = _revenueShareToken;
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
        return s.revenueShareToken;
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function getDistribution(uint256 distributionId)
        external
        view
        override
        returns (
            address payoutToken,
            uint256 totalAmount,
            uint256 checkpointBlock,
            bytes32 merkleRoot,
            uint256 totalClaimed,
            bool finalized
        )
    {
        Layout storage s = _layout();
        Distribution storage dist = s.distributions[distributionId];
        return (
            dist.payoutToken,
            dist.totalAmount,
            dist.checkpointBlock,
            dist.merkleRoot,
            dist.totalClaimed,
            dist.finalized
        );
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function hasClaimed(uint256 distributionId, address account) external view override returns (bool) {
        Layout storage s = _layout();
        return s.distributions[distributionId].claimed[account];
    }

    /**
     * @inheritdoc IPaymentManager
     */
    function distributionCounter() external view override returns (uint256) {
        Layout storage s = _layout();
        return s.distributionCounter;
    }
}
