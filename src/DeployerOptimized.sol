// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Example of optimized helper to reduce code duplication
library RoleResolver {
    /**
     * @notice Resolves role indices to hat IDs
     * @dev Single function to replace 7 duplicate loops
     * @param orgRegistry The org registry contract
     * @param orgId Organization identifier
     * @param roleIndices Array of role indices to resolve
     * @return hatIds Array of corresponding hat IDs
     */
    function resolveRoleHats(address orgRegistry, bytes32 orgId, uint256[] memory roleIndices)
        internal
        view
        returns (uint256[] memory hatIds)
    {
        hatIds = new uint256[](roleIndices.length);
        for (uint256 i = 0; i < roleIndices.length; i++) {
            // Could add validation here:
            // require(roleIndices[i] < maxRoles, "Invalid role index");
            hatIds[i] = IOrgRegistry(orgRegistry).getRoleHat(orgId, roleIndices[i]);
        }
    }
}

// Interface for OrgRegistry
interface IOrgRegistry {
    function getRoleHat(bytes32 orgId, uint256 roleIndex) external view returns (uint256);
}

/**
 * Example usage in Deployer:
 *
 * Instead of:
 *   uint256[] memory memberHats = new uint256[](params.roleAssignments.quickJoinRoles.length);
 *   for (uint256 i = 0; i < params.roleAssignments.quickJoinRoles.length; i++) {
 *       memberHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.quickJoinRoles[i]);
 *   }
 *
 * Use:
 *   uint256[] memory memberHats = RoleResolver.resolveRoleHats(
 *       address(l.orgRegistry),
 *       params.orgId,
 *       params.roleAssignments.quickJoinRoles
 *   );
 *
 * This reduces bytecode by ~500 bytes per usage (7 usages = ~3.5KB saved)
 */
