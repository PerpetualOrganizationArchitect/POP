// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────────  OpenZeppelin  ───────────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {SwitchableBeacon} from "./SwitchableBeacon.sol";

/*────────────────────────────── Core deps ──────────────────────────────*/
import "./OrgRegistry.sol";
import {ModuleDeploymentLib} from "./libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "./libs/ModuleTypes.sol";

// Import interfaces from library to avoid duplication
import {IPoaManager, IHybridVotingInit} from "./libs/ModuleDeploymentLib.sol";
/*──────────────────── External management contracts ────────────────────*/
// IPoaManager moved to ModuleDeploymentLib to break circular dependency

/*────────────────────── Module‑specific hooks ──────────────────────────*/
interface IEligibilityModule {
    function setToggleModule(address) external;
    function setWearerEligibility(address wearer, uint256 hatId, bool eligible, bool standing) external;
    function setDefaultEligibility(uint256 hatId, bool eligible, bool standing) external;
    function setEligibilityModuleAdminHat(uint256) external;
    function mintHatToAddress(uint256 hatId, address wearer) external;
    function transferSuperAdmin(address) external;
}

interface IToggleModule {
    function setEligibilityModule(address) external;
    function setHatStatus(uint256 hatId, bool active) external;
    function transferAdmin(address) external;
}

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
    function setHatMinterAuthorization(address minter, bool authorized) external;
}

/*── init‑selector helpers (reduce bytecode & safety) ────────────────────*/
// IHybridVotingInit moved to ModuleDeploymentLib to break circular dependency

interface IParticipationVotingInit {
    function initialize(
        address executor_,
        address token_,
        bytes32[] calldata roles,
        address[] calldata targets,
        uint8 quorumPct,
        bool quadratic,
        uint256 minBal
    ) external;
}

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error EmptyInit();
error UnsupportedType();
error BeaconProbeFail();
error OrgExistsMismatch();
error InitFailed();
error ArrayLengthMismatch();
error Reentrant();

/*──────────────── Beacon Interface (selector optimization) ────────────*/
interface IBeaconLike {
    function implementation() external view returns (address);
}

