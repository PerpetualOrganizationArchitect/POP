// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {SwitchableBeacon} from "../SwitchableBeacon.sol";
import "../OrgRegistry.sol";
import {ModuleDeploymentLib} from "../libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../libs/ModuleTypes.sol";
import {RoleResolver} from "../libs/RoleResolver.sol";
import {IPoaManager} from "../libs/ModuleDeploymentLib.sol";
/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();

/**
 * @title AccessFactory
 * @notice Factory contract for deploying access control and token infrastructure
 * @dev Deploys BeaconProxy instances for QuickJoin and ParticipationToken
 */
contract AccessFactory {
    /*──────────────────── Role Assignments ────────────────────*/
    struct RoleAssignments {
        uint256[] quickJoinRoles;
        uint256[] tokenMemberRoles;
        uint256[] tokenApproverRoles;
    }

    /*──────────────────── Access Deployment Params ────────────────────*/
    struct AccessParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address executor;
        address deployer; // OrgDeployer address for registration callbacks
        address registryAddr; // Universal account registry
        uint256[] roleHatIds;
        bool autoUpgrade;
        RoleAssignments roleAssignments;
    }

    /*──────────────────── Access Deployment Result ────────────────────*/
    struct AccessResult {
        address quickJoin;
        address participationToken;
    }

    /*══════════════  MAIN DEPLOYMENT FUNCTION  ═════════════=*/

    /**
     * @notice Deploys complete access control infrastructure for an organization
     * @param params Access deployment parameters
     * @return result Addresses of deployed access components
     */
    function deployAccess(AccessParams memory params) external returns (AccessResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.executor == address(0)
        ) {
            revert InvalidAddress();
        }

        /* 1. Deploy QuickJoin */
        {
            // Get the role hat IDs for new members
            uint256[] memory memberHats =
                RoleResolver.resolveRoleHats(OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.quickJoinRoles);

            address beacon = _createBeacon(
                ModuleTypes.QUICK_JOIN_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
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

            result.quickJoin = ModuleDeploymentLib.deployQuickJoin(
                config, params.executor, params.registryAddr, address(this), memberHats, beacon
            );
        }

        /* 2. Deploy Participation Token */
        {
            string memory tName = string(abi.encodePacked(params.orgName, " Token"));
            string memory tSymbol = "PT";

            // Get the role hat IDs for member and approver permissions
            uint256[] memory memberHats = RoleResolver.resolveRoleHats(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.tokenMemberRoles
            );

            uint256[] memory approverHats = RoleResolver.resolveRoleHats(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.tokenApproverRoles
            );

            address beacon = _createBeacon(
                ModuleTypes.PARTICIPATION_TOKEN_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
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

            result.participationToken =
                ModuleDeploymentLib.deployParticipationToken(config, params.executor, tName, tSymbol, memberHats, approverHats, beacon);
        }

        return result;
    }

    /*══════════════  INTERNAL HELPERS  ═════════════=*/

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
