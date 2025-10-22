// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

import {OrgDeployer} from "../src/OrgDeployer.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {HybridVoting} from "../src/HybridVoting.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {Executor, IExecutor} from "../src/Executor.sol";
import {IHybridVotingInit} from "../src/libs/ModuleDeploymentLib.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";

/**
 * @title RunOrgActions
 * @notice Comprehensive script demonstrating organization actions after deployment
 * @dev Showcases TaskManager, HybridVoting, and other module interactions
 *
 * This script demonstrates:
 * 1. Organization deployment
 * 2. Member onboarding (QuickJoin + hat minting)
 * 3. Participation token management
 * 4. Task creation and lifecycle (TaskManager)
 * 5. Project creation and role permissions
 * 6. Proposal creation and voting (HybridVoting)
 * 7. Proposal execution through governance
 *
 * Usage:
 *   # First deploy infrastructure (if not already deployed)
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $RPC_URL --broadcast
 *
 *   # Then run this script to demonstrate org actions
 *   forge script script/RunOrgActions.s.sol:RunOrgActions \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --slow
 *
 * Environment Variables Required:
 *   - DEPLOYER_PRIVATE_KEY: Private key for deployment and funding demo accounts
 *   - ORG_CONFIG_PATH: (Optional) Path to org config (default: script/org-config-governance-demo.json)
 *
 * Note: Script automatically generates ephemeral test accounts - no need for multiple private keys!
 *
 * Note: Run with --slow flag to give block time between actions
 */
contract RunOrgActions is Script {
    /*=========================== STRUCTS ===========================*/

    // JSON parsing structs - must match org config JSON structure
    struct OrgConfigJson {
        string orgId;
        string orgName;
        bool autoUpgrade;
        QuorumConfig quorum;
        RoleConfig[] roles;
        VotingClassConfig[] votingClasses;
        RoleAssignmentsConfig roleAssignments;
        address[] ddInitialTargets;
        bool withPaymaster;
    }

    struct QuorumConfig {
        uint8 hybrid;
        uint8 directDemocracy;
    }

    struct RoleConfig {
        string name;
        string image;
        bool canVote;
    }

    struct VotingClassConfig {
        string strategy;
        uint8 slicePct;
        bool quadratic;
        uint256 minBalance;
        address asset;
        uint256[] hatIds;
    }

    struct RoleAssignmentsConfig {
        uint256[] quickJoinRoles;
        uint256[] tokenMemberRoles;
        uint256[] tokenApproverRoles;
        uint256[] taskCreatorRoles;
        uint256[] educationCreatorRoles;
        uint256[] educationMemberRoles;
        uint256[] hybridProposalCreatorRoles;
        uint256[] ddVotingRoles;
        uint256[] ddCreatorRoles;
    }

    struct OrgContracts {
        address executor;
        address hybridVoting;
        address directDemocracyVoting;
        address quickJoin;
        address participationToken;
        address taskManager;
        address educationHub;
        address paymentManager;
        uint256 topHatId;
        uint256[] roleHatIds;
    }

    struct MemberAddresses {
        address deployer;
        address member1;
        address member2;
        address coordinator;
        address admin;
    }

    struct MemberKeys {
        uint256 member1;
        uint256 member2;
        uint256 coordinator;
    }

    /*=========================== STATE ===========================*/

    bytes32 public orgId;
    OrgContracts public org;
    MemberAddresses public members;
    MemberKeys public memberKeys;
    IHats public hats;

    /*=========================== MAIN ===========================*/

    function run() public {
        console.log("\n========================================================");
        console.log("   POA Organization Actions Demo                       ");
        console.log("========================================================\n");

        // Step 1: Deploy Organization
        _deployOrganization();

        // Step 2: Onboard Members
        _onboardMembers();

        // Step 3: Distribute Participation Tokens
        _distributeTokens();

        // Step 4: Create Project and Tasks
        _demonstrateTaskManager();

        // Step 5: Create and Execute Governance Proposal
        _demonstrateGovernance();

        console.log("\n========================================================");
        console.log("   Demo Complete! All Actions Executed Successfully    ");
        console.log("========================================================\n");
    }

    /*=========================== STEP 1: DEPLOY ===========================*/

    function _deployOrganization() internal {
        console.log("=======================================================");
        console.log("STEP 1: Deploying Organization");
        console.log("=======================================================\n");

        // Read infrastructure addresses
        string memory infraJson = vm.readFile("script/infrastructure.json");
        address orgDeployerAddr = vm.parseJsonAddress(infraJson, ".orgDeployer");
        address globalAccountRegistry = vm.parseJsonAddress(infraJson, ".globalAccountRegistry");
        address hatsAddr = vm.parseJsonAddress(infraJson, ".hatsProtocol");
        address orgRegistryAddr = vm.parseJsonAddress(infraJson, ".orgRegistry");

        require(orgDeployerAddr != address(0), "OrgDeployer not found - deploy infrastructure first");

        hats = IHats(hatsAddr);

        // Get org config path
        string memory configPath = vm.envOr("ORG_CONFIG_PATH", string("script/org-config-governance-demo.json"));

        // Load member addresses
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        members.deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer Address:", members.deployer);
        console.log("OrgDeployer Contract:", orgDeployerAddr);
        console.log("Config Path:", configPath);

        // Parse config
        string memory configJson = vm.readFile(configPath);
        OrgConfigJson memory config = _parseOrgConfig(configJson);

        orgId = keccak256(bytes(config.orgId));

        console.log("\nOrganization:");
        console.log("  ID:", config.orgId);
        console.log("  Name:", config.orgName);
        console.log("  Roles:", config.roles.length);
        console.log("  Voting Classes:", config.votingClasses.length);

        // Build deployment params (deployer will receive ADMIN hat)
        OrgDeployer.DeploymentParams memory params = _buildDeploymentParams(config, globalAccountRegistry, members.deployer);

        // Deploy
        vm.startBroadcast(deployerPrivateKey);

        OrgDeployer orgDeployer = OrgDeployer(orgDeployerAddr);
        OrgDeployer.DeploymentResult memory result = orgDeployer.deployFullOrg(params);

        vm.stopBroadcast();

        // Store org contracts
        org.executor = result.executor;
        org.hybridVoting = result.hybridVoting;
        org.directDemocracyVoting = result.directDemocracyVoting;
        org.quickJoin = result.quickJoin;
        org.participationToken = result.participationToken;
        org.taskManager = result.taskManager;
        org.educationHub = result.educationHub;
        org.paymentManager = result.paymentManager;

        // Get role hat IDs from OrgRegistry
        OrgRegistry orgRegistry = OrgRegistry(orgRegistryAddr);
        org.roleHatIds = new uint256[](4); // 4 roles in config
        org.roleHatIds[0] = orgRegistry.getRoleHat(orgId, 0); // MEMBER
        org.roleHatIds[1] = orgRegistry.getRoleHat(orgId, 1); // COORDINATOR
        org.roleHatIds[2] = orgRegistry.getRoleHat(orgId, 2); // CONTRIBUTOR
        org.roleHatIds[3] = orgRegistry.getRoleHat(orgId, 3); // ADMIN

        console.log("\n[OK] Organization Deployed Successfully");
        console.log("  Executor:", org.executor);
        console.log("  HybridVoting:", org.hybridVoting);
        console.log("  TaskManager:", org.taskManager);
        console.log("  ParticipationToken:", org.participationToken);
        console.log("  QuickJoin:", org.quickJoin);
        console.log("  Role Hat IDs:", org.roleHatIds.length);
    }

    /*=========================== STEP 2: ONBOARD ===========================*/

    function _onboardMembers() internal {
        console.log("\n=======================================================");
        console.log("STEP 2: Onboarding Members");
        console.log("=======================================================\n");

        // Generate ephemeral accounts for demo (no need to store private keys!)
        console.log("-> Generating ephemeral test accounts...");

        (members.member1, memberKeys.member1) = makeAddrAndKey("member1-ephemeral");
        (members.member2, memberKeys.member2) = makeAddrAndKey("member2-ephemeral");
        (members.coordinator, memberKeys.coordinator) = makeAddrAndKey("coordinator-ephemeral");

        console.log("Member 1:", members.member1);
        console.log("Member 2:", members.member2);
        console.log("Coordinator:", members.coordinator);

        // Fund accounts with gas money from deployer
        uint256 gasAllowance = 0.01 ether; // ~$30 worth, enough for demo
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("\n-> Funding test accounts from deployer...");
        vm.startBroadcast(deployerKey);
        payable(members.member1).transfer(gasAllowance);
        payable(members.member2).transfer(gasAllowance);
        payable(members.coordinator).transfer(gasAllowance);
        vm.stopBroadcast();

        console.log("  [OK] Each account funded with", gasAllowance / 1e18, "ETH");

        QuickJoin quickJoin = QuickJoin(org.quickJoin);

        // Member 1 joins (will get MEMBER role - role index 0)
        console.log("\n-> Member 1 joining...");
        vm.broadcast(memberKeys.member1);
        quickJoin.quickJoinNoUser("member1");
        console.log("  [OK] Joined successfully");

        // Member 2 joins
        console.log("-> Member 2 joining...");
        vm.broadcast(memberKeys.member2);
        quickJoin.quickJoinNoUser("member2");
        console.log("  [OK] Joined successfully");

        // Coordinator joins
        console.log("-> Coordinator joining...");
        vm.broadcast(memberKeys.coordinator);
        quickJoin.quickJoinNoUser("coordinator");
        console.log("  [OK] Joined successfully");

        console.log("\n[OK] All Members Onboarded");
        console.log("  (Note: All members have MEMBER role with full demo permissions)");
    }

    /*=========================== STEP 3: TOKENS ===========================*/

    function _distributeTokens() internal {
        console.log("\n=======================================================");
        console.log("STEP 3: Distributing Participation Tokens");
        console.log("=======================================================\n");

        ParticipationToken token = ParticipationToken(org.participationToken);

        console.log("Token Address:", address(token));
        console.log("Token Name:", token.name());
        console.log("Token Symbol:", token.symbol());

        // Members request tokens
        console.log("\n-> Member 1 requesting tokens...");
        vm.broadcast(memberKeys.member1);
        token.requestTokens(10 ether, "Initial token request for participation");
        console.log("  [OK] Requested 10 tokens");

        console.log("-> Member 2 requesting tokens...");
        vm.broadcast(memberKeys.member2);
        token.requestTokens(10 ether, "Initial token request for participation");
        console.log("  [OK] Requested 10 tokens");

        console.log("-> Coordinator requesting tokens...");
        vm.broadcast(memberKeys.coordinator);
        token.requestTokens(20 ether, "Coordinator token request");
        console.log("  [OK] Requested 20 tokens");

        // Note: In production, an approver would need to approve these requests
        // For demo purposes, we're showing the request flow
        // Approval would require: token.approveRequest(requestId)

        console.log("\n[OK] Token Distribution Initiated");
        console.log("  (Note: Requests pending approval from token approver)");
    }

    /*=========================== STEP 4: TASK MANAGER ===========================*/

    function _demonstrateTaskManager() internal {
        console.log("\n=======================================================");
        console.log("STEP 4: Demonstrating Task Manager");
        console.log("=======================================================\n");

        TaskManager tm = TaskManager(org.taskManager);

        console.log("TaskManager Address:", address(tm));

        // Create a project
        console.log("\n-> Coordinator creating project...");

        address[] memory managers = new address[](0);
        uint256[] memory emptyHats = new uint256[](0);

        // Set up task permissions: MEMBER, COORDINATOR, and ADMIN can claim tasks
        uint256[] memory claimHats = new uint256[](3);
        claimHats[0] = org.roleHatIds[0]; // MEMBER
        claimHats[1] = org.roleHatIds[1]; // COORDINATOR
        claimHats[2] = org.roleHatIds[3]; // ADMIN

        vm.broadcast(memberKeys.coordinator);
        bytes32 projectId = tm.createProject(
            abi.encode("metadata", "Building core governance infrastructure for the cooperative"),
            1000 ether, // Project cap
            managers,
            emptyHats, // createHats
            claimHats, // claimHats - MEMBER, COORDINATOR, ADMIN can claim
            emptyHats, // reviewHats
            emptyHats // assignHats
        );

        console.log("  [OK] Project Created");
        console.log("  Project ID:", vm.toString(uint256(projectId)));

        // Create tasks in the project
        // Note: Task IDs auto-increment starting from 0
        console.log("\n-> Creating Task 0: Deploy Voting System");
        vm.broadcast(memberKeys.coordinator);
        tm.createTask(
            10 ether, // payout in participation tokens
            abi.encode("task", "voting-deployment"),
            projectId,
            address(0), // bountyToken (0 = no bounty)
            0, // bountyPayout
            false // requiresApplication (can be claimed directly)
        );
        uint256 task0 = 0; // First task ID starts at 0
        console.log("  [OK] Task 0 Created");

        console.log("-> Creating Task 1: Documentation");
        vm.broadcast(memberKeys.coordinator);
        tm.createTask(
            5 ether, // payout
            abi.encode("task", "docs"),
            projectId,
            address(0),
            0,
            true // Requires application for this one
        );
        uint256 task1 = 1; // Second task ID
        console.log("  [OK] Task 1 Created");

        // Member 1 claims task 0 (directly claimable)
        console.log("\n-> Member 1 claiming Task 0...");
        vm.broadcast(memberKeys.member1);
        tm.claimTask(task0);
        console.log("  [OK] Task 0 Claimed");

        // Member 2 applies for task 1 (requires application)
        console.log("-> Member 2 applying for Task 1...");
        vm.broadcast(memberKeys.member2);
        tm.applyForTask(task1, keccak256("application-details-member2"));
        console.log("  [OK] Application Submitted");

        // Coordinator approves Member 2's application
        console.log("-> Coordinator approving Member 2 for Task 1...");
        vm.broadcast(memberKeys.coordinator);
        tm.approveApplication(task1, members.member2);
        console.log("  [OK] Application Approved, Task Assigned");

        // Members submit task work
        console.log("\n-> Member 1 submitting Task 0...");
        vm.broadcast(memberKeys.member1);
        tm.submitTask(task0, abi.encode("submission", "voting-system-deployed"));
        console.log("  [OK] Task 0 Submitted for Review");

        console.log("-> Member 2 submitting Task 1...");
        vm.broadcast(memberKeys.member2);
        tm.submitTask(task1, abi.encode("submission", "documentation-complete"));
        console.log("  [OK] Task 1 Submitted for Review");

        // Coordinator completes tasks (approves the submissions)
        console.log("\n-> Coordinator completing Task 0...");
        vm.broadcast(memberKeys.coordinator);
        tm.completeTask(task0);
        console.log("  [OK] Task 0 Completed");

        console.log("-> Coordinator completing Task 1...");
        vm.broadcast(memberKeys.coordinator);
        tm.completeTask(task1);
        console.log("  [OK] Task 1 Completed");

        console.log("\n[OK] Task Manager Demonstration Complete");
        console.log("  Project Created: 1");
        console.log("  Tasks Completed: 2");
    }

    /*=========================== STEP 5: GOVERNANCE ===========================*/

    function _demonstrateGovernance() internal {
        console.log("\n=======================================================");
        console.log("STEP 5: Demonstrating Governance (HybridVoting)");
        console.log("=======================================================\n");

        HybridVoting voting = HybridVoting(org.hybridVoting);
        Executor executor = Executor(payable(org.executor));

        console.log("HybridVoting Address:", address(voting));
        console.log("Executor Address:", address(executor));

        // Create a governance signaling proposal
        // This demonstrates the voting mechanism without executing onchain actions

        console.log("\n-> Coordinator creating governance proposal...");

        // Create a governance proposal (signaling poll)
        // This demonstrates the HybridVoting mechanism
        // Note: Executable proposals require targets to be in HybridVoting's allowedTarget list
        // Only Executor is in the allowlist by default

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);

        // Both options have empty batches (this is a signaling vote)
        batches[0] = new IExecutor.Call[](0); // Option 0: YES
        batches[1] = new IExecutor.Call[](0); // Option 1: NO

        uint256[] memory emptyHatIds = new uint256[](0);

        vm.broadcast(memberKeys.coordinator);
        voting.createProposal(
            abi.encode("ipfs://proposal-update-task-timeout"),
            4320, // 3 days in minutes
            2, // 2 options (YES/NO)
            batches,
            emptyHatIds // No hat restrictions
        );

        uint256 proposalId = voting.proposalsCount() - 1;

        console.log("  [OK] Proposal Created (ID:", proposalId, ")");
        console.log("  Description: Signaling Vote - Should we update task timeout?");
        console.log("  Type: Non-executable (signaling poll)");
        console.log("  Duration: 3 days");

        // Members vote on the proposal
        // Vote format: vote(proposalId, optionIndices[], optionWeights[])
        // optionIndices: which options you're voting for (0=YES, 1=NO)
        // optionWeights: weight for each option (must sum to 100)

        console.log("\n-> Member 1 voting YES (100%)...");
        uint8[] memory yesOption = new uint8[](1);
        yesOption[0] = 0; // Option 0 = YES

        uint8[] memory fullWeight = new uint8[](1);
        fullWeight[0] = 100; // 100% weight to YES

        vm.broadcast(memberKeys.member1);
        voting.vote(proposalId, yesOption, fullWeight);
        console.log("  [OK] Vote Cast");

        console.log("-> Member 2 voting YES (100%)...");
        vm.broadcast(memberKeys.member2);
        voting.vote(proposalId, yesOption, fullWeight);
        console.log("  [OK] Vote Cast");

        console.log("-> Coordinator voting YES (100%)...");
        vm.broadcast(memberKeys.coordinator);
        voting.vote(proposalId, yesOption, fullWeight);
        console.log("  [OK] Vote Cast");

        // In production, we would need to:
        // 1. Wait for voting deadline to pass
        // 2. Call voting.announce(proposalId) to finalize voting
        // 3. Call executor.execute(...) to execute the proposal
        // For this demo, we're showing the voting flow

        console.log("\n[OK] Governance Demonstration Complete");
        console.log("  Proposal Created: 1");
        console.log("  Votes Cast: 3");
        console.log("  (Note: Execution requires waiting for deadline + announce + execute)");
    }

    /*=========================== CONFIG PARSING ===========================*/

    function _parseOrgConfig(string memory configJson) internal returns (OrgConfigJson memory config) {
        // Parse top-level fields
        config.orgId = vm.parseJsonString(configJson, ".orgId");
        config.orgName = vm.parseJsonString(configJson, ".orgName");
        config.autoUpgrade = vm.parseJsonBool(configJson, ".autoUpgrade");
        config.withPaymaster = vm.parseJsonBool(configJson, ".withPaymaster");

        // Parse quorum
        config.quorum.hybrid = uint8(vm.parseJsonUint(configJson, ".quorum.hybrid"));
        config.quorum.directDemocracy = uint8(vm.parseJsonUint(configJson, ".quorum.directDemocracy"));

        // Parse roles array
        uint256 rolesLength = 0;
        for (uint256 i = 0; i < 100; i++) { // reasonable max
            try vm.parseJsonString(
                configJson, string.concat(".roles[", vm.toString(i), "].name")
            ) returns (string memory) {
                rolesLength++;
            } catch {
                break;
            }
        }

        config.roles = new RoleConfig[](rolesLength);
        for (uint256 i = 0; i < rolesLength; i++) {
            string memory basePath = string.concat(".roles[", vm.toString(i), "]");
            config.roles[i].name = vm.parseJsonString(configJson, string.concat(basePath, ".name"));
            config.roles[i].image = vm.parseJsonString(configJson, string.concat(basePath, ".image"));
            config.roles[i].canVote = vm.parseJsonBool(configJson, string.concat(basePath, ".canVote"));
        }

        // Parse voting classes array
        uint256 votingClassesLength = 0;
        for (uint256 i = 0; i < 100; i++) { // reasonable max
            try vm.parseJsonString(
                configJson, string.concat(".votingClasses[", vm.toString(i), "].strategy")
            ) returns (string memory) {
                votingClassesLength++;
            } catch {
                break;
            }
        }

        config.votingClasses = new VotingClassConfig[](votingClassesLength);
        for (uint256 i = 0; i < votingClassesLength; i++) {
            string memory basePath = string.concat(".votingClasses[", vm.toString(i), "]");
            config.votingClasses[i].strategy = vm.parseJsonString(configJson, string.concat(basePath, ".strategy"));
            config.votingClasses[i].slicePct = uint8(vm.parseJsonUint(configJson, string.concat(basePath, ".slicePct")));
            config.votingClasses[i].quadratic = vm.parseJsonBool(configJson, string.concat(basePath, ".quadratic"));
            config.votingClasses[i].minBalance = vm.parseJsonUint(configJson, string.concat(basePath, ".minBalance"));
            config.votingClasses[i].asset = vm.parseJsonAddress(configJson, string.concat(basePath, ".asset"));

            // Parse hatIds array
            bytes memory hatIdsData = vm.parseJson(configJson, string.concat(basePath, ".hatIds"));
            config.votingClasses[i].hatIds = abi.decode(hatIdsData, (uint256[]));
        }

        // Parse role assignments
        bytes memory quickJoinData = vm.parseJson(configJson, ".roleAssignments.quickJoinRoles");
        config.roleAssignments.quickJoinRoles = abi.decode(quickJoinData, (uint256[]));

        bytes memory tokenMemberData = vm.parseJson(configJson, ".roleAssignments.tokenMemberRoles");
        config.roleAssignments.tokenMemberRoles = abi.decode(tokenMemberData, (uint256[]));

        bytes memory tokenApproverData = vm.parseJson(configJson, ".roleAssignments.tokenApproverRoles");
        config.roleAssignments.tokenApproverRoles = abi.decode(tokenApproverData, (uint256[]));

        bytes memory taskCreatorData = vm.parseJson(configJson, ".roleAssignments.taskCreatorRoles");
        config.roleAssignments.taskCreatorRoles = abi.decode(taskCreatorData, (uint256[]));

        bytes memory educationCreatorData = vm.parseJson(configJson, ".roleAssignments.educationCreatorRoles");
        config.roleAssignments.educationCreatorRoles = abi.decode(educationCreatorData, (uint256[]));

        bytes memory educationMemberData = vm.parseJson(configJson, ".roleAssignments.educationMemberRoles");
        config.roleAssignments.educationMemberRoles = abi.decode(educationMemberData, (uint256[]));

        bytes memory hybridProposalData = vm.parseJson(configJson, ".roleAssignments.hybridProposalCreatorRoles");
        config.roleAssignments.hybridProposalCreatorRoles = abi.decode(hybridProposalData, (uint256[]));

        bytes memory ddVotingData = vm.parseJson(configJson, ".roleAssignments.ddVotingRoles");
        config.roleAssignments.ddVotingRoles = abi.decode(ddVotingData, (uint256[]));

        bytes memory ddCreatorData = vm.parseJson(configJson, ".roleAssignments.ddCreatorRoles");
        config.roleAssignments.ddCreatorRoles = abi.decode(ddCreatorData, (uint256[]));

        // Parse DD initial targets
        bytes memory ddTargetsData = vm.parseJson(configJson, ".ddInitialTargets");
        config.ddInitialTargets = abi.decode(ddTargetsData, (address[]));

        return config;
    }

    /*=========================== PARAM BUILDING ===========================*/

    function _roleArrayToBitmap(uint256[] memory roles) internal pure returns (uint256 bitmap) {
        for (uint256 i = 0; i < roles.length; i++) {
            require(roles[i] < 256, "Role index must be < 256");
            bitmap |= (1 << roles[i]);
        }
    }

    function _buildDeploymentParams(OrgConfigJson memory config, address globalAccountRegistry, address deployerAddress)
        internal
        pure
        returns (OrgDeployer.DeploymentParams memory params)
    {
        // Set basic params
        params.orgId = keccak256(bytes(config.orgId));
        params.orgName = config.orgName;
        params.registryAddr = globalAccountRegistry;
        params.deployerAddress = deployerAddress; // Address to receive ADMIN hat
        params.autoUpgrade = config.autoUpgrade;
        params.hybridQuorumPct = config.quorum.hybrid;
        params.ddQuorumPct = config.quorum.directDemocracy;
        params.ddInitialTargets = config.ddInitialTargets;

        // Build role arrays
        params.roleNames = new string[](config.roles.length);
        params.roleImages = new string[](config.roles.length);
        params.roleCanVote = new bool[](config.roles.length);

        for (uint256 i = 0; i < config.roles.length; i++) {
            params.roleNames[i] = config.roles[i].name;
            params.roleImages[i] = config.roles[i].image;
            params.roleCanVote[i] = config.roles[i].canVote;
        }

        // Build voting classes
        params.hybridClasses = new IHybridVotingInit.ClassConfig[](config.votingClasses.length);

        for (uint256 i = 0; i < config.votingClasses.length; i++) {
            VotingClassConfig memory vClass = config.votingClasses[i];

            IHybridVotingInit.ClassStrategy strategy;
            if (keccak256(bytes(vClass.strategy)) == keccak256(bytes("DIRECT"))) {
                strategy = IHybridVotingInit.ClassStrategy.DIRECT;
            } else if (keccak256(bytes(vClass.strategy)) == keccak256(bytes("ERC20_BAL"))) {
                strategy = IHybridVotingInit.ClassStrategy.ERC20_BAL;
            } else {
                revert("Invalid strategy: must be DIRECT or ERC20_BAL");
            }

            params.hybridClasses[i] = IHybridVotingInit.ClassConfig({
                strategy: strategy,
                slicePct: vClass.slicePct,
                quadratic: vClass.quadratic,
                minBalance: vClass.minBalance,
                asset: vClass.asset,
                hatIds: vClass.hatIds
            });
        }

        // Build role assignments (convert arrays to bitmaps)
        params.roleAssignments = OrgDeployer.RoleAssignments({
            quickJoinRolesBitmap: _roleArrayToBitmap(config.roleAssignments.quickJoinRoles),
            tokenMemberRolesBitmap: _roleArrayToBitmap(config.roleAssignments.tokenMemberRoles),
            tokenApproverRolesBitmap: _roleArrayToBitmap(config.roleAssignments.tokenApproverRoles),
            taskCreatorRolesBitmap: _roleArrayToBitmap(config.roleAssignments.taskCreatorRoles),
            educationCreatorRolesBitmap: _roleArrayToBitmap(config.roleAssignments.educationCreatorRoles),
            educationMemberRolesBitmap: _roleArrayToBitmap(config.roleAssignments.educationMemberRoles),
            hybridProposalCreatorRolesBitmap: _roleArrayToBitmap(config.roleAssignments.hybridProposalCreatorRoles),
            ddVotingRolesBitmap: _roleArrayToBitmap(config.roleAssignments.ddVotingRoles),
            ddCreatorRolesBitmap: _roleArrayToBitmap(config.roleAssignments.ddCreatorRoles)
        });

        return params;
    }
}
