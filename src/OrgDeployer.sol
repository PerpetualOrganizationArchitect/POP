// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";

import "./OrgRegistry.sol";
import {IHybridVotingInit} from "./libs/ModuleDeploymentLib.sol";
import {RoleResolver} from "./libs/RoleResolver.sol";
import {GovernanceFactory} from "./factories/GovernanceFactory.sol";
import {AccessFactory} from "./factories/AccessFactory.sol";
import {ModulesFactory} from "./factories/ModulesFactory.sol";

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
error OrgExistsMismatch();
error Reentrant();

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
    address paymentManager
);

event PaymasterDeployed(bytes32 indexed orgId, address indexed paymasterHub, address entryPoint);

/**
 * @title OrgDeployer
 * @notice Thin orchestrator for deploying complete organizations using factory pattern
 * @dev Coordinates GovernanceFactory, AccessFactory, and ModulesFactory
 */
contract OrgDeployer is Initializable {
    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgdeployer.storage
    struct Layout {
        GovernanceFactory governanceFactory;
        AccessFactory accessFactory;
        ModulesFactory modulesFactory;
        OrgRegistry orgRegistry;
        address poaManager;
        address hatsTreeSetup;
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
        address _hatsTreeSetup
    ) public initializer {
        if (
            _governanceFactory == address(0) || _accessFactory == address(0) || _modulesFactory == address(0)
                || _poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0)
                || _hatsTreeSetup == address(0)
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
        l._status = 1; // Initialize manual reentrancy guard
        hats = IHats(_hats);
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
        uint256 quickJoinRolesBitmap;           // Bit N set = Role N assigned on join
        uint256 tokenMemberRolesBitmap;         // Bit N set = Role N can hold tokens
        uint256 tokenApproverRolesBitmap;       // Bit N set = Role N can approve transfers
        uint256 taskCreatorRolesBitmap;         // Bit N set = Role N can create tasks
        uint256 educationCreatorRolesBitmap;    // Bit N set = Role N can create education
        uint256 educationMemberRolesBitmap;     // Bit N set = Role N can access education
        uint256 hybridProposalCreatorRolesBitmap; // Bit N set = Role N can create proposals
        uint256 ddVotingRolesBitmap;            // Bit N set = Role N can vote in polls
        uint256 ddCreatorRolesBitmap;           // Bit N set = Role N can create polls
    }

    struct DeploymentParams {
        bytes32 orgId;
        string orgName;
        address registryAddr;
        bool autoUpgrade;
        uint8 hybridQuorumPct;
        uint8 ddQuorumPct;
        IHybridVotingInit.ClassConfig[] hybridClasses;
        address[] ddInitialTargets;
        string[] roleNames;
        string[] roleImages;
        bool[] roleCanVote;
        RoleAssignments roleAssignments;
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

    function _deployFullOrgInternal(DeploymentParams calldata params) internal returns (DeploymentResult memory result) {
        Layout storage l = _layout();

        /* 1. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName));
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

        /* 5. Deploy Access Infrastructure (QuickJoin, Token) */
        AccessFactory.AccessResult memory access;
        {
            AccessFactory.RoleAssignments memory accessRoles = AccessFactory.RoleAssignments({
                quickJoinRolesBitmap: params.roleAssignments.quickJoinRolesBitmap,
                tokenMemberRolesBitmap: params.roleAssignments.tokenMemberRolesBitmap,
                tokenApproverRolesBitmap: params.roleAssignments.tokenApproverRolesBitmap
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
                roleAssignments: accessRoles
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
                roleAssignments: moduleRoles
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
        IParticipationToken(result.participationToken).setEducationHub(result.educationHub);

        /* 9. Authorize QuickJoin to mint hats */
        IExecutorAdmin(result.executor).setHatMinterAuthorization(result.quickJoin, true);

        /* 10. Link executor to governor */
        IExecutorAdmin(result.executor).setCaller(result.hybridVoting);

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
            result.paymentManager
        );

        return result;
    }

    /*════════════════  PAYMASTER DEPLOYMENT  ════════════════*/

    struct PaymasterParams {
        bytes paymasterBytecode;
        address entryPoint;
    }

    /**
     * @notice Deploys a complete organization WITH PaymasterHub in a single transaction
     * @dev Uses bytecode-as-calldata pattern to avoid embedding PaymasterHub bytecode
     * @param params Standard deployment parameters (same as deployFullOrg)
     * @param paymasterParams PaymasterHub-specific parameters
     * @return result Deployed organization components
     * @return paymasterHub Deployed PaymasterHub address
     */
    function deployFullOrgWithPaymaster(DeploymentParams calldata params, PaymasterParams calldata paymasterParams)
        external
        returns (DeploymentResult memory result, address paymasterHub)
    {
        // Manual reentrancy guard
        Layout storage l = _layout();
        if (l._status == 2) revert Reentrant();
        l._status = 2;

        // Deploy core organization using provided params
        result = _deployFullOrgInternal(params);

        // Get topHatId from org registry (needed for PaymasterHub)
        uint256 topHatId = l.orgRegistry.getTopHat(params.orgId);

        // Deploy PaymasterHub using bytecode from calldata (no embedding!)
        bytes memory initCode = abi.encodePacked(
            paymasterParams.paymasterBytecode,
            abi.encode(paymasterParams.entryPoint, address(hats), topHatId) // Constructor args
        );

        assembly {
            paymasterHub := create(0, add(initCode, 0x20), mload(initCode))
            if iszero(paymasterHub) { revert(0, 0) }
        }

        // Emit paymaster deployment event
        emit PaymasterDeployed(params.orgId, paymasterHub, paymasterParams.entryPoint);

        // Reset reentrancy guard
        l._status = 1;

        return (result, paymasterHub);
    }

    /**
     * @notice Deploys a PaymasterHub for an existing organization
     * @dev Can be called after deployFullOrg() to add gas sponsorship capability
     * @param orgId Organization identifier (must exist)
     * @param paymasterBytecode PaymasterHub creation bytecode
     * @param entryPoint ERC-4337 EntryPoint address
     * @return paymasterHub Deployed PaymasterHub address
     */
    function deployPaymasterForOrg(bytes32 orgId, bytes calldata paymasterBytecode, address entryPoint)
        external
        returns (address paymasterHub)
    {
        Layout storage l = _layout();

        // Verify org exists
        if (!_orgExists(orgId)) revert OrgExistsMismatch();

        // Get topHatId from org registry
        uint256 topHatId = l.orgRegistry.getTopHat(orgId);

        // Deploy PaymasterHub using bytecode from calldata
        bytes memory initCode = abi.encodePacked(
            paymasterBytecode,
            abi.encode(entryPoint, address(hats), topHatId) // Constructor args
        );

        assembly {
            paymasterHub := create(0, add(initCode, 0x20), mload(initCode))
            if iszero(paymasterHub) { revert(0, 0) }
        }

        // Emit paymaster deployment event
        emit PaymasterDeployed(orgId, paymasterHub, entryPoint);

        return paymasterHub;
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
        govParams.participationToken = address(0);
        govParams.autoUpgrade = params.autoUpgrade;
        govParams.hybridQuorumPct = params.hybridQuorumPct;
        govParams.ddQuorumPct = params.ddQuorumPct;
        govParams.hybridClasses = params.hybridClasses;
        govParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        govParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        govParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        govParams.ddInitialTargets = params.ddInitialTargets;
        govParams.roleNames = params.roleNames;
        govParams.roleImages = params.roleImages;
        govParams.roleCanVote = params.roleCanVote;

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
        votingParams.participationToken = participationToken;
        votingParams.autoUpgrade = params.autoUpgrade;
        votingParams.hybridQuorumPct = params.hybridQuorumPct;
        votingParams.ddQuorumPct = params.ddQuorumPct;
        votingParams.hybridClasses = params.hybridClasses;
        votingParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        votingParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        votingParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        votingParams.ddInitialTargets = params.ddInitialTargets;
        votingParams.roleNames = params.roleNames;
        votingParams.roleImages = params.roleImages;
        votingParams.roleCanVote = params.roleCanVote;

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
}
