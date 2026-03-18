// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @title PaymasterPostOpLib
/// @author POA Engineering
/// @notice PostOp accounting helpers for PaymasterHub budget and solidarity adjustments
/// @dev All functions are internal pure (inlined at compile time) for zero gas overhead
library PaymasterPostOpLib {
    /// @notice Replace a budget reservation with the actual gas cost
    /// @dev Used in postOp to swap the maxCost reservation made during validation
    ///      with the actual (lower) gas cost: usedInEpoch - reserved + actual
    /// @param usedInEpoch Current used amount in the epoch (includes reservation)
    /// @param reserved Amount reserved during validation (maxCost)
    /// @param actual Actual gas cost from EntryPoint (actual <= reserved)
    /// @return Updated usedInEpoch value
    function adjustBudget(uint128 usedInEpoch, uint256 reserved, uint256 actual) internal pure returns (uint128) {
        return usedInEpoch - uint128(reserved) + uint128(actual);
    }

    /// @notice Deduct from solidarity balance, clamped to prevent underflow
    /// @dev Used in sponsorship fallback paths where the function must never revert.
    ///      Returns min(balance, cost) as the deduction amount.
    /// @param balance Current solidarity fund balance
    /// @param cost Amount to deduct
    /// @return newBalance Updated solidarity balance after deduction
    /// @return deducted Actual amount deducted (may be less than cost if balance is insufficient)
    function clampedDeduction(uint128 balance, uint256 cost)
        internal
        pure
        returns (uint128 newBalance, uint128 deducted)
    {
        deducted = balance < uint128(cost) ? balance : uint128(cost);
        newBalance = balance - deducted;
    }
}
