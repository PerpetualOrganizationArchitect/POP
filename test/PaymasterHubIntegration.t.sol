// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";
import "./PaymasterHub.t.sol";

/**
 * @title PaymasterHubIntegrationTest
 * @notice Integration tests simulating real-world ERC-4337 flows
 * @dev Tests the full lifecycle: validation -> execution -> settlement
 */
contract PaymasterHubIntegrationTest is Test {
    PaymasterHub public hub;
    MockEntryPoint public entryPoint;
    MockHats public hats;
    MockAccount public account1;
    MockAccount public account2;

    address public admin = address(0x1);
    address public bundler1 = address(0x2);
    address public bundler2 = address(0x3);
    address public alice = address(0x4);
    address public bob = address(0x5);
    address public targetContract = address(0x6);

    uint256 constant ADMIN_HAT = 1;
    uint256 constant CONTRIBUTOR_HAT = 100;
    uint256 constant GUEST_HAT = 200;

    event UsageIncreased(bytes32 indexed subjectKey, uint256 delta, uint64 usedInEpoch, uint32 epochStart);
    event BountyPaid(bytes32 indexed userOpHash, address indexed to, uint256 amount);

    function setUp() public {
        // Deploy infrastructure
        entryPoint = new MockEntryPoint();
        hats = new MockHats();

        // Deploy accounts
        account1 = new MockAccount();
        account2 = new MockAccount();

        // Deploy PaymasterHub
        hub = new PaymasterHub(address(entryPoint), address(hats), ADMIN_HAT);

        // Setup roles
        hats.mintHat(ADMIN_HAT, admin);
        hats.mintHat(CONTRIBUTOR_HAT, alice);
        hats.mintHat(CONTRIBUTOR_HAT, bob);
        hats.mintHat(GUEST_HAT, alice);

        // Fund accounts
        vm.deal(admin, 1000 ether);
        vm.deal(bundler1, 10 ether);
        vm.deal(bundler2, 10 ether);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        // Initial setup by admin
        vm.startPrank(admin);

        // Deposit to EntryPoint
        hub.depositToEntryPoint{value: 100 ether}();

        // Fund bounty pool
        hub.fundBounty{value: 10 ether}();

        // Enable bounty
        hub.setBounty(true, 0.1 ether, 500); // 5% bounty

        // Set global fee caps
        hub.setFeeCaps(
            100 gwei, // maxFeePerGas
            10 gwei, // maxPriorityFeePerGas
            1000000, // maxCallGas
            500000, // maxVerificationGas
            200000 // maxPreVerificationGas
        );

        vm.stopPrank();
    }

    /**
     * @notice Test complete flow for account-based budget
     */
    function testCompleteFlow_AccountBudget() public {
        // Admin sets up rules and budget
        vm.startPrank(admin);

        // Allow execute selector on targetContract (extracted from execute(address,uint256,bytes) call)
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 500000);

        // Set budget for alice's account
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 1 ether, 1 hours);

        vm.stopPrank();

        // Alice creates and submits UserOp
        PackedUserOperation memory userOp = _createUserOp(
            address(account1),
            targetContract,
            abi.encodeWithSignature("doSomething()"),
            0 // account subject
        );

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Bundler validates the operation
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.1 ether);

        assertEq(validationData, 0, "Validation should pass");

        // Simulate execution and settlement
        uint256 actualGasCost = 0.05 ether;

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost);

        // Verify budget was consumed
        PaymasterHub.Budget memory budget = hub.budgetOf(aliceKey);
        assertEq(budget.usedInEpoch, actualGasCost, "Budget should be consumed");

        // Verify remaining budget
        uint256 remaining = hub.remaining(aliceKey);
        assertEq(remaining, 1 ether - actualGasCost, "Remaining should be reduced");
    }

    /**
     * @notice Test complete flow for hat-based budget
     */
    function testCompleteFlow_HatBudget() public {
        // Admin sets up rules and budget for contributors
        vm.startPrank(admin);

        // Mint contributor hat to the accounts (senders of UserOps)
        hats.mintHat(CONTRIBUTOR_HAT, address(account1));
        hats.mintHat(CONTRIBUTOR_HAT, address(account2));

        // Allow execute on any account
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);

        // Set budget for contributor hat
        bytes32 contributorKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(CONTRIBUTOR_HAT))));
        hub.setBudget(contributorKey, 5 ether, 1 days);

        vm.stopPrank();

        // Alice uses hat budget
        PackedUserOperation memory aliceOp = _createUserOpWithHat(
            address(account1), alice, targetContract, abi.encodeWithSignature("doSomething()"), CONTRIBUTOR_HAT
        );

        bytes32 aliceOpHash = keccak256(abi.encode(aliceOp));

        // Validate Alice's operation
        vm.prank(address(entryPoint));
        (bytes memory aliceContext,) = hub.validatePaymasterUserOp(aliceOp, aliceOpHash, 0.5 ether);

        // Execute Alice's operation
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, aliceContext, 0.3 ether);

        // Bob also uses the same hat budget
        PackedUserOperation memory bobOp = _createUserOpWithHat(
            address(account2), bob, targetContract, abi.encodeWithSignature("doSomethingElse()"), CONTRIBUTOR_HAT
        );

        bytes32 bobOpHash = keccak256(abi.encode(bobOp));

        // Validate Bob's operation
        vm.prank(address(entryPoint));
        (bytes memory bobContext,) = hub.validatePaymasterUserOp(bobOp, bobOpHash, 0.5 ether);

        // Execute Bob's operation
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, bobContext, 0.2 ether);

        // Verify shared budget usage
        PaymasterHub.Budget memory budget = hub.budgetOf(contributorKey);
        assertEq(budget.usedInEpoch, 0.5 ether, "Combined usage should be 0.5 ether");
        assertEq(hub.remaining(contributorKey), 4.5 ether, "Remaining should be 4.5 ether");
    }

    /**
     * @notice Test mailbox and bounty flow
     */
    function testCompleteFlow_MailboxAndBounty() public {
        // Setup
        vm.startPrank(admin);
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 2 ether, 1 days);
        vm.stopPrank();

        // Alice posts to mailbox first
        PackedUserOperation memory userOp =
            _createUserOp(address(account1), targetContract, abi.encodeWithSignature("doSomething()"), 0);

        bytes memory packedOp = abi.encode(userOp);

        vm.prank(alice);
        bytes32 mailboxHash = hub.postUserOp(packedOp);

        // Create UserOp with mailbox commit
        bytes32 fullHash = keccak256(packedOp);
        uint64 mailboxCommit8 = uint64(uint256(fullHash) >> 192);

        // Update paymasterAndData with mailbox commit
        userOp.paymasterAndData =
            abi.encodePacked(address(hub), uint8(1), uint8(0), bytes20(address(account1)), uint32(0), mailboxCommit8);

        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Bundler picks up and validates
        uint256 bundlerBalanceBefore = bundler1.balance;

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);

        // Execute with bounty payment
        uint256 actualGasCost = 0.1 ether;
        uint256 expectedBounty = 0.005 ether; // 5% of actual cost

        vm.prank(address(entryPoint));
        vm.expectEmit(true, true, false, true);
        emit BountyPaid(userOpHash, address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38), expectedBounty); // tx.origin in Foundry
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost);

        // Verify bounty was paid to tx.origin (DefaultSender in Foundry)
        address defaultSender = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        assertGt(defaultSender.balance, 0, "DefaultSender should receive bounty");
    }

    /**
     * @notice Test epoch rolling and budget refresh
     */
    function testCompleteFlow_EpochRolling() public {
        // Setup with short epoch
        vm.startPrank(admin);
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        // Already covered by execute rule above
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 1 ether, 1 hours); // 1 hour epoch
        vm.stopPrank();

        // First operation in epoch 1
        PackedUserOperation memory op1 =
            _createUserOp(address(account1), targetContract, abi.encodeWithSignature("operation1()"), 0);

        vm.prank(address(entryPoint));
        (bytes memory context1,) = hub.validatePaymasterUserOp(op1, keccak256(abi.encode(op1)), 0.8 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context1, 0.8 ether);

        // Try second operation - should fail due to budget
        PackedUserOperation memory op2 =
            _createUserOp(address(account1), targetContract, abi.encodeWithSignature("operation2()"), 0);

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
        hub.validatePaymasterUserOp(op2, keccak256(abi.encode(op2)), 0.3 ether);

        // Move to next epoch
        vm.warp(block.timestamp + 1 hours + 1);

        // Now should succeed with fresh budget
        vm.prank(address(entryPoint));
        (bytes memory context2,) = hub.validatePaymasterUserOp(op2, keccak256(abi.encode(op2)), 0.9 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context2, 0.9 ether);

        // Verify budget was reset
        PaymasterHub.Budget memory budget = hub.budgetOf(aliceKey);
        assertEq(budget.usedInEpoch, 0.9 ether, "Should only show current epoch usage");
    }

    /**
     * @notice Test batch execution with multiple targets
     */
    function testCompleteFlow_BatchExecution() public {
        // Setup
        vm.startPrank(admin);

        // Allow batch execute
        hub.setRule(address(account1), bytes4(keccak256("executeBatch(address[],bytes[])")), true, 0);

        // Set budget
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 3 ether, 1 days);

        vm.stopPrank();

        // Create batch operation
        address[] memory targets = new address[](3);
        targets[0] = address(0x100);
        targets[1] = address(0x200);
        targets[2] = address(0x300);

        bytes[] memory data = new bytes[](3);
        data[0] = abi.encodeWithSignature("func1()");
        data[1] = abi.encodeWithSignature("func2()");
        data[2] = abi.encodeWithSignature("func3()");

        bytes memory batchCallData =
            abi.encodeWithSelector(bytes4(keccak256("executeBatch(address[],bytes[])")), targets, data);

        PackedUserOperation memory batchOp = PackedUserOperation({
            sender: address(account1),
            nonce: 0,
            initCode: "",
            callData: batchCallData,
            accountGasLimits: UserOpLib.packAccountGasLimits(200000, 800000),
            preVerificationGas: 100000,
            maxFeePerGas: 50 gwei,
            maxPriorityFeePerGas: 5 gwei,
            paymasterAndData: abi.encodePacked(
                address(hub), uint8(1), uint8(0), bytes20(address(account1)), uint32(0), uint64(0)
            ),
            signature: ""
        });

        bytes32 batchOpHash = keccak256(abi.encode(batchOp));

        // Validate and execute
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(batchOp, batchOpHash, 1 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.7 ether);

        // Verify execution
        PaymasterHub.Budget memory budget = hub.budgetOf(aliceKey);
        assertEq(budget.usedInEpoch, 0.7 ether, "Budget should be consumed for batch");
    }

    /**
     * @notice Test concurrent operations from multiple bundlers
     */
    function testCompleteFlow_ConcurrentBundlers() public {
        // Setup
        vm.startPrank(admin);
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        // Already covered by execute rule above

        // Single budget for alice
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 2 ether, 1 days);

        // Single budget for bob
        bytes32 bobKey = keccak256(abi.encodePacked(uint8(0), address(account2)));
        hub.setBudget(bobKey, 2 ether, 1 days);

        vm.stopPrank();

        // Create operations
        PackedUserOperation memory aliceOp =
            _createUserOp(address(account1), targetContract, abi.encodeWithSignature("aliceAction()"), 0);

        PackedUserOperation memory bobOp =
            _createUserOp(address(account2), targetContract, abi.encodeWithSignature("bobAction()"), 0);

        // Bundler1 handles Alice's operation
        vm.prank(address(entryPoint));
        (bytes memory aliceContext,) = hub.validatePaymasterUserOp(aliceOp, keccak256(abi.encode(aliceOp)), 0.5 ether);

        // Bundler2 handles Bob's operation simultaneously
        vm.prank(address(entryPoint));
        (bytes memory bobContext,) = hub.validatePaymasterUserOp(bobOp, keccak256(abi.encode(bobOp)), 0.5 ether);

        // Both execute
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, aliceContext, 0.3 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, bobContext, 0.4 ether);

        // Verify independent budget tracking
        assertEq(hub.budgetOf(aliceKey).usedInEpoch, 0.3 ether, "Alice's budget");
        assertEq(hub.budgetOf(bobKey).usedInEpoch, 0.4 ether, "Bob's budget");
    }

    /**
     * @notice Test operation reversion handling
     */
    function testCompleteFlow_OperationReversion() public {
        // Setup
        vm.startPrank(admin);
        hub.setRule(targetContract, bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);
        bytes32 aliceKey = keccak256(abi.encodePacked(uint8(0), address(account1)));
        hub.setBudget(aliceKey, 2 ether, 1 days);
        vm.stopPrank();

        // Create operation
        PackedUserOperation memory userOp =
            _createUserOp(address(account1), targetContract, abi.encodeWithSignature("willRevert()"), 0);

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, keccak256(abi.encode(userOp)), 0.5 ether);

        // Execute with opReverted mode
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opReverted, context, 0.2 ether);

        // Budget should still be consumed for reverted operations
        PaymasterHub.Budget memory budget = hub.budgetOf(aliceKey);
        assertEq(budget.usedInEpoch, 0.2 ether, "Gas should be charged even on revert");
    }

    // ============ Helper Functions ============

    function _createUserOp(address sender, address target, bytes memory targetCallData, uint8 subjectType)
        internal
        view
        returns (PackedUserOperation memory)
    {
        bytes memory callData =
            abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), target, 0, targetCallData);

        bytes memory paymasterAndData =
            abi.encodePacked(address(hub), uint8(1), subjectType, bytes20(sender), uint32(0), uint64(0));

        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(150000, 300000),
            preVerificationGas: 75000,
            maxFeePerGas: 30 gwei,
            maxPriorityFeePerGas: 3 gwei,
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    function _createUserOpWithHat(
        address sender,
        address actualSender,
        address target,
        bytes memory targetCallData,
        uint256 hatId
    ) internal view returns (PackedUserOperation memory) {
        bytes memory callData =
            abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), target, 0, targetCallData);

        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1),
            uint8(1), // hat subject
            bytes20(uint160(hatId)),
            uint32(0),
            uint64(0)
        );

        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(150000, 300000),
            preVerificationGas: 75000,
            maxFeePerGas: 30 gwei,
            maxPriorityFeePerGas: 3 gwei,
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }
}