/*───────────────────────────  Deployer  ───────────────────────────────*/
contract Deployer is Initializable {
    using ModuleDeploymentLib for ModuleDeploymentLib.DeployConfig;
    
    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.deployer.storage
    struct Layout {
        /* immutables */
        IPoaManager poaManager;
        OrgRegistry orgRegistry;
        /* manual reentrancy guard */
        uint256 _status;
    }

    IHats public hats;

    // keccak256("poa.deployer.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x4f6cf4b446a382b8bde8d35e8ca59cc30d80d9a326b56d1a5212b27a0198fc7f;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* events */

    /* initializer */
    constructor() initializer {}

    function initialize(address _poaManager, address _orgRegistry, address _hats) public initializer {
        if (_poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0)) {
            revert InvalidAddress();
        }
        Layout storage l = _layout();
        l.poaManager = IPoaManager(_poaManager);
        l.orgRegistry = OrgRegistry(_orgRegistry);
        l._status = 1; // Initialize manual reentrancy guard
        hats = IHats(_hats);
    }

    /*──────────────────── Helper function for creating DeployConfig ───────────────────────*/
    function _getDeployConfig(bytes32 orgId, bool autoUpgrade, address customImpl, address moduleOwner) 
        private 
        view 
        returns (ModuleDeploymentLib.DeployConfig memory) 
    {
        Layout storage l = _layout();
        return ModuleDeploymentLib.DeployConfig({
            poaManager: l.poaManager,
            orgRegistry: l.orgRegistry,
            hats: address(hats),
            orgId: orgId,
            moduleOwner: moduleOwner,
            autoUpgrade: autoUpgrade,
            customImpl: customImpl
        });
    }

    /*══════════════  MODULE‑SPECIFIC DEPLOY HELPERS  ═════════════=*/
    
    /*---------  EligibilityModule  ---------*/
    function _deployEligibilityModule(bytes32 orgId, bool autoUp, address customImpl)
        internal
        returns (address emProxy)
    {
        address beacon = _createBeacon(ModuleTypes.ELIGIBILITY_MODULE_ID, address(this), autoUp, customImpl);
        ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(orgId, autoUp, customImpl, address(this));
        emProxy = ModuleDeploymentLib.deployEligibilityModule(config, address(this), address(0), beacon);
    }

    /*---------  ToggleModule  ---------*/
    function _deployToggleModule(bytes32 orgId, address adminAddr, bool autoUp, address customImpl)
        internal
        returns (address tmProxy)
    {
        address beacon = _createBeacon(ModuleTypes.TOGGLE_MODULE_ID, address(this), autoUp, customImpl);
        ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(orgId, autoUp, customImpl, address(this));
        tmProxy = ModuleDeploymentLib.deployToggleModule(config, adminAddr, beacon);
    }
    
    /*──────────────────── Helper to create SwitchableBeacon ───────────────────────*/
    function _createBeacon(
        bytes32 typeId,
        address moduleOwner,
        bool autoUpgrade,
        address customImpl
    ) private returns (address beacon) {
        Layout storage l = _layout();
        
        address poaBeacon = l.poaManager.getBeaconById(typeId);
        if (poaBeacon == address(0)) revert UnsupportedType();

        address initImpl = address(0);
        SwitchableBeacon.Mode beaconMode = SwitchableBeacon.Mode.Mirror;

        if (!autoUpgrade) {
            // For static mode, get the current implementation
            initImpl = (customImpl == address(0)) ? l.poaManager.getCurrentImplementationById(typeId) : customImpl;
            if (initImpl == address(0)) revert UnsupportedType();
            beaconMode = SwitchableBeacon.Mode.Static;
        }

        // Create SwitchableBeacon with appropriate configuration
        beacon = address(new SwitchableBeacon(moduleOwner, poaBeacon, initImpl, beaconMode));
    }

    /*──────────────────── Helper Functions ───────────────────────*/

    function _updateClassesWithTokenAndHats(
        IHybridVotingInit.ClassConfig[] memory classes,
        address token,
        bytes32 orgId
    ) internal view returns (IHybridVotingInit.ClassConfig[] memory) {
        Layout storage l = _layout();

        // Get the role hat IDs now that they've been created
        uint256[] memory votingHats = new uint256[](2);
        votingHats[0] = l.orgRegistry.getRoleHat(orgId, 0); // DEFAULT role hat
        votingHats[1] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        // For democracy hats, use only the EXECUTIVE role hat
        uint256[] memory democracyHats = new uint256[](1);
        democracyHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        // Create a new array with updated configurations
        IHybridVotingInit.ClassConfig[] memory finalClasses = new IHybridVotingInit.ClassConfig[](classes.length);

        for (uint256 i = 0; i < classes.length; i++) {
            finalClasses[i] = classes[i];

            // Update token address for ERC20_BAL strategies
            if (finalClasses[i].strategy == IHybridVotingInit.ClassStrategy.ERC20_BAL) {
                if (finalClasses[i].asset == address(0)) {
                    finalClasses[i].asset = token;
                }
                // For token voting, use voting hats (both DEFAULT and EXECUTIVE)
                finalClasses[i].hatIds = votingHats;
            }
            // Update hat IDs for DIRECT strategies
            else if (finalClasses[i].strategy == IHybridVotingInit.ClassStrategy.DIRECT) {
                // For direct democracy, use democracy hats (only EXECUTIVE)
                finalClasses[i].hatIds = democracyHats;
            }
        }

        return finalClasses;
    }

    /*════════════════  FULL ORG  DEPLOYMENT  ════════════════*/
    struct DeploymentParams {
        bytes32 orgId;
        string orgName;
        address registryAddr;
        bool autoUpgrade;
        uint8 quorumPct;
        IHybridVotingInit.ClassConfig[] votingClasses;
        string[] roleNames;
        string[] roleImages;
        bool[] roleCanVote;
    }

    function deployFullOrg(
        bytes32 orgId,
        string calldata orgName,
        address registryAddr,
        bool autoUpgrade,
        uint8 quorumPct,
        IHybridVotingInit.ClassConfig[] calldata votingClasses,
        string[] calldata roleNames,
        string[] calldata roleImages,
        bool[] calldata roleCanVote
    )
        external
        returns (
            address hybridVoting,
            address executorAddr,
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        // Manual reentrancy guard to avoid stack-too-deep
        Layout storage l = _layout();
        if (l._status == 2) revert Reentrant();
        l._status = 2;

        DeploymentParams memory params = DeploymentParams({
            orgId: orgId,
            orgName: orgName,
            registryAddr: registryAddr,
            autoUpgrade: autoUpgrade,
            quorumPct: quorumPct,
            votingClasses: votingClasses,
            roleNames: roleNames,
            roleImages: roleImages,
            roleCanVote: roleCanVote
        });

        (hybridVoting, executorAddr, quickJoin, participationToken, taskManager, educationHub) =
            _deployFullOrgInternal(params);

        // Reset reentrancy guard
        l._status = 1;

        return (hybridVoting, executorAddr, quickJoin, participationToken, taskManager, educationHub);
    }

    function _deployFullOrgInternal(DeploymentParams memory params)
        internal
        returns (
            address hybridVoting,
            address executorAddr,
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        Layout storage l = _layout();
        address execBeacon;

        /* 1. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName));
        } else {
            // Org already exists - this should not happen in normal deployment
            revert OrgExistsMismatch();
        }

        /* 2. Deploy Executor with temporary ownership */
        {
            execBeacon = _createBeacon(ModuleTypes.EXECUTOR_ID, address(this), params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), address(this));
            executorAddr = ModuleDeploymentLib.deployExecutor(config, address(this), execBeacon);
        }

        /* 3. Set the executor for the org */
        l.orgRegistry.setOrgExecutor(params.orgId, executorAddr);

        /* 4. Deploy and configure modules for Hats tree */
        address eligibilityModule = _deployEligibilityModule(params.orgId, params.autoUpgrade, address(0));
        address toggleModule = _deployToggleModule(params.orgId, address(this), params.autoUpgrade, address(0));
        
        // Configure module relationships
        IEligibilityModule(eligibilityModule).setToggleModule(toggleModule);
        IToggleModule(toggleModule).setEligibilityModule(eligibilityModule);
        
        /* 5. Setup Hats Tree */
        {
            // Create top hat
            uint256 topHatId = hats.mintTopHat(
                address(this),
                string(abi.encodePacked("ipfs://", params.orgName)),
                ""
            );
            IEligibilityModule(eligibilityModule).setWearerEligibility(address(this), topHatId, true, true);
            IToggleModule(toggleModule).setHatStatus(topHatId, true);
            
            // Create eligibility admin hat
            uint256 eligibilityAdminHatId = hats.createHat(
                topHatId,
                "ELIGIBILITY_ADMIN",
                1,
                eligibilityModule,
                toggleModule,
                true,
                "ELIGIBILITY_ADMIN"
            );
            IEligibilityModule(eligibilityModule).setWearerEligibility(
                eligibilityModule,
                eligibilityAdminHatId,
                true,
                true
            );
            IToggleModule(toggleModule).setHatStatus(eligibilityAdminHatId, true);
            hats.mintHat(eligibilityAdminHatId, eligibilityModule);
            IEligibilityModule(eligibilityModule).setEligibilityModuleAdminHat(eligibilityAdminHatId);
            
            // Create role hats
            uint256 len = params.roleNames.length;
            uint256[] memory roleHatIds = new uint256[](len);
            
            // Create hats in reverse order for proper hierarchy
            for (uint256 i = len; i > 0; i--) {
                uint256 idx = i - 1;
                uint256 adminHatId;
                
                if (idx == len - 1) {
                    adminHatId = eligibilityAdminHatId;
                } else {
                    adminHatId = roleHatIds[idx + 1];
                }
                
                uint256 newHatId = hats.createHat(
                    adminHatId,
                    params.roleNames[idx],
                    type(uint32).max,
                    eligibilityModule,
                    toggleModule,
                    true,
                    params.roleNames[idx]
                );
                roleHatIds[idx] = newHatId;
                
                IEligibilityModule(eligibilityModule).setWearerEligibility(
                    executorAddr,
                    newHatId,
                    true,
                    true
                );
                IToggleModule(toggleModule).setHatStatus(newHatId, true);
                
                if (params.roleCanVote[idx]) {
                    IEligibilityModule(eligibilityModule).mintHatToAddress(newHatId, executorAddr);
                }
            }
            
            // Transfer top hat to executor
            hats.transferHat(topHatId, address(this), executorAddr);
            
            // Set default eligibility
            IEligibilityModule(eligibilityModule).setDefaultEligibility(topHatId, true, true);
            for (uint256 i = 0; i < roleHatIds.length; i++) {
                IEligibilityModule(eligibilityModule).setDefaultEligibility(roleHatIds[i], true, true);
            }
            
            // Transfer module admin rights
            IEligibilityModule(eligibilityModule).transferSuperAdmin(executorAddr);
            IToggleModule(toggleModule).transferAdmin(executorAddr);
            
            // Register the Hats tree in OrgRegistry
            l.orgRegistry.registerHatsTree(params.orgId, topHatId, roleHatIds);
        }

        /* 6. QuickJoin */
        {
            // Get the DEFAULT role hat ID for new members
            uint256[] memory memberHats = new uint256[](1);
            memberHats[0] = l.orgRegistry.getRoleHat(params.orgId, 0); // DEFAULT role hat
            
            address beacon = _createBeacon(ModuleTypes.QUICK_JOIN_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            quickJoin = ModuleDeploymentLib.deployQuickJoin(config, executorAddr, params.registryAddr, address(this), memberHats, beacon);
        }

        /* 7. Participation token */
        {
            string memory tName = string(abi.encodePacked(params.orgName, " Token"));
            string memory tSymbol = "PT";
            
            // Get the role hat IDs for member and approver permissions
            uint256[] memory memberHats = new uint256[](1);
            memberHats[0] = l.orgRegistry.getRoleHat(params.orgId, 0); // DEFAULT role hat
            
            uint256[] memory approverHats = new uint256[](1);
            approverHats[0] = l.orgRegistry.getRoleHat(params.orgId, 1); // EXECUTIVE role hat
            
            address beacon = _createBeacon(ModuleTypes.PARTICIPATION_TOKEN_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            participationToken = ModuleDeploymentLib.deployParticipationToken(config, executorAddr, tName, tSymbol, memberHats, approverHats, beacon);
        }

        /* 8. TaskManager */
        {
            // Get the role hat IDs for creator permissions
            uint256[] memory creatorHats = new uint256[](1);
            creatorHats[0] = l.orgRegistry.getRoleHat(params.orgId, 1); // EXECUTIVE role hat
            
            address beacon = _createBeacon(ModuleTypes.TASK_MANAGER_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            taskManager = ModuleDeploymentLib.deployTaskManager(config, executorAddr, participationToken, creatorHats, beacon);
            IParticipationToken(participationToken).setTaskManager(taskManager);
        }

        /* 9. EducationHub */
        {
            // Get the role hat IDs for creator and member permissions
            uint256[] memory creatorHats = new uint256[](1);
            creatorHats[0] = l.orgRegistry.getRoleHat(params.orgId, 1); // EXECUTIVE role hat
            
            uint256[] memory memberHats = new uint256[](1);
            memberHats[0] = l.orgRegistry.getRoleHat(params.orgId, 0); // DEFAULT role hat
            
            address beacon = _createBeacon(ModuleTypes.EDUCATION_HUB_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            educationHub = ModuleDeploymentLib.deployEducationHub(config, executorAddr, participationToken, creatorHats, memberHats, false, beacon);
            IParticipationToken(participationToken).setEducationHub(educationHub);
        }

        /* 10. HybridVoting governor */
        {
            // Update token address in voting classes if needed
            IHybridVotingInit.ClassConfig[] memory finalClasses =
                _updateClassesWithTokenAndHats(params.votingClasses, participationToken, params.orgId);
            
            // For creator hats, use the EXECUTIVE role hat
            uint256[] memory creatorHats = new uint256[](1);
            creatorHats[0] = l.orgRegistry.getRoleHat(params.orgId, 1); // EXECUTIVE role hat
            
            address beacon = _createBeacon(ModuleTypes.HYBRID_VOTING_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            hybridVoting = ModuleDeploymentLib.deployHybridVoting(config, executorAddr, creatorHats, params.quorumPct, finalClasses, true, beacon);
        }

        /* authorize QuickJoin to mint hats (before setting voting contract as caller) */
        IExecutorAdmin(executorAddr).setHatMinterAuthorization(quickJoin, true);

        /* link executor to governor */
        IExecutorAdmin(executorAddr).setCaller(hybridVoting);

        /* Transfer SwitchableBeacon ownership from deployer to executor */
        SwitchableBeacon(execBeacon).transferOwnership(executorAddr);

        /* renounce executor ownership - now only governed by voting */
        OwnableUpgradeable(executorAddr).renounceOwnership();
    }

    /*══════════════  UTILITIES  ═════════════=*/
    function getBeaconImplementation(address beacon) external view returns (address impl) {
        (bool ok, bytes memory ret) = beacon.staticcall(
            abi.encodeWithSelector(IBeaconLike.implementation.selector)
        );
        if (!ok) revert BeaconProbeFail();
        impl = abi.decode(ret, (address));
    }

    function _orgExists(bytes32 id) internal view returns (bool) {
        // Destructure the tuple to get the exists field (4th element)
        (,,, bool exists) = _layout().orgRegistry.orgOf(id);
        return exists;
    }

    // Public getter for poaManager
    function poaManager() external view returns (address) {
        return address(_layout().poaManager);
    }

    // Public getter for orgRegistry
    function orgRegistry() external view returns (address) {
        return address(_layout().orgRegistry);
    }


    /* ─────────── Module Getters ─────────── */
    function getEligibilityModule(bytes32 orgId) external view returns (address) {
        Layout storage l = _layout();
        return l.orgRegistry.getOrgContract(orgId, ModuleTypes.ELIGIBILITY_MODULE_ID);
    }

    function getToggleModule(bytes32 orgId) external view returns (address) {
        Layout storage l = _layout();
        return l.orgRegistry.getOrgContract(orgId, ModuleTypes.TOGGLE_MODULE_ID);
    }
}