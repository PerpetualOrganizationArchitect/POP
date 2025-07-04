// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ValidationLib
 * @notice Library for common validation operations
 * @dev Reduces bytecode by extracting validation logic into reusable functions
 */
library ValidationLib {
    /* ─────────── Errors ─────────── */
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error CapBelowCommitted();

    /* ─────────── Constants ─────────── */
    uint256 internal constant MAX_PAYOUT = 1e24; // 1 000 000 tokens (18 dec)
    uint96 internal constant MAX_PAYOUT_96 = 1e24; // same as above, but as uint96

    /* ─────────── Core Functions ─────────── */

    /**
     * @notice Validate that an address is not zero
     * @param addr The address to validate
     */
    function requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Validate that a string/bytes is not empty
     * @param data The bytes data to validate
     */
    function requireNonEmptyBytes(bytes calldata data) internal pure {
        if (data.length == 0) revert InvalidString();
    }

    /**
     * @notice Validate payout amount (non-zero and within limits)
     * @param payout The payout amount to validate
     */
    function requireValidPayout(uint256 payout) internal pure {
        if (payout == 0 || payout > MAX_PAYOUT) revert InvalidPayout();
    }

    /**
     * @notice Validate payout amount for uint96 (non-zero and within limits)
     * @param payout The payout amount to validate
     */
    function requireValidPayout96(uint256 payout) internal pure {
        if (payout == 0 || payout > MAX_PAYOUT_96) revert InvalidPayout();
    }

    /**
     * @notice Validate bounty payout (can be zero, but if non-zero must be within limits)
     * @param payout The bounty payout amount to validate
     */
    function requireValidBountyPayout(uint256 payout) internal pure {
        if (payout > MAX_PAYOUT_96) revert InvalidPayout();
    }

    /**
     * @notice Validate bounty token and payout combination
     * @param bountyToken The bounty token address
     * @param bountyPayout The bounty payout amount
     */
    function requireValidBountyConfig(address bountyToken, uint256 bountyPayout) internal pure {
        // If bounty payout > 0, token must not be zero address
        if (bountyPayout > 0 && bountyToken == address(0)) revert ZeroAddress();

        // If token is set, payout must be > 0
        if (bountyToken != address(0) && bountyPayout == 0) revert InvalidPayout();

        // Validate bounty payout amount
        requireValidBountyPayout(bountyPayout);
    }

    /**
     * @notice Validate that a new cap is not below committed amount
     * @param newCap The new cap to validate
     * @param committed The currently committed/spent amount
     */
    function requireValidCap(uint256 newCap, uint256 committed) internal pure {
        if (newCap != 0 && newCap < committed) revert CapBelowCommitted();
    }

    /**
     * @notice Validate cap amount (within max limits)
     * @param cap The cap amount to validate
     */
    function requireValidCapAmount(uint256 cap) internal pure {
        if (cap > MAX_PAYOUT) revert InvalidPayout();
    }

    /**
     * @notice Validate task creation parameters
     * @param payout The task payout
     * @param metadata The task metadata
     * @param bountyToken The bounty token address
     * @param bountyPayout The bounty payout amount
     */
    function requireValidTaskParams(uint256 payout, bytes calldata metadata, address bountyToken, uint256 bountyPayout)
        internal
        pure
    {
        requireValidPayout96(payout);
        requireNonEmptyBytes(metadata);
        requireValidBountyConfig(bountyToken, bountyPayout);
    }

    /**
     * @notice Validate project creation parameters
     * @param metadata The project metadata
     * @param cap The project cap
     */
    function requireValidProjectParams(bytes calldata metadata, uint256 cap) internal pure {
        requireNonEmptyBytes(metadata);
        requireValidCapAmount(cap);
    }

    /**
     * @notice Validate that an application hash is not empty
     * @param applicationHash The application hash to validate
     */
    function requireValidApplicationHash(bytes32 applicationHash) internal pure {
        if (applicationHash == bytes32(0)) revert InvalidString();
    }
}
