// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import "./PaymasterHub.t.sol";

/**
 * @title PaymasterHubInvariantsTest
 * @notice Property-based tests verifying critical invariants of the PaymasterHub
 * @dev Tests ensure security properties hold under various conditions
 */
contract PaymasterHubInvariantsTest is Test {
    PaymasterHub public hub;
    MockEntryPoint public entryPoint;
    MockHats public hats;
    MockAccount public account;
    
    address public admin = address(0x1);
    address public attacker = address(0x666);
    
    uint256 constant ADMIN_HAT = 1;
    uint256 constant USER_HAT = 2;
    
    // Track state for invariant testing
    mapping(bytes32 => uint256) public totalUsageTracked;
    mapping(bytes32 => bool) public bountyPaidTracked;
    uint256 public totalDepositTracked;
    uint256 public totalBountyTracked;
    
    function setUp() public {
        entryPoint = new MockEntryPoint();
        hats = new MockHats();
        account = new MockAccount();
        hub = new PaymasterHub(address(entryPoint), address(hats), ADMIN_HAT);
        
        hats.mintHat(ADMIN_HAT, admin);
        hats.mintHat(USER_HAT, address(account));
        
        vm.deal(admin, 1000 ether);
        vm.deal(attacker, 100 ether);
        
        // Initial setup
        vm.startPrank(admin);
        hub.depositToEntryPoint{value: 50 ether}();
        totalDepositTracked = 50 ether;
        hub.fundBounty{value: 5 ether}();
        totalBountyTracked = 5 ether;
        hub.setBounty(true, 0.1 ether, 1000); // 10% bounty
        hub.setFeeCaps(200 gwei, 20 gwei, 2000000, 1000000, 500000);
        vm.stopPrank();
    }
    
    // ============ Invariant 1: Budget Usage Never Exceeds Cap ============
    
    /**
     * @notice Invariant: usedInEpoch ≤ capPerEpoch for all subjects at all times
     */
    function invariant_BudgetUsageNeverExceedsCap() public {
        // This would be called by foundry's invariant testing
        // Check a sample of known subject keys
        bytes32[] memory subjectKeys = _getKnownSubjectKeys();
        
        for (uint256 i = 0; i < subjectKeys.length; i++) {
            PaymasterHub.Budget memory budget = hub.budgetOf(subjectKeys[i]);
            assertLe(
                budget.usedInEpoch,
                budget.capPerEpoch,
                "Usage should never exceed cap"
            );
        }
    }
    
    /**
     * @notice Test that budget enforcement is atomic and consistent
     */
    function testInvariant_AtomicBudgetEnforcement(
        uint64 cap,
        uint8 numOps,
        uint256 seed
    ) public {
        cap = uint64(bound(cap, 0.1 ether, 10 ether));
        numOps = uint8(bound(numOps, 1, 20));
        
        // Setup
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        
        vm.startPrank(admin);
        hub.setBudget(subjectKey, cap, 1 days);
        hub.setRule(address(0x123), bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        vm.stopPrank();
        
        uint256 totalUsed = 0;
        uint256 random = seed;
        
        for (uint256 i = 0; i < numOps; i++) {
            // Generate random cost
            random = uint256(keccak256(abi.encode(random)));
            uint256 maxCost = bound(random, 0.001 ether, cap);
            
            PackedUserOperation memory userOp = _createUserOp(address(account));
            bytes32 userOpHash = keccak256(abi.encode(userOp, i)); // Unique hash
            
            // Try to validate
            if (totalUsed + maxCost <= cap) {
                // Should succeed
                vm.prank(address(entryPoint));
                (bytes memory context, ) = hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);
                
                // Simulate actual usage
                uint256 actualCost = bound(random % maxCost, 0, maxCost);
                vm.prank(address(entryPoint));
                hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualCost);
                
                totalUsed += actualCost;
                
                // Verify invariant
                PaymasterHub.Budget memory budget = hub.budgetOf(subjectKey);
                assertEq(budget.usedInEpoch, totalUsed, "Usage tracking mismatch");
                assertLe(budget.usedInEpoch, budget.capPerEpoch, "Usage exceeds cap");
            } else {
                // Should fail
                vm.prank(address(entryPoint));
                vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
                hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);
            }
        }
    }
    
    // ============ Invariant 2: Only EntryPoint Can Call Paymaster Functions ============
    
    /**
     * @notice Test that only EntryPoint can call validatePaymasterUserOp
     */
    function testInvariant_OnlyEntryPointValidate(address caller) public {
        vm.assume(caller != address(entryPoint));
        vm.assume(caller != address(0));
        
        PackedUserOperation memory userOp = _createUserOp(address(account));
        
        vm.prank(caller);
        vm.expectRevert(PaymasterHub.EPOnly.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.1 ether);
    }
    
    /**
     * @notice Test that only EntryPoint can call postOp
     */
    function testInvariant_OnlyEntryPointPostOp(address caller, bytes memory context) public {
        vm.assume(caller != address(entryPoint));
        vm.assume(caller != address(0));
        
        vm.prank(caller);
        vm.expectRevert(PaymasterHub.EPOnly.selector);
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.01 ether);
    }
    
    // ============ Invariant 3: Bounty Single-Shot Protection ============
    
    /**
     * @notice Test that bounties can only be paid once per userOpHash
     */
    function testInvariant_BountySingleShot() public {
        // Setup
        vm.startPrank(admin);
        hub.setRule(address(0x123), bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        hub.setBudget(subjectKey, 10 ether, 1 days);
        vm.stopPrank();
        
        // Create op with mailbox commit
        PackedUserOperation memory userOp = _createUserOpWithMailbox(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        
        // First validation and execution
        vm.prank(address(entryPoint));
        (bytes memory context1, ) = hub.validatePaymasterUserOp(userOp, userOpHash, 1 ether);
        
        // tx.origin in Foundry is DefaultSender
        address defaultSender = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        uint256 bundlerBalanceBefore = defaultSender.balance;
        
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context1, 0.1 ether);
        
        uint256 firstBounty = defaultSender.balance - bundlerBalanceBefore;
        assertGt(firstBounty, 0, "First bounty should be paid");
        
        // Second attempt with same userOpHash - create new context
        vm.prank(address(entryPoint));
        (bytes memory context2, ) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);
        
        bundlerBalanceBefore = defaultSender.balance;
        
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context2, 0.1 ether);
        
        uint256 secondBounty = defaultSender.balance - bundlerBalanceBefore;
        assertEq(secondBounty, 0, "Second bounty should not be paid");
    }
    
    // ============ Invariant 4: Epoch Consistency ============
    
    /**
     * @notice Test that epoch rolling is consistent and predictable
     */
    function testInvariant_EpochConsistency(
        uint32 epochLen,
        uint256 timeJump1,
        uint256 timeJump2
    ) public {
        epochLen = uint32(bound(epochLen, 1 hours, 30 days));
        timeJump1 = bound(timeJump1, 0, 100 days);
        timeJump2 = bound(timeJump2, 0, 100 days);
        
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        
        vm.startPrank(admin);
        hub.setBudget(subjectKey, 1 ether, epochLen);
        hub.setRule(address(0x123), bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        vm.stopPrank();
        
        uint256 startTime = block.timestamp;
        PaymasterHub.Budget memory budget1 = hub.budgetOf(subjectKey);
        uint32 initialEpochStart = budget1.epochStart;
        
        // Use some budget
        _usebudget(subjectKey, 0.3 ether);
        
        // Jump time
        vm.warp(startTime + timeJump1);
        
        // Check epoch consistency
        PaymasterHub.Budget memory budget2 = hub.budgetOf(subjectKey);
        uint256 epochsPassed1 = timeJump1 / epochLen;
        
        if (epochsPassed1 > 0) {
            // Should have rolled
            _usebudget(subjectKey, 0.1 ether); // Trigger roll
            budget2 = hub.budgetOf(subjectKey);
            assertEq(
                budget2.epochStart,
                initialEpochStart + (uint32(epochsPassed1) * epochLen),
                "Epoch start calculation error"
            );
            assertEq(budget2.usedInEpoch, 0.1 ether, "Usage should reset after roll");
        } else {
            // Should not have rolled
            assertEq(budget2.epochStart, initialEpochStart, "Epoch should not change");
            assertEq(budget2.usedInEpoch, 0.3 ether, "Usage should persist");
        }
        
        // Second jump
        vm.warp(startTime + timeJump1 + timeJump2);
        
        uint256 totalTimePassed = timeJump1 + timeJump2;
        uint256 totalEpochsPassed = totalTimePassed / epochLen;
        
        _usebudget(subjectKey, 0.05 ether); // Trigger potential roll
        PaymasterHub.Budget memory budget3 = hub.budgetOf(subjectKey);
        
        assertEq(
            budget3.epochStart,
            initialEpochStart + (uint32(totalEpochsPassed) * epochLen),
            "Epoch calculation should be cumulative"
        );
    }
    
    // ============ Invariant 5: Access Control Integrity ============
    
    /**
     * @notice Test that admin functions cannot be called by non-admins
     */
    function testInvariant_AdminAccessControl(address caller) public {
        vm.assume(caller != admin);
        vm.assume(!hats.isWearerOfHat(caller, ADMIN_HAT));
        
        vm.startPrank(caller);
        
        // Test operator function (setRule can be called by operator OR admin)
        vm.expectRevert(PaymasterHub.NotOperator.selector);
        hub.setRule(address(0x1), bytes4(0x12345678), true, 100000);
        
        vm.expectRevert(PaymasterHub.NotOperator.selector);
        hub.setBudget(bytes32(0), 1 ether, 1 days);
        
        vm.expectRevert(PaymasterHub.NotOperator.selector);
        hub.setFeeCaps(100 gwei, 10 gwei, 1000000, 500000, 200000);
        
        vm.expectRevert(PaymasterHub.NotAdmin.selector);
        hub.setPause(true);
        
        vm.expectRevert(PaymasterHub.NotAdmin.selector);
        hub.setBounty(true, 0.1 ether, 1000);
        
        // Test depositToEntryPoint with a small amount that won't cause OutOfFunds
        vm.deal(caller, 0.01 ether);
        vm.expectRevert(PaymasterHub.NotOperator.selector);
        hub.depositToEntryPoint{value: 0.01 ether}();
        
        vm.expectRevert(PaymasterHub.NotAdmin.selector);
        hub.withdrawFromEntryPoint(payable(caller), 1 ether);
        
        vm.expectRevert(PaymasterHub.NotAdmin.selector);
        hub.sweepBounty(payable(caller), 1 ether);
        
        vm.stopPrank();
    }
    
    // ============ Invariant 6: Fund Separation ============
    
    /**
     * @notice Test that EntryPoint deposits and bounty funds are properly separated
     */
    function testInvariant_FundSeparation(
        uint256 depositAmount,
        uint256 bountyAmount,
        uint256 withdrawAmount
    ) public {
        depositAmount = bound(depositAmount, 0.1 ether, 100 ether);
        bountyAmount = bound(bountyAmount, 0.1 ether, 50 ether);
        withdrawAmount = bound(withdrawAmount, 0, depositAmount);
        
        uint256 initialEPBalance = entryPoint.balanceOf(address(hub));
        uint256 initialContractBalance = address(hub).balance;
        
        // Deposit to EntryPoint
        vm.prank(admin);
        hub.depositToEntryPoint{value: depositAmount}();
        
        assertEq(
            entryPoint.balanceOf(address(hub)),
            initialEPBalance + depositAmount,
            "EntryPoint deposit mismatch"
        );
        
        // Fund bounty
        vm.prank(admin);
        hub.fundBounty{value: bountyAmount}();
        
        assertEq(
            address(hub).balance,
            initialContractBalance + bountyAmount,
            "Bounty fund mismatch"
        );
        
        // Withdraw from EntryPoint shouldn't affect bounty
        address payable recipient = payable(address(0x999));
        vm.prank(admin);
        hub.withdrawFromEntryPoint(recipient, withdrawAmount);
        
        assertEq(
            address(hub).balance,
            initialContractBalance + bountyAmount,
            "Bounty should not be affected by EP withdrawal"
        );
        
        assertEq(
            entryPoint.balanceOf(address(hub)),
            initialEPBalance + depositAmount - withdrawAmount,
            "EntryPoint balance after withdrawal"
        );
    }
    
    // ============ Invariant 7: Deterministic Policy ============
    
    /**
     * @notice Test that validation results are deterministic given same inputs
     */
    function testInvariant_DeterministicValidation() public {
        // Setup
        vm.startPrank(admin);
        hub.setRule(address(0x123), bytes4(keccak256("execute(address,uint256,bytes)")), true, 500000);
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        hub.setBudget(subjectKey, 5 ether, 1 days);
        vm.stopPrank();
        
        PackedUserOperation memory userOp = _createUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 1 ether;
        
        // First validation
        vm.prank(address(entryPoint));
        (bytes memory context1, uint256 validationData1) = hub.validatePaymasterUserOp(
            userOp,
            userOpHash,
            maxCost
        );
        
        // Reset state by not executing postOp
        
        // Second validation with same inputs
        vm.prank(address(entryPoint));
        (bytes memory context2, uint256 validationData2) = hub.validatePaymasterUserOp(
            userOp,
            userOpHash,
            maxCost
        );
        
        // Results should be deterministic (except for timestamps in context)
        assertEq(validationData1, validationData2, "Validation data should be deterministic");
        
        // Decode contexts to compare non-timestamp fields
        (bytes32 sk1, , bytes32 hash1, uint64 commit1, address origin1) = 
            abi.decode(context1, (bytes32, uint32, bytes32, uint64, address));
        (bytes32 sk2, , bytes32 hash2, uint64 commit2, address origin2) = 
            abi.decode(context2, (bytes32, uint32, bytes32, uint64, address));
        
        assertEq(sk1, sk2, "Subject keys should match");
        assertEq(hash1, hash2, "Op hashes should match");
        assertEq(commit1, commit2, "Commits should match");
        assertEq(origin1, origin2, "Origins should match");
    }
    
    // ============ Helper Functions ============
    
    function _createUserOp(address sender) internal view returns (PackedUserOperation memory) {
        bytes memory callData = abi.encodeWithSelector(
            bytes4(keccak256("execute(address,uint256,bytes)")),
            address(0x123),
            0,
            ""
        );
        
        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1),
            uint8(0),
            bytes20(sender),
            uint32(0),
            uint64(0)
        );
        
        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(100000, 200000),
            preVerificationGas: 50000,
            maxFeePerGas: 10 gwei,
            maxPriorityFeePerGas: 1 gwei,
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }
    
    function _createUserOpWithMailbox(address sender) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory userOp = _createUserOp(sender);
        
        bytes32 fullHash = keccak256(abi.encode(userOp));
        uint64 mailboxCommit8 = uint64(uint256(fullHash) >> 192);
        
        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1),
            uint8(0),
            bytes20(sender),
            uint32(0),
            mailboxCommit8
        );
        
        userOp.paymasterAndData = paymasterAndData;
        return userOp;
    }
    
    function _usebudget(bytes32 subjectKey, uint256 amount) internal {
        PackedUserOperation memory userOp = _createUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp, block.timestamp));
        
        vm.prank(address(entryPoint));
        try hub.validatePaymasterUserOp(userOp, userOpHash, amount) returns (bytes memory context, uint256) {
            vm.prank(address(entryPoint));
            hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, amount);
        } catch {
            // Validation failed, that's ok for this helper
        }
    }
    
    function _getKnownSubjectKeys() internal view returns (bytes32[] memory) {
        bytes32[] memory keys = new bytes32[](2);
        keys[0] = keccak256(abi.encodePacked(uint8(0), address(account)));
        keys[1] = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(USER_HAT))));
        return keys;
    }
}