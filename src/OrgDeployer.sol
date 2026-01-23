// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";

import "./OrgRegistry.sol";
import {IHybridVotingInit} from "./libs/ModuleDeploymentLib.sol";
import {RoleResolver} from "./libs/RoleResolver.sol";
import {GovernanceFactory, IHatsTreeSetup} from "./factories/GovernanceFactory.sol";
import {AccessFactory} from "./factories/AccessFactory.sol";
import {ModulesFactory} from "./factories/ModulesFactory.sol";
import {RoleConfigStructs} from "./libs/RoleConfigStructs.sol";

/*────────────────────── Module‑specific hooks ──────────────────────────*/
interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
    function setHatMinterAuthorization(address minter, bool authorized) external;
    function configureVouching(
        address eligibilityModule,
        uint256 hatId,
        uint32 quorum,
        uint256 membershipHatId,
        bool combineWithHierarchy
    ) external;
    function batchConfigureVouching(
        address eligibilityModule,
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external;
    function setDefaultEligibility(address eligibilityModule, uint256 hatId, bool eligible, bool standing) external;
}

interface IPaymasterHub {
    function registerOrg(bytes32 orgId, uint256 adminHatId, uint256 operatorHatId) external;
}

interface ITaskManagerBootstrap {
    struct BootstrapProjectConfig {
        bytes title;
        bytes32 metadataHash;
        uint256 cap;
        address[] managers;
        uint256[] createHats;
        uint256[] claimHats;
        uint256[] reviewHats;
        uint256[] assignHats;
    }

    struct BootstrapTaskConfig {
        uint8 projectIndex;
        uint256 payout;
        bytes title;
        bytes32 metadataHash;
        address bountyToken;
        uint256 bountyPayout;
        bool requiresApplication;
    }

    function bootstrapProjectsAndTasks(BootstrapProjectConfig[] calldata projects, BootstrapTaskConfig[] calldata tasks)
        external
        returns (bytes32[] memory projectIds);
}

/**
 * @title OrgDeployer
 * @notice Thin orchestrator for deploying complete organizations using factory pattern
 * @dev Coordinates GovernanceFactory, AccessFactory, and ModulesFactory
 */
