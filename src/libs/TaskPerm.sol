// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @dev Bit-mask helpers for granular task permissions.
 * Flags may be OR-combined (e.g. CREATE | ASSIGN).
 */
library TaskPerm {
    uint8 internal constant CREATE = 1 << 0;
    uint8 internal constant CLAIM = 1 << 1;
    uint8 internal constant REVIEW = 1 << 2;
    uint8 internal constant ASSIGN = 1 << 3;

    function has(uint8 mask, uint8 flag) internal pure returns (bool) {
        return mask & flag != 0;
    }
}
