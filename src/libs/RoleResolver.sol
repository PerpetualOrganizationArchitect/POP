// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "../OrgRegistry.sol";

/**
 * @title RoleResolver
 * @notice Library to reduce code duplication in Deployer by centralizing role-to-hat resolution
 * @dev Saves approximately 3.5KB of bytecode by deduplicating 7 similar loop patterns
 */
library RoleResolver {
    /**
     * @notice Resolves an array of role indices to their corresponding Hat IDs
     * @param orgRegistry The OrgRegistry contract address
     * @param orgId The organization identifier
     * @param roleIndices Array of role indices (0, 1, 2, etc.)
     * @return hatIds Array of corresponding Hat IDs from the Hats Protocol
     */
    function resolveRoleHats(OrgRegistry orgRegistry, bytes32 orgId, uint256[] memory roleIndices)
        internal
        view
        returns (uint256[] memory hatIds)
    {
        uint256 length = roleIndices.length;
        hatIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            hatIds[i] = orgRegistry.getRoleHat(orgId, roleIndices[i]);
        }
    }

    /**
     * @notice Validates that all role indices are within bounds
     * @param roleIndices Array of role indices to validate
     * @param maxRoles Maximum number of roles in the organization
     * @return valid True if all indices are valid
     */
    function validateRoleIndices(uint256[] memory roleIndices, uint256 maxRoles) internal pure returns (bool valid) {
        uint256 length = roleIndices.length;
        for (uint256 i = 0; i < length; i++) {
            if (roleIndices[i] >= maxRoles) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Ensures array is not empty (for critical roles that must be assigned)
     * @param roleIndices Array to check
     * @return True if array has at least one element
     */
    function requireNonEmpty(uint256[] memory roleIndices) internal pure returns (bool) {
        return roleIndices.length > 0;
    }

    /**
     * @notice Resolves a bitmap of role indices to their corresponding Hat IDs
     * @dev Uses bitmap where bit N represents role index N (supports up to 256 roles)
     * @param orgRegistry The OrgRegistry contract address
     * @param orgId The organization identifier
     * @param rolesBitmap Bitmap where bit N set means role N is assigned
     * @return hatIds Array of corresponding Hat IDs from the Hats Protocol
     */
    function resolveRoleBitmap(OrgRegistry orgRegistry, bytes32 orgId, uint256 rolesBitmap)
        internal
        view
        returns (uint256[] memory hatIds)
    {
        if (rolesBitmap == 0) {
            return new uint256[](0);
        }

        // Count number of set bits (number of roles)
        uint256 count = _countSetBits(rolesBitmap);
        hatIds = new uint256[](count);

        // Extract role indices and resolve to hat IDs
        uint256 index = 0;
        for (uint256 roleIdx = 0; roleIdx < 256; roleIdx++) {
            if ((rolesBitmap & (1 << roleIdx)) != 0) {
                hatIds[index] = orgRegistry.getRoleHat(orgId, roleIdx);
                index++;

                // Early exit when all roles found
                if (index == count) break;
            }
        }
    }

    /**
     * @notice Count number of set bits in bitmap (population count)
     * @dev Uses Brian Kernighan's algorithm for efficiency
     * @param bitmap The bitmap to count
     * @return count Number of set bits
     */
    function _countSetBits(uint256 bitmap) private pure returns (uint256 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1; // Clear lowest set bit
            count++;
        }
    }
}