contract OrgDeployer is Initializable {
    /// @notice Contract version for tracking deployments
    string public constant VERSION = "1.0.1";

    /*────────────────────────────  Errors  ───────────────────────────────*/
    error InvalidAddress();
    error OrgExistsMismatch();
    error Reentrant();
    error InvalidRoleConfiguration();

    /*────────────────────────────  Events  ───────────────────────────────*/
    event OrgDeployed(
        bytes32 indexed orgId,
        address indexed executor,
        address hybridVoting,
        address directDemocracyVoting,
        address quickJoin,
        address participationToken,
        address taskManager,
        address educationHub,
        address paymentManager,
        address eligibilityModule,
        address toggleModule,
        uint256 topHatId,
        uint256[] roleHatIds
    );

    event RolesCreated(
        bytes32 indexed orgId, uint256[] hatIds, string[] names, string[] images, bytes32[] metadataCIDs, bool[] canVote
    );

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgdeployer.storage
    struct Layout {
        GovernanceFactory governanceFactory;
        AccessFactory accessFactory;
        ModulesFactory modulesFactory;
        OrgRegistry orgRegistry;
        address poaManager;
        address hatsTreeSetup;
        address paymasterHub; // Shared PaymasterHub for all orgs
        address universalPasskeyFactory; // Universal PasskeyAccountFactory for all orgs
        uint256 _status; // manual reentrancy guard
    }

    IHats public hats;

    bytes32 private constant _STORAGE_SLOT = 0x9f1e8f9f8d4c3b2a1e7f6d5c4b3a2e1f0d9c8b7a6e5f4d3c2b1a0e9f8d7c6b5a;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*════════════════  INITIALIZATION  ════════════════*/

    constructor() initializer {}

    function initialize(
        address _governanceFactory,
        address _accessFactory,
        address _modulesFactory,
        address _poaManager,
        address _orgRegistry,
        address _hats,
        address _hatsTreeSetup,
        address _paymasterHub
    ) public initializer {
        if (
            _governanceFactory == address(0) || _accessFactory == address(0) || _modulesFactory == address(0)
                || _poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0)
                || _hatsTreeSetup == address(0) || _paymasterHub == address(0)
        ) {
            revert InvalidAddress();
        }

        Layout storage l = _layout();
        l.governanceFactory = GovernanceFactory(_governanceFactory);
        l.accessFactory = AccessFactory(_accessFactory);
        l.modulesFactory = ModulesFactory(_modulesFactory);
        l.orgRegistry = OrgRegistry(_orgRegistry);
        l.poaManager = _poaManager;
        l.hatsTreeSetup = _hatsTreeSetup;
        l.paymasterHub = _paymasterHub;
        l._status = 1; // Initialize manual reentrancy guard
        hats = IHats(_hats);
    }

    /**
     * @notice Set the universal passkey factory address
     * @dev Callable by PoaManager, or anyone for one-time initial setup (when factory is not yet set)
     */
    function setUniversalPasskeyFactory(address _universalFactory) external {
        Layout storage l = _layout();
        // Allow one-time setup by anyone (when factory is not yet set), or require PoaManager for updates
        if (l.universalPasskeyFactory != address(0) && msg.sender != l.poaManager) {
            revert InvalidAddress();
        }
        l.universalPasskeyFactory = _universalFactory;
    }

    /*════════════════  DEPLOYMENT STRUCTS  ════════════════*/

    struct DeploymentResult {
        address hybridVoting;
        address directDemocracyVoting;
        address executor;
        address quickJoin;
        address participationToken;
        address taskManager;
        address educationHub;
        address paymentManager;
    }

    struct RoleAssignments {
        uint256 quickJoinRolesBitmap; // Bit N set = Role N assigned on join
        uint256 tokenMemberRolesBitmap; // Bit N set = Role N can hold tokens
        uint256 tokenApproverRolesBitmap; // Bit N set = Role N can approve transfers
        uint256 taskCreatorRolesBitmap; // Bit N set = Role N can create tasks
        uint256 educationCreatorRolesBitmap; // Bit N set = Role N can create education
        uint256 educationMemberRolesBitmap; // Bit N set = Role N can access education
        uint256 hybridProposalCreatorRolesBitmap; // Bit N set = Role N can create proposals
        uint256 ddVotingRolesBitmap; // Bit N set = Role N can vote in polls
        uint256 ddCreatorRolesBitmap; // Bit N set = Role N can create polls
    }

    struct BootstrapConfig {
        ITaskManagerBootstrap.BootstrapProjectConfig[] projects;
        ITaskManagerBootstrap.BootstrapTaskConfig[] tasks;
    }

    struct DeploymentParams {
        bytes32 orgId;
        string orgName;
        bytes32 metadataHash; // IPFS CID sha256 digest (optional, bytes32(0) is valid)
        address registryAddr;
        address deployerAddress; // Address to receive ADMIN hat
        string deployerUsername; // Optional username for deployer (empty string = skip registration)
        bool autoUpgrade;
        uint8 hybridQuorumPct;
        uint8 ddQuorumPct;
        IHybridVotingInit.ClassConfig[] hybridClasses;
        address[] ddInitialTargets;
        RoleConfigStructs.RoleConfig[] roles; // Complete role configuration (replaces roleNames, roleImages, roleCanVote)
        RoleAssignments roleAssignments;
        bool passkeyEnabled; // Whether passkey support is enabled (uses universal factory)
        ModulesFactory.EducationHubConfig educationHubConfig; // EducationHub deployment configuration
        BootstrapConfig bootstrap; // Optional: initial projects and tasks to create
    }

    /*════════════════  VALIDATION  ════════════════*/

    /// @notice Validates role configurations for correctness
    /// @dev Checks indices, prevents cycles, validates vouching configs
    /// @param roles Array of role configurations to validate
    function _validateRoleConfigs(RoleConfigStructs.RoleConfig[] calldata roles) internal pure {
        uint256 len = roles.length;

        // Must have at least one role
        if (len == 0) revert InvalidRoleConfiguration();

        // Practical limit to prevent gas issues
        if (len > 32) revert InvalidRoleConfiguration();

        for (uint256 i = 0; i < len; i++) {
            RoleConfigStructs.RoleConfig calldata role = roles[i];

            // Validate vouching configuration
            if (role.vouching.enabled) {
                // Quorum must be positive
                if (role.vouching.quorum == 0) revert InvalidRoleConfiguration();

                // Voucher role index must be valid
                if (role.vouching.voucherRoleIndex >= len) {
                    revert InvalidRoleConfiguration();
                }
            }

            // Validate hierarchy configuration
            if (role.hierarchy.adminRoleIndex != type(uint256).max) {
                // Admin role index must be valid
                if (role.hierarchy.adminRoleIndex >= len) {
                    revert InvalidRoleConfiguration();
                }

                // Prevent simple self-referential cycles
                if (role.hierarchy.adminRoleIndex == i) {
                    revert InvalidRoleConfiguration();
                }
            }

            // Validate name is not empty
            if (bytes(role.name).length == 0) revert InvalidRoleConfiguration();
        }

        // Note: Full cycle detection would require graph traversal
        // The Hats contract itself will revert if actual cycles exist during tree creation
    }

    /*════════════════  MAIN DEPLOYMENT FUNCTION  ════════════════*/

    function deployFullOrg(DeploymentParams calldata params) external returns (DeploymentResult memory result) {
        // Manual reentrancy guard
        Layout storage l = _layout();
        if (l._status == 2) revert Reentrant();
        l._status = 2;

        result = _deployFullOrgInternal(params);

        // Reset reentrancy guard
        l._status = 1;

        return result;
    }

    /*════════════════  INTERNAL ORCHESTRATION  ════════════════*/

    function _deployFullOrgInternal(DeploymentParams calldata params)
        internal
        returns (DeploymentResult memory result)
    {
        Layout storage l = _layout();

        /* 1. Validate role configurations */
        _validateRoleConfigs(params.roles);

        /* 2. Validate deployer address */
        if (params.deployerAddress == address(0)) {
            revert InvalidAddress();
        }

        /* 3. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName), params.metadataHash);
        } else {
            revert OrgExistsMismatch();
        }

        /* 2. Deploy Governance Infrastructure (Executor, Hats modules, Hats tree) */
        GovernanceFactory.GovernanceResult memory gov = _deployGovernanceInfrastructure(params);
        result.executor = gov.executor;

        /* 3. Set the executor for the org */
        l.orgRegistry.setOrgExecutor(params.orgId, result.executor);

        /* 4. Register Hats tree in OrgRegistry */
        l.orgRegistry.registerHatsTree(params.orgId, gov.topHatId, gov.roleHatIds);

        /* 5. Register org with shared PaymasterHub */
        IPaymasterHub(l.paymasterHub).registerOrg(params.orgId, gov.topHatId, 0);

        /* 6. Deploy Access Infrastructure (QuickJoin, Token) */
        AccessFactory.AccessResult memory access;
        {
            AccessFactory.RoleAssignments memory accessRoles = AccessFactory.RoleAssignments({
                quickJoinRolesBitmap: params.roleAssignments.quickJoinRolesBitmap,
                tokenMemberRolesBitmap: params.roleAssignments.tokenMemberRolesBitmap,
                tokenApproverRolesBitmap: params.roleAssignments.tokenApproverRolesBitmap
            });

            // Use universal factory if passkey is enabled
            AccessFactory.PasskeyConfig memory passkeyConfig = AccessFactory.PasskeyConfig({
                enabled: params.passkeyEnabled,
                universalFactory: params.passkeyEnabled ? l.universalPasskeyFactory : address(0)
            });

            AccessFactory.AccessParams memory accessParams = AccessFactory.AccessParams({
                orgId: params.orgId,
                orgName: params.orgName,
                poaManager: l.poaManager,
                orgRegistry: address(l.orgRegistry),
                hats: address(hats),
                executor: result.executor,
                deployer: address(this), // For registration callbacks
                registryAddr: params.registryAddr,
                roleHatIds: gov.roleHatIds,
                autoUpgrade: params.autoUpgrade,
                roleAssignments: accessRoles,
                passkeyConfig: passkeyConfig
            });

            access = l.accessFactory.deployAccess(accessParams);
            result.quickJoin = access.quickJoin;
            result.participationToken = access.participationToken;
        }

        /* 6. Deploy Functional Modules (TaskManager, Education, Payment) */
        ModulesFactory.ModulesResult memory modules;
        {
            ModulesFactory.RoleAssignments memory moduleRoles = ModulesFactory.RoleAssignments({
                taskCreatorRolesBitmap: params.roleAssignments.taskCreatorRolesBitmap,
                educationCreatorRolesBitmap: params.roleAssignments.educationCreatorRolesBitmap,
                educationMemberRolesBitmap: params.roleAssignments.educationMemberRolesBitmap
            });

            ModulesFactory.ModulesParams memory moduleParams = ModulesFactory.ModulesParams({
                orgId: params.orgId,
                orgName: params.orgName,
                poaManager: l.poaManager,
                orgRegistry: address(l.orgRegistry),
                hats: address(hats),
                executor: result.executor,
                deployer: address(this), // For registration callbacks
                participationToken: result.participationToken,
                roleHatIds: gov.roleHatIds,
                autoUpgrade: params.autoUpgrade,
                roleAssignments: moduleRoles,
                educationHubConfig: params.educationHubConfig
            });

            modules = l.modulesFactory.deployModules(moduleParams);
            result.taskManager = modules.taskManager;
            result.educationHub = modules.educationHub;
            result.paymentManager = modules.paymentManager;
        }

        /* 7. Deploy Voting Mechanisms (HybridVoting, DirectDemocracyVoting) */
        (result.hybridVoting, result.directDemocracyVoting) =
            _deployVotingMechanisms(params, result.executor, result.participationToken, gov.roleHatIds);

        /* 8. Wire up cross-module connections */
        IParticipationToken(result.participationToken).setTaskManager(result.taskManager);
        if (params.educationHubConfig.enabled) {
            IParticipationToken(result.participationToken).setEducationHub(result.educationHub);
        }

        /* 8.5. Bootstrap initial projects and tasks if configured */
        if (params.bootstrap.projects.length > 0) {
            // Resolve role indices to hat IDs in bootstrap config
            ITaskManagerBootstrap.BootstrapProjectConfig[] memory resolvedProjects =
                _resolveBootstrapRoles(params.bootstrap.projects, gov.roleHatIds);
            ITaskManagerBootstrap(result.taskManager)
                .bootstrapProjectsAndTasks(resolvedProjects, params.bootstrap.tasks);
        }

        /* 9. Authorize QuickJoin to mint hats */
        IExecutorAdmin(result.executor).setHatMinterAuthorization(result.quickJoin, true);

        /* 10. Link executor to governor */
        IExecutorAdmin(result.executor).setCaller(result.hybridVoting);

        /* 10.5. Configure vouching system from role configurations (batch optimized) */
        {
            // Count roles with vouching enabled
            uint256 vouchCount = 0;
            for (uint256 i = 0; i < params.roles.length; i++) {
                if (params.roles[i].vouching.enabled) vouchCount++;
            }

            if (vouchCount > 0) {
                uint256[] memory hatIds = new uint256[](vouchCount);
                uint32[] memory quorums = new uint32[](vouchCount);
                uint256[] memory membershipHatIds = new uint256[](vouchCount);
                bool[] memory combineFlags = new bool[](vouchCount);
                uint256 vouchIndex = 0;

                for (uint256 i = 0; i < params.roles.length; i++) {
                    RoleConfigStructs.RoleConfig calldata role = params.roles[i];
                    if (role.vouching.enabled) {
                        hatIds[vouchIndex] = gov.roleHatIds[i];
                        quorums[vouchIndex] = role.vouching.quorum;
                        membershipHatIds[vouchIndex] = gov.roleHatIds[role.vouching.voucherRoleIndex];
                        combineFlags[vouchIndex] = role.vouching.combineWithHierarchy;
                        vouchIndex++;
                    }
                }

                IExecutorAdmin(result.executor)
                    .batchConfigureVouching(gov.eligibilityModule, hatIds, quorums, membershipHatIds, combineFlags);
            }
        }

        /* 11. Renounce executor ownership - now only governed by voting */
        OwnableUpgradeable(result.executor).renounceOwnership();

        /* 12. Emit event for subgraph indexing */
        emit OrgDeployed(
            params.orgId,
            result.executor,
            result.hybridVoting,
            result.directDemocracyVoting,
            result.quickJoin,
            result.participationToken,
            result.taskManager,
            result.educationHub,
            result.paymentManager,
            gov.eligibilityModule,
            gov.toggleModule,
            gov.topHatId,
            gov.roleHatIds
        );

        /* 13. Emit role metadata for subgraph indexing */
        {
            uint256 roleCount = params.roles.length;
            string[] memory names = new string[](roleCount);
            string[] memory images = new string[](roleCount);
            bytes32[] memory metadataCIDs = new bytes32[](roleCount);
            bool[] memory canVoteFlags = new bool[](roleCount);

            for (uint256 i = 0; i < roleCount; i++) {
                names[i] = params.roles[i].name;
                images[i] = params.roles[i].image;
                metadataCIDs[i] = params.roles[i].metadataCID;
                canVoteFlags[i] = params.roles[i].canVote;
            }

            emit RolesCreated(params.orgId, gov.roleHatIds, names, images, metadataCIDs, canVoteFlags);
        }

        return result;
    }

    /*══════════════  UTILITIES  ═════════════=*/

    function _orgExists(bytes32 id) internal view returns (bool) {
        (,,, bool exists) = _layout().orgRegistry.orgOf(id);
        return exists;
    }

    /**
     * @notice Internal helper to deploy governance infrastructure
     * @dev Extracted to reduce stack depth in main deployment function
     */
    function _deployGovernanceInfrastructure(DeploymentParams calldata params)
        internal
        returns (GovernanceFactory.GovernanceResult memory)
    {
        Layout storage l = _layout();

        GovernanceFactory.GovernanceParams memory govParams;
        govParams.orgId = params.orgId;
        govParams.orgName = params.orgName;
        govParams.poaManager = l.poaManager;
        govParams.orgRegistry = address(l.orgRegistry);
        govParams.hats = address(hats);
        govParams.hatsTreeSetup = l.hatsTreeSetup;
        govParams.deployer = address(this);
        govParams.deployerAddress = params.deployerAddress; // Pass deployer address for ADMIN hat
        govParams.accountRegistry = params.registryAddr; // UniversalAccountRegistry for username registration
        govParams.participationToken = address(0);
        govParams.deployerUsername = params.deployerUsername; // Optional username (empty = skip)
        govParams.autoUpgrade = params.autoUpgrade;
        govParams.hybridQuorumPct = params.hybridQuorumPct;
        govParams.ddQuorumPct = params.ddQuorumPct;
        govParams.hybridClasses = params.hybridClasses;
        govParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        govParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        govParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        govParams.ddInitialTargets = params.ddInitialTargets;
        govParams.roles = params.roles;

        return l.governanceFactory.deployInfrastructure(govParams);
    }

    /**
     * @notice Internal helper to deploy voting mechanisms after token is available
     * @dev Extracted to reduce stack depth in main deployment function
     */
    function _deployVotingMechanisms(
        DeploymentParams calldata params,
        address executor,
        address participationToken,
        uint256[] memory roleHatIds
    ) internal returns (address hybridVoting, address directDemocracyVoting) {
        Layout storage l = _layout();

        GovernanceFactory.GovernanceParams memory votingParams;
        votingParams.orgId = params.orgId;
        votingParams.orgName = params.orgName;
        votingParams.poaManager = l.poaManager;
        votingParams.orgRegistry = address(l.orgRegistry);
        votingParams.hats = address(hats);
        votingParams.hatsTreeSetup = l.hatsTreeSetup;
        votingParams.deployer = address(this);
        votingParams.deployerAddress = params.deployerAddress;
        votingParams.participationToken = participationToken;
        votingParams.autoUpgrade = params.autoUpgrade;
        votingParams.hybridQuorumPct = params.hybridQuorumPct;
        votingParams.ddQuorumPct = params.ddQuorumPct;
        votingParams.hybridClasses = params.hybridClasses;
        votingParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        votingParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        votingParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        votingParams.ddInitialTargets = params.ddInitialTargets;
        votingParams.roles = params.roles;

        return l.governanceFactory.deployVoting(votingParams, executor, roleHatIds);
    }

    /**
     * @notice Allows factories to register contracts via OrgDeployer's ownership
     * @dev Only callable by approved factory contracts during deployment
     */
    function registerContract(
        bytes32 orgId,
        bytes32 typeId,
        address proxy,
        address beacon,
        bool autoUpgrade,
        address moduleOwner,
        bool lastRegister
    ) external {
        Layout storage l = _layout();

        // Only allow factory contracts to call this
        if (
            msg.sender != address(l.governanceFactory) && msg.sender != address(l.accessFactory)
                && msg.sender != address(l.modulesFactory)
        ) {
            revert InvalidAddress();
        }

        // Only allow during bootstrap (deployment phase)
        (,, bool bootstrap,) = l.orgRegistry.orgOf(orgId);
        if (!bootstrap) revert("Deployment complete");

        // Forward registration to OrgRegistry (we are the owner)
        l.orgRegistry.registerOrgContract(orgId, typeId, proxy, beacon, autoUpgrade, moduleOwner, lastRegister);
    }

    /**
     * @notice Batch register multiple contracts from factories
     * @dev Only callable by approved factory contracts. Reduces gas overhead by batching registrations.
     * @param orgId The organization identifier
     * @param registrations Array of contracts to register
     * @param autoUpgrade Whether contracts auto-upgrade with their beacons
     */
    function batchRegisterContracts(
        bytes32 orgId,
        OrgRegistry.ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external {
        Layout storage l = _layout();

        // Only allow factory contracts to call this
        if (
            msg.sender != address(l.governanceFactory) && msg.sender != address(l.accessFactory)
                && msg.sender != address(l.modulesFactory)
        ) {
            revert InvalidAddress();
        }

        // Only allow during bootstrap (deployment phase)
        (,, bool bootstrap,) = l.orgRegistry.orgOf(orgId);
        if (!bootstrap) revert("Deployment complete");

        // Forward batch registration to OrgRegistry (we are the owner)
        l.orgRegistry.batchRegisterOrgContracts(orgId, registrations, autoUpgrade, lastRegister);
    }

    /**
     * @notice Resolve role indices to hat IDs in bootstrap project configs
     * @dev Role indices in config are converted to actual hat IDs using roleHatIds array
     */
    function _resolveBootstrapRoles(
        ITaskManagerBootstrap.BootstrapProjectConfig[] calldata projects,
        uint256[] memory roleHatIds
    ) internal pure returns (ITaskManagerBootstrap.BootstrapProjectConfig[] memory resolved) {
        resolved = new ITaskManagerBootstrap.BootstrapProjectConfig[](projects.length);

        for (uint256 i = 0; i < projects.length; i++) {
            resolved[i] = ITaskManagerBootstrap.BootstrapProjectConfig({
                title: projects[i].title,
                metadataHash: projects[i].metadataHash,
                cap: projects[i].cap,
                managers: projects[i].managers,
                createHats: _resolveRoleIndicesToHatIds(projects[i].createHats, roleHatIds),
                claimHats: _resolveRoleIndicesToHatIds(projects[i].claimHats, roleHatIds),
                reviewHats: _resolveRoleIndicesToHatIds(projects[i].reviewHats, roleHatIds),
                assignHats: _resolveRoleIndicesToHatIds(projects[i].assignHats, roleHatIds)
            });
        }

        return resolved;
    }

    /**
     * @notice Convert array of role indices to array of hat IDs
     */
    function _resolveRoleIndicesToHatIds(uint256[] calldata roleIndices, uint256[] memory roleHatIds)
        internal
        pure
        returns (uint256[] memory hatIds)
    {
        hatIds = new uint256[](roleIndices.length);
        for (uint256 i = 0; i < roleIndices.length; i++) {
            require(roleIndices[i] < roleHatIds.length, "Invalid role index in bootstrap config");
            hatIds[i] = roleHatIds[roleIndices[i]];
        }
        return hatIds;
    }
}
