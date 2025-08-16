// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title VoteCalc
 * @notice Unified voting calculation library for all governor types
 * @dev Pure library for voting math operations used across DirectDemocracy, Participation, and Hybrid voting
 */
library VoteCalc {
    /* ─────────── Errors ─────────── */
    error LengthMismatch();
    error InvalidIndex();
    error InvalidWeight();
    error DuplicateIndex();
    error WeightSumNot100(uint256 sum);
    error Overflow();

    /* ─────────── Structs ─────────── */
    struct Weights {
        uint8[] idxs;
        uint8[] weights;
        uint256 optionsLen;
    }

    /* ─────────── Weight Validation ─────────── */
    
    /**
     * @notice Validates weight distribution across options
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

    /* ─────────── Power Derivation ─────────── */
    
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
        
        // Square root implementation using Babylonian method
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
    function powersHybrid(
        bool hasDemocracyHat,
        uint256 bal,
        uint256 minBal,
        bool quadratic
    ) internal pure returns (uint256 ddRaw, uint256 ptRaw) {
        if (hasDemocracyHat) ddRaw = 100; // one unit per eligible voter
        
        uint256 p = powerPT(bal, minBal, quadratic);
        if (p > 0) ptRaw = p * 100; // match existing scaling
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
        internal pure returns (uint256[] memory adds)
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
        internal pure returns (uint256[] memory ddAdds, uint256[] memory ptAdds)
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

    /* ─────────── Winner & Quorum ─────────── */
    
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
        bool meetsQuorum = (hi * 100 > totalWeight * quorumPct);
        bool meetsMargin = requireStrictMajority ? (hi > second) : (hi >= second);
        
        ok = meetsQuorum && meetsMargin;
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
        uint256 sliceDD = ddSharePct;         // out of 100
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

    /* ─────────── Math Utilities ─────────── */
    
    /**
     * @notice Calculate square root using optimized assembly
     * @param x Input value
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        
        assembly {
            // Bit-scan seed
            let z := shl(7, 1) // 128
            for {} lt(z, x) { z := shl(2, z) } {} // climb in powers of 4
            z := shr(1, z) // 2^⌈log2(x)/2⌉
            
            // 4 Newton steps
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            z := shr(1, add(z, div(x, z)))
            
            // Final min(z, x/z)
            let w := div(x, z)
            y := z
            if gt(z, w) { y := w }
        }
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