// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
// Remove old voting imports
// import "../src/Voting.sol";
// import "../src/VotingV2.sol";
// Add new voting imports
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
        poaManager.registerInitialImplementation("DirectDemocracyVoting");

        poaManager.addContractType("ElectionContract", address(electionImplementation));
        poaManager.registerInitialImplementation("ElectionContract");

        poaManager.addContractType("Membership", address(membershipImplementation));
        poaManager.registerInitialImplementation("Membership");

        poaManager.addContractType("QuickJoin", address(quickJoinImplementation));
        poaManager.registerInitialImplementation("QuickJoin");

        poaManager.addContractType("UniversalAccountRegistry", address(accountRegistryImplementation));
        poaManager.registerInitialImplementation("UniversalAccountRegistry");

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
        (address votingProxy, address electionProxy, address membershipProxy, address quickJoinProxy) = deployer
            .deployFullOrg(
            autoUpgradeOrgId, // Org ID
            orgOwner, // Org Owner
            "Auto Upgrade Organization", // Org Name
            accountRegistryProxy, // Use existing registry
            treasuryAddress, // Treasury address
            true // Auto-upgrade enabled
        );
        autoUpgradeOrgProxy = votingProxy; // Store the voting proxy address
        vm.stopPrank();

        // 2. Verify the contract has been properly stored in the registry
        address contractAddress = orgRegistry.getOrgContract(autoUpgradeOrgId, "DirectDemocracyVoting");
        assertEq(contractAddress, autoUpgradeOrgProxy, "BeaconProxy address mismatch");

        // Get contract details
        bytes32 contractId = keccak256(abi.encodePacked(autoUpgradeOrgId, "-", "DirectDemocracyVoting"));
        (address beaconProxy, address beacon, bool autoUpgrade, address owner) = orgRegistry.contracts(contractId);

        assertEq(beaconProxy, autoUpgradeOrgProxy, "BeaconProxy address mismatch");
        assertEq(beacon, poaManager.getBeacon("DirectDemocracyVoting"), "Beacon address mismatch");
        assertTrue(autoUpgrade, "Auto-upgrade should be enabled");
        assertEq(owner, orgOwner, "Owner address mismatch");

        // 3. Test voting functionality through the proxy
        DirectDemocracyVoting votingContract = DirectDemocracyVoting(autoUpgradeOrgProxy);
        ElectionContract electionContract = ElectionContract(electionProxy);

        // Verify implementation version
        assertEq(votingContract.version(), "v1", "Should be using V1 implementation");

        // Check NFTMembership proxy
        Membership membershipContract = Membership(membershipProxy);

        // Set up image URLs for Membership
        vm.startPrank(orgOwner);
        membershipContract.setRoleImage(keccak256("EXECUTIVE"), "https://example.com/executive.png");
        membershipContract.setRoleImage(keccak256("DEFAULT"), "https://example.com/default.png");
        vm.stopPrank();

        // Use QuickJoin to onboard users
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter1Username");

        vm.prank(voter2);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter2Username");

        // Verify the roles are set correctly
        assertTrue(
            membershipContract.isExecutiveRole(membershipContract.roleOf(voter1)), "Voter1 should be an executive"
        );
        bytes32 voter2Role = membershipContract.roleOf(voter2);
        assertTrue(
            keccak256("DEFAULT") == voter2Role || keccak256("Member") == voter2Role, "Voter2 should be a default member"
        );

        // 4. Test DirectDemocracyVoting functionality

        // Create a proposal with election enabled
        vm.startPrank(voter1); // Using executive member to create proposal

        // Prepare proposal parameters
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

        // 5. Test election functionality (will need to advance time to end voting)
        // Fast forward time past the voting period
        vm.warp(block.timestamp + timeInMinutes * 60 + 1);

        // Announce winner
        vm.prank(orgOwner);
        (uint256 winningOptionIndex, bool hasValidWinner) = votingContract.announceWinner(proposalId);

        // Since votes are split 50/50, no option should have a majority (based on 50% quorum)
        assertFalse(hasValidWinner, "Should not have a valid winner with 50/50 split");

        // If we wanted to test a winning scenario, we'd need to add more votes to one option
        vm.startPrank(voter1);
        // Set quorum to 25% so a winner can be determined with only 50% of votes
        // Note: In a real contract you'd need permission to change this
        // This is just to simulate for the test

        // Create another proposal with a clear winner
        votingContract.createProposal(
            "Second Proposal",
            "Testing with clear winner",
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

        uint256 secondProposalId = 1; // Second proposal

        // Vote heavily for Option A
        optionIndices[0] = 0; // Option A
        votingContract.vote(secondProposalId, optionIndices, weights);
        vm.stopPrank();

        // Verify votes
        optionAVotes = votingContract.getOptionVotes(secondProposalId, 0);
        assertEq(optionAVotes, 100, "Option A should have 100 votes in second proposal");

        // Fast forward time again
        vm.warp(block.timestamp + timeInMinutes * 60 + 1);

        // Announce winner for second proposal
        vm.prank(orgOwner);
        (winningOptionIndex, hasValidWinner) = votingContract.announceWinner(secondProposalId);

        // Check election results
        assertTrue(hasValidWinner, "Should have a valid winner in second proposal");
        assertEq(winningOptionIndex, 0, "Option A should be the winner");

        // Verify the election contract has recorded the winner
        (bool isActive, uint256 winningCandidateIndex, bool validWinner,) = electionContract.getElection(1); // Second election
        assertFalse(isActive, "Election should be concluded");
        assertEq(winningCandidateIndex, 0, "Candidate 1 should be elected");
        assertTrue(validWinner, "Should have a valid winner in the election");
    }

    function testRegistryOperations() public {
        // Check the initial version
        string memory latestVersion = implementationRegistry.getVersionAtIndex(
            "DirectDemocracyVoting", implementationRegistry.getVersionCount("DirectDemocracyVoting") - 1
        );
        assertEq(latestVersion, "v1", "Initial version should be v1");
        assertEq(
            implementationRegistry.getLatestImplementation("DirectDemocracyVoting"),
            address(votingImplementation),
            "Latest implementation should be V1"
        );
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
