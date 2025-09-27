// SPDX-License-Identifier: MIT
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
    function resolveRoleHats(
        OrgRegistry orgRegistry,
        bytes32 orgId,
        uint256[] memory roleIndices
    ) internal view returns (uint256[] memory hatIds) {
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
    function validateRoleIndices(
        uint256[] memory roleIndices,
        uint256 maxRoles
    ) internal pure returns (bool valid) {
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
}