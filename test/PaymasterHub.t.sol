// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {PaymasterHubLens, Config, Budget, Rule, FeeCaps, Bounty} from "../src/PaymasterHubLens.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

contract MockEntryPoint is IEntryPoint {
    mapping(address => uint256) private _deposits;
    address public lastPaymaster;

    function depositTo(address account) external payable override {
        _deposits[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external override {
        require(_deposits[msg.sender] >= withdrawAmount, "Insufficient deposit");
        _deposits[msg.sender] -= withdrawAmount;
        withdrawAddress.transfer(withdrawAmount);
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _deposits[account];
    }

    // Helper to simulate validatePaymasterUserOp call
    function simulateValidatePaymasterUserOp(
        address paymaster,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        lastPaymaster = paymaster;
        return IPaymaster(paymaster).validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    // Helper to simulate postOp call
    function simulatePostOp(address paymaster, IPaymaster.PostOpMode mode, bytes memory context, uint256 actualGasCost)
        external
    {
        IPaymaster(paymaster).postOp(mode, context, actualGasCost);
    }
}

contract MockHats is IHats {
    mapping(address => mapping(uint256 => bool)) private _wearers;

    function mintHat(uint256 _hatId, address _wearer) external returns (bool success) {
        _wearers[_wearer][_hatId] = true;
        return true;
    }

    function isWearerOfHat(address _wearer, uint256 _hatId) external view returns (bool) {
        return _wearers[_wearer][_hatId];
    }

    // Mock other required IHats functions
    function createHat(uint256, string calldata, uint32, address, address, bool, string calldata)
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function batchCreateHats(
        uint256[] calldata,
        string[] calldata,
        uint32[] calldata,
        address[] calldata,
        address[] calldata,
        bool[] calldata,
        string[] calldata
    ) external pure returns (bool) {
        return true;
    }

    function getNextId(uint256) external pure returns (uint256) {
        return 0;
    }

    function batchMintHats(uint256[] calldata, address[] calldata) external pure returns (bool) {
        return true;
    }

    function setHatStatus(uint256, bool) external pure returns (bool) {
        return true;
    }

    function checkHatStatus(uint256) external pure returns (bool) {
        return true;
    }

    function setHatWearerStatus(uint256, address, bool, bool) external pure returns (bool) {
        return true;
    }

    function checkHatWearerStatus(uint256, address) external pure returns (bool) {
        return true;
    }

    function renounceHat(uint256) external {}

    function transferHat(uint256, address, address) external {}

    function makeHatImmutable(uint256) external {}

    function changeHatDetails(uint256, string calldata, string calldata) external {}

    function changeHatEligibility(uint256, address) external {}

    function changeHatToggle(uint256, address) external {}

    function changeHatImageURI(uint256, string calldata) external {}

    function changeHatMaxSupply(uint256, uint32) external {}

    function requestLinkTopHatToTree(uint32, uint256) external {}

    function unlinkTopHatFromTree(uint32, address) external {}

    function viewHat(uint256)
        external
        pure
        returns (
            string memory details,
            uint32 maxSupply,
            uint32 supply,
            address eligibility,
            address toggle,
            string memory imageURI,
            uint16 lastHatId,
            bool mutable_,
            bool active
        )
    {
        return ("", 0, 0, address(0), address(0), "", 0, false, true);
    }

    function changeHatDetails(uint256, string memory) external {}

    function approveLinkTopHatToTree(uint32, uint256, address, address, string calldata, string calldata) external {}

    function relinkTopHatWithinTree(uint32, uint256, address, address, string calldata, string calldata) external {}

    function isTopHat(uint256) external pure returns (bool) {
        return false;
    }

    function isLocalTopHat(uint256) external pure returns (bool) {
        return false;
    }

    function isValidHatId(uint256) external pure returns (bool) {
        return true;
    }

    function getLocalHatLevel(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTopHatDomain(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTippyTopHatDomain(uint32) external pure returns (uint32) {
        return 0;
    }

    function noCircularLinkage(uint32, uint256) external pure returns (bool) {
        return true;
    }

    function sameTippyTopHatDomain(uint32, uint256) external pure returns (bool) {
        return true;
    }

    function getAdminAtLevel(uint256, uint32) external pure returns (uint256) {
        return 0;
    }

    function getAdminAtLocalLevel(uint256, uint32) external pure returns (uint256) {
        return 0;
    }

    function getTopHatDomainOfHat(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTippyTopHatDomainOfHat(uint256) external pure returns (uint32) {
        return 0;
    }

    function tippyHatDomain() external pure returns (uint32) {
        return 0;
    }

    function noCircularLinkage(uint32) external pure returns (uint256) {
        return 0;
    }

    function linkedTreeAdmins(uint32) external pure returns (uint256) {
        return 0;
    }

    function linkedTreeRequests(uint32) external pure returns (uint256) {
        return 0;
    }

    function lastTopHatId() external pure returns (uint256) {
        return 0;
    }

    function baseImageURI() external pure returns (string memory) {
        return "";
    }

    // Missing implementations
    function balanceOf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function balanceOfBatch(address[] calldata, uint256[] calldata) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function buildHatId(uint256, uint16) external pure returns (uint256) {
        return 0;
    }

    function getHatEligibilityModule(uint256) external pure returns (address) {
        return address(0);
    }

    function getHatLevel(uint256) external pure returns (uint32) {
        return 0;
    }

    function getHatMaxSupply(uint256) external pure returns (uint32) {
        return 0;
    }

    function getHatToggleModule(uint256) external pure returns (address) {
        return address(0);
    }

    function getImageURIForHat(uint256) external pure returns (string memory) {
        return "";
    }

    function hatSupply(uint256) external pure returns (uint32) {
        return 0;
    }

    function isAdminOfHat(address, uint256) external pure returns (bool) {
        return false;
    }

    function isEligible(address, uint256) external pure returns (bool) {
        return true;
    }

    function isInGoodStanding(address, uint256) external pure returns (bool) {
        return true;
    }

    function mintTopHat(address, string memory, string memory) external pure returns (uint256) {
        return 0;
    }

    function uri(uint256) external pure returns (string memory) {
        return "";
    }
}

contract MockAccount {
    // SimpleAccount-like execute function
    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Execution failed");
        return result;
    }

    function executeBatch(address[] calldata targets, bytes[] calldata data) external payable {
        require(targets.length == data.length, "Length mismatch");
        for (uint256 i = 0; i < targets.length; i++) {
            (bool success,) = targets[i].call(data[i]);
            require(success, "Batch execution failed");
        }
    }
}

contract PaymasterHubTest is Test {
    PaymasterHub public hub;
    PaymasterHubLens public lens;
    MockEntryPoint public entryPoint;
    MockHats public hats;
    MockAccount public account;

    address public admin = address(0x1);
    address public bundler = address(0x2);
    address public user = address(0x3);

    uint256 constant ADMIN_HAT = 1;
    uint256 constant USER_HAT = 2;

    // Events to test
    event RuleSet(address indexed target, bytes4 indexed selector, bool allowed, uint32 maxCallGasHint);
    event BudgetSet(bytes32 indexed subjectKey, uint128 capPerEpoch, uint32 epochLen, uint32 epochStart);
    event UsageIncreased(bytes32 indexed subjectKey, uint256 delta, uint128 usedInEpoch, uint32 epochStart);
    event BountyPaid(bytes32 indexed userOpHash, address indexed to, uint256 amount);

    // Allow test contract to receive ETH for bounty tests
    receive() external payable {}

    function setUp() public {
        // Deploy mocks
        entryPoint = new MockEntryPoint();
        hats = new MockHats();
        account = new MockAccount();

        // Deploy PaymasterHub
        hub = new PaymasterHub(address(entryPoint), address(hats), ADMIN_HAT);

        // Deploy PaymasterHubLens
        lens = new PaymasterHubLens(address(hub));

        // Setup hats
        hats.mintHat(ADMIN_HAT, admin);
        hats.mintHat(USER_HAT, user);

        // Fund accounts
        vm.deal(admin, 100 ether);
        vm.deal(bundler, 10 ether);
        vm.deal(user, 10 ether);
    }

    function testInitialization() public {
        Config memory config = lens.config();
        assertEq(hub.ENTRY_POINT(), address(entryPoint));
        assertEq(config.hats, address(hats));
        assertEq(config.adminHatId, ADMIN_HAT);
        assertEq(config.paused, false);
        assertEq(config.version, 1);
    }

    function testAdminAccessControl() public {
        // Non-admin should fail
        vm.prank(user);
        vm.expectRevert(PaymasterHub.NotAdmin.selector);
        hub.setPause(true);

        // Admin should succeed
        vm.prank(admin);
        hub.setPause(true);

        Config memory config = lens.config();
        assertTrue(config.paused);
    }

    function testSetRule() public {
        address target = address(0x1234);
        bytes4 selector = bytes4(0x12345678);

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit RuleSet(target, selector, true, 100000);
        hub.setRule(target, selector, true, 100000);

        Rule memory rule = lens.ruleOf(target, selector);
        assertTrue(rule.allowed);
        assertEq(rule.maxCallGasHint, 100000);
    }

    function testSetBudget() public {
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(user)));
        uint128 cap = 1 ether;
        uint32 epochLen = 1 days;

        vm.prank(admin);
        vm.expectEmit(true, false, false, true);
        emit BudgetSet(subjectKey, cap, epochLen, uint32(block.timestamp));
        hub.setBudget(subjectKey, cap, epochLen);

        Budget memory budget = lens.budgetOf(subjectKey);
        assertEq(budget.capPerEpoch, cap);
        assertEq(budget.epochLen, epochLen);
        assertEq(budget.epochStart, uint32(block.timestamp));
    }

    function testValidatePaymasterUserOp_AccountSubject() public {
        // Setup
        _setupBasicRulesAndBudget();

        // Create UserOp
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 0.1 ether;

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        // Check results
        assertEq(validationData, 0);
        assertTrue(context.length > 0);
    }

    function testValidatePaymasterUserOp_HatSubject() public {
        // Setup
        _setupBasicRulesAndBudget();

        // Setup hat budget
        bytes32 hatSubjectKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(USER_HAT))));
        vm.prank(admin);
        hub.setBudget(hatSubjectKey, 2 ether, 1 days);

        // Create UserOp with hat subject
        PackedUserOperation memory userOp = _createHatBasedUserOp(user, USER_HAT);
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 0.1 ether;

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);

        // Check results
        assertEq(validationData, 0);
        assertTrue(context.length > 0);
    }

    function testValidatePaymasterUserOp_RevertOnPaused() public {
        _setupBasicRulesAndBudget();

        // Pause the contract
        vm.prank(admin);
        hub.setPause(true);

        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Should revert when paused
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.Paused.selector);
        hub.validatePaymasterUserOp(userOp, userOpHash, 0.1 ether);
    }

    function testValidatePaymasterUserOp_RevertOnInvalidVersion() public {
        _setupBasicRulesAndBudget();

        // Create UserOp with invalid version
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        // Modify paymasterAndData to have version 2
        bytes memory invalidPaymasterData = abi.encodePacked(
            address(hub),
            uint8(2), // Invalid version
            uint8(0), // subject type
            bytes20(address(account)),
            uint32(0),
            uint64(0)
        );
        userOp.paymasterAndData = invalidPaymasterData;

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.InvalidVersion.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.1 ether);
    }

    function testValidatePaymasterUserOp_RevertOnBudgetExceeded() public {
        _setupBasicRulesAndBudget();

        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));
        uint256 maxCost = 2 ether; // Exceeds budget

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
        hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    function testValidatePaymasterUserOp_RevertOnDeniedRule() public {
        // Setup budget but no rules
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        vm.prank(admin);
        hub.setBudget(subjectKey, 1 ether, 1 days);

        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(address(entryPoint));
        // Contract extracts target from execute parameters (0x123) and uses execute selector
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(0x123), bytes4(keccak256("execute(address,uint256,bytes)"))
            )
        );
        hub.validatePaymasterUserOp(userOp, userOpHash, 0.1 ether);
    }

    function testPostOp_UpdatesUsage() public {
        _setupBasicRulesAndBudget();

        // First validate to get context
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);

        // Execute postOp
        uint256 actualGasCost = 0.01 ether;
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));

        vm.prank(address(entryPoint));
        vm.expectEmit(true, false, false, true);
        emit UsageIncreased(subjectKey, actualGasCost, uint64(actualGasCost), uint32(block.timestamp));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost);

        // Check budget was updated
        Budget memory budget = lens.budgetOf(subjectKey);
        assertEq(budget.usedInEpoch, actualGasCost);
    }

    function testPostOp_WithBounty() public {
        _setupBasicRulesAndBudget();

        // Enable bounty
        vm.prank(admin);
        hub.setBounty(true, 0.01 ether, 1000); // 10% bounty

        // Fund bounty pool
        vm.prank(admin);
        hub.fundBounty{value: 1 ether}();

        // Create UserOp with mailbox commit
        PackedUserOperation memory userOp = _createUserOpWithMailbox(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);

        // Execute postOp - should pay bounty
        uint256 actualGasCost = 0.01 ether;
        uint256 expectedBounty = 0.001 ether; // 10% of actual cost

        // Note: tx.origin in Foundry is DefaultSender (0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38)
        address expectedRecipient = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);
        uint256 balanceBefore = expectedRecipient.balance;

        vm.prank(address(entryPoint));
        vm.expectEmit(true, true, false, true);
        emit BountyPaid(userOpHash, expectedRecipient, expectedBounty);
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualGasCost);

        // Check DefaultSender received bounty (since it's tx.origin in Foundry tests)
        assertEq(expectedRecipient.balance - balanceBefore, expectedBounty);
    }

    function testEpochRolling() public {
        _setupBasicRulesAndBudget();

        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        // Use budget in first epoch
        vm.prank(address(entryPoint));
        (bytes memory context1,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context1, 0.5 ether);

        Budget memory budget1 = lens.budgetOf(subjectKey);
        assertEq(budget1.usedInEpoch, 0.5 ether);

        // Move to next epoch
        vm.warp(block.timestamp + 1 days + 1);

        // Should be able to use full budget again
        vm.prank(address(entryPoint));
        (bytes memory context2,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.8 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context2, 0.3 ether);

        Budget memory budget2 = lens.budgetOf(subjectKey);
        assertEq(budget2.usedInEpoch, 0.3 ether); // Reset after epoch roll
        assertTrue(budget2.epochStart > budget1.epochStart);
    }

    function testFeeCaps() public {
        _setupBasicRulesAndBudget();

        // Set fee caps
        vm.prank(admin);
        hub.setFeeCaps(
            1 gwei, // maxFeePerGas
            1 gwei, // maxPriorityFeePerGas
            100000, // maxCallGas
            50000, // maxVerificationGas
            20000 // maxPreVerificationGas
        );

        // Create UserOp exceeding fee caps
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        userOp.maxFeePerGas = 2 gwei; // Exceeds cap
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.FeeTooHigh.selector);
        hub.validatePaymasterUserOp(userOp, userOpHash, 0.1 ether);
    }

    function testDepositAndWithdraw() public {
        // Deposit to EntryPoint
        vm.prank(admin);
        hub.depositToEntryPoint{value: 5 ether}();

        assertEq(entryPoint.balanceOf(address(hub)), 5 ether);

        // Withdraw from EntryPoint
        address payable recipient = payable(address(0x999));
        uint256 balanceBefore = recipient.balance;

        vm.prank(admin);
        hub.withdrawFromEntryPoint(recipient, 2 ether);

        assertEq(entryPoint.balanceOf(address(hub)), 3 ether);
        assertEq(recipient.balance - balanceBefore, 2 ether);
    }

    function testMailboxFunction() public {
        bytes memory packedOp = abi.encodePacked("test user op data");
        bytes32 expectedHash = keccak256(packedOp);

        vm.expectEmit(true, true, false, false);
        emit PaymasterHub.UserOpPosted(expectedHash, user);

        vm.prank(user);
        bytes32 returnedHash = hub.postUserOp(packedOp);

        assertEq(returnedHash, expectedHash);
    }

    // ============ Helper Functions ============

    function _setupBasicRulesAndBudget() internal {
        // Set up basic rule for execute function
        vm.startPrank(admin);

        // Allow calls to address(0x123) with execute selector (since that's what gets validated)
        hub.setRule(address(0x123), bytes4(keccak256("execute(address,uint256,bytes)")), true, 0);

        // Set budget for account subject
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));
        hub.setBudget(subjectKey, 1 ether, 1 days);

        // Set reasonable fee caps
        hub.setFeeCaps(
            100 gwei, // maxFeePerGas
            10 gwei, // maxPriorityFeePerGas
            500000, // maxCallGas
            200000, // maxVerificationGas
            100000 // maxPreVerificationGas
        );

        // Deposit funds
        hub.depositToEntryPoint{value: 10 ether}();

        vm.stopPrank();
    }

    function _createBasicUserOp(address sender) internal view returns (PackedUserOperation memory) {
        bytes memory callData =
            abi.encodeWithSelector(bytes4(keccak256("execute(address,uint256,bytes)")), address(0x123), 0, "");

        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1), // version
            uint8(0), // account subject
            bytes20(sender),
            uint32(0), // RULE_ID_GENERIC
            uint64(0) // no mailbox
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

    function _createHatBasedUserOp(address sender, uint256 hatId) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory userOp = _createBasicUserOp(sender);

        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1), // version
            uint8(1), // hat subject
            bytes20(uint160(hatId)),
            uint32(0), // RULE_ID_GENERIC
            uint64(0) // no mailbox
        );

        userOp.paymasterAndData = paymasterAndData;
        return userOp;
    }

    function _createUserOpWithMailbox(address sender) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory userOp = _createBasicUserOp(sender);

        // Calculate mailbox commit
        bytes32 fullHash = keccak256(abi.encode(userOp));
        uint64 mailboxCommit8 = uint64(uint256(fullHash) >> 192);

        bytes memory paymasterAndData = abi.encodePacked(
            address(hub),
            uint8(1), // version
            uint8(0), // account subject
            bytes20(sender),
            uint32(0), // RULE_ID_GENERIC
            mailboxCommit8
        );

        userOp.paymasterAndData = paymasterAndData;
        return userOp;
    }

    // ============ Fuzzing Tests ============

    function testFuzz_BudgetEnforcement(uint64 cap, uint64 used, uint256 maxCost) public {
        cap = uint64(bound(cap, 0.01 ether, 10 ether));
        used = uint64(bound(used, 0, cap));
        maxCost = bound(maxCost, 0, 100 ether);

        _setupBasicRulesAndBudget();

        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));

        // Set specific budget
        vm.prank(admin);
        hub.setBudget(subjectKey, cap, 1 days);

        // Simulate prior usage
        if (used > 0) {
            PackedUserOperation memory userOp = _createBasicUserOp(address(account));
            bytes32 userOpHash = keccak256(abi.encode(userOp));

            vm.prank(address(entryPoint));
            (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, used);

            vm.prank(address(entryPoint));
            hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, used);
        }

        // Try to use more budget
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(address(entryPoint));
        if (used + maxCost > cap) {
            vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
            hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);
        } else {
            (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, maxCost);
            assertTrue(context.length > 0);
        }
    }

    function testFuzz_EpochRolling(uint32 epochLen, uint256 timeJump) public {
        epochLen = uint32(bound(epochLen, 1 hours, 30 days));
        timeJump = bound(timeJump, 0, 365 days);

        _setupBasicRulesAndBudget();

        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), address(account)));

        // Set budget with specific epoch length
        vm.prank(admin);
        hub.setBudget(subjectKey, 1 ether, epochLen);

        // Use some budget
        PackedUserOperation memory userOp = _createBasicUserOp(address(account));
        bytes32 userOpHash = keccak256(abi.encode(userOp));

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, userOpHash, 0.5 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 0.5 ether);

        // Jump time
        vm.warp(block.timestamp + timeJump);

        // Check if we can use budget again
        Budget memory budget = lens.budgetOf(subjectKey);
        uint256 remaining = lens.remaining(subjectKey);

        if (timeJump >= epochLen) {
            // Should have reset
            assertEq(remaining, 1 ether);
        } else {
            // Should still be within same epoch
            assertEq(remaining, 0.5 ether);
        }
    }
}
