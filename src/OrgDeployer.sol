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
        address executor;
        address quickJoin;
        address participationToken;
        address taskManager;
        address educationHub;
        address paymentManager;
    }

    struct RoleAssignments {
        uint256[] quickJoinRoles;
        uint256[] tokenMemberRoles;
        uint256[] tokenApproverRoles;
        uint256[] taskCreatorRoles;
        uint256[] educationCreatorRoles;
        uint256[] educationMemberRoles;
        uint256[] proposalCreatorRoles;
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

    /*════════════════  MAIN DEPLOYMENT FUNCTION  ════════════════*/

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
    ) external returns (DeploymentResult memory result) {
        // Manual reentrancy guard
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

        result = _deployFullOrgInternal(params);

        // Reset reentrancy guard
        l._status = 1;

        return result;
    }

    /*════════════════  INTERNAL ORCHESTRATION  ════════════════*/

    function _deployFullOrgInternal(DeploymentParams memory params) internal returns (DeploymentResult memory result) {
        Layout storage l = _layout();

        /* 1. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName));
        } else {
            revert OrgExistsMismatch();
        }

        /* 2. Deploy Governance Infrastructure (Executor, Hats, Voting) */
        GovernanceFactory.GovernanceResult memory gov;
        {
            GovernanceFactory.GovernanceParams memory govParams = GovernanceFactory.GovernanceParams({
                orgId: params.orgId,
                orgName: params.orgName,
                poaManager: l.poaManager,
                orgRegistry: address(l.orgRegistry),
                hats: address(hats),
                hatsTreeSetup: l.hatsTreeSetup,
                deployer: address(this), // For registration callbacks
                autoUpgrade: params.autoUpgrade,
                roleNames: params.roleNames,
                roleImages: params.roleImages,
                roleCanVote: params.roleCanVote
            });

            gov = l.governanceFactory.deployGovernance(govParams);
            result.executor = gov.executor;
        }

        /* 3. Set the executor for the org */
        l.orgRegistry.setOrgExecutor(params.orgId, result.executor);

        /* 4. Register Hats tree in OrgRegistry */
        l.orgRegistry.registerHatsTree(params.orgId, gov.topHatId, gov.roleHatIds);

        /* 5. Deploy Access Infrastructure (QuickJoin, Token) */
        AccessFactory.AccessResult memory access;
        {
            AccessFactory.RoleAssignments memory accessRoles = AccessFactory.RoleAssignments({
                quickJoinRoles: params.roleAssignments.quickJoinRoles,
                tokenMemberRoles: params.roleAssignments.tokenMemberRoles,
                tokenApproverRoles: params.roleAssignments.tokenApproverRoles
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

        /* 6. Deploy Functional Modules (TaskManager, Education, Payment, Voting) */
        ModulesFactory.ModulesResult memory modules;
        {
            ModulesFactory.RoleAssignments memory moduleRoles = ModulesFactory.RoleAssignments({
                taskCreatorRoles: params.roleAssignments.taskCreatorRoles,
                educationCreatorRoles: params.roleAssignments.educationCreatorRoles,
                educationMemberRoles: params.roleAssignments.educationMemberRoles,
                proposalCreatorRoles: params.roleAssignments.proposalCreatorRoles,
                tokenMemberRoles: params.roleAssignments.tokenMemberRoles
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
                quorumPct: params.quorumPct,
                votingClasses: params.votingClasses,
                roleAssignments: moduleRoles
            });

            modules = l.modulesFactory.deployModules(moduleParams);
            result.taskManager = modules.taskManager;
            result.educationHub = modules.educationHub;
            result.paymentManager = modules.paymentManager;
            result.hybridVoting = modules.hybridVoting;
        }

        /* 7. Wire up cross-module connections */
        IParticipationToken(result.participationToken).setTaskManager(result.taskManager);
        IParticipationToken(result.participationToken).setEducationHub(result.educationHub);

        /* 8. Authorize QuickJoin to mint hats */
        IExecutorAdmin(result.executor).setHatMinterAuthorization(result.quickJoin, true);

        /* 9. Link executor to governor */
        IExecutorAdmin(result.executor).setCaller(result.hybridVoting);

        /* 10. Renounce executor ownership - now only governed by voting */
        OwnableUpgradeable(result.executor).renounceOwnership();

        /* 11. Emit event for subgraph indexing */
        emit OrgDeployed(
            params.orgId,
            result.executor,
            result.hybridVoting,
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
}
