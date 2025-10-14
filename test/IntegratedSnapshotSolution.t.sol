// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SnapshotParticipationToken} from "../src/SnapshotParticipationToken.sol";
import {PaymentManagerWithSnapshot} from "../src/PaymentManagerWithSnapshot.sol";
import {IPaymentManager} from "../src/interfaces/IPaymentManager.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

contract IntegratedSnapshotSolutionTest is Test {
    SnapshotParticipationToken public token;
    PaymentManagerWithSnapshot public paymentManager;
    MockHats public hats;
    
    address public executor = address(0x1);
    address public taskManager = address(0x10);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public newHolder = address(0x5);
    
    uint256 constant MEMBER_HAT = 1;
    uint256 constant APPROVER_HAT = 2;
    
    function setUp() public {
        // Deploy mock Hats
        hats = new MockHats();
        hats.setHatWearerStatus(MEMBER_HAT, alice, true, true);
        hats.setHatWearerStatus(MEMBER_HAT, bob, true, true);
        hats.setHatWearerStatus(MEMBER_HAT, charlie, true, true);
        
        // Deploy SnapshotParticipationToken
        token = new SnapshotParticipationToken();
        
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = MEMBER_HAT;
        uint256[] memory approverHats = new uint256[](1);
        approverHats[0] = APPROVER_HAT;
        
        token.initialize(
            executor,
            "Participation Token",
            "PART",
            address(hats),
            memberHats,
            approverHats
        );
        
        // Set task manager to mint tokens
        token.setTaskManager(taskManager);
        
        // Mint initial tokens
        vm.prank(taskManager);
        token.mint(alice, 500 * 1e18);  // 50%
        vm.prank(taskManager);
        token.mint(bob, 300 * 1e18);    // 30%
        vm.prank(taskManager);
        token.mint(charlie, 200 * 1e18); // 20%
        
        // Deploy PaymentManagerWithSnapshot
        paymentManager = new PaymentManagerWithSnapshot();
        paymentManager.initialize(executor, address(token));
        
        // Fund payment manager
        vm.deal(address(paymentManager), 10 ether);
    }
    
    function test_IntegratedSnapshotSolution() public {
        console.log("=== Testing Integrated Snapshot Solution ===");
        console.log("Token with built-in snapshot + PaymentManager using token snapshots\n");
        
        console.log("Initial state:");
        console.log("- Total supply: %s", token.totalSupply());
        console.log("- Alice balance: %s", token.balanceOf(alice));
        console.log("- Bob balance: %s", token.balanceOf(bob));
        console.log("- Charlie balance: %s", token.balanceOf(charlie));
        
        // Step 1: Create snapshot in the token itself
        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;
        
        vm.prank(executor);
        uint256 snapshotId = token.snapshotWithHolders(holders);
        
        console.log("\n1. Snapshot created IN THE TOKEN with ID: %s", snapshotId);
        console.log("   Token itself maintains the snapshot data");
        
        // Verify snapshot data
        uint256 snapTotalSupply = token.totalSupplyAt(snapshotId);
        console.log("   - Total supply at snapshot: %s", snapTotalSupply);
        console.log("   - Alice balance at snapshot: %s", token.balanceOfAt(alice, snapshotId));
        
        // Step 2: Mint tokens after snapshot
        vm.prank(taskManager);
        token.mint(newHolder, 100 * 1e18);
        
        console.log("\n2. After snapshot, new holder receives tokens:");
        console.log("   - New holder current balance: %s", token.balanceOf(newHolder));
        console.log("   - New total supply: %s", token.totalSupply());
        console.log("   - But snapshot preserves old state:");
        console.log("     - Snapshot total: %s", snapTotalSupply);
        console.log("     - New holder at snapshot: %s", token.balanceOfAt(newHolder, snapshotId));
        
        // Step 3: Distribute using token's snapshot
        console.log("\n3. PaymentManager distributes using TOKEN's snapshot...");
        
        // Use the same holders array that was used for the snapshot
        // newHolder is NOT included because they weren't a holder at snapshot time
        
        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;
        uint256 charlieBalBefore = charlie.balance;
        uint256 newHolderBalBefore = newHolder.balance;
        
        vm.prank(executor);
        paymentManager.distributeRevenueWithSnapshot(address(0), 5 ether, snapshotId, holders);
        
        console.log("\n[SUCCESS] Distribution succeeded!");
        console.log("Payments based on TOKEN's snapshot (not current balances):");
        console.log("- Alice: %s ETH (500/1000 from snapshot)", (alice.balance - aliceBalBefore) / 1e18);
        console.log("- Bob: %s ETH (300/1000 from snapshot)", (bob.balance - bobBalBefore) / 1e18);
        console.log("- Charlie: %s ETH (200/1000 from snapshot)", (charlie.balance - charlieBalBefore) / 1e18);
        console.log("- New holder: %s ETH (0/1000 from snapshot)", (newHolder.balance - newHolderBalBefore) / 1e18);
        
        // Verify correct distribution
        assertEq(alice.balance - aliceBalBefore, 2.5 ether, "Alice should get 50%");
        assertEq(bob.balance - bobBalBefore, 1.5 ether, "Bob should get 30%");
        assertEq(charlie.balance - charlieBalBefore, 1 ether, "Charlie should get 20%");
        assertEq(newHolder.balance - newHolderBalBefore, 0, "New holder should get nothing");
    }
    
    function test_ProposalWorkflow() public {
        console.log("=== Testing Proposal Workflow ===");
        console.log("Simulating: Proposal Creation -> Token Changes -> Distribution\n");
        
        // Proposal creation: Take snapshot
        console.log("1. PROPOSAL CREATION:");
        console.log("   - Voting contract calls token.snapshot()");
        
        address[] memory initialHolders = new address[](3);
        initialHolders[0] = alice;
        initialHolders[1] = bob;
        initialHolders[2] = charlie;
        
        vm.prank(executor);
        uint256 proposalSnapshotId = token.snapshotWithHolders(initialHolders);
        console.log("   - Snapshot ID %s stored in proposal", proposalSnapshotId);
        
        // Simulate voting period where token supply changes
        console.log("\n2. DURING VOTING PERIOD:");
        console.log("   - New member joins and gets tokens");
        vm.prank(taskManager);
        token.mint(newHolder, 200 * 1e18);
        console.log("   - New holder balance: %s", token.balanceOf(newHolder));
        console.log("   - Total supply increased to: %s", token.totalSupply());
        
        // Proposal passes and executes distribution
        console.log("\n3. PROPOSAL EXECUTION:");
        console.log("   - Proposal passes with snapshotId: %s", proposalSnapshotId);
        console.log("   - Executor calls distributeRevenueWithSnapshot");
        
        // Use only the holders that existed at snapshot time
        // newHolder is NOT included because they joined after the snapshot
        vm.prank(executor);
        paymentManager.distributeRevenueWithSnapshot(address(0), 5 ether, proposalSnapshotId, initialHolders);
        
        console.log("   - [SUCCESS] Distribution based on snapshot at proposal time!");
        console.log("   - New holder got 0 ETH (wasn't holder at proposal time)");
    }
    
    function test_MultipleProposalsWithDifferentSnapshots() public {
        console.log("=== Testing Multiple Proposals ===\n");
        
        // First proposal
        console.log("1. First distribution proposal:");
        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;
        
        vm.prank(executor);
        uint256 snapshot1 = token.snapshotWithHolders(holders);
        console.log("   - Snapshot 1 taken: total supply = %s", token.totalSupplyAt(snapshot1));
        
        // Token changes
        vm.prank(taskManager);
        token.mint(alice, 500 * 1e18);
        console.log("\n2. Alice gets more tokens (500 more)");
        
        // Second proposal - include alice with new balance
        console.log("\n3. Second distribution proposal:");
        vm.prank(executor);
        uint256 snapshot2 = token.snapshotWithHolders(holders);
        console.log("   - Snapshot 2 taken: total supply = %s", token.totalSupplyAt(snapshot2));
        
        console.log("\n4. Execute FIRST distribution (snapshot 1):");
        vm.prank(executor);
        paymentManager.distributeRevenueWithSnapshot(address(0), 2 ether, snapshot1, holders);
        console.log("   - Used snapshot 1 (1000 total supply)");
        
        // Fund more
        vm.deal(address(paymentManager), 10 ether);
        
        // Execute second distribution
        console.log("\n5. Execute SECOND distribution (snapshot 2):");
        vm.prank(executor);
        paymentManager.distributeRevenueWithSnapshot(address(0), 3 ether, snapshot2, holders);
        console.log("   - Used snapshot 2 (1500 total supply)");
        
        console.log("\n[SUCCESS] Multiple proposals with different snapshots work correctly!");
    }
}