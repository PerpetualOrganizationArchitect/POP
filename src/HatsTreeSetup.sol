// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {IEligibilityModule, IToggleModule} from "./interfaces/IHatsModules.sol";

import {OrgRegistry} from "./OrgRegistry.sol";
import {UniversalAccountRegistry} from "./UniversalAccountRegistry.sol";
import {RoleConfigStructs} from "./libs/RoleConfigStructs.sol";

/**
 * @title HatsTreeSetup
 * @notice Temporary contract for setting up Hats Protocol trees
 * @dev This contract is deployed temporarily to handle all Hats operations and reduce Deployer size
 */
contract HatsTreeSetup {
    /*════════════════  SETUP STRUCTS  ════════════════*/

    struct SetupResult {
        uint256 topHatId;
        uint256[] roleHatIds;
        address eligibilityModule;
        address toggleModule;
    }

    struct SetupParams {
        IHats hats;
        OrgRegistry orgRegistry;
        bytes32 orgId;
        address eligibilityModule;
        address toggleModule;
        address deployer;
        address deployerAddress; // Address to receive ADMIN hat
        address executor;
        address accountRegistry; // UniversalAccountRegistry for username registration
        string orgName;
        string deployerUsername; // Optional username for deployer (empty string = skip registration)
        RoleConfigStructs.RoleConfig[] roles; // Complete role configuration
    }

    /**
     * @notice Sets up a complete Hats tree for an organization with custom hierarchy
     * @dev This function handles arbitrary tree structures, not just linear hierarchies
     * @dev Deployer must transfer superAdmin rights to this contract before calling
     * @param params Complete setup parameters including role configurations
     * @return result Setup result containing topHat, roleHatIds, and module addresses
     */
    function setupHatsTree(SetupParams memory params) external returns (SetupResult memory result) {
        result.eligibilityModule = params.eligibilityModule;
        result.toggleModule = params.toggleModule;

        // Configure module relationships
        IEligibilityModule(params.eligibilityModule).setToggleModule(params.toggleModule);
        IToggleModule(params.toggleModule).setEligibilityModule(params.eligibilityModule);

        // Create top hat - mint to this contract so it can create child hats
        result.topHatId = params.hats.mintTopHat(address(this), string(abi.encodePacked("ipfs://", params.orgName)), "");
        IEligibilityModule(params.eligibilityModule).setWearerEligibility(address(this), result.topHatId, true, true);
        IToggleModule(params.toggleModule).setHatStatus(result.topHatId, true);

        // Create eligibility admin hat - this hat can mint any role
        uint256 eligibilityAdminHatId = params.hats
            .createHat(
                result.topHatId,
                "ELIGIBILITY_ADMIN",
                1,
                params.eligibilityModule,
                params.toggleModule,
                true,
                "ELIGIBILITY_ADMIN"
            );
        IEligibilityModule(params.eligibilityModule)
            .setWearerEligibility(params.eligibilityModule, eligibilityAdminHatId, true, true);
        IToggleModule(params.toggleModule).setHatStatus(eligibilityAdminHatId, true);
        params.hats.mintHat(eligibilityAdminHatId, params.eligibilityModule);
        IEligibilityModule(params.eligibilityModule).setEligibilityModuleAdminHat(eligibilityAdminHatId);
        // Register hat creation for subgraph indexing
        IEligibilityModule(params.eligibilityModule)
            .registerHatCreation(eligibilityAdminHatId, result.topHatId, true, true);

        // Create role hats sequentially to properly handle hierarchies
        uint256 len = params.roles.length;
        result.roleHatIds = new uint256[](len);

        // Multi-pass: resolve dependencies and create hats in correct order
        bool[] memory created = new bool[](len);
        uint256 createdCount = 0;

        while (createdCount < len) {
            uint256 passCreatedCount = 0;

            for (uint256 i = 0; i < len; i++) {
                if (created[i]) continue;

                RoleConfigStructs.RoleConfig memory role = params.roles[i];

                // Determine admin hat ID
                uint256 adminHatId;
                bool canCreate = false;

                if (role.hierarchy.adminRoleIndex == type(uint256).max) {
                    adminHatId = eligibilityAdminHatId;
                    canCreate = true;
                } else if (created[role.hierarchy.adminRoleIndex]) {
                    adminHatId = result.roleHatIds[role.hierarchy.adminRoleIndex];
                    canCreate = true;
                }

                if (canCreate) {
                    // Create hat with configuration
                    uint32 maxSupply = role.hatConfig.maxSupply == 0 ? type(uint32).max : role.hatConfig.maxSupply;
                    uint256 newHatId = params.hats
                        .createHat(
                            adminHatId,
                            role.name,
                            maxSupply,
                            params.eligibilityModule,
                            params.toggleModule,
                            role.hatConfig.mutableHat,
                            role.image
                        );
                    result.roleHatIds[i] = newHatId;

                    // Register hat creation for subgraph indexing
                    IEligibilityModule(params.eligibilityModule)
                        .registerHatCreation(newHatId, adminHatId, role.defaults.eligible, role.defaults.standing);

                    created[i] = true;
                    createdCount++;
                    passCreatedCount++;
                }
            }

            // Circular dependency check
            if (passCreatedCount == 0 && createdCount < len) {
                revert("Circular dependency in role hierarchy");
            }
        }

        // Step 5: Set eligibility and toggle status for all hats
        for (uint256 i = 0; i < len; i++) {
            uint256 hatId = result.roleHatIds[i];
            RoleConfigStructs.RoleConfig memory role = params.roles[i];

            IEligibilityModule(params.eligibilityModule).setWearerEligibility(params.executor, hatId, true, true);
            IEligibilityModule(params.eligibilityModule).setWearerEligibility(params.deployerAddress, hatId, true, true);
            IToggleModule(params.toggleModule).setHatStatus(hatId, true);
            IEligibilityModule(params.eligibilityModule)
                .setDefaultEligibility(hatId, role.defaults.eligible, role.defaults.standing);

            // Set eligibility for additional wearers
            for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {
                IEligibilityModule(params.eligibilityModule)
                    .setWearerEligibility(role.distribution.additionalWearers[j], hatId, true, true);
            }
        }

        // Step 6: Collect all minting operations for batch execution
        uint256 mintCount = 0;
        for (uint256 i = 0; i < len; i++) {
            RoleConfigStructs.RoleConfig memory role = params.roles[i];
            if (!role.canVote) continue;

            if (role.distribution.mintToDeployer) mintCount++;
            if (role.distribution.mintToExecutor) mintCount++;
            mintCount += role.distribution.additionalWearers.length;
        }

        if (mintCount > 0) {
            uint256[] memory hatIdsToMint = new uint256[](mintCount);
            address[] memory wearersToMint = new address[](mintCount);
            uint256 mintIndex = 0;

            // Register deployer username once if needed
            if (params.accountRegistry != address(0) && bytes(params.deployerUsername).length > 0) {
                UniversalAccountRegistry registry = UniversalAccountRegistry(params.accountRegistry);
                if (bytes(registry.getUsername(params.deployerAddress)).length == 0) {
                    registry.registerAccountQuickJoin(params.deployerUsername, params.deployerAddress);
                }
            }

            for (uint256 i = 0; i < len; i++) {
                RoleConfigStructs.RoleConfig memory role = params.roles[i];
                if (!role.canVote) continue;

                uint256 hatId = result.roleHatIds[i];

                if (role.distribution.mintToDeployer) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = params.deployerAddress;
                    mintIndex++;
                }

                if (role.distribution.mintToExecutor) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = params.executor;
                    mintIndex++;
                }

                for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = role.distribution.additionalWearers[j];
                    mintIndex++;
                }
            }

            // Step 7: Batch mint all hats via EligibilityModule
            for (uint256 i = 0; i < mintCount; i++) {
                IEligibilityModule(params.eligibilityModule).mintHatToAddress(hatIdsToMint[i], wearersToMint[i]);
            }
        }

        // Transfer top hat to executor
        params.hats.transferHat(result.topHatId, address(this), params.executor);

        // Set default eligibility for top hat
        IEligibilityModule(params.eligibilityModule).setDefaultEligibility(result.topHatId, true, true);

        // Transfer module admin rights to executor
        IEligibilityModule(params.eligibilityModule).transferSuperAdmin(params.executor);
        IToggleModule(params.toggleModule).transferAdmin(params.executor);

        return result;
    }
}
