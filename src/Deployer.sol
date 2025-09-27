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
import {IEligibilityModule, IToggleModule} from "./interfaces/IHatsModules.sol";

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

/*──────────────────── External management contracts ────────────────────*/
// IPoaManager moved to ModuleDeploymentLib to break circular dependency

/*────────────────────── Module‑specific hooks ──────────────────────────*/

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
    function setHatMinterAuthorization(address minter, bool authorized) external;
}


/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();
error OrgExistsMismatch();
error Reentrant();

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
        /* HatsTreeSetup contract address */
        address hatsTreeSetup;
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

    function initialize(address _poaManager, address _orgRegistry, address _hats, address _hatsTreeSetup) public initializer {
        if (_poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0) || _hatsTreeSetup == address(0)) {
            revert InvalidAddress();
        }
        Layout storage l = _layout();
        l.poaManager = IPoaManager(_poaManager);
        l.orgRegistry = OrgRegistry(_orgRegistry);
        l._status = 1; // Initialize manual reentrancy guard
        hats = IHats(_hats);
        l.hatsTreeSetup = _hatsTreeSetup;
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
        bytes32 orgId,
        RoleAssignments memory roleAssignments
    ) internal view returns (IHybridVotingInit.ClassConfig[] memory) {
        Layout storage l = _layout();
        
        for (uint256 i = 0; i < classes.length; i++) {
            if (classes[i].strategy == IHybridVotingInit.ClassStrategy.ERC20_BAL) {
                if (classes[i].asset == address(0)) {
                    classes[i].asset = token;
                }
                // For token-based voting, use token member roles
                uint256[] memory hats = new uint256[](roleAssignments.tokenMemberRoles.length);
                for (uint256 j = 0; j < roleAssignments.tokenMemberRoles.length; j++) {
                    hats[j] = l.orgRegistry.getRoleHat(orgId, roleAssignments.tokenMemberRoles[j]);
                }
                classes[i].hatIds = hats;
            } else if (classes[i].strategy == IHybridVotingInit.ClassStrategy.DIRECT) {
                // For direct voting, use proposal creator roles
                uint256[] memory hats = new uint256[](roleAssignments.proposalCreatorRoles.length);
                for (uint256 j = 0; j < roleAssignments.proposalCreatorRoles.length; j++) {
                    hats[j] = l.orgRegistry.getRoleHat(orgId, roleAssignments.proposalCreatorRoles[j]);
                }
                classes[i].hatIds = hats;
            }
        }
        return classes;
    }

    /*════════════════  FULL ORG  DEPLOYMENT  ════════════════*/
    struct RoleAssignments {
        uint256[] quickJoinRoles;        // Roles that new members get via QuickJoin
        uint256[] tokenMemberRoles;      // Roles that can hold participation tokens
        uint256[] tokenApproverRoles;    // Roles that can approve token transfers
        uint256[] taskCreatorRoles;      // Roles that can create tasks
        uint256[] educationCreatorRoles; // Roles that can create education content
        uint256[] educationMemberRoles;  // Roles that can access education content
        uint256[] proposalCreatorRoles;  // Roles that can create proposals
    }
    
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
        RoleAssignments roleAssignments;
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
        bool[] calldata roleCanVote,
        RoleAssignments calldata roleAssignments
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
            roleCanVote: roleCanVote,
            roleAssignments: roleAssignments
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
        
        /* 5. Setup Hats Tree */
        uint256 topHatId;
        uint256[] memory roleHatIds;
        {
            // Transfer superAdmin rights to HatsTreeSetup contract
            IEligibilityModule(eligibilityModule).transferSuperAdmin(l.hatsTreeSetup);
            IToggleModule(toggleModule).transferAdmin(l.hatsTreeSetup);
            
            // Call HatsTreeSetup to do all the Hats configuration
            IHatsTreeSetup.SetupParams memory setupParams = IHatsTreeSetup.SetupParams({
                hats: hats,
                orgRegistry: l.orgRegistry,
                orgId: params.orgId,
                eligibilityModule: eligibilityModule,
                toggleModule: toggleModule,
                deployer: address(this),
                executor: executorAddr,
                orgName: params.orgName,
                roleNames: params.roleNames,
                roleImages: params.roleImages,
                roleCanVote: params.roleCanVote
            });
            IHatsTreeSetup.SetupResult memory result = IHatsTreeSetup(l.hatsTreeSetup).setupHatsTree(setupParams);
            
            topHatId = result.topHatId;
            roleHatIds = result.roleHatIds;
            
            // Register the Hats tree in OrgRegistry (must be done by Deployer as it's the owner during bootstrap)
            l.orgRegistry.registerHatsTree(params.orgId, topHatId, roleHatIds);
        }

        /* 6. QuickJoin */
        {
            // Get the role hat IDs for new members
            uint256[] memory memberHats = new uint256[](params.roleAssignments.quickJoinRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.quickJoinRoles.length; i++) {
                memberHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.quickJoinRoles[i]);
            }
            
            address beacon = _createBeacon(ModuleTypes.QUICK_JOIN_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            quickJoin = ModuleDeploymentLib.deployQuickJoin(config, executorAddr, params.registryAddr, address(this), memberHats, beacon);
        }

        /* 7. Participation token */
        {
            string memory tName = string(abi.encodePacked(params.orgName, " Token"));
            string memory tSymbol = "PT";
            
            // Get the role hat IDs for member and approver permissions
            uint256[] memory memberHats = new uint256[](params.roleAssignments.tokenMemberRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.tokenMemberRoles.length; i++) {
                memberHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.tokenMemberRoles[i]);
            }
            
            uint256[] memory approverHats = new uint256[](params.roleAssignments.tokenApproverRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.tokenApproverRoles.length; i++) {
                approverHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.tokenApproverRoles[i]);
            }
            
            address beacon = _createBeacon(ModuleTypes.PARTICIPATION_TOKEN_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            participationToken = ModuleDeploymentLib.deployParticipationToken(config, executorAddr, tName, tSymbol, memberHats, approverHats, beacon);
        }

        /* 8. TaskManager */
        {
            // Get the role hat IDs for creator permissions
            uint256[] memory creatorHats = new uint256[](params.roleAssignments.taskCreatorRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.taskCreatorRoles.length; i++) {
                creatorHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.taskCreatorRoles[i]);
            }
            
            address beacon = _createBeacon(ModuleTypes.TASK_MANAGER_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            taskManager = ModuleDeploymentLib.deployTaskManager(config, executorAddr, participationToken, creatorHats, beacon);
            IParticipationToken(participationToken).setTaskManager(taskManager);
        }

        /* 9. EducationHub */
        {
            // Get the role hat IDs for creator and member permissions
            uint256[] memory creatorHats = new uint256[](params.roleAssignments.educationCreatorRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.educationCreatorRoles.length; i++) {
                creatorHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.educationCreatorRoles[i]);
            }
            
            uint256[] memory memberHats = new uint256[](params.roleAssignments.educationMemberRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.educationMemberRoles.length; i++) {
                memberHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.educationMemberRoles[i]);
            }
            
            address beacon = _createBeacon(ModuleTypes.EDUCATION_HUB_ID, executorAddr, params.autoUpgrade, address(0));
            ModuleDeploymentLib.DeployConfig memory config = _getDeployConfig(params.orgId, params.autoUpgrade, address(0), executorAddr);
            educationHub = ModuleDeploymentLib.deployEducationHub(config, executorAddr, participationToken, creatorHats, memberHats, false, beacon);
            IParticipationToken(participationToken).setEducationHub(educationHub);
        }

        /* 10. HybridVoting governor */
        {
            // Update token address in voting classes if needed
            IHybridVotingInit.ClassConfig[] memory finalClasses =
                _updateClassesWithTokenAndHats(params.votingClasses, participationToken, params.orgId, params.roleAssignments);
            
            // Get the role hat IDs for proposal creators
            uint256[] memory creatorHats = new uint256[](params.roleAssignments.proposalCreatorRoles.length);
            for (uint256 i = 0; i < params.roleAssignments.proposalCreatorRoles.length; i++) {
                creatorHats[i] = l.orgRegistry.getRoleHat(params.orgId, params.roleAssignments.proposalCreatorRoles[i]);
            }
            
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

    function _orgExists(bytes32 id) internal view returns (bool) {
        // Destructure the tuple to get the exists field (4th element)
        (,,, bool exists) = _layout().orgRegistry.orgOf(id);
        return exists;
    }

}