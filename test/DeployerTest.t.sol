// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {DirectDemocracyVoting} from "../src/DirectDemocracyVoting.sol";
import {ElectionContract} from "../src/ElectionContract.sol";
// Replace NFTMembership import
import {Membership} from "../src/Membership.sol";
// Import specific contracts to avoid interface collisions
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import "../src/ImplementationRegistry.sol";
import "../src/PoaManager.sol";
import "../src/OrgRegistry.sol";
// Import the new contracts
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";
// Import only the Deployer contract to avoid interface collisions
import {Deployer} from "../src/Deployer.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract DeployerTest is Test {
    // Contracts
    DirectDemocracyVoting votingImplementation;
    ElectionContract electionImplementation;
    Membership membershipImplementation;
    Membership membershipV2Implementation;
    UniversalAccountRegistry accountRegistryImplementation;
    QuickJoin quickJoinImplementation;
    ParticipationToken participationTokenImplementation;
    TaskManager taskManagerImplementation;
    EducationHub educationHubImplementation;
    ImplementationRegistry implementationRegistry;
    PoaManager poaManager;
    OrgRegistry orgRegistry;
    Deployer deployer;

    // Test addresses
    address public poaAdmin = address(1);
    address public orgOwner = address(2);
    address public voter1 = address(3);
    address public voter2 = address(4);
    address public treasuryAddress = address(5);
    address public taskWorker = address(6);

    // Organization IDs
    bytes32 public autoUpgradeOrgId = keccak256("AutoUpgradeOrg");
    bytes32 public manualUpgradeOrgId = keccak256("ManualUpgradeOrg");
    bytes32 public fullOrgId = keccak256("FullOrg");
    bytes32 public globalRegistryId = keccak256("POA-GLOBAL-ACCOUNT-REGISTRY");

    // Proxy addresses for the organizations
    address public autoUpgradeOrgProxy;
    address public manualUpgradeOrgProxy;
    address public accountRegistryProxy;

    function setUp() public {
        // Deploy implementations
        votingImplementation = new DirectDemocracyVoting();
        electionImplementation = new ElectionContract();
        membershipImplementation = new Membership();
        membershipV2Implementation = new Membership();
        accountRegistryImplementation = new UniversalAccountRegistry();
        quickJoinImplementation = new QuickJoin();
        participationTokenImplementation = new ParticipationToken();
        taskManagerImplementation = new TaskManager();
        educationHubImplementation = new EducationHub();

        vm.startPrank(poaAdmin);

        // Deploy the ImplementationRegistry
        implementationRegistry = new ImplementationRegistry();

        // Deploy the PoaManager with the implementation registry
        poaManager = new PoaManager(address(implementationRegistry));

        // Deploy the OrgRegistry
        orgRegistry = new OrgRegistry();

        // Deploy the Deployer contract with references to PoaManager and OrgRegistry
        deployer = new Deployer(address(poaManager), address(orgRegistry));

        // Transfer ownership of the registries
        orgRegistry.transferOwnership(address(deployer));
        implementationRegistry.transferOwnership(address(poaManager));

        // Add contract types and register initial implementations
        poaManager.addContractType("DirectDemocracyVoting", address(votingImplementation));
        poaManager.addContractType("ElectionContract", address(electionImplementation));
        poaManager.addContractType("Membership", address(membershipImplementation));
        poaManager.addContractType("QuickJoin", address(quickJoinImplementation));
        poaManager.addContractType("UniversalAccountRegistry", address(accountRegistryImplementation));
        poaManager.addContractType("ParticipationToken", address(participationTokenImplementation));
        poaManager.addContractType("TaskManager", address(taskManagerImplementation));
        poaManager.addContractType("EducationHub", address(educationHubImplementation));

        // Deploy global UniversalAccountRegistry
        address accountRegistryBeacon = poaManager.getBeacon("UniversalAccountRegistry");
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address)",
            poaAdmin // Account registry owned by POA admin
        );
        BeaconProxy registryProxy = new BeaconProxy(accountRegistryBeacon, initData);
        accountRegistryProxy = address(registryProxy);

        vm.stopPrank();
    }

    function testFullOrgDeployWithAutoUpgrade() public {
        // 1. Deploy an organization with auto-upgrade enabled using deployFullOrg
        vm.startPrank(orgOwner);
        (
            address votingProxy,
            address electionProxy,
            address membershipProxy,
            address quickJoinProxy,
            address participationTokenProxy,
            address taskManagerProxy,
            address educationHubProxy
        ) = deployer.deployFullOrg(
            autoUpgradeOrgId, // Org ID
            orgOwner, // Org Owner
            "Auto Upgrade Organization", // Org Name
            accountRegistryProxy, // Use existing registry
            treasuryAddress, // Treasury address
            true // Auto-upgrade enabled
        );
        autoUpgradeOrgProxy = votingProxy; // Store the voting proxy address
        vm.stopPrank();

        // 2. Verify all contracts have been properly stored in the registry
        address votingContractAddress = orgRegistry.getOrgContract(autoUpgradeOrgId, "DirectDemocracyVoting");
        assertEq(votingContractAddress, votingProxy, "Voting BeaconProxy address mismatch");

        address participationTokenAddress = orgRegistry.getOrgContract(autoUpgradeOrgId, "ParticipationToken");
        assertEq(participationTokenAddress, participationTokenProxy, "ParticipationToken BeaconProxy address mismatch");

        address taskManagerAddress = orgRegistry.getOrgContract(autoUpgradeOrgId, "TaskManager");
        assertEq(taskManagerAddress, taskManagerProxy, "TaskManager BeaconProxy address mismatch");

        // Get contract details for voting
        bytes32 votingTypeId = keccak256(bytes("DirectDemocracyVoting"));
        bytes32 votingContractId = keccak256(abi.encodePacked(autoUpgradeOrgId, votingTypeId));
        (address votingBeaconProxy, address votingBeacon, bool votingAutoUpgrade, address votingOwner) =
            orgRegistry.contractOf(votingContractId);

        assertEq(votingBeaconProxy, autoUpgradeOrgProxy, "Voting BeaconProxy address mismatch");
        assertEq(votingBeacon, poaManager.getBeacon("DirectDemocracyVoting"), "Voting Beacon address mismatch");
        assertTrue(votingAutoUpgrade, "Voting Auto-upgrade should be enabled");
        assertEq(votingOwner, orgOwner, "Voting Owner address mismatch");

        // Get contract details for ParticipationToken
        bytes32 tokenTypeId = keccak256(bytes("ParticipationToken"));
        bytes32 tokenContractId = keccak256(abi.encodePacked(autoUpgradeOrgId, tokenTypeId));
        (address tokenBeaconProxy, address tokenBeacon, bool tokenAutoUpgrade, address tokenOwner) =
            orgRegistry.contractOf(tokenContractId);

        assertEq(tokenBeaconProxy, participationTokenProxy, "Token BeaconProxy address mismatch");
        assertEq(tokenBeacon, poaManager.getBeacon("ParticipationToken"), "Token Beacon address mismatch");
        assertTrue(tokenAutoUpgrade, "Token Auto-upgrade should be enabled");
        assertEq(tokenOwner, orgOwner, "Token Owner address mismatch");

        // Get contract details for TaskManager
        bytes32 taskTypeId = keccak256(bytes("TaskManager"));
        bytes32 taskContractId = keccak256(abi.encodePacked(autoUpgradeOrgId, taskTypeId));
        (address taskBeaconProxy, address taskBeacon, bool taskAutoUpgrade, address taskOwner) =
            orgRegistry.contractOf(taskContractId);

        assertEq(taskBeaconProxy, taskManagerProxy, "Task BeaconProxy address mismatch");
        assertEq(taskBeacon, poaManager.getBeacon("TaskManager"), "Task Beacon address mismatch");
        assertTrue(taskAutoUpgrade, "Task Auto-upgrade should be enabled");
        assertEq(taskOwner, orgOwner, "Task Owner address mismatch");

        // Get contract details for EducationHub
        bytes32 educationTypeId = keccak256(bytes("EducationHub"));
        bytes32 educationContractId = keccak256(abi.encodePacked(autoUpgradeOrgId, educationTypeId));
        (address educationBeaconProxy, address educationBeacon, bool educationAutoUpgrade, address educationOwner) =
            orgRegistry.contractOf(educationContractId);

        assertEq(educationBeaconProxy, educationHubProxy, "EducationHub BeaconProxy address mismatch");
        assertEq(educationBeacon, poaManager.getBeacon("EducationHub"), "EducationHub Beacon address mismatch");
        assertTrue(educationAutoUpgrade, "EducationHub Auto-upgrade should be enabled");
        assertEq(educationOwner, orgOwner, "EducationHub Owner address mismatch");

        // 3. Initialize the contract instances
        DirectDemocracyVoting votingContract = DirectDemocracyVoting(autoUpgradeOrgProxy);
        ElectionContract electionContract = ElectionContract(electionProxy);
        Membership membershipContract = Membership(membershipProxy);
        ParticipationToken tokenContract = ParticipationToken(participationTokenProxy);
        TaskManager taskManagerContract = TaskManager(taskManagerProxy);
        EducationHub educationHubContract = EducationHub(educationHubProxy);
        // Verify implementation versions
        assertEq(votingContract.version(), "v1", "Should be using Voting V1 implementation");
        assertEq(tokenContract.version(), "v1", "Should be using Token V1 implementation");
        assertEq(taskManagerContract.version(), "v1", "Should be using TaskManager V1 implementation");
        assertEq(educationHubContract.version(), "v1", "Should be using EducationHub V1 implementation");
        // 4. Set up memberships
        vm.startPrank(orgOwner);
        membershipContract.setRoleImage(keccak256("EXECUTIVE"), "https://example.com/executive.png");
        membershipContract.setRoleImage(keccak256("DEFAULT"), "https://example.com/default.png");
        vm.stopPrank();

        // Onboard users
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter1Username");

        vm.prank(voter2);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter2Username");

        vm.prank(taskWorker);
        QuickJoin(quickJoinProxy).quickJoinNoUser("TaskWorkerUsername");

        // Verify the roles
        assertTrue(
            membershipContract.isExecutiveRole(membershipContract.roleOf(voter1)), "Voter1 should be an executive"
        );
        bytes32 voter2Role = membershipContract.roleOf(voter2);
        assertTrue(
            keccak256("DEFAULT") == voter2Role || keccak256("Member") == voter2Role, "Voter2 should be a default member"
        );

        // 5. Test ParticipationToken functionality
        // Check token info
        assertEq(tokenContract.name(), "Auto Upgrade Organization Token", "Token name should match");
        assertEq(tokenContract.symbol(), "TKN", "Token symbol should match");

        // Check initial balance
        assertEq(tokenContract.balanceOf(voter1), 0, "Initial token balance should be zero");

        // 6. Test TaskManager functionality
        // Create a task
        vm.startPrank(voter1); // Use executive role to create task

        string memory ipfsHash = "QmTaskHashExample";
        string memory projectName = "Test Project";
        uint256 payoutAmount = 100;

        taskManagerContract.createTask(payoutAmount, ipfsHash, projectName);

        uint256 taskId = 0; // First task

        // Claim the task as taskWorker
        vm.stopPrank();
        vm.prank(taskWorker);
        taskManagerContract.claimTask(taskId);

        // Submit task completion
        vm.prank(taskWorker);
        taskManagerContract.submitTask(taskId, "QmCompletionProofHash");

        // Verify task completion as executive
        vm.prank(voter1);
        taskManagerContract.completeTask(taskId);

        // Check that tokens were minted to taskWorker
        assertEq(tokenContract.balanceOf(taskWorker), payoutAmount, "Task worker should receive tokens");

        // Test EducationHub functionality
        vm.startPrank(voter1);
        educationHubContract.createModule("QmModuleHashExample", 100, 1);
        educationHubContract.completeModule(0, 1);
        assertEq(tokenContract.balanceOf(voter1), 100, "Voter1 should receive tokens from module completion");
        vm.stopPrank();

        // Continue with voting tests...
        vm.startPrank(voter1);

        // Create a proposal with election enabled
        string memory proposalName = "Test Proposal";
        string memory proposalDesc = "Testing the voting system";
        uint256 timeInMinutes = 60; // 1 hour voting duration

        // Option names
        string[] memory optionNames = new string[](2);
        optionNames[0] = "Option A";
        optionNames[1] = "Option B";

        // Transfer settings (not used in this test)
        uint256 transferTriggerOptionIndex = 0;
        address payable transferRecipient = payable(address(0));
        uint256 transferAmount = 0;
        bool transferEnabled = false;
        address transferToken = address(0);
        DirectDemocracyVoting.TokenType tokenType = DirectDemocracyVoting.TokenType.ETHER;

        // Election settings
        bool electionEnabled = true;

        // Candidate information
        address[] memory candidateAddresses = new address[](2);
        candidateAddresses[0] = voter1;
        candidateAddresses[1] = voter2;

        string[] memory candidateNames = new string[](2);
        candidateNames[0] = "Candidate 1";
        candidateNames[1] = "Candidate 2";

        // Create the proposal
        votingContract.createProposal(
            proposalName,
            proposalDesc,
            timeInMinutes,
            optionNames,
            transferTriggerOptionIndex,
            transferRecipient,
            transferAmount,
            transferEnabled,
            transferToken,
            tokenType,
            electionEnabled,
            candidateAddresses,
            candidateNames
        );

        // Verify proposal creation
        uint256 proposalsCount = votingContract.proposalsCount();
        assertEq(proposalsCount, 1, "Should have 1 proposal");

        // Vote on the proposal
        uint256 proposalId = 0; // First proposal

        // Cast votes from two different voters with different weights for each option
        uint256[] memory optionIndices = new uint256[](1);
        optionIndices[0] = 0; // Voting for Option A

        uint256[] memory weights = new uint256[](1);
        weights[0] = 100; // 100% of weight on Option A

        // Vote as voter1
        votingContract.vote(proposalId, optionIndices, weights);
        vm.stopPrank();

        // Vote as voter2 for Option B
        vm.startPrank(voter2);
        optionIndices[0] = 1; // Voting for Option B
        votingContract.vote(proposalId, optionIndices, weights);
        vm.stopPrank();

        // Verify vote counts
        uint256 optionAVotes = votingContract.getOptionVotes(proposalId, 0);
        uint256 optionBVotes = votingContract.getOptionVotes(proposalId, 1);
        assertEq(optionAVotes, 100, "Option A should have 100 votes");
        assertEq(optionBVotes, 100, "Option B should have 100 votes");
    }

    function testRegistryOperations() public {
        // Check the initial version of an implementation
        address impl = implementationRegistry.getLatestImplementation("DirectDemocracyVoting");
        assertEq(impl, address(votingImplementation), "Latest implementation should be correct");

        // Check version info using existing methods
        address storedImpl = implementationRegistry.getImplementation("DirectDemocracyVoting", "v1");
        address latestImpl = implementationRegistry.getLatestImplementation("DirectDemocracyVoting");
        assertEq(storedImpl, address(votingImplementation), "Implementation address should match");
        assertTrue(storedImpl == latestImpl, "Should be marked as latest version");
    }

    /**
     * @notice Helper to convert bytes32 to string
     */
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while (i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < bytesArray.length; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }
}
