// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SwitchableBeacon} from "../SwitchableBeacon.sol";
import "../OrgRegistry.sol";
import {ModuleDeploymentLib, IHybridVotingInit} from "../libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../libs/ModuleTypes.sol";
import {RoleResolver} from "../libs/RoleResolver.sol";
import {IPoaManager} from "../libs/ModuleDeploymentLib.sol";

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();

/**
 * @title ModulesFactory
 * @notice Factory contract for deploying functional modules (TaskManager, EducationHub, etc.)
 * @dev Deploys BeaconProxy instances for all module types
 */
contract ModulesFactory {
    /*──────────────────── Role Assignments ────────────────────*/
    struct RoleAssignments {
        uint256[] taskCreatorRoles;
        uint256[] educationCreatorRoles;
        uint256[] educationMemberRoles;
        uint256[] proposalCreatorRoles;
        uint256[] tokenMemberRoles; // For voting classes
    }

    /*──────────────────── Modules Deployment Params ────────────────────*/
    struct ModulesParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address executor;
        address deployer; // OrgDeployer address for registration callbacks
        address participationToken;
        uint256[] roleHatIds;
        bool autoUpgrade;
        uint8 quorumPct;
        IHybridVotingInit.ClassConfig[] votingClasses;
        RoleAssignments roleAssignments;
    }

    /*──────────────────── Modules Deployment Result ────────────────────*/
    struct ModulesResult {
        address taskManager;
        address educationHub;
        address paymentManager;
        address hybridVoting;
    }

    /*══════════════  MAIN DEPLOYMENT FUNCTION  ═════════════=*/

    /**
     * @notice Deploys complete functional module infrastructure for an organization
     * @param params Modules deployment parameters
     * @return result Addresses of deployed module components
     */
    function deployModules(ModulesParams memory params) external returns (ModulesResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.executor == address(0) || params.participationToken == address(0)
        ) {
            revert InvalidAddress();
        }

        /* 1. Deploy TaskManager */
        {
            // Get the role hat IDs for creator permissions
            uint256[] memory creatorHats =
                RoleResolver.resolveRoleHats(OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.taskCreatorRoles);

            address beacon = _createBeacon(
                ModuleTypes.TASK_MANAGER_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0),
                registrar: params.deployer // Callback to OrgDeployer for registration
            });

            result.taskManager = ModuleDeploymentLib.deployTaskManager(
                config, params.executor, params.participationToken, creatorHats, beacon
            );
        }

        /* 2. Deploy EducationHub */
        {
            // Get the role hat IDs for creator and member permissions
            uint256[] memory creatorHats = RoleResolver.resolveRoleHats(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.educationCreatorRoles
            );

            uint256[] memory memberHats = RoleResolver.resolveRoleHats(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.educationMemberRoles
            );

            address beacon = _createBeacon(
                ModuleTypes.EDUCATION_HUB_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0),
                registrar: params.deployer // Callback to OrgDeployer for registration
            });

            result.educationHub = ModuleDeploymentLib.deployEducationHub(
                config, params.executor, params.participationToken, creatorHats, memberHats, false, beacon
            );
        }

        /* 3. Deploy PaymentManager */
        {
            address beacon = _createBeacon(
                ModuleTypes.PAYMENT_MANAGER_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0),
                registrar: params.deployer // Callback to OrgDeployer for registration
            });

            result.paymentManager =
                ModuleDeploymentLib.deployPaymentManager(config, params.executor, params.participationToken, beacon, false);
        }

        /* 4. Deploy HybridVoting */
        {
            // Update token address in voting classes if needed
            IHybridVotingInit.ClassConfig[] memory finalClasses =
                _updateClassesWithTokenAndHats(params.votingClasses, params.participationToken, params.orgRegistry, params.orgId, params.roleAssignments);

            // Get the role hat IDs for proposal creators
            uint256[] memory creatorHats = RoleResolver.resolveRoleHats(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.proposalCreatorRoles
            );

            address beacon = _createBeacon(
                ModuleTypes.HYBRID_VOTING_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0),
                registrar: params.deployer // Callback to OrgDeployer for registration
            });

            result.hybridVoting = ModuleDeploymentLib.deployHybridVoting(
                config, params.executor, creatorHats, params.quorumPct, finalClasses, true, beacon
            );
        }

        return result;
    }

    /*══════════════  INTERNAL HELPERS  ═════════════=*/

    /**
     * @notice Updates voting classes with token addresses and role hat IDs
     * @dev Fills in missing token addresses and resolves role indices to hat IDs
     */
    function _updateClassesWithTokenAndHats(
        IHybridVotingInit.ClassConfig[] memory classes,
        address token,
        address orgRegistry,
        bytes32 orgId,
        RoleAssignments memory roleAssignments
    ) internal view returns (IHybridVotingInit.ClassConfig[] memory) {
        for (uint256 i = 0; i < classes.length; i++) {
            if (classes[i].strategy == IHybridVotingInit.ClassStrategy.ERC20_BAL) {
                if (classes[i].asset == address(0)) {
                    classes[i].asset = token;
                }
                // For token-based voting, use token member roles
                classes[i].hatIds =
                    RoleResolver.resolveRoleHats(OrgRegistry(orgRegistry), orgId, roleAssignments.tokenMemberRoles);
            } else if (classes[i].strategy == IHybridVotingInit.ClassStrategy.DIRECT) {
                // For direct voting, use proposal creator roles
                classes[i].hatIds =
                    RoleResolver.resolveRoleHats(OrgRegistry(orgRegistry), orgId, roleAssignments.proposalCreatorRoles);
            }
        }
        return classes;
    }

    /**
     * @notice Creates a SwitchableBeacon for a module type
     * @dev Returns a beacon address that points to the implementation
     */
    function _createBeacon(bytes32 typeId, address poaManager, address moduleOwner, bool autoUpgrade, address customImpl)
        internal
        returns (address beacon)
    {
        IPoaManager poa = IPoaManager(poaManager);

        address poaBeacon = poa.getBeaconById(typeId);
        if (poaBeacon == address(0)) revert UnsupportedType();

        address initImpl = address(0);
        SwitchableBeacon.Mode beaconMode = SwitchableBeacon.Mode.Mirror;

        if (!autoUpgrade) {
            // For static mode, get the current implementation
            initImpl = (customImpl == address(0)) ? poa.getCurrentImplementationById(typeId) : customImpl;
            if (initImpl == address(0)) revert UnsupportedType();
            beaconMode = SwitchableBeacon.Mode.Static;
        }

        // Create SwitchableBeacon with appropriate configuration
        beacon = address(new SwitchableBeacon(moduleOwner, poaBeacon, initImpl, beaconMode));
    }
}
