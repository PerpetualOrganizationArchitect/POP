// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {SwitchableBeacon} from "../SwitchableBeacon.sol";
import "../OrgRegistry.sol";
import {ModuleDeploymentLib} from "../libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../libs/ModuleTypes.sol";
import {IPoaManager} from "../libs/ModuleDeploymentLib.sol";
import {IEligibilityModule, IToggleModule} from "../interfaces/IHatsModules.sol";

/*──────────────────── HatsTreeSetup interface ────────────────────*/
interface IHatsTreeSetup {
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

    function setupHatsTree(SetupParams memory params) external returns (SetupResult memory);
}

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();

/**
 * @title GovernanceFactory
 * @notice Factory contract for deploying governance infrastructure (Executor, Hats modules)
 * @dev Deploys BeaconProxy instances, NOT implementation contracts
 */
contract GovernanceFactory {
    /*──────────────────── Governance Deployment Params ────────────────────*/
    struct GovernanceParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address hatsTreeSetup;
        address deployer; // OrgDeployer address for registration callbacks
        bool autoUpgrade;
        string[] roleNames;
        string[] roleImages;
        bool[] roleCanVote;
    }

    /*──────────────────── Governance Deployment Result ────────────────────*/
    struct GovernanceResult {
        address executor;
        address eligibilityModule;
        address toggleModule;
        uint256 topHatId;
        uint256[] roleHatIds;
    }

    /*══════════════  MAIN DEPLOYMENT FUNCTION  ═════════════=*/

    /**
     * @notice Deploys complete governance infrastructure for an organization
     * @param params Governance deployment parameters
     * @return result Addresses and IDs of deployed governance components
     */
    function deployGovernance(GovernanceParams memory params) external returns (GovernanceResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.hatsTreeSetup == address(0)
        ) {
            revert InvalidAddress();
        }

        /* 1. Deploy Executor with temporary ownership */
        address execBeacon;
        {
            execBeacon = _createBeacon(
                ModuleTypes.EXECUTOR_ID,
                params.poaManager,
                address(this), // temporary owner
                params.autoUpgrade,
                address(0) // no custom impl
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: address(this),
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0),
                registrar: params.deployer // Callback to OrgDeployer for registration
            });

            result.executor = ModuleDeploymentLib.deployExecutor(config, params.deployer, execBeacon);
        }

        /* 2. Deploy and configure modules for Hats tree */
        result.eligibilityModule = _deployEligibilityModule(
            params.orgId, params.poaManager, params.orgRegistry, params.hats, params.autoUpgrade, params.deployer
        );

        result.toggleModule = _deployToggleModule(
            params.orgId, params.poaManager, params.orgRegistry, params.hats, params.autoUpgrade, params.deployer
        );

        /* 3. Setup Hats Tree */
        {
            // Transfer superAdmin rights to HatsTreeSetup contract
            IEligibilityModule(result.eligibilityModule).transferSuperAdmin(params.hatsTreeSetup);
            IToggleModule(result.toggleModule).transferAdmin(params.hatsTreeSetup);

            // Call HatsTreeSetup to do all the Hats configuration
            IHatsTreeSetup.SetupParams memory setupParams = IHatsTreeSetup.SetupParams({
                hats: IHats(params.hats),
                orgRegistry: OrgRegistry(params.orgRegistry),
                orgId: params.orgId,
                eligibilityModule: result.eligibilityModule,
                toggleModule: result.toggleModule,
                deployer: address(this),
                executor: result.executor,
                orgName: params.orgName,
                roleNames: params.roleNames,
                roleImages: params.roleImages,
                roleCanVote: params.roleCanVote
            });

            IHatsTreeSetup.SetupResult memory setupResult =
                IHatsTreeSetup(params.hatsTreeSetup).setupHatsTree(setupParams);

            result.topHatId = setupResult.topHatId;
            result.roleHatIds = setupResult.roleHatIds;
        }

        /* 4. Transfer executor beacon ownership back to executor itself */
        SwitchableBeacon(execBeacon).transferOwnership(result.executor);

        return result;
    }

    /*══════════════  INTERNAL DEPLOYMENT HELPERS  ═════════════=*/

    /**
     * @notice Deploys EligibilityModule BeaconProxy
     */
    function _deployEligibilityModule(
        bytes32 orgId,
        address poaManager,
        address orgRegistry,
        address hats,
        bool autoUpgrade,
        address deployer
    ) internal returns (address emProxy) {
        address beacon = _createBeacon(
            ModuleTypes.ELIGIBILITY_MODULE_ID, poaManager, address(this), autoUpgrade, address(0)
        );

        ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
            poaManager: IPoaManager(poaManager),
            orgRegistry: OrgRegistry(orgRegistry),
            hats: hats,
            orgId: orgId,
            moduleOwner: address(this),
            autoUpgrade: autoUpgrade,
            customImpl: address(0),
            registrar: deployer // Callback to OrgDeployer for registration
        });

        emProxy = ModuleDeploymentLib.deployEligibilityModule(config, address(this), address(0), beacon);
    }

    /**
     * @notice Deploys ToggleModule BeaconProxy
     */
    function _deployToggleModule(
        bytes32 orgId,
        address poaManager,
        address orgRegistry,
        address hats,
        bool autoUpgrade,
        address deployer
    ) internal returns (address tmProxy) {
        address beacon = _createBeacon(ModuleTypes.TOGGLE_MODULE_ID, poaManager, address(this), autoUpgrade, address(0));

        ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
            poaManager: IPoaManager(poaManager),
            orgRegistry: OrgRegistry(orgRegistry),
            hats: hats,
            orgId: orgId,
            moduleOwner: address(this),
            autoUpgrade: autoUpgrade,
            customImpl: address(0),
            registrar: deployer // Callback to OrgDeployer for registration
        });

        tmProxy = ModuleDeploymentLib.deployToggleModule(config, address(this), beacon);
    }

    /**
     * @notice Creates a SwitchableBeacon for a module type
     * @dev Returns a beacon address that points to the implementation
     */
    function _createBeacon(
        bytes32 typeId,
        address poaManager,
        address moduleOwner,
        bool autoUpgrade,
        address customImpl
    ) internal returns (address beacon) {
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
