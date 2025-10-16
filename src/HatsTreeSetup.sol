// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {IEligibilityModule, IToggleModule} from "./interfaces/IHatsModules.sol";

import {OrgRegistry} from "./OrgRegistry.sol";

/**
 * @title HatsTreeSetup
 * @notice Temporary contract for setting up Hats Protocol trees
 * @dev This contract is deployed temporarily to handle all Hats operations and reduce Deployer size
 */
contract HatsTreeSetup {
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
        address executor;
        string orgName;
        string[] roleNames;
        string[] roleImages;
        bool[] roleCanVote;
    }

    /**
     * @notice Sets up a complete Hats tree for an organization
     * @dev This function does all the heavy lifting that was previously in Deployer
     * @dev Deployer must transfer superAdmin rights to this contract before calling
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

        // Create eligibility admin hat
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

        // Create role hats
        uint256 len = params.roleNames.length;
        result.roleHatIds = new uint256[](len);

        // Create hats in reverse order for proper hierarchy
        for (uint256 i = len; i > 0; i--) {
            uint256 idx = i - 1;
            uint256 adminHatId = (idx == len - 1) ? eligibilityAdminHatId : result.roleHatIds[idx + 1];

            uint256 newHatId = params.hats
                .createHat(
                    adminHatId,
                    params.roleNames[idx],
                    type(uint32).max,
                    params.eligibilityModule,
                    params.toggleModule,
                    true,
                    params.roleNames[idx]
                );
            result.roleHatIds[idx] = newHatId;

            IEligibilityModule(params.eligibilityModule).setWearerEligibility(params.executor, newHatId, true, true);
            IToggleModule(params.toggleModule).setHatStatus(newHatId, true);

            if (params.roleCanVote[idx]) {
                IEligibilityModule(params.eligibilityModule).mintHatToAddress(newHatId, params.executor);
            }
        }

        // Transfer top hat to executor
        params.hats.transferHat(result.topHatId, address(this), params.executor);

        // Set default eligibility
        IEligibilityModule(params.eligibilityModule).setDefaultEligibility(result.topHatId, true, true);
        for (uint256 i = 0; i < result.roleHatIds.length; i++) {
            IEligibilityModule(params.eligibilityModule).setDefaultEligibility(result.roleHatIds[i], true, true);
        }

        // Transfer module admin rights to executor
        IEligibilityModule(params.eligibilityModule).transferSuperAdmin(params.executor);
        IToggleModule(params.toggleModule).transferAdmin(params.executor);

        // Don't register the Hats tree here - let Deployer do it
        // params.orgRegistry.registerHatsTree(params.orgId, result.topHatId, result.roleHatIds);

        return result;
    }
}
