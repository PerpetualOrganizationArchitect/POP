// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title VotingMath
 * @notice Unified library for all voting calculations and math utilities
 * @dev Pure library combining all voting math operations used across DirectDemocracy, Participation, and Hybrid voting
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
    error LengthMismatch();

    /* ─────────── Constants ─────────── */
    uint256 private constant MAX_UINT256 = type(uint256).max;

    /* ─────────── Structs ─────────── */
    struct Weights {
        uint8[] idxs;
        uint8[] weights;
        uint256 optionsLen;
    }

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

    /* ─────────── Weight Validation (New Struct Version) ─────────── */

    /**
     * @notice Validates weight distribution across options (struct version)
     * @param w Weight struct containing indices, weights, and option count
     * @dev Reverts on: length mismatch, invalid index, duplicate index, weight>100, sum!=100
     */
    function validateWeights(Weights memory w) internal pure {
        uint256 len = w.idxs.length;
        if (len == 0 || len != w.weights.length) revert LengthMismatch();

        uint256 seen;
        uint256 sum;

        unchecked {
            for (uint256 i; i < len; ++i) {
                uint256 ix = w.idxs[i];
                if (ix >= w.optionsLen) revert InvalidIndex();

                uint8 wt = w.weights[i];
                if (wt > 100) revert InvalidWeight();

                if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
                seen |= 1 << ix;

                sum += wt;
            }
        }

        if (sum != 100) revert WeightSumNot100(sum);
    }

    /**
     * @notice Validate weight distribution (legacy version for backward compatibility)
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

    /* ─────────── Power Calculation Functions ─────────── */

    /**
     * @notice Calculate voting power based on balance and quadratic setting (legacy)
     * @param balance Token balance
     * @param quadratic Whether to use quadratic voting
     * @return power The calculated voting power
     */
    function calculateVotingPower(uint256 balance, bool quadratic) internal pure returns (uint256 power) {
        if (balance == 0) return 0;
        return quadratic ? sqrt(balance) : balance;
    }

    /**
     * @notice Calculate voting power for participation token holders
     * @param bal Token balance
     * @param minBal Minimum balance required
     * @param quadratic Whether to use quadratic voting
     * @return power The calculated voting power
     */
    function powerPT(uint256 bal, uint256 minBal, bool quadratic) internal pure returns (uint256 power) {
        if (bal < minBal) return 0;
        if (!quadratic) return bal;
        return sqrt(bal);
    }

    /**
     * @notice Calculate voting powers for hybrid voting
     * @param hasDemocracyHat Whether voter has democracy hat
     * @param bal Token balance
     * @param minBal Minimum balance required
     * @param quadratic Whether to use quadratic voting
     * @return ddRaw Direct democracy raw power
     * @return ptRaw Participation token raw power
     */
    function powersHybrid(bool hasDemocracyHat, uint256 bal, uint256 minBal, bool quadratic)
        internal
        pure
        returns (uint256 ddRaw, uint256 ptRaw)
    {
        if (hasDemocracyHat) ddRaw = 100; // one unit per eligible voter

        uint256 p = powerPT(bal, minBal, quadratic);
        if (p > 0) ptRaw = p * 100; // match existing scaling
    }

    /**
     * @notice Calculate raw voting power for a voter (legacy)
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

    /* ─────────── Accumulation Helpers ─────────── */

    /**
     * @notice Calculate vote deltas for participation token voting
     * @param power Voter's voting power
     * @param idxs Option indices
     * @param weights Vote weights per option
     * @return adds Vote increments per option
     */
    function deltasPT(uint256 power, uint8[] memory idxs, uint8[] memory weights)
        internal
        pure
        returns (uint256[] memory adds)
    {
        uint256 len = idxs.length;
        adds = new uint256[](len);

        unchecked {
            for (uint256 i; i < len; ++i) {
                adds[i] = power * uint256(weights[i]);
            }
        }
    }

    /**
     * @notice Calculate vote deltas for hybrid voting
     * @param ddRaw Direct democracy raw power
     * @param ptRaw Participation token raw power
     * @param idxs Option indices
     * @param weights Vote weights per option
     * @return ddAdds DD vote increments per option
     * @return ptAdds PT vote increments per option
     */
    function deltasHybrid(uint256 ddRaw, uint256 ptRaw, uint8[] memory idxs, uint8[] memory weights)
        internal
        pure
        returns (uint256[] memory ddAdds, uint256[] memory ptAdds)
    {
        uint256 len = idxs.length;
        ddAdds = new uint256[](len);
        ptAdds = new uint256[](len);

        unchecked {
            for (uint256 i; i < len; ++i) {
                ddAdds[i] = (ddRaw * weights[i]) / 100;
                ptAdds[i] = (ptRaw * weights[i]) / 100;
            }
        }
    }

    /* ─────────── Winner & Quorum Functions ─────────── */

    /**
     * @notice Check if a proposal meets quorum requirements (legacy)
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
     * @notice Determine winner using majority rules
     * @param optionScores Per-option vote totals
     * @param totalWeight Total voting weight (e.g., sum power or voters*100)
     * @param quorumPct Required quorum percentage (1-100)
     * @param requireStrictMajority Whether winner must strictly exceed second place
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest score
     * @return second Second highest score
     */
    function pickWinnerMajority(
        uint256[] memory optionScores,
        uint256 totalWeight,
        uint8 quorumPct,
        bool requireStrictMajority
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        uint256 len = optionScores.length;

        for (uint256 i; i < len; ++i) {
            uint256 v = optionScores[i];
            if (v > hi) {
                second = hi;
                hi = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
        }

        if (hi == 0) return (win, false, hi, second);

        // Quorum check: hi * 100 > totalWeight * quorumPct
        bool quorumMet = (hi * 100 > totalWeight * quorumPct);
        bool meetsMargin = requireStrictMajority ? (hi > second) : (hi >= second);

        ok = quorumMet && meetsMargin;
    }

    /**
     * @notice Determine winner for hybrid two-slice voting
     * @param ddRaw Per-option direct democracy raw votes
     * @param ptRaw Per-option participation token raw votes
     * @param ddTotalRaw Total DD raw votes
     * @param ptTotalRaw Total PT raw votes
     * @param ddSharePct DD share percentage (e.g., 50 = 50%)
     * @param quorumPct Required quorum percentage (1-100)
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest combined score
     * @return second Second highest combined score
     */
    function pickWinnerTwoSlice(
        uint256[] memory ddRaw,
        uint256[] memory ptRaw,
        uint256 ddTotalRaw,
        uint256 ptTotalRaw,
        uint8 ddSharePct,
        uint8 quorumPct
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        if (ddTotalRaw == 0 && ptTotalRaw == 0) return (0, false, 0, 0);

        uint256 len = ddRaw.length;
        uint256 sliceDD = ddSharePct; // out of 100
        uint256 slicePT = 100 - ddSharePct;

        for (uint256 i; i < len; ++i) {
            uint256 sDD = (ddTotalRaw == 0) ? 0 : (ddRaw[i] * sliceDD) / ddTotalRaw;
            uint256 sPT = (ptTotalRaw == 0) ? 0 : (ptRaw[i] * slicePT) / ptTotalRaw;
            uint256 tot = sDD + sPT; // both scaled to [0..100]

            if (tot > hi) {
                second = hi;
                hi = tot;
                win = i;
            } else if (tot > second) {
                second = tot;
            }
        }

        // Quorum interpreted on the final scaled total (max 100)
        // Requires strict margin for hybrid voting
        ok = (hi > second) && (hi >= quorumPct);
    }

    /**
     * @notice Determine winner for N-class voting
     * @param perOptionPerClassRaw [option][class] raw vote matrix
     * @param totalsRaw [class] total raw votes per class
     * @param slices [class] slice percentages (must sum to 100)
     * @param quorumPct Required quorum percentage (1-100)
     * @param strict Whether to require strict majority (winner > second)
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest combined score
     * @return second Second highest combined score
     */
    function pickWinnerNSlices(
        uint256[][] memory perOptionPerClassRaw,
        uint256[] memory totalsRaw,
        uint8[] memory slices,
        uint8 quorumPct,
        bool strict
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        uint256 numOptions = perOptionPerClassRaw.length;
        if (numOptions == 0) return (0, false, 0, 0);

        uint256 numClasses = slices.length;

        // Calculate combined scores for each option
        for (uint256 opt; opt < numOptions; ++opt) {
            uint256 score;

            for (uint256 cls; cls < numClasses; ++cls) {
                if (totalsRaw[cls] > 0) {
                    // Calculate this class's contribution to the option's score
                    uint256 classContribution = (perOptionPerClassRaw[opt][cls] * slices[cls]) / totalsRaw[cls];
                    score += classContribution;
                }
            }

            // Track winner and second place
            if (score > hi) {
                second = hi;
                hi = score;
                win = opt;
            } else if (score > second) {
                second = score;
            }
        }

        // Check quorum and margin requirements
        bool quorumMet = hi >= quorumPct;
        bool meetsMargin = strict ? (hi > second) : (hi >= second);
        ok = quorumMet && meetsMargin;
    }

    /**
     * @notice Validate class slices sum to 100
     * @param slices Array of slice percentages
     */
    function validateClassSlices(uint8[] memory slices) internal pure {
        if (slices.length == 0) revert InvalidQuorum();
        uint256 sum;
        for (uint256 i; i < slices.length; ++i) {
            if (slices[i] == 0 || slices[i] > 100) revert InvalidSplit();
            sum += slices[i];
        }
        if (sum != 100) revert InvalidSplit();
    }

    /* ─────────── Math Utilities ─────────── */

    /**
     * @notice Calculate square root using optimized assembly
     * @param x Input value
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        if (x <= 3) return 1;

        // Calculate the square root using the Babylonian method
        // with overflow protection
        unchecked {
            y = x;
            uint256 z = (x + 1) / 2;
            while (z < y) {
                y = z;
                z = (x / z + z) / 2;
            }
        }
    }

    /**
     * @notice Check for overflow in uint128
     * @param value Value to check
     */
    function checkOverflow(uint256 value) internal pure {
        if (value > type(uint128).max) revert Overflow();
    }

    /**
     * @notice Check if value fits in uint128
     * @param value Value to check
     * @return Whether value fits in uint128
     */
    function fitsUint128(uint256 value) internal pure returns (bool) {
        return value <= type(uint128).max;
    }

    /**
     * @notice Check if value fits in uint96
     * @param value Value to check
     * @return Whether value fits in uint96
     */
    function fitsUint96(uint256 value) internal pure returns (bool) {
        return value <= type(uint96).max;
    }
}
