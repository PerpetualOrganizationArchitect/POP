// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "../src/Voting.sol";
import "../src/VotingV2.sol";
import "../src/ImplementationRegistry.sol";
import "../src/PoaManager.sol";
import "../src/OrgRegistry.sol";
import "../src/Deployer.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

contract DeployerTest is Test {
    // Contracts
    Voting votingImplementation;
    VotingV2 votingV2Implementation;
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
    
    // Proxy addresses for the organizations
    address public autoUpgradeOrgProxy;
    address public manualUpgradeOrgProxy;
    
    function setUp() public {
        // Deploy the initial voting implementation
        votingImplementation = new Voting();
        
        // Deploy the updated voting implementation (for later testing)
        votingV2Implementation = new VotingV2();
        
        vm.startPrank(poaAdmin);
        
        // Deploy the ImplementationRegistry
        implementationRegistry = new ImplementationRegistry();
        
        // Deploy the PoaManager with the initial voting implementation and registry
        poaManager = new PoaManager(
            address(votingImplementation),
            address(implementationRegistry)
        );
        
        // Deploy the OrgRegistry
        orgRegistry = new OrgRegistry();
        
        // Deploy the Deployer contract with references to PoaManager and OrgRegistry
        deployer = new Deployer(address(poaManager), address(orgRegistry));
        
        // Transfer ownership of the registries
        orgRegistry.transferOwnership(address(deployer));
        implementationRegistry.transferOwnership(address(poaManager));
        
        // Now that PoaManager owns the ImplementationRegistry, register the initial implementation
        poaManager.registerInitialImplementation();
        
        vm.stopPrank();
    }
    
    function testOrgDeployWithAutoUpgrade() public {
        // 1. Deploy an organization with auto-upgrade enabled
        vm.startPrank(orgOwner);
        autoUpgradeOrgProxy = deployer.deployOrg(
            autoUpgradeOrgId,  // Org ID
            orgOwner,          // Org Owner
            true,              // Auto-upgrade enabled
            address(0)         // No custom implementation (not needed with auto-upgrade)
        );
        vm.stopPrank();
        
        // 2. Verify the OrgInfo has been properly stored in the registry
        (
            address beaconProxy,
            address beacon,
            bool autoUpgrade,
            address owner
        ) = orgRegistry.orgs(autoUpgradeOrgId);
        
        assertEq(beaconProxy, autoUpgradeOrgProxy, "BeaconProxy address mismatch");
        assertEq(beacon, address(poaManager.poaBeacon()), "Beacon address mismatch");
        assertTrue(autoUpgrade, "Auto-upgrade should be enabled");
        assertEq(owner, orgOwner, "Owner address mismatch");
        
        // 3. Test voting functionality through the proxy
        Voting votingProxy = Voting(autoUpgradeOrgProxy);
        
        // Verify implementation version
        assertEq(votingProxy.version(), "v1", "Should be using V1 implementation");
        
        // Verify implementation is registered correctly
        assertEq(
            implementationRegistry.implementations("v1"), 
            address(votingImplementation), 
            "Implementation not registered correctly"
        );
        
        // Cast some votes
        vm.startPrank(voter1);
        votingProxy.vote(1, true);  // Vote YES on proposal 1
        vm.stopPrank();
        
        vm.startPrank(voter2);
        votingProxy.vote(1, false); // Vote NO on proposal 1
        vm.stopPrank();
        
        // Check vote tallies
        (uint256 yesVotes, uint256 noVotes) = votingProxy.getVotes(1);
        assertEq(yesVotes, 1, "Should have 1 YES vote");
        assertEq(noVotes, 1, "Should have 1 NO vote");
        
        // 4. Upgrade the implementation through PoaManager
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon(address(votingV2Implementation), "v2");
        vm.stopPrank();
        
        // Verify the implementation is registered correctly in the registry
        assertEq(
            implementationRegistry.implementations("v2"), 
            address(votingV2Implementation), 
            "V2 not registered correctly"
        );
        
        assertEq(
            implementationRegistry.latestVersion(),
            "v2",
            "Latest version not updated correctly"
        );
        
        // 5. Verify the proxy's implementation has been upgraded
        assertEq(votingProxy.version(), "v2", "Should be using V2 implementation after upgrade");
        
        // 6. Test the new functionality from V2
        VotingV2 votingV2Proxy = VotingV2(autoUpgradeOrgProxy);
        
        // Finalize the proposal (new function in V2)
        vm.startPrank(orgOwner);
        votingV2Proxy.finalizeProposal(1);
        vm.stopPrank();
        
        // Check if the proposal was properly finalized
        bool passed = votingV2Proxy.proposalPassed(1);
        assertFalse(passed, "Proposal should not have passed (tie vote)");
        
        // 7. Verify votes were preserved across the upgrade
        (yesVotes, noVotes) = votingV2Proxy.getVotes(1);
        assertEq(yesVotes, 1, "YES votes should be preserved after upgrade");
        assertEq(noVotes, 1, "NO votes should be preserved after upgrade");
    }
    
    function testOrgDeployWithManualUpgrade() public {
        // 1. Deploy an organization with manual upgrading (false for auto-upgrade)
        vm.startPrank(orgOwner);
        manualUpgradeOrgProxy = deployer.deployOrg(
            manualUpgradeOrgId,  // Org ID
            orgOwner,            // Org Owner
            false,               // Auto-upgrade disabled (manual upgrades)
            address(0)           // Use Poa's current implementation (but won't auto-upgrade)
        );
        vm.stopPrank();
        
        // 2. Verify the OrgInfo has been properly stored in the registry
        (
            address beaconProxy,
            address beacon,
            bool autoUpgrade,
            address owner
        ) = orgRegistry.orgs(manualUpgradeOrgId);
        
        assertEq(beaconProxy, manualUpgradeOrgProxy, "BeaconProxy address mismatch");
        assertNotEq(beacon, address(poaManager.poaBeacon()), "Beacon should NOT be Poa's beacon");
        assertFalse(autoUpgrade, "Auto-upgrade should be disabled");
        assertEq(owner, orgOwner, "Owner address mismatch");
        
        // 3. Test voting functionality through the proxy
        Voting votingProxy = Voting(manualUpgradeOrgProxy);
        
        // Cast some votes
        vm.startPrank(voter1);
        votingProxy.vote(1, true);  // Vote YES on proposal 1
        vm.stopPrank();
        
        // 4. Upgrade the Poa beacon
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon(address(votingV2Implementation), "v2");
        vm.stopPrank();
        
        // 5. Verify that the manual upgrade org is still using V1
        assertEq(votingProxy.version(), "v1", "Should still be using V1 implementation");
        
        // 6. Get the org's beacon and upgrade it manually
        address orgBeacon = beacon; // From the org info we retrieved earlier
        
        // The org owner can upgrade their own beacon
        vm.startPrank(orgOwner);
        UpgradeableBeacon(orgBeacon).upgradeTo(address(votingV2Implementation));
        vm.stopPrank();
        
        // 7. Verify the proxy's implementation has now been upgraded
        assertEq(votingProxy.version(), "v2", "Should be using V2 implementation after manual upgrade");
        
        // 8. Test V2 functionality
        VotingV2 votingV2Proxy = VotingV2(manualUpgradeOrgProxy);
        
        // Verify votes were preserved across the upgrade
        (uint256 yesVotes, uint256 noVotes) = votingV2Proxy.getVotes(1);
        assertEq(yesVotes, 1, "YES votes should be preserved after manual upgrade");
        assertEq(noVotes, 0, "Should have 0 NO votes");
    }
    
    function testRegistryOperations() public {
        // Check the initial version
        assertEq(implementationRegistry.latestVersion(), "v1", "Initial version should be v1");
        assertEq(
            implementationRegistry.getLatestImplementation(),
            address(votingImplementation),
            "Latest implementation should be V1"
        );
        
        // Register a new implementation
        vm.startPrank(poaAdmin);
        poaManager.upgradeBeacon(address(votingV2Implementation), "v2");
        vm.stopPrank();
        
        // Check the updated version
        assertEq(implementationRegistry.latestVersion(), "v2", "Latest version should be v2");
        assertEq(
            implementationRegistry.getLatestImplementation(),
            address(votingV2Implementation),
            "Latest implementation should be V2"
        );
        
        // Verify we can get specific versions
        assertEq(
            implementationRegistry.getImplementation("v1"),
            address(votingImplementation),
            "Should get V1 implementation"
        );
        
        assertEq(
            implementationRegistry.getImplementation("v2"),
            address(votingV2Implementation),
            "Should get V2 implementation"
        );
        
        // Verify we have 2 versions registered
        assertEq(
            implementationRegistry.getVersionCount(),
            2,
            "Should have 2 versions registered"
        );
    }
} 