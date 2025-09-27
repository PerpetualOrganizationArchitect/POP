// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PaymentManager} from "../src/PaymentManager.sol";
import {IPaymentManager} from "../src/interfaces/IPaymentManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract PaymentManagerTest is Test {
    PaymentManager public paymentManager;
    MockToken public revenueShareToken;
    MockToken public paymentToken;

    address public executor = address(0x1);
    address public alice = address(0x2);
    address public bob = address(0x3);
    address public charlie = address(0x4);
    address public payer = address(0x5);

    uint256 constant INITIAL_BALANCE = 1000 * 1e18;

    event PaymentReceived(address indexed payer, uint256 amount, address indexed token);
    event RevenueDistributed(address indexed token, uint256 amount);
    event OptOutToggled(address indexed user, bool optedOut);
    event RevenueShareTokenSet(address indexed token);

    function setUp() public {
        // Deploy tokens
        revenueShareToken = new MockToken("Revenue Share Token", "RST");
        paymentToken = new MockToken("Payment Token", "PAY");

        // Deploy PaymentManager and initialize
        paymentManager = new PaymentManager();
        paymentManager.initialize(executor, address(revenueShareToken));

        // Setup initial token balances for holders
        revenueShareToken.mint(alice, 500 * 1e18); // 50% of supply
        revenueShareToken.mint(bob, 300 * 1e18); // 30% of supply
        revenueShareToken.mint(charlie, 200 * 1e18); // 20% of supply

        // Give payer some tokens to pay with
        paymentToken.mint(payer, INITIAL_BALANCE);

        // Fund the test contract with ETH
        vm.deal(payer, 100 ether);
        vm.deal(address(this), 100 ether);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                ETH PAYMENT TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_ReceiveETH() public {
        uint256 paymentAmount = 1 ether;

        vm.prank(payer);
        vm.expectEmit(true, false, false, true);
        emit PaymentReceived(payer, paymentAmount, address(0));

        (bool success,) = address(paymentManager).call{value: paymentAmount}("");
        assertTrue(success);

        assertEq(address(paymentManager).balance, paymentAmount);
    }

    function test_PayETH() public {
        uint256 paymentAmount = 1 ether;

        vm.prank(payer);
        vm.expectEmit(true, false, false, true);
        emit PaymentReceived(payer, paymentAmount, address(0));

        paymentManager.pay{value: paymentAmount}();

        assertEq(address(paymentManager).balance, paymentAmount);
    }

    function test_RevertReceiveZeroETH() public {
        vm.prank(payer);
        (bool success,) = address(paymentManager).call{value: 0}("");
        assertFalse(success);
    }

    function test_RevertPayZeroETH() public {
        vm.prank(payer);
        vm.expectRevert(IPaymentManager.ZeroAmount.selector);
        paymentManager.pay{value: 0}();
    }

    /*──────────────────────────────────────────────────────────────────────────
                                ERC20 PAYMENT TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_PayERC20() public {
        uint256 paymentAmount = 100 * 1e18;

        vm.startPrank(payer);
        paymentToken.approve(address(paymentManager), paymentAmount);

        vm.expectEmit(true, false, false, true);
        emit PaymentReceived(payer, paymentAmount, address(paymentToken));

        paymentManager.payERC20(address(paymentToken), paymentAmount);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(paymentManager)), paymentAmount);
    }

    function test_RevertPayERC20_ZeroAmount() public {
        vm.startPrank(payer);
        paymentToken.approve(address(paymentManager), 100 * 1e18);

        vm.expectRevert(IPaymentManager.ZeroAmount.selector);
        paymentManager.payERC20(address(paymentToken), 0);
        vm.stopPrank();
    }

    function test_RevertPayERC20_ZeroAddress() public {
        vm.prank(payer);
        vm.expectRevert(IPaymentManager.ZeroAddress.selector);
        paymentManager.payERC20(address(0), 100 * 1e18);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                DISTRIBUTION TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_DistributeETH() public {
        // First, add ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 10 ether}();

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;
        uint256 charlieBalBefore = charlie.balance;

        vm.prank(executor);
        vm.expectEmit(true, false, false, true);
        emit RevenueDistributed(address(0), 10 ether);

        paymentManager.distributeRevenue(address(0), 10 ether, holders);

        // Check distributions (alice: 50%, bob: 30%, charlie: 20%)
        assertEq(alice.balance - aliceBalBefore, 5 ether);
        assertEq(bob.balance - bobBalBefore, 3 ether);
        assertEq(charlie.balance - charlieBalBefore, 2 ether);
    }

    function test_DistributeERC20() public {
        // First, add tokens to the contract
        uint256 distributionAmount = 100 * 1e18;
        vm.prank(payer);
        paymentToken.transfer(address(paymentManager), distributionAmount);

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        vm.prank(executor);
        vm.expectEmit(true, false, false, true);
        emit RevenueDistributed(address(paymentToken), distributionAmount);

        paymentManager.distributeRevenue(address(paymentToken), distributionAmount, holders);

        // Check distributions (alice: 50%, bob: 30%, charlie: 20%)
        assertEq(paymentToken.balanceOf(alice), 50 * 1e18);
        assertEq(paymentToken.balanceOf(bob), 30 * 1e18);
        assertEq(paymentToken.balanceOf(charlie), 20 * 1e18);
    }

    function test_DistributeWithOptOut() public {
        // Bob opts out
        vm.prank(bob);
        paymentManager.optOut(true);
        assertTrue(paymentManager.isOptedOut(bob));

        // Add ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 10 ether}();

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;
        uint256 charlieBalBefore = charlie.balance;

        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 10 ether, holders);

        // Bob should get nothing, alice and charlie split based on their weights
        assertEq(bob.balance, bobBalBefore); // Bob gets nothing

        // Alice has 500 tokens, Charlie has 200 tokens (total eligible: 700)
        // Alice gets: 10 * 500/1000 = 5 ether
        // Charlie gets: 10 * 200/1000 = 2 ether
        // 3 ether remains in contract (Bob's share)
        assertEq(alice.balance - aliceBalBefore, 5 ether);
        assertEq(charlie.balance - charlieBalBefore, 2 ether);
    }

    function test_DistributeWithZeroBalance() public {
        // Create a new address with zero eligibility tokens
        address dave = address(0x6);

        // Add ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 10 ether}();

        address[] memory holders = new address[](4);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;
        holders[3] = dave;

        uint256 daveBalBefore = dave.balance;

        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 10 ether, holders);

        // Dave should get nothing
        assertEq(dave.balance, daveBalBefore);
    }

    function test_RevertDistribute_NotOwner() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        vm.prank(alice);
        vm.expectRevert();
        paymentManager.distributeRevenue(address(0), 1 ether, holders);
    }

    function test_RevertDistribute_InsufficientFunds() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        vm.prank(executor);
        vm.expectRevert(IPaymentManager.InsufficientFunds.selector);
        paymentManager.distributeRevenue(address(0), 1 ether, holders);
    }

    function test_RevertDistribute_ZeroAmount() public {
        address[] memory holders = new address[](1);
        holders[0] = alice;

        vm.prank(executor);
        vm.expectRevert(IPaymentManager.InvalidDistributionParams.selector);
        paymentManager.distributeRevenue(address(0), 0, holders);
    }

    function test_RevertDistribute_EmptyHolders() public {
        address[] memory holders = new address[](0);

        vm.prank(executor);
        vm.expectRevert(IPaymentManager.InvalidDistributionParams.selector);
        paymentManager.distributeRevenue(address(0), 1 ether, holders);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                OPT-OUT TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_OptOut() public {
        assertFalse(paymentManager.isOptedOut(alice));

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit OptOutToggled(alice, true);

        paymentManager.optOut(true);
        assertTrue(paymentManager.isOptedOut(alice));

        // Can opt back in
        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit OptOutToggled(alice, false);

        paymentManager.optOut(false);
        assertFalse(paymentManager.isOptedOut(alice));
    }

    /*──────────────────────────────────────────────────────────────────────────
                                ADMIN TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_SetRevenueShareToken() public {
        MockToken newToken = new MockToken("New Token", "NEW");

        vm.prank(executor);
        vm.expectEmit(true, false, false, false);
        emit RevenueShareTokenSet(address(newToken));

        paymentManager.setRevenueShareToken(address(newToken));
        assertEq(paymentManager.revenueShareToken(), address(newToken));
    }

    function test_RevertSetRevenueShareToken_NotOwner() public {
        MockToken newToken = new MockToken("New Token", "NEW");

        vm.prank(alice);
        vm.expectRevert();
        paymentManager.setRevenueShareToken(address(newToken));
    }

    function test_RevertSetRevenueShareToken_ZeroAddress() public {
        vm.prank(executor);
        vm.expectRevert(IPaymentManager.ZeroAddress.selector);
        paymentManager.setRevenueShareToken(address(0));
    }

    /*──────────────────────────────────────────────────────────────────────────
                            MULTIPLE DISTRIBUTION TESTS
    ──────────────────────────────────────────────────────────────────────────*/

    function test_MultipleDistributions_UnderBalance() public {
        // Add 20 ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 20 ether}();

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;
        uint256 charlieBalBefore = charlie.balance;

        // First distribution: 5 ETH
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 5 ether, holders);

        // Verify first distribution
        assertEq(alice.balance - aliceBalBefore, 2.5 ether); // 50% of 5
        assertEq(bob.balance - bobBalBefore, 1.5 ether); // 30% of 5
        assertEq(charlie.balance - charlieBalBefore, 1 ether); // 20% of 5

        // Update balances for next check
        aliceBalBefore = alice.balance;
        bobBalBefore = bob.balance;
        charlieBalBefore = charlie.balance;

        // Second distribution: 8 ETH
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 8 ether, holders);

        // Verify second distribution
        assertEq(alice.balance - aliceBalBefore, 4 ether); // 50% of 8
        assertEq(bob.balance - bobBalBefore, 2.4 ether); // 30% of 8
        assertEq(charlie.balance - charlieBalBefore, 1.6 ether); // 20% of 8

        // Third distribution: 7 ETH (total distributed = 20, equals balance)
        aliceBalBefore = alice.balance;
        bobBalBefore = bob.balance;
        charlieBalBefore = charlie.balance;

        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 7 ether, holders);

        // Verify third distribution
        assertEq(alice.balance - aliceBalBefore, 3.5 ether); // 50% of 7
        assertEq(bob.balance - bobBalBefore, 2.1 ether); // 30% of 7
        assertEq(charlie.balance - charlieBalBefore, 1.4 ether); // 20% of 7

        // Contract should have 0 balance now
        assertEq(address(paymentManager).balance, 0);
    }

    function test_MultipleDistributions_OverBalance() public {
        // Add 10 ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 10 ether}();

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        // First distribution: 7 ETH (under balance)
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 7 ether, holders);

        // Verify contract still has 3 ETH
        assertEq(address(paymentManager).balance, 3 ether);

        // Try to distribute more than remaining balance (should revert)
        vm.prank(executor);
        vm.expectRevert(IPaymentManager.InsufficientFunds.selector);
        paymentManager.distributeRevenue(address(0), 5 ether, holders);

        // Should be able to distribute exactly the remaining balance
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 3 ether, holders);

        // Contract should have 0 balance now
        assertEq(address(paymentManager).balance, 0);
    }

    function test_MultipleDistributions_WithTokenChanges() public {
        // Add 15 ETH to the contract
        vm.prank(payer);
        paymentManager.pay{value: 15 ether}();

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        // First distribution with original token balances
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 5 ether, holders);

        // Change token balances - mint more to alice
        revenueShareToken.mint(alice, 500 * 1e18); // Alice now has 1000 (66.67% of new total)
        // New total: Alice 1000, Bob 300, Charlie 200 = 1500

        uint256 aliceBalBefore = alice.balance;
        uint256 bobBalBefore = bob.balance;
        uint256 charlieBalBefore = charlie.balance;

        // Second distribution with new token balances
        vm.prank(executor);
        paymentManager.distributeRevenue(address(0), 6 ether, holders);

        // Verify distribution with new weights
        assertEq(alice.balance - aliceBalBefore, 4 ether); // 1000/1500 * 6 = 4
        assertEq(bob.balance - bobBalBefore, 1.2 ether); // 300/1500 * 6 = 1.2
        assertEq(charlie.balance - charlieBalBefore, 0.8 ether); // 200/1500 * 6 = 0.8
    }

    function test_MultipleDistributions_ERC20() public {
        // Fund contract with payment tokens
        vm.prank(payer);
        paymentToken.approve(address(paymentManager), 300 * 1e18);
        vm.prank(payer);
        paymentManager.payERC20(address(paymentToken), 300 * 1e18);

        address[] memory holders = new address[](3);
        holders[0] = alice;
        holders[1] = bob;
        holders[2] = charlie;

        // First distribution: 100 tokens
        vm.prank(executor);
        paymentManager.distributeRevenue(address(paymentToken), 100 * 1e18, holders);

        assertEq(paymentToken.balanceOf(alice), 50 * 1e18); // 50% of 100
        assertEq(paymentToken.balanceOf(bob), 30 * 1e18); // 30% of 100
        assertEq(paymentToken.balanceOf(charlie), 20 * 1e18); // 20% of 100

        // Second distribution: 150 tokens
        vm.prank(executor);
        paymentManager.distributeRevenue(address(paymentToken), 150 * 1e18, holders);

        assertEq(paymentToken.balanceOf(alice), 125 * 1e18); // 50 + 75
        assertEq(paymentToken.balanceOf(bob), 75 * 1e18); // 30 + 45
        assertEq(paymentToken.balanceOf(charlie), 50 * 1e18); // 20 + 30

        // Try to distribute more than remaining balance (should revert)
        vm.prank(executor);
        vm.expectRevert(IPaymentManager.InsufficientFunds.selector);
        paymentManager.distributeRevenue(address(paymentToken), 100 * 1e18, holders);

        // Distribute remaining 50 tokens
        vm.prank(executor);
        paymentManager.distributeRevenue(address(paymentToken), 50 * 1e18, holders);

        assertEq(paymentToken.balanceOf(address(paymentManager)), 0);
    }

    /*──────────────────────────────────────────────────────────────────────────
                                EDGE CASES & FUZZING
    ──────────────────────────────────────────────────────────────────────────*/

    function testFuzz_PayETH(uint256 amount) public {
        vm.assume(amount > 0 && amount < 100 ether);

        vm.prank(payer);
        paymentManager.pay{value: amount}();

        assertEq(address(paymentManager).balance, amount);
    }

    function testFuzz_PayERC20(uint256 amount) public {
        vm.assume(amount > 0 && amount < INITIAL_BALANCE);

        vm.startPrank(payer);
        paymentToken.approve(address(paymentManager), amount);
        paymentManager.payERC20(address(paymentToken), amount);
        vm.stopPrank();

        assertEq(paymentToken.balanceOf(address(paymentManager)), amount);
    }
}
