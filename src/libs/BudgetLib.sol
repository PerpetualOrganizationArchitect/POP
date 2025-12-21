// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title BudgetLib
 * @notice Library for budget management operations
 * @dev Reduces bytecode by extracting common budget logic into reusable functions
 */
library BudgetLib {
    /* ─────────── Errors ─────────── */
    error BudgetExceeded();
    error SpentUnderflow();
    error CapBelowCommitted();

    /* ─────────── Data Types ─────────── */
    struct Budget {
        uint128 cap; // 16 bytes
        uint128 spent; // 16 bytes (total 32 bytes)
    }

    /* ─────────── Core Functions ─────────── */

    /**
     * @notice Add spent amount to budget with cap checking
     * @param budget The budget struct to modify
     * @param delta Amount to add to spent
     * @param cap The budget cap (0 means unlimited)
     */
    function addSpent(Budget storage budget, uint256 delta, uint256 cap) internal {
        uint256 newSpent = budget.spent + delta;
        if (newSpent > type(uint128).max) revert BudgetExceeded();
        if (cap != 0 && newSpent > cap) revert BudgetExceeded();
        budget.spent = uint128(newSpent);
    }

    /**
     * @notice Add spent amount to budget using budget's own cap
     * @param budget The budget struct to modify
     * @param delta Amount to add to spent
     */
    function addSpent(Budget storage budget, uint256 delta) internal {
        addSpent(budget, delta, budget.cap);
    }

    /**
     * @notice Subtract spent amount from budget with underflow protection
     * @param budget The budget struct to modify
     * @param delta Amount to subtract from spent
     */
    function subtractSpent(Budget storage budget, uint256 delta) internal {
        if (budget.spent < delta) revert SpentUnderflow();
        unchecked {
            budget.spent -= uint128(delta);
        }
    }

    /**
     * @notice Update budget spent amount (can increase or decrease)
     * @param budget The budget struct to modify
     * @param oldAmount Previous amount to rollback
     * @param newAmount New amount to apply
     * @param cap The budget cap (0 means unlimited)
     */
    function updateSpent(Budget storage budget, uint256 oldAmount, uint256 newAmount, uint256 cap) internal {
        // Rollback old amount
        if (oldAmount > 0) {
            subtractSpent(budget, oldAmount);
        }

        // Apply new amount
        if (newAmount > 0) {
            addSpent(budget, newAmount, cap);
        }
    }

    /**
     * @notice Update budget spent amount using budget's own cap
     * @param budget The budget struct to modify
     * @param oldAmount Previous amount to rollback
     * @param newAmount New amount to apply
     */
    function updateSpent(Budget storage budget, uint256 oldAmount, uint256 newAmount) internal {
        updateSpent(budget, oldAmount, newAmount, budget.cap);
    }

    /**
     * @notice Check if an amount can be added without exceeding cap
     * @param budget The budget struct to check
     * @param delta Amount to potentially add
     * @return bool True if the addition would not exceed cap
     */
    function canAddSpent(Budget storage budget, uint256 delta) internal view returns (bool) {
        if (budget.cap == 0) return true; // Unlimited
        return budget.spent + delta <= budget.cap;
    }

    /**
     * @notice Get remaining budget capacity
     * @param budget The budget struct to check
     * @return uint256 Remaining capacity (returns max uint256 if unlimited)
     */
    function remainingCapacity(Budget storage budget) internal view returns (uint256) {
        if (budget.cap == 0) return type(uint256).max; // Unlimited
        if (budget.spent >= budget.cap) return 0;
        return budget.cap - budget.spent;
    }

    /**
     * @notice Check if a new cap is valid (not below current spent)
     * @param budget The budget struct to check
     * @param newCap The proposed new cap
     * @return bool True if the new cap is valid
     */
    function isValidCap(Budget storage budget, uint256 newCap) internal view returns (bool) {
        return newCap == 0 || newCap >= budget.spent;
    }

    /**
     * @notice Set budget cap with validation
     * @param budget The budget struct to modify
     * @param newCap The new cap to set
     */
    function setCap(Budget storage budget, uint256 newCap) internal {
        if (!isValidCap(budget, newCap)) revert CapBelowCommitted();
        budget.cap = uint128(newCap);
    }
}
