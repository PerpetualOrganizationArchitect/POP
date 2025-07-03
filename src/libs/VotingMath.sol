// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VotingMath
 * @notice Pure library for voting calculations and math utilities
 * @dev All functions are pure/view and can be safely extracted to reduce contract size
 */
library VotingMath {
    /* ─────────── Errors ─────────── */
    error InvalidQuorum();
    error InvalidSplit();
    error InvalidMinBalance();
    error MinBalanceNotMet(uint256 required);
    error RoleNotAllowed();
    error DuplicateIndex();
    error InvalidIndex();
    error InvalidWeight();
    error WeightSumNot100(uint256 sum);
    error Overflow();
    error TargetSelf();
    error TargetNotAllowed();

    /* ─────────── Constants ─────────── */
    uint256 private constant MAX_UINT256 = type(uint256).max;

    /* ─────────── Validation Functions ─────────── */

    /**
     * @notice Validate quorum percentage
     * @param quorum Quorum percentage (1-100)
     */
    function validateQuorum(uint8 quorum) internal pure {
        if (quorum == 0 || quorum > 100) revert InvalidQuorum();
    }

    /**
     * @notice Validate split percentage
     * @param split Split percentage (0-100)
     */
    function validateSplit(uint8 split) internal pure {
        if (split > 100) revert InvalidSplit();
    }

    /**
     * @notice Validate minimum balance
     * @param minBalance Minimum balance required
     */
    function validateMinBalance(uint256 minBalance) internal pure {
        if (minBalance == 0) revert InvalidMinBalance();
    }

    /**
     * @notice Check if balance meets minimum requirement
     * @param balance Current balance
     * @param minBalance Minimum required balance
     */
    function checkMinBalance(uint256 balance, uint256 minBalance) internal pure {
        if (balance < minBalance) revert MinBalanceNotMet(minBalance);
    }

    /* ─────────── Math Functions ─────────── */

    /* ─────────── Square Root ─────────── */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        assembly {
            /* ---------- bit-scan seed ---------- */
            let z := shl(7, 1) // 128
            for {} lt(z, x) { z := shl(2, z) } {} // climb in powers of 4
            z := shr(1, z) // 2^⌈log2(x)/2⌉

            /* ---------- 4 Newton steps ---------- */
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))

            /* ---------- final min(z, x/z) ---------- */
            let w := div(x, z)
            y := z
            if gt(z, w) { y := w }
        }
    }

    /**
     * @notice Calculate voting power based on balance and quadratic setting
     * @param balance Token balance
     * @param quadratic Whether to use quadratic voting
     * @return power The calculated voting power
     */
    function calculateVotingPower(uint256 balance, bool quadratic) internal pure returns (uint256 power) {
        if (balance == 0) return 0;
        return quadratic ? sqrt(balance) : balance;
    }

    /**
     * @notice Calculate scaled voting power for an option
     * @param rawVotes Raw votes for the option
     * @param totalRaw Total raw votes
     * @param slicePercentage Percentage slice for this voting type
     * @return scaled The scaled voting power
     */
    function calculateScaledPower(uint256 rawVotes, uint256 totalRaw, uint256 slicePercentage)
        internal
        pure
        returns (uint256 scaled)
    {
        if (totalRaw == 0) return 0;
        return (rawVotes * slicePercentage) / totalRaw;
    }

    /**
     * @notice Calculate total scaled power from DD and PT components
     * @param scaledDD Scaled direct democracy power
     * @param scaledPT Scaled participation token power
     * @return total The total scaled power
     */
    function calculateTotalScaledPower(uint256 scaledDD, uint256 scaledPT) internal pure returns (uint256 total) {
        return scaledDD + scaledPT;
    }

    /**
     * @notice Check if a proposal meets quorum requirements
     * @param highestVote Highest vote count
     * @param secondHighest Second highest vote count
     * @param totalWeight Total voting weight
     * @param quorumPercentage Required quorum percentage
     * @return valid Whether the proposal meets quorum
     */
    function meetsQuorum(uint256 highestVote, uint256 secondHighest, uint256 totalWeight, uint8 quorumPercentage)
        internal
        pure
        returns (bool valid)
    {
        return (highestVote * 100 >= totalWeight * quorumPercentage) && (highestVote > secondHighest);
    }

    /**
     * @notice Calculate raw voting power for a voter
     * @param hasDemocracyHat Whether voter has democracy hat
     * @param tokenBalance Token balance
     * @param minBalance Minimum required balance
     * @param quadratic Whether to use quadratic voting
     * @return ddRaw Direct democracy raw power
     * @return ptRaw Participation token raw power
     */
    function calculateRawPowers(bool hasDemocracyHat, uint256 tokenBalance, uint256 minBalance, bool quadratic)
        internal
        pure
        returns (uint256 ddRaw, uint256 ptRaw)
    {
        // Direct democracy power (only if has democracy hat)
        ddRaw = hasDemocracyHat ? 100 : 0;

        // Participation token power
        if (tokenBalance < minBalance) {
            ptRaw = 0;
        } else {
            uint256 power = calculateVotingPower(tokenBalance, quadratic);
            ptRaw = power * 100; // raw numerator
        }
    }

    /**
     * @notice Calculate slice percentages for DD and PT voting
     * @param ddSharePct Direct democracy share percentage
     * @return sliceDD DD slice percentage
     * @return slicePT PT slice percentage
     */
    function calculateSlicePercentages(uint8 ddSharePct) internal pure returns (uint256 sliceDD, uint256 slicePT) {
        sliceDD = ddSharePct;
        slicePT = 100 - ddSharePct;
    }

    /**
     * @notice Validate weight distribution
     * @param weights Array of weights
     * @param indices Array of indices
     * @param numOptions Number of options
     * @return sum Total weight sum
     */
    function validateWeights(uint8[] calldata weights, uint8[] calldata indices, uint256 numOptions)
        internal
        pure
        returns (uint256 sum)
    {
        uint256 seen;
        sum = 0;

        for (uint256 i; i < weights.length;) {
            uint8 ix = indices[i];
            if (ix >= numOptions) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;
            if (weights[i] > 100) revert InvalidWeight();
            sum += weights[i];
            unchecked {
                ++i;
            }
        }

        if (sum != 100) revert WeightSumNot100(sum);
    }

    /**
     * @notice Check for overflow in uint128
     * @param value Value to check
     */
    function checkOverflow(uint256 value) internal pure {
        if (value > type(uint128).max) revert Overflow();
    }
}
