// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Voting.sol";
import "../src/VotingV2.sol";
import "../src/NFTMembership.sol";
// Import specific contracts to avoid interface collisions
import {DirectDemocracyToken} from "../src/DirectDemocracyToken.sol";
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
    Voting votingImplementation;
    VotingV2 votingV2Implementation;
    NFTMembership nftMembershipImplementation;
    NFTMembership nftMembershipV2Implementation;
    DirectDemocracyToken tokenImplementation;
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
        votingImplementation = new Voting();
        votingV2Implementation = new VotingV2();
        nftMembershipImplementation = new NFTMembership();
        nftMembershipV2Implementation = new NFTMembership();
        tokenImplementation = new DirectDemocracyToken();
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
        poaManager.addContractType("Voting", address(votingImplementation));
        poaManager.registerInitialImplementation("Voting");

        poaManager.addContractType("Membership", address(nftMembershipImplementation));
        poaManager.registerInitialImplementation("Membership");

        poaManager.addContractType("QuickJoin", address(quickJoinImplementation));
        poaManager.registerInitialImplementation("QuickJoin");

        poaManager.addContractType("DirectDemocracyToken", address(tokenImplementation));
        poaManager.registerInitialImplementation("DirectDemocracyToken");

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
        (address votingProxy, address membershipProxy, address quickJoinProxy, address tokenProxy) = deployer
            .deployFullOrg(
            autoUpgradeOrgId, // Org ID
            orgOwner, // Org Owner
            "Auto Upgrade Organization", // Org Name
            address(0), // No existing token, will create a new one
            accountRegistryProxy, // Use existing registry
            true // Auto-upgrade enabled
        );
        autoUpgradeOrgProxy = votingProxy; // Store the voting proxy address
        vm.stopPrank();

        // 2. Verify the contract has been properly stored in the registry
        address contractAddress = orgRegistry.getOrgContract(autoUpgradeOrgId, "Voting");
        assertEq(contractAddress, autoUpgradeOrgProxy, "BeaconProxy address mismatch");

        // Get contract details
        bytes32 contractId = keccak256(abi.encodePacked(autoUpgradeOrgId, "-", "Voting"));
        (address beaconProxy, address beacon, bool autoUpgrade, address owner) = orgRegistry.contracts(contractId);

        assertEq(beaconProxy, autoUpgradeOrgProxy, "BeaconProxy address mismatch");
        assertEq(beacon, poaManager.getBeacon("Voting"), "Beacon address mismatch");
        assertTrue(autoUpgrade, "Auto-upgrade should be enabled");
        assertEq(owner, orgOwner, "Owner address mismatch");

        // 3. Test voting functionality through the proxy
        Voting votingContract = Voting(autoUpgradeOrgProxy);

        // Verify implementation version
        assertEq(votingContract.version(), "v1", "Should be using V1 implementation");

        // Verify implementation is registered correctly
        assertEq(
            implementationRegistry.getImplementation("Voting", "v1"),
            address(votingImplementation),
            "Implementation not registered correctly"
        );

        // Check NFTMembership proxy
        NFTMembership membershipContract = NFTMembership(membershipProxy);

        // Create a QuickJoin address for testing - this is allowed to mint default NFTs
        address quickJoinAddress = quickJoinProxy;

        // Set up image URLs for NFTMembership, BEFORE trying to change membership type
        vm.startPrank(orgOwner);
        membershipContract.setMemberTypeImage("Executive", "https://example.com/executive.png");
        membershipContract.setMemberTypeImage("Default", "https://example.com/default.png");
        vm.stopPrank();

        // Use QuickJoin to onboard users
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter1Username");

        vm.prank(voter2);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter2Username");

        // Verify the roles are set correctly
        assertTrue(membershipContract.checkIsExecutive(voter1), "Voter1 should be an executive");
        assertEq(membershipContract.checkMemberTypeByAddress(voter2), "Default", "Voter2 should be a default member");

        // Cast some votes
        vm.startPrank(voter1);
        votingContract.vote(1, true); // Vote YES on proposal 1
        vm.stopPrank();

        vm.startPrank(voter2);
        votingContract.vote(1, false); // Vote NO on proposal 1
        vm.stopPrank();

        // Check vote tallies
        (uint256 yesVotes, uint256 noVotes) = votingContract.getVotes(1);
        assertEq(yesVotes, 1, "Should have 1 YES vote");
        assertEq(noVotes, 1, "Should have 1 NO vote");

        // 4. Upgrade the implementation through PoaManager
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon("Voting", address(votingV2Implementation), "v2");

        // Register a v2 for Membership (same implementation but different version)
        poaManager.upgradeBeacon("Membership", address(nftMembershipV2Implementation), "v2");
        vm.stopPrank();

        // Verify the implementation is registered correctly in the registry
        assertEq(
            implementationRegistry.getImplementation("Voting", "v2"),
            address(votingV2Implementation),
            "V2 not registered correctly"
        );

        // Check latest version is v2
        string memory latestVersion =
            implementationRegistry.getVersionAtIndex("Voting", implementationRegistry.getVersionCount("Voting") - 1);
        assertEq(latestVersion, "v2", "Latest version not updated correctly");

        // 5. Verify the proxy's implementation has been upgraded
        assertEq(votingContract.version(), "v2", "Should be using V2 implementation after upgrade");

        // 6. Test the new functionality from V2
        VotingV2 votingV2Contract = VotingV2(autoUpgradeOrgProxy);

        // Finalize the proposal (new function in V2)
        vm.startPrank(orgOwner);
        votingV2Contract.finalizeProposal(1);
        vm.stopPrank();

        // Check if the proposal was properly finalized
        bool passed = votingV2Contract.proposalPassed(1);
        assertFalse(passed, "Proposal should not have passed (tie vote)");

        // 7. Verify votes were preserved across the upgrade
        (yesVotes, noVotes) = votingV2Contract.getVotes(1);
        assertEq(yesVotes, 1, "YES votes should be preserved after upgrade");
        assertEq(noVotes, 1, "NO votes should be preserved after upgrade");
    }

    function testFullOrgDeployWithManualUpgrade() public {
        // 1. Deploy an organization with manual upgrading (false for auto-upgrade)
        vm.startPrank(orgOwner);
        (address votingProxy, address membershipProxy, address quickJoinProxy, address tokenProxy) = deployer
            .deployFullOrg(
            manualUpgradeOrgId, // Org ID
            orgOwner, // Org Owner
            "Manual Upgrade Organization", // Org Name
            address(0), // No existing token, will create a new one
            accountRegistryProxy, // Use existing registry
            false // Auto-upgrade disabled (manual upgrades)
        );
        manualUpgradeOrgProxy = votingProxy; // Store the voting proxy address
        vm.stopPrank();

        // 2. Verify the contract has been properly stored in the registry
        address contractAddress = orgRegistry.getOrgContract(manualUpgradeOrgId, "Voting");
        assertEq(contractAddress, manualUpgradeOrgProxy, "BeaconProxy address mismatch");

        // Get contract details
        bytes32 contractId = keccak256(abi.encodePacked(manualUpgradeOrgId, "-", "Voting"));
        (address beaconProxy, address beacon, bool autoUpgrade, address owner) = orgRegistry.contracts(contractId);

        assertEq(beaconProxy, manualUpgradeOrgProxy, "BeaconProxy address mismatch");
        assertNotEq(beacon, poaManager.getBeacon("Voting"), "Beacon should NOT be Poa's beacon");
        assertFalse(autoUpgrade, "Auto-upgrade should be disabled");
        assertEq(owner, orgOwner, "Owner address mismatch");

        // 3. Test voting functionality through the proxy
        Voting votingContract = Voting(manualUpgradeOrgProxy);

        // Check NFTMembership proxy
        NFTMembership membershipContract = NFTMembership(membershipProxy);

        // Set up image URLs for NFTMembership
        vm.startPrank(orgOwner);
        membershipContract.setMemberTypeImage("Executive", "https://example.com/executive.png");
        membershipContract.setMemberTypeImage("Default", "https://example.com/default.png");
        vm.stopPrank();

        // Use QuickJoin to onboard users
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("Voter1Username");

        // Cast some votes
        vm.startPrank(voter1);
        votingContract.vote(1, true); // Vote YES on proposal 1
        vm.stopPrank();

        // 4. Upgrade the Poa beacon
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon("Voting", address(votingV2Implementation), "v2");
        vm.stopPrank();

        // 5. Verify that the manual upgrade org is still using V1
        assertEq(votingContract.version(), "v1", "Should still be using V1 implementation");

        // 6. Get the org's beacon and upgrade it manually
        address orgBeacon = beacon; // From the org info we retrieved earlier

        // The org owner can upgrade their own beacon
        vm.startPrank(orgOwner);
        UpgradeableBeacon(orgBeacon).upgradeTo(address(votingV2Implementation));
        vm.stopPrank();

        // 7. Verify the proxy's implementation has now been upgraded
        assertEq(votingContract.version(), "v2", "Should be using V2 implementation after manual upgrade");

        // 8. Test V2 functionality
        VotingV2 votingV2Contract = VotingV2(manualUpgradeOrgProxy);

        // Verify votes were preserved across the upgrade
        uint256 yesVotes;
        uint256 noVotes;
        (yesVotes, noVotes) = votingV2Contract.getVotes(1);
        assertEq(yesVotes, 1, "YES votes should be preserved after manual upgrade");
        assertEq(noVotes, 0, "Should have 0 NO votes");
    }

    function testFullOrgDeployWithGlobalContracts() public {
        // Deploy a full organization including QuickJoin with the organization-specific token and registry
        // ... existing code ...
    }

    function testRegistryOperations() public {
        // Check the initial version
        string memory latestVersion =
            implementationRegistry.getVersionAtIndex("Voting", implementationRegistry.getVersionCount("Voting") - 1);
        assertEq(latestVersion, "v1", "Initial version should be v1");
        assertEq(
            implementationRegistry.getLatestImplementation("Voting"),
            address(votingImplementation),
            "Latest implementation should be V1"
        );

        // Register a new implementation
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon("Voting", address(votingV2Implementation), "v2");
        vm.stopPrank();

        // Check the updated version
        latestVersion =
            implementationRegistry.getVersionAtIndex("Voting", implementationRegistry.getVersionCount("Voting") - 1);
        assertEq(latestVersion, "v2", "Latest version should be v2");
        assertEq(
            implementationRegistry.getLatestImplementation("Voting"),
            address(votingV2Implementation),
            "Latest implementation should be V2"
        );

        // Verify we can get specific versions
        assertEq(
            implementationRegistry.getImplementation("Voting", "v1"),
            address(votingImplementation),
            "Should get V1 implementation"
        );

        assertEq(
            implementationRegistry.getImplementation("Voting", "v2"),
            address(votingV2Implementation),
            "Should get V2 implementation"
        );

        // Verify we have 2 versions registered
        assertEq(implementationRegistry.getVersionCount("Voting"), 2, "Should have 2 versions registered");
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
