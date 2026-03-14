// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// PasskeyAccount
import {PasskeyAccount} from "../src/PasskeyAccount.sol";
import {PasskeyAccountFactory} from "../src/PasskeyAccountFactory.sol";
import {IPasskeyAccount} from "../src/interfaces/IPasskeyAccount.sol";

// PaymasterHub
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";

// Hats
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

/**
 * @title PasskeyPaymasterIntegrationTest
 * @notice Comprehensive integration tests for PasskeyAccount + PaymasterHub compatibility
 * @dev Tests the full ERC-4337 flow with passkey accounts and paymaster sponsorship
 */
contract PasskeyPaymasterIntegrationTest is Test {
    /*══════════════════════════════════════════════════════════════════════
                                  MOCK CONTRACTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Mock EntryPoint that orchestrates the ERC-4337 validation flow
    MockEntryPointIntegration entryPoint;

    /// @notice Mock Hats for access control
    MockHatsIntegration hats;

    /// @notice Mock target contract for execute() calls
    MockTarget mockTarget;

    /*══════════════════════════════════════════════════════════════════════
                                  STATE VARIABLES
    ══════════════════════════════════════════════════════════════════════*/

    // PasskeyAccount infrastructure
    PasskeyAccount accountImpl;
    PasskeyAccountFactory factoryImpl;
    UpgradeableBeacon accountBeacon;
    UpgradeableBeacon factoryBeacon;
    PasskeyAccountFactory factory;

    // PaymasterHub
    PaymasterHub hub;

    // Test addresses
    address owner = address(0x1);
    address poaManager = address(0x2);
    address orgAdmin = address(0x3);
    address user = address(0x4);
    address guardian = address(0x5);
    address bundler = address(0x6);

    // Voucher key pair for signing vouches
    uint256 constant VOUCHER_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address voucherAddr; // Will be derived from private key

    // Hat IDs
    uint256 constant ADMIN_HAT = 1;
    uint256 constant OPERATOR_HAT = 2;
    uint256 constant USER_HAT = 3;
    uint256 constant VOUCHER_HAT = 4;

    // Org ID
    bytes32 constant ORG_ID = keccak256("TEST_ORG");

    // Test credentials (not real cryptographic keys - structure testing only)
    bytes32 constant CREDENTIAL_ID = keccak256("test_credential_1");
    bytes32 constant PUB_KEY_X = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    bytes32 constant PUB_KEY_Y = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

    // PaymasterHub constants
    uint8 constant PAYMASTER_DATA_VERSION = 1;
    uint8 constant SUBJECT_TYPE_ACCOUNT = 0x00;
    uint8 constant SUBJECT_TYPE_HAT = 0x01;
    uint32 constant RULE_ID_GENERIC = 0x00000000;
    uint32 constant RULE_ID_EXECUTOR = 0x00000001;
    uint32 constant RULE_ID_COARSE = 0x000000FF;

    // Function selectors
    bytes4 constant EXECUTE_SELECTOR = 0xb61d27f6; // execute(address,uint256,bytes)
    bytes4 constant EXECUTE_BATCH_SELECTOR = 0x47e1da2a; // executeBatch(address[],uint256[],bytes[])
    bytes4 constant SIMPLE_EXECUTE_BATCH_SELECTOR = 0x18dfb3c7; // executeBatch(address[],bytes[])

    /*══════════════════════════════════════════════════════════════════════
                                     EVENTS
    ══════════════════════════════════════════════════════════════════════*/

    event RuleSet(
        bytes32 indexed orgId, address indexed target, bytes4 indexed selector, bool allowed, uint32 maxCallGasHint
    );
    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event BatchExecuted(uint256 count);

    /*══════════════════════════════════════════════════════════════════════
                                     SETUP
    ══════════════════════════════════════════════════════════════════════*/

    function setUp() public {
        // Derive voucher address from private key
        voucherAddr = vm.addr(VOUCHER_PRIVATE_KEY);

        vm.startPrank(owner);

        // Deploy mocks
        entryPoint = new MockEntryPointIntegration();
        hats = new MockHatsIntegration();
        mockTarget = new MockTarget();

        // Setup hats
        hats.mintHat(ADMIN_HAT, orgAdmin);
        hats.mintHat(OPERATOR_HAT, orgAdmin);
        hats.mintHat(USER_HAT, user);
        hats.mintHat(VOUCHER_HAT, voucherAddr);

        // ════════════════════════════════════════════════════════════════
        // Deploy PasskeyAccount infrastructure (universal factory)
        // ════════════════════════════════════════════════════════════════

        accountImpl = new PasskeyAccount();
        factoryImpl = new PasskeyAccountFactory();

        accountBeacon = new UpgradeableBeacon(address(accountImpl), owner);
        factoryBeacon = new UpgradeableBeacon(address(factoryImpl), owner);

        bytes memory factoryInitData = abi.encodeWithSelector(
            PasskeyAccountFactory.initialize.selector,
            owner, // poaManager
            address(accountBeacon),
            guardian, // poaGuardian
            uint48(7 days) // recoveryDelay
        );
        factory = PasskeyAccountFactory(address(new BeaconProxy(address(factoryBeacon), factoryInitData)));

        // ════════════════════════════════════════════════════════════════
        // Deploy PaymasterHub
        // ════════════════════════════════════════════════════════════════

        PaymasterHub hubImpl = new PaymasterHub();
        bytes memory hubInitData =
            abi.encodeWithSelector(PaymasterHub.initialize.selector, address(entryPoint), address(hats), poaManager);
        ERC1967Proxy hubProxy = new ERC1967Proxy(address(hubImpl), hubInitData);
        hub = PaymasterHub(payable(address(hubProxy)));

        vm.stopPrank();

        // Register org in PaymasterHub (requires poaManager)
        vm.prank(poaManager);
        hub.registerOrg(ORG_ID, ADMIN_HAT, OPERATOR_HAT);

        // Fund test accounts BEFORE using them for deposits
        vm.deal(owner, 100 ether);
        vm.deal(orgAdmin, 100 ether);
        vm.deal(user, 100 ether);
        vm.deal(bundler, 100 ether);

        // Fund PaymasterHub via EntryPoint deposit (requires org operator with funds)
        vm.prank(orgAdmin);
        hub.depositToEntryPoint{value: 1 ether}(ORG_ID);

        // Deposit for org in PaymasterHub
        vm.prank(owner);
        hub.depositForOrg{value: 0.1 ether}(ORG_ID);
    }

    /*══════════════════════════════════════════════════════════════════════
                            HELPER FUNCTIONS
    ══════════════════════════════════════════════════════════════════════*/

    function _createPasskeyAccount() internal returns (PasskeyAccount) {
        vm.prank(user);
        address account = factory.createAccount(CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
        return PasskeyAccount(payable(account));
    }

    function _setupDefaultBudget(address account) internal {
        // Set a generous default budget for the account
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(account)))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 1 ether, 1 days);
    }

    function _buildPaymasterData(bytes32 orgId, uint8 subjectType, bytes32 subjectId, uint32 ruleId)
        internal
        view
        returns (bytes memory)
    {
        // ERC-4337 v0.7 format: paymaster(20) | verificationGasLimit(16) | postOpGasLimit(16) | version(1) | orgId(32) | subjectType(1) | subjectId(32) | ruleId(4) = 122 bytes
        return abi.encodePacked(
            address(hub), // 20 bytes
            uint128(200_000), // paymasterVerificationGasLimit - 16 bytes
            uint128(100_000), // paymasterPostOpGasLimit - 16 bytes
            PAYMASTER_DATA_VERSION, // 1 byte
            orgId, // 32 bytes
            subjectType, // 1 byte
            subjectId, // 32 bytes
            ruleId // 4 bytes
        );
    }

    function _buildExecuteCalldata(address target, uint256 value, bytes memory data)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(EXECUTE_SELECTOR, target, value, data);
    }

    function _buildExecuteBatchCalldata(address[] memory targets, uint256[] memory values, bytes[] memory datas)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodeWithSelector(EXECUTE_BATCH_SELECTOR, targets, values, datas);
    }

    function _createUserOp(address sender, bytes memory callData, bytes memory paymasterAndData, bytes memory signature)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(500000, 500000), // verification, call
            preVerificationGas: 100000,
            gasFees: UserOpLib.packGasFees(1 gwei, 10 gwei),
            paymasterAndData: paymasterAndData,
            signature: signature
        });
    }

    /*══════════════════════════════════════════════════════════════════════
                    EXECUTE() COMPATIBILITY TESTS
    ══════════════════════════════════════════════════════════════════════*/

    function testExecute_RuleValidation_Allowed() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Set rule allowing mockTarget.doSomething()
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build UserOperation with execute() calling mockTarget.doSomething()
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Simulate EntryPoint calling validatePaymasterUserOp
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        // Should succeed (validationData == 0 means success)
        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");
    }

    function testExecute_RuleValidation_Denied() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Don't set any rules - by default everything is denied

        // Build UserOperation
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Simulate EntryPoint calling validatePaymasterUserOp
        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(mockTarget), MockTarget.doSomething.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecute_ExtractsInnerTargetAndSelector() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Create two different targets
        MockTarget target1 = new MockTarget();
        MockTarget target2 = new MockTarget();

        // Only allow target1.doSomething(), NOT target2
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(target1), MockTarget.doSomething.selector, true, 0);

        // Build UserOp calling target1 - should succeed
        bytes memory innerCall1 = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData1 = _buildExecuteCalldata(address(target1), 0, innerCall1);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp1 = _createUserOp(address(account), callData1, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context1, uint256 validationData1) = hub.validatePaymasterUserOp(userOp1, bytes32(0), 0.001 ether);
        assertEq(validationData1, 0, "Target1 should be allowed");
        assertTrue(context1.length > 0);

        // Build UserOp calling target2 - should fail
        bytes memory innerCall2 = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData2 = _buildExecuteCalldata(address(target2), 0, innerCall2);

        PackedUserOperation memory userOp2 = _createUserOp(address(account), callData2, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(target2), MockTarget.doSomething.selector)
        );
        hub.validatePaymasterUserOp(userOp2, bytes32(0), 0.001 ether);
    }

    /*══════════════════════════════════════════════════════════════════════
                    EXECUTEBATCH() INNER-CALL RULE VALIDATION TESTS
    ══════════════════════════════════════════════════════════════════════*/

    function testExecuteBatch_AllInnerCallsWhitelisted_Succeeds() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist each inner target/selector individually
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomethingElse.selector, true, 0);
        vm.stopPrank();

        // Build executeBatch with 2 inner calls
        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(mockTarget);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        datas[1] = abi.encodeWithSelector(MockTarget.doSomethingElse.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "executeBatch with all whitelisted inner calls should pass");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_NoRulesSet_DeniesFirstInnerCall() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Don't set any rules - first inner call should be denied
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(mockTarget), MockTarget.doSomething.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_InnerSelectorsCorrectlyExtracted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Only whitelist doSomething, NOT doSomethingElse
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build batch with both calls - second should be denied
        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(mockTarget);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        datas[1] = abi.encodeWithSelector(MockTarget.doSomethingElse.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(mockTarget), MockTarget.doSomethingElse.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_OneInnerCallDenied_RevertsPrecise() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        MockTarget target2 = new MockTarget();

        // Whitelist target1.doSomething and target2.doSomethingElse
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);
        hub.setRule(ORG_ID, address(target2), MockTarget.doSomethingElse.selector, true, 0);
        vm.stopPrank();

        // Batch calls target2.doSomething (NOT whitelisted - only doSomethingElse is)
        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(target2);

        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        datas[1] = abi.encodeWithSelector(MockTarget.doSomething.selector); // Wrong selector for target2

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(target2), MockTarget.doSomething.selector)
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_EmptyBatch_Succeeds() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Empty batch - no inner calls to deny
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory datas = new bytes[](0);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Empty batch should pass");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_SingleInnerCall_MatchesExecuteBehavior() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist the inner call
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Single inner call in batch - should work same as execute()
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Single-call batch should match execute behavior");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_OnboardingSelectors_RegisterAndJoinAndClaim() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Deploy mock org contracts
        MockRegistry mockRegistry = new MockRegistry();
        MockQuickJoin mockQuickJoin = new MockQuickJoin();
        MockEligibility mockEligibility = new MockEligibility();

        // Whitelist all 3 onboarding selectors
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockRegistry), MockRegistry.registerAccount.selector, true, 0);
        hub.setRule(ORG_ID, address(mockQuickJoin), MockQuickJoin.quickJoinWithUser.selector, true, 0);
        hub.setRule(ORG_ID, address(mockEligibility), MockEligibility.claimVouchedHat.selector, true, 0);
        vm.stopPrank();

        // Build the exact same batch as PasskeyOnboardingService.deployWithExistingCredential
        address[] memory targets = new address[](3);
        targets[0] = address(mockRegistry);
        targets[1] = address(mockQuickJoin);
        targets[2] = address(mockEligibility);

        uint256[] memory values = new uint256[](3);
        values[0] = 0;
        values[1] = 0;
        values[2] = 0;

        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encodeWithSelector(MockRegistry.registerAccount.selector, "testuser");
        datas[1] = abi.encodeWithSelector(MockQuickJoin.quickJoinWithUser.selector);
        datas[2] = abi.encodeWithSelector(MockEligibility.claimVouchedHat.selector, uint256(42));

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Onboarding batch (register + join + claim) should pass");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_OnboardingSelectors_MissingClaimRule_Denied() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        MockRegistry mockRegistry = new MockRegistry();
        MockQuickJoin mockQuickJoin = new MockQuickJoin();
        MockEligibility mockEligibility = new MockEligibility();

        // Whitelist register and join, but NOT claimVouchedHat
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockRegistry), MockRegistry.registerAccount.selector, true, 0);
        hub.setRule(ORG_ID, address(mockQuickJoin), MockQuickJoin.quickJoinWithUser.selector, true, 0);
        // Deliberately NOT whitelisting claimVouchedHat
        vm.stopPrank();

        address[] memory targets = new address[](3);
        targets[0] = address(mockRegistry);
        targets[1] = address(mockQuickJoin);
        targets[2] = address(mockEligibility);

        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encodeWithSelector(MockRegistry.registerAccount.selector, "testuser");
        datas[1] = abi.encodeWithSelector(MockQuickJoin.quickJoinWithUser.selector);
        datas[2] = abi.encodeWithSelector(MockEligibility.claimVouchedHat.selector, uint256(42));

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(mockEligibility), MockEligibility.claimVouchedHat.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_MixedTargets_AllWhitelisted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        MockTarget target2 = new MockTarget();
        MockTarget target3 = new MockTarget();

        // Whitelist all 3 different targets with different selectors
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);
        hub.setRule(ORG_ID, address(target2), MockTarget.doSomethingElse.selector, true, 0);
        hub.setRule(ORG_ID, address(target3), MockTarget.doWithValue.selector, true, 0);
        vm.stopPrank();

        address[] memory targets = new address[](3);
        targets[0] = address(mockTarget);
        targets[1] = address(target2);
        targets[2] = address(target3);

        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        datas[1] = abi.encodeWithSelector(MockTarget.doSomethingElse.selector);
        datas[2] = abi.encodeWithSelector(MockTarget.doWithValue.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "All whitelisted mixed targets should pass");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_MixedTargets_SecondDenied() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        MockTarget target2 = new MockTarget();

        // Only whitelist first target, NOT second
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        address[] memory targets = new address[](2);
        targets[0] = address(mockTarget);
        targets[1] = address(target2);

        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        datas[1] = abi.encodeWithSelector(MockTarget.doSomethingElse.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(target2), MockTarget.doSomethingElse.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_SimpleAccountPattern_Recognized() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist the inner call
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build SimpleAccount executeBatch(address[],bytes[]) with selector 0x18dfb3c7
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = abi.encodeWithSelector(SIMPLE_EXECUTE_BATCH_SELECTOR, targets, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "SimpleAccount executeBatch should validate inner calls");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_SimpleAccountPattern_Denied() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // No rule set - inner call should be denied
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = abi.encodeWithSelector(SIMPLE_EXECUTE_BATCH_SELECTOR, targets, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(
                PaymasterHub.RuleDenied.selector, address(mockTarget), MockTarget.doSomething.selector
            )
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_InnerCallEmptyData_UsesZeroSelector() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Inner call with empty bytes - selector defaults to bytes4(0)
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = ""; // Empty calldata - raw transfer / fallback

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Should be denied: (mockTarget, bytes4(0)) is not whitelisted
        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(mockTarget), bytes4(0)));
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_InnerCallShortData_UsesZeroSelector() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Inner call with < 4 bytes - selector defaults to bytes4(0)
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = hex"aabb"; // Only 2 bytes

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(mockTarget), bytes4(0)));
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_EmptyDataWhitelisted_Passes() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist bytes4(0) for mockTarget - allowing raw transfer / fallback
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), bytes4(0), true, 0);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = ""; // Empty calldata

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Empty data should pass when bytes4(0) is whitelisted");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_NestedBatchInsideBatch_DeniedUnlessWhitelisted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Only whitelist the benign inner call, NOT executeBatch on the account itself
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Construct a nested executeBatch as inner calldata targeting the account
        address[] memory innerTargets = new address[](1);
        innerTargets[0] = address(mockTarget);
        uint256[] memory innerValues = new uint256[](1);
        bytes[] memory innerDatas = new bytes[](1);
        innerDatas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory nestedBatchCalldata =
            abi.encodeWithSelector(EXECUTE_BATCH_SELECTOR, innerTargets, innerValues, innerDatas);

        // Outer batch: one call targets the account itself with executeBatch
        address[] memory targets = new address[](1);
        targets[0] = address(account); // Self-call
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = nestedBatchCalldata; // executeBatch as inner call

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Should be denied: (account, executeBatch_selector) is not whitelisted
        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(account), EXECUTE_BATCH_SELECTOR)
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_NestedExecuteInsideBatch_DeniedUnlessWhitelisted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist benign call, NOT execute() on the account itself
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Inner call: execute(address,uint256,bytes) targeting account itself
        bytes memory innerExecuteCalldata = abi.encodeWithSelector(
            EXECUTE_SELECTOR, address(mockTarget), uint256(0), abi.encodeWithSelector(MockTarget.doSomething.selector)
        );

        address[] memory targets = new address[](1);
        targets[0] = address(account); // Self-call via execute()
        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = innerExecuteCalldata;

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Should be denied: (account, execute_selector) is not whitelisted
        vm.prank(address(entryPoint));
        vm.expectRevert(abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(account), EXECUTE_SELECTOR));
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_CoarseMode_DeniedWhenAccountRuleNotSet() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Whitelist inner calls for GENERIC mode, but NOT the account-level executeBatch
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        // Use COARSE mode - needs (account, executeBatch) rule, not inner rules
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_COARSE
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(account), EXECUTE_BATCH_SELECTOR)
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_MaxCallGasHint_IgnoredInBatchPath() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Set rule with a restrictive gas hint (50k)
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 50000);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        // UserOp has callGasLimit=500000 (from _createUserOp), which exceeds the 50k hint
        // In single execute() path this would revert with GasTooHigh, but batch ignores gas hints
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        // Passes: batch path intentionally skips per-call gas hint checks
        assertEq(validationData, 0, "Batch path should ignore maxCallGasHint");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_CoarseMode_StillUsesAccountLevel() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // With RULE_ID_COARSE, executeBatch should still use (sender, executeBatch) - old behavior
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(account), EXECUTE_BATCH_SELECTOR, true, 0);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_COARSE
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "COARSE mode should still use account-level validation for batch");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_ExecutorMode_StillUsesAccountLevel() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // With RULE_ID_EXECUTOR, executeBatch should still use (sender, executeBatch)
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(account), EXECUTE_BATCH_SELECTOR, true, 0);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_EXECUTOR
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "EXECUTOR mode should still use account-level validation for batch");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_OrgOperationSelectors_VouchAndVote() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        MockEligibility mockEligibility = new MockEligibility();
        MockVoting mockVoting = new MockVoting();
        MockTaskManager mockTaskManager = new MockTaskManager();

        // Whitelist common org member operations
        vm.startPrank(orgAdmin);
        hub.setRule(ORG_ID, address(mockEligibility), MockEligibility.vouchFor.selector, true, 0);
        hub.setRule(ORG_ID, address(mockVoting), MockVoting.vote.selector, true, 0);
        hub.setRule(ORG_ID, address(mockTaskManager), MockTaskManager.claimTask.selector, true, 0);
        vm.stopPrank();

        address[] memory targets = new address[](3);
        targets[0] = address(mockEligibility);
        targets[1] = address(mockVoting);
        targets[2] = address(mockTaskManager);

        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);
        datas[0] = abi.encodeWithSelector(MockEligibility.vouchFor.selector, address(0xBEEF), uint256(42));
        datas[1] = abi.encodeWithSelector(MockVoting.vote.selector, uint256(1), uint8(0));
        datas[2] = abi.encodeWithSelector(MockTaskManager.claimTask.selector, uint256(7));

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Batch of org operations should pass when all whitelisted");
        assertTrue(context.length > 0);
    }

    /*══════════════════════════════════════════════════════════════════════
                    RULE MODE TESTS (GENERIC, EXECUTOR, COARSE)
    ══════════════════════════════════════════════════════════════════════*/

    function testRuleMode_Generic_ExtractsInnerCall() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // With RULE_ID_GENERIC, inner target/selector should be extracted
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0);
        assertTrue(context.length > 0);
    }

    function testRuleMode_Coarse_OnlyChecksAccountSelector() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // With RULE_ID_COARSE, only account's execute selector is checked
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(account), EXECUTE_SELECTOR, true, 0);

        // Inner call is to an unauthorized target, but COARSE mode ignores it
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_COARSE
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        // Should pass because COARSE mode only checks execute() on account, not inner call
        assertEq(validationData, 0);
        assertTrue(context.length > 0);
    }

    /*══════════════════════════════════════════════════════════════════════
                    GAS CAP TESTS WITH PASSKEY ACCOUNTS
    ══════════════════════════════════════════════════════════════════════*/

    function testGasCaps_VerificationGas_PasskeyAccount() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Set gas caps - important for P256 verification which can be expensive
        vm.prank(orgAdmin);
        hub.setFeeCaps(
            ORG_ID,
            100 gwei, // maxFeePerGas
            10 gwei, // maxPriorityFeePerGas
            1000000, // maxCallGas
            500000, // maxVerificationGas - P256 fallback needs ~330k
            200000 // maxPreVerificationGas
        );

        // Whitelist the call
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        // UserOp with gas limits within caps
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(400000, 800000), // verification=400k (within 500k cap)
            preVerificationGas: 100000,
            gasFees: UserOpLib.packGasFees(5 gwei, 50 gwei),
            paymasterAndData: paymasterAndData,
            signature: ""
        });

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
        assertEq(validationData, 0, "Should pass with gas within limits");
        assertTrue(context.length > 0);
    }

    function testGasCaps_VerificationGas_ExceedsLimit() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Set strict gas caps
        vm.prank(orgAdmin);
        hub.setFeeCaps(ORG_ID, 100 gwei, 10 gwei, 1000000, 300000, 200000); // maxVerificationGas = 300k

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        // UserOp with verification gas exceeding cap (400k > 300k)
        PackedUserOperation memory userOp = PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(400000, 800000), // verification=400k exceeds 300k cap
            preVerificationGas: 100000,
            gasFees: UserOpLib.packGasFees(5 gwei, 50 gwei),
            paymasterAndData: paymasterAndData,
            signature: ""
        });

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.GasTooHigh.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    /*══════════════════════════════════════════════════════════════════════
                    BUDGET TESTS WITH PASSKEY ACCOUNTS
    ══════════════════════════════════════════════════════════════════════*/

    function testBudget_PerAccount_PasskeyAccount() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Set budget for this specific account
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.01 ether, 1 days);

        // Whitelist the call
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // First call should succeed (within budget)
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.005 ether);
        assertEq(validationData, 0);
        assertTrue(context.length > 0);
    }

    function testBudget_PerAccount_ExceedsBudget() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Set small budget
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.001 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Try to use more than budget allows
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.01 ether); // maxCost > budget
    }

    /*══════════════════════════════════════════════════════════════════════
                    FULL FLOW INTEGRATION TEST
    ══════════════════════════════════════════════════════════════════════*/

    function testFullFlow_ValidateUserOp() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Setup rules
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // validatePaymasterUserOp should succeed for passkey accounts
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);
        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");

        // Verify context contains explicit onboarding flag + correct orgId.
        (bool isOnboarding, bytes32 decodedOrgId,,) = abi.decode(context, (bool, bytes32, bytes32, uint32));
        assertFalse(isOnboarding, "Regular org operation should not be flagged as onboarding");
        assertEq(decodedOrgId, ORG_ID, "Context should contain correct orgId");
    }

    /*══════════════════════════════════════════════════════════════════════
                    PAYMASTERANDDATA ENCODING TESTS
    ══════════════════════════════════════════════════════════════════════*/

    function testPaymasterAndData_CorrectFormat() public {
        PasskeyAccount account = _createPasskeyAccount();

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        // Should be exactly 122 bytes (86 + 32 subjectId + 4 ruleId for v0.7 gas limits)
        assertEq(paymasterAndData.length, 122, "paymasterAndData should be 122 bytes");

        // Verify structure using assembly to extract values from memory
        address paymaster;
        uint8 version;
        bytes32 orgId;

        assembly {
            // Skip length prefix (32 bytes), then read 20 bytes for paymaster
            paymaster := shr(96, mload(add(paymasterAndData, 32)))
            // Version is at offset 52 (after paymaster + v0.7 gas limits)
            version := shr(248, mload(add(paymasterAndData, 84)))
            // OrgId is at offset 53-84
            orgId := mload(add(paymasterAndData, 85))
        }

        assertEq(paymaster, address(hub), "Paymaster address mismatch");
        assertEq(version, PAYMASTER_DATA_VERSION, "Version mismatch");
        assertEq(orgId, ORG_ID, "OrgId mismatch");
    }

    function testPaymasterAndData_InvalidLength() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Create malformed paymasterAndData (too short)
        bytes memory shortData = abi.encodePacked(address(hub), PAYMASTER_DATA_VERSION, ORG_ID); // Only 53 bytes

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, shortData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.InvalidPaymasterData.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    /*══════════════════════════════════════════════════════════════════════
                    HAT ELIGIBILITY TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Test that a user who is eligible for a hat but NOT wearing it can still use the paymaster
    function testHat_EligibleButNotWearing_Succeeds() public {
        // Use a new address that is NOT a hat wearer but IS eligible (e.g. vouched)
        address eligibleUser = address(0xE119);

        // Set the user as eligible (but not wearing) via the mock
        MockHatsIntegration(address(hats)).setEligible(eligibleUser, USER_HAT, true);

        // Setup budget for hat-based subject
        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        // Set rule allowing execute on mockTarget
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build UserOp with SUBJECT_TYPE_HAT
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(eligibleUser, callData, paymasterAndData, "");

        // Validate should succeed - eligible users can use paymaster even without wearing the hat
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        assertEq(validationData, 0, "Eligible user should pass validation");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /// @notice Test that a user who is NOT eligible for a hat fails SUBJECT_TYPE_HAT validation
    function testHat_NotEligible_Fails() public {
        address ineligibleUser = address(0xBAD);

        // Do NOT set eligible - user is neither wearing nor eligible

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(ineligibleUser, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.Ineligible.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.01 ether);
    }

    /// @notice Test that an existing hat wearer still passes SUBJECT_TYPE_HAT validation
    function testHat_ExistingWearer_Succeeds() public {
        // `user` already wears USER_HAT from setUp (mintHat sets both wearer and active)
        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(user, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        assertEq(validationData, 0, "Validation should succeed for existing hat wearer");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /// @notice Test that deactivating a hat blocks sponsorship even if user is eligible
    function testHat_DeactivatedHat_Fails() public {
        address eligibleUser = address(0xE119);

        // Set the user as eligible
        MockHatsIntegration(address(hats)).setEligible(eligibleUser, USER_HAT, true);

        // Deactivate the hat
        MockHatsIntegration(address(hats)).setActive(USER_HAT, false);

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(eligibleUser, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.Ineligible.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.01 ether);
    }

    /// @notice Test that deactivating a hat blocks existing wearers too
    function testHat_DeactivatedHat_BlocksExistingWearer() public {
        // `user` wears USER_HAT from setUp
        // Deactivate the hat
        MockHatsIntegration(address(hats)).setActive(USER_HAT, false);

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(user, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.Ineligible.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.01 ether);
    }

    /// @notice Test that reactivating a hat restores sponsorship
    function testHat_ReactivatedHat_RestoresAccess() public {
        address eligibleUser = address(0xE119);
        MockHatsIntegration(address(hats)).setEligible(eligibleUser, USER_HAT, true);

        // Deactivate then reactivate
        MockHatsIntegration(address(hats)).setActive(USER_HAT, false);
        MockHatsIntegration(address(hats)).setActive(USER_HAT, true);

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes32(USER_HAT)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes32(USER_HAT), 0);

        PackedUserOperation memory userOp = _createUserOp(eligibleUser, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        assertEq(validationData, 0, "Validation should succeed after hat reactivation");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /*══════════════════════════════════════════════════════════════════════
                    PAYLOAD FORMAT BOUNDARY TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Exactly 121 bytes (one short) must revert
    function testPaymasterAndData_ExactBoundary121Reverts() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Build 122-byte valid data, then trim last byte to get 121
        bytes memory valid = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory tooShort = new bytes(121);
        for (uint256 i = 0; i < 121; i++) {
            tooShort[i] = valid[i];
        }

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, tooShort, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.InvalidPaymasterData.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    /// @notice Exactly 122 bytes must be accepted
    function testPaymasterAndData_ExactBoundary122Succeeds() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        assertEq(paymasterAndData.length, 122, "Should be exactly 122 bytes");

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);
        assertEq(validationData, 0, "Validation should succeed with exactly 122 bytes");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /// @notice Longer-than-minimum payloads (e.g. old 130-byte format) must still be accepted
    function testPaymasterAndData_LongerThan122Succeeds() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build valid 122-byte data, then append 8 trailing bytes (simulating old 130-byte format)
        bytes memory base = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory extended = abi.encodePacked(base, uint64(0));
        assertEq(extended.length, 130, "Should be 130 bytes (old format)");

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, extended, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);
        assertEq(validationData, 0, "Validation should succeed with 130 bytes (backward compat)");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /*══════════════════════════════════════════════════════════════════════
                    CONTEXT ENCODING / POSTOP ROUND-TRIP TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Validate → postOp round-trip succeeds for normal org operation (opSucceeded)
    function testPostOp_NormalOrgOp_Succeeds() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // PostOp with opSucceeded should not revert
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 50_000, 1);
    }

    /// @notice Validate → postOp round-trip succeeds for normal org operation (opReverted)
    function testPostOp_NormalOrgOp_Reverted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Validate
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // PostOp with opReverted should not revert
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opReverted, context, 50_000, 1);
    }

    /// @notice Context encodes exactly 5 fields: isOnboarding, orgId, subjectKey, epochStart, maxCost
    function testContext_SixFieldEncoding() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // Decode all 6 fields - would revert if encoding doesn't match
        (
            bool isOnboarding,
            bytes32 orgId,
            bytes32 subjectKey,
            uint32 epochStart,
            uint256 reservedBudget,
            uint256 reservedOrgBalance
        ) = abi.decode(context, (bool, bytes32, bytes32, uint32, uint256, uint256));

        assertFalse(isOnboarding, "Normal op should not be onboarding");
        assertEq(orgId, ORG_ID, "OrgId should match");
        assertTrue(subjectKey != bytes32(0), "SubjectKey should be non-zero");
        assertTrue(epochStart > 0, "EpochStart should be non-zero");
        assertEq(reservedBudget, 0.01 ether, "Reserved budget should match maxCost");
        assertEq(reservedOrgBalance, 0.01 ether, "Reserved org balance should match maxCost");
    }

    /// @notice Verify postOp updates budget usage (accounting works without bounty)
    function testPostOp_UpdatesBudget() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Check budget before
        PaymasterHub.Budget memory budgetBefore = hub.getBudget(ORG_ID, subjectKey);
        assertEq(budgetBefore.usedInEpoch, 0, "Budget should start at 0");

        uint256 maxCost = 0.01 ether;
        // Validate (reserves maxCost in budget)
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), maxCost);

        // After validation, budget should have reserved maxCost
        PaymasterHub.Budget memory budgetReserved = hub.getBudget(ORG_ID, subjectKey);
        assertEq(budgetReserved.usedInEpoch, maxCost, "Budget should reserve maxCost after validation");

        uint256 gasCost = 50_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, gasCost, 1);

        // After postOp, reservation replaced with actual cost
        PaymasterHub.Budget memory budgetAfter = hub.getBudget(ORG_ID, subjectKey);
        assertEq(budgetAfter.usedInEpoch, gasCost, "Budget usage should reflect actual gas cost");
    }

    /*══════════════════════════════════════════════════════════════════════
                    BUNDLE SAFETY TESTS (C-1, C-3)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Two UserOps for the same subject in one bundle cannot bypass the budget
    function testBundleSafety_TwoOpsReserveBudget() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        // Set budget cap at 0.009 ether
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.009 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Op 1 validation: maxCost=0.005 ETH, reserves in budget (0.005 < 0.009 cap)
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.005 ether);

        // Op 2 validation: maxCost=0.005 ETH, but budget already has 0.005 reserved
        // Total would be 0.01 > 0.009 cap → must revert
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.005 ether);
    }

    /// @notice Two UserOps for the same org cannot overdraw the org balance
    function testBundleSafety_TwoOpsReserveOrgBalance() public {
        // Use a fresh org with controlled deposit (setUp deposits 0.1 ETH for ORG_ID)
        bytes32 freshOrg = keccak256("BUNDLE_ORG");
        uint256 FRESH_ADMIN_HAT = 200;
        uint256 FRESH_OPERATOR_HAT = 201;
        hats.mintHat(FRESH_ADMIN_HAT, orgAdmin);
        hats.mintHat(FRESH_OPERATOR_HAT, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(freshOrg, FRESH_ADMIN_HAT, FRESH_OPERATOR_HAT);

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        // Set large budget so budget check doesn't block
        vm.prank(orgAdmin);
        hub.setBudget(freshOrg, subjectKey, 10 ether, 1 days);

        // Deposit only 0.008 ether
        vm.deal(orgAdmin, 1 ether);
        vm.prank(orgAdmin);
        hub.depositForOrg{value: 0.008 ether}(freshOrg);

        // Warp past grace period so org must use deposits
        vm.warp(block.timestamp + 91 days);

        // Pause solidarity so org must cover 100% from deposits
        vm.prank(poaManager);
        hub.pauseSolidarityDistribution();

        vm.prank(orgAdmin);
        hub.setRule(freshOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(
            freshOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Op 1: maxCost=0.005, reserves from 0.008 deposit → 0.003 remaining
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.005 ether);

        // Op 2: maxCost=0.005, but only 0.003 remaining → must revert
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.InsufficientOrgBalance.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.005 ether);
    }

    /*══════════════════════════════════════════════════════════════════════
                    POSTOP FALLBACK TEST (C-2)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice postOpReverted mode charges 100% from deposits and doesn't revert
    function testPostOp_PostOpReverted_FallbackChargesDeposits() public {
        // Warp past the default 90-day grace period so the fee applies
        vm.warp(block.timestamp + 91 days);

        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        PaymasterHub.OrgFinancials memory finBefore = hub.getOrgFinancials(ORG_ID);

        // Validate (creates context with reservation)
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // PostOp with postOpReverted should NOT revert (uses fallback path)
        uint256 gasCost = 50_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.postOpReverted, context, gasCost, 1);

        // Verify org was charged actual cost + fee from deposits
        PaymasterHub.OrgFinancials memory finAfter = hub.getOrgFinancials(ORG_ID);
        PaymasterHub.SolidarityFund memory sol = hub.getSolidarityFund();

        uint256 fee = (gasCost * uint256(sol.feePercentageBps)) / 10000;
        assertEq(
            uint256(finAfter.spent) - uint256(finBefore.spent), gasCost + fee, "Org should be charged actual + fee"
        );
    }

    /*══════════════════════════════════════════════════════════════════════
                    GRACE PERIOD FEE TEST (H-4)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice During grace period, no solidarity fee debt accrues on org
    function testGracePeriod_NoFeeDebt() public {
        // Register a fresh org with NO deposits
        bytes32 graceOrg = keccak256("GRACE_ORG");
        uint256 GRACE_ADMIN_HAT = 100;
        uint256 GRACE_OPERATOR_HAT = 101;
        hats.mintHat(GRACE_ADMIN_HAT, orgAdmin);
        hats.mintHat(GRACE_OPERATOR_HAT, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(graceOrg, GRACE_ADMIN_HAT, GRACE_OPERATOR_HAT);

        // Configure grace period (90 days)
        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        // Fund solidarity so grace ops can be covered
        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();

        // Resume solidarity distribution if paused
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(graceOrg, subjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(graceOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            graceOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Validate and postOp during grace period (no deposits, zero-deposit grace path)
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 50_000, 1);

        // org.spent should be 0 - no fee debt during grace
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(graceOrg);
        assertEq(fin.spent, 0, "Org should have no spending debt during grace period");
    }

    /*══════════════════════════════════════════════════════════════════════
                    RESERVATION INVARIANT TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice After postOp, budget should reflect actual cost, not reservation
    function testReservation_BudgetReleaseDelta() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        uint256 maxCost = 0.05 ether;
        uint256 actualCost = 50_000;

        // Validate - reserves maxCost in budget
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), maxCost);

        PaymasterHub.Budget memory mid = hub.getBudget(ORG_ID, subjectKey);
        assertEq(mid.usedInEpoch, maxCost, "Budget should hold reservation");

        // PostOp - releases reservation, charges actual
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualCost, 1);

        PaymasterHub.Budget memory after_ = hub.getBudget(ORG_ID, subjectKey);
        assertEq(after_.usedInEpoch, actualCost, "Budget should hold actual cost, not reservation");
    }

    /// @notice postOp releases reservation so the next op can use the freed budget
    function testReservation_PostOpReleasesForNextOp() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        // Budget cap slightly above 2 * maxCost to test tight budgets
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.012 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Op 1: validate with maxCost=0.01 (reserves 0.01 of 0.012 cap)
        vm.prank(address(entryPoint));
        (bytes memory ctx1,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // Op 1: postOp with actualCost=1000 (releases 0.01 reservation, charges 1000)
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx1, 1000, 1);

        // Op 2: validate with maxCost=0.01 should succeed (budget now has 1000 used of 0.012 cap)
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.01 ether);

        // Verify: budget should show reservation + prior actual
        PaymasterHub.Budget memory b = hub.getBudget(ORG_ID, subjectKey);
        assertEq(b.usedInEpoch, 1000 + 0.01 ether, "Budget should reflect prior actual + new reservation");
    }

    /// @notice Three ops progressively exhaust budget - third one fails
    function testBundleSafety_ThreeOpsProgressiveExhaustion() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        // Cap at exactly 3x the maxCost minus 1 wei
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.015 ether - 1, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Op 1: 0.005 reserved (total 0.005)
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.005 ether);

        // Op 2: 0.005 reserved (total 0.01)
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.005 ether);

        // Op 3: 0.005 would make total 0.015 > cap (0.015 - 1), must revert
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.BudgetExceeded.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(3)), 0.005 ether);
    }

    /// @notice Context encodes reservedOrgBalance=0 for grace+zero-deposit org
    function testReservation_GraceOrgContextHasZeroOrgReservation() public {
        // Setup fresh grace org with no deposits
        bytes32 graceOrg = keccak256("RESERVATION_GRACE_ORG");
        uint256 hatA = 300;
        uint256 hatO = 301;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(graceOrg, hatA, hatO);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();

        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(graceOrg, subjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(graceOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            graceOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        (,,,,, uint256 reservedOrgBalance) = abi.decode(context, (bool, bytes32, bytes32, uint32, uint256, uint256));

        assertEq(reservedOrgBalance, 0, "Grace org with zero deposits should have reservedOrgBalance=0");
    }

    /// @notice Funded org context encodes reservedOrgBalance = maxCost
    function testReservation_FundedOrgContextHasMaxCostReservation() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.02 ether);

        (,,,, uint256 reservedBudget, uint256 reservedOrgBalance) =
            abi.decode(context, (bool, bytes32, bytes32, uint32, uint256, uint256));

        assertEq(reservedBudget, 0.02 ether, "Budget reservation should equal maxCost");
        assertEq(reservedOrgBalance, 0.02 ether, "Funded org should reserve maxCost in org balance");
    }

    /*══════════════════════════════════════════════════════════════════════
                    FALLBACK ACCOUNTING TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Fallback for grace org doesn't underflow (reservedOrgBalance=0)
    function testFallback_GraceOrgNoUnderflow() public {
        bytes32 graceOrg = keccak256("FALLBACK_GRACE_ORG");
        uint256 hatA = 400;
        uint256 hatO = 401;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(graceOrg, hatA, hatO);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();

        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(graceOrg, subjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(graceOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            graceOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // Fallback should NOT revert even though org has zero deposits and reservedOrgBalance=0
        uint256 gasCost = 50_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.postOpReverted, context, gasCost, 1);

        // Verify: org was charged actual cost + fee (creates deficit, but doesn't revert)
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(graceOrg);
        assertTrue(fin.spent > 0, "Fallback should charge org even with zero deposits");

        // Budget should reflect actual cost
        PaymasterHub.Budget memory b = hub.getBudget(graceOrg, subjectKey);
        assertEq(b.usedInEpoch, gasCost, "Budget should hold actual cost after fallback");
    }

    /// @notice Fallback increments solidarityUsedThisPeriod to bound repeated fallbacks
    function testFallback_CountsAgainstGraceSpendingLimit() public {
        bytes32 graceOrg = keccak256("SPENDING_LIMIT_ORG");
        uint256 hatA = 500;
        uint256 hatO = 501;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(graceOrg, hatA, hatO);

        // Set tight grace spending limit
        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 100_000, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();

        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(graceOrg, subjectKey, 10 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(graceOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            graceOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // 3 cycles of validate+fallback, each adds 25_000 to solidarityUsedThisPeriod
        for (uint256 i = 1; i <= 3; i++) {
            vm.prank(address(entryPoint));
            (bytes memory ctx,) = hub.validatePaymasterUserOp(userOp, bytes32(i), 30_000);

            vm.prank(address(entryPoint));
            hub.postOp(IPaymaster.PostOpMode.postOpReverted, ctx, 25_000, 1);
        }

        // solidarityUsedThisPeriod is now 75_000. Next validate: 75_000 + 30_000 = 105_000 > 100_000
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.GracePeriodSpendLimitReached.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(4)), 30_000);
    }

    /// @notice Org balance reservation is correctly unreserved after normal postOp
    function testReservation_OrgBalanceUnreservedAfterPostOp() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Pause solidarity so we get the simple deposit-only path
        vm.prank(poaManager);
        hub.pauseSolidarityDistribution();

        // Warp past grace
        vm.warp(block.timestamp + 91 days);

        PaymasterHub.OrgFinancials memory before_ = hub.getOrgFinancials(ORG_ID);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        uint256 maxCost = 0.01 ether;
        uint256 actualCost = 50_000;

        // Validate - reserves maxCost in org.spent
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), maxCost);

        PaymasterHub.OrgFinancials memory mid = hub.getOrgFinancials(ORG_ID);
        assertEq(mid.spent - before_.spent, maxCost, "Org should have reserved maxCost");

        // PostOp - unreserves maxCost, charges actual + fee
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualCost, 1);

        PaymasterHub.OrgFinancials memory after_ = hub.getOrgFinancials(ORG_ID);
        PaymasterHub.SolidarityFund memory sol = hub.getSolidarityFund();
        uint256 fee = (actualCost * uint256(sol.feePercentageBps)) / 10000;

        assertEq(after_.spent - before_.spent, actualCost + fee, "Final spent should be actual + fee, not maxCost");
        assertTrue(after_.spent < mid.spent, "PostOp should have reduced spent from reservation level");
    }

    /*══════════════════════════════════════════════════════════════════════
                    EPOCH BOUNDARY TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice If epoch rolls between validate and postOp, reservation is harmlessly lost
    function testEpochRoll_ReservationClearedByReset() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        // Short epoch for testing (1 hour)
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 1 ether, 1 hours);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Validate at time T (maxCost within 0.1 ETH org deposit from setUp)
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        // Warp past epoch boundary
        vm.warp(block.timestamp + 2 hours);

        // PostOp still succeeds - epoch roll is lazy (only in _checkBudget during validation)
        // postOp sees the same epochStart and adjusts reservation → actual cost
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 50_000, 1);

        // Budget has actual cost in old epoch (not yet rolled)
        PaymasterHub.Budget memory b = hub.getBudget(ORG_ID, subjectKey);
        assertEq(b.usedInEpoch, 50_000, "PostOp adjusts reservation to actual even after time passes");

        // Next validation triggers lazy epoch roll → budget resets
        vm.prank(address(entryPoint));
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.01 ether);

        PaymasterHub.Budget memory rolled = hub.getBudget(ORG_ID, subjectKey);
        assertEq(
            rolled.usedInEpoch, 0.01 ether, "After epoch roll, usedInEpoch should be only new reservation (old cleared)"
        );
    }

    /*══════════════════════════════════════════════════════════════════════
                    INVARIANT: ORG DEPOSIT >= SPENT (non-grace)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice After validate+postOp cycle for funded org, deposited >= spent always holds
    function testInvariant_FundedOrgDepositGteSpent() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 10 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Pause solidarity for simple deposit-only accounting
        vm.prank(poaManager);
        hub.pauseSolidarityDistribution();
        vm.warp(block.timestamp + 91 days);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Run 5 validate+postOp cycles
        for (uint256 i = 1; i <= 5; i++) {
            vm.prank(address(entryPoint));
            (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(i), 0.001 ether);

            // After validation: deposited >= spent (reservation is within bounds)
            PaymasterHub.OrgFinancials memory midFin = hub.getOrgFinancials(ORG_ID);
            assertTrue(midFin.deposited >= midFin.spent, "Invariant violated mid-cycle: deposited < spent");

            vm.prank(address(entryPoint));
            hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, 50_000, 1);

            // After postOp: deposited >= spent
            PaymasterHub.OrgFinancials memory postFin = hub.getOrgFinancials(ORG_ID);
            assertTrue(postFin.deposited >= postFin.spent, "Invariant violated post-cycle: deposited < spent");
        }
    }

    /// @notice Multiple ops in bundle all correctly reserve, then postOps correctly settle
    function testBundleSafety_FullBundleCycle() public {
        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 10 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Pause solidarity for simple accounting
        vm.prank(poaManager);
        hub.pauseSolidarityDistribution();
        vm.warp(block.timestamp + 91 days);

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        PaymasterHub.OrgFinancials memory before_ = hub.getOrgFinancials(ORG_ID);

        // Simulate bundle: 3 validations first (like EntryPoint does)
        bytes memory ctx1;
        bytes memory ctx2;
        bytes memory ctx3;

        vm.prank(address(entryPoint));
        (ctx1,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);
        vm.prank(address(entryPoint));
        (ctx2,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.01 ether);
        vm.prank(address(entryPoint));
        (ctx3,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(3)), 0.01 ether);

        // After all validations: org.spent should be before + 3 * maxCost reserved
        PaymasterHub.OrgFinancials memory midFin = hub.getOrgFinancials(ORG_ID);
        assertEq(midFin.spent - before_.spent, 0.03 ether, "3 reservations should sum correctly");

        // Budget should also hold all 3 reservations
        PaymasterHub.Budget memory midBudget = hub.getBudget(ORG_ID, subjectKey);
        assertEq(midBudget.usedInEpoch, 0.03 ether, "Budget should hold 3 reservations");

        // Then 3 postOps (actual costs much less than reserved)
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx1, 10_000, 1);
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx2, 20_000, 1);
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx3, 30_000, 1);

        // Budget should hold sum of actual costs
        PaymasterHub.Budget memory finalBudget = hub.getBudget(ORG_ID, subjectKey);
        assertEq(finalBudget.usedInEpoch, 60_000, "Budget should hold sum of actual costs");

        // Org financials: spent should be actual costs + fees (not reservations)
        PaymasterHub.OrgFinancials memory finalFin = hub.getOrgFinancials(ORG_ID);
        uint256 totalActual = 60_000;
        PaymasterHub.SolidarityFund memory sol = hub.getSolidarityFund();
        uint256 totalFee = (10_000 + 20_000 + 30_000) * uint256(sol.feePercentageBps) / 10000;
        assertEq(finalFin.spent - before_.spent, totalActual + totalFee, "Spent should be actual costs + fees");

        // Invariant: deposited >= spent
        assertTrue(finalFin.deposited >= finalFin.spent, "deposited >= spent must hold");
    }

    /*══════════════════════════════════════════════════════════════════════
                    ORDERING FIX REGRESSION TESTS
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Post-grace org with deposits at minDepositRequired succeeds.
    ///         Regression test: with old ordering (_checkOrgBalance before _checkSolidarityAccess),
    ///         the maxCost reservation would deflate depositAvailable below minDepositRequired,
    ///         causing a spurious InsufficientDepositForSolidarity revert.
    function testOrdering_SolidarityCheckSeesCleanDeposits() public {
        // Create a fresh org
        bytes32 orderOrg = keccak256("ORDER_TEST_ORG");
        uint256 hatA = 600;
        uint256 hatO = 601;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(orderOrg, hatA, hatO);

        // Warp past grace period
        vm.warp(block.timestamp + 91 days);

        // Set grace config: minDepositRequired = 0.003 ether
        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        // Unpause solidarity distribution
        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        // Deposit exactly at minDepositRequired (0.003 ether)
        vm.prank(owner);
        hub.depositForOrg{value: 0.003 ether}(orderOrg);

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(orderOrg, subjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(orderOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            orderOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // maxCost of 0.002 ether would push deposits below minDeposit with old ordering.
        // With correct ordering, solidarity access sees the clean 0.003 ether deposit first.
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.002 ether);

        assertEq(validationData, 0, "Validation should succeed - solidarity check sees clean deposits");
        assertTrue(context.length > 0, "Context should be returned");

        // After validation, org.spent should have the reservation
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(orderOrg);
        assertEq(fin.spent, 0.002 ether, "Reservation applied after solidarity check");
    }

    /*══════════════════════════════════════════════════════════════════════
                    GRACE FALLBACK FEE ZEROING TEST
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice During grace, fallback charges actualGasCost but NOT the solidarity fee
    function testFallback_GracePeriodZerosFee() public {
        bytes32 graceOrg = keccak256("GRACE_FEE_ZERO_ORG");
        uint256 hatA = 700;
        uint256 hatO = 701;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(graceOrg, hatA, hatO);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(graceOrg, subjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(graceOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            graceOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        PaymasterHub.SolidarityFund memory solBefore = hub.getSolidarityFund();

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        uint256 gasCost = 50_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.postOpReverted, context, gasCost, 1);

        // Verify: no fee collected during grace fallback
        PaymasterHub.SolidarityFund memory solAfter = hub.getSolidarityFund();
        assertEq(solAfter.balance, solBefore.balance, "Solidarity balance unchanged - no fee during grace fallback");

        // Verify: org.spent = actualGasCost only (no fee component)
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(graceOrg);
        assertEq(fin.spent, gasCost, "Org charged actual cost only, no fee during grace");
    }

    /*══════════════════════════════════════════════════════════════════════
                    50/50 SPLIT CORRECTNESS (ACTIVE SOLIDARITY)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Post-grace org with active solidarity gets 50/50 split
    function testPostOp_5050SplitWithActiveSolidarity() public {
        // Create fresh org
        bytes32 splitOrg = keccak256("SPLIT_TEST_ORG");
        uint256 hatA = 800;
        uint256 hatO = 801;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(splitOrg, hatA, hatO);

        // Warp past grace
        vm.warp(block.timestamp + 91 days);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        // Fund solidarity and unpause
        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        // Deposit enough for Tier 1 (>= minDeposit)
        vm.prank(owner);
        hub.depositForOrg{value: 0.01 ether}(splitOrg);

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(splitOrg, subjectKey, 1 ether, 1 days);
        vm.prank(orgAdmin);
        hub.setRule(splitOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            splitOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        PaymasterHub.OrgFinancials memory finBefore = hub.getOrgFinancials(splitOrg);
        PaymasterHub.SolidarityFund memory solBefore = hub.getSolidarityFund();

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.001 ether);

        uint256 actualCost = 100_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualCost, 1);

        PaymasterHub.OrgFinancials memory finAfter = hub.getOrgFinancials(splitOrg);
        PaymasterHub.SolidarityFund memory solAfter = hub.getSolidarityFund();

        uint256 fee = (actualCost * uint256(solBefore.feePercentageBps)) / 10000;
        uint256 halfCost = actualCost / 2;

        // Org paid: half the cost (from deposits) + fee
        uint256 orgDelta = finAfter.spent - finBefore.spent;
        assertEq(orgDelta, halfCost + fee, "Org should pay half + fee");

        // Solidarity paid: half the cost (minus fee income)
        uint256 solidarityDelta = solBefore.balance - solAfter.balance;
        assertEq(solidarityDelta, halfCost - fee, "Solidarity net = half paid - fee received");

        // solidarityUsedThisPeriod tracks solidarity's contribution
        assertEq(finAfter.solidarityUsedThisPeriod, halfCost, "solidarityUsedThisPeriod should track solidarity half");
    }

    /*══════════════════════════════════════════════════════════════════════
            BUNDLE WITH ACTIVE SOLIDARITY (POST-GRACE)
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice Two ops in a bundle with active solidarity - second op sees reduced deposits from first's reservation
    function testBundleSafety_ActiveSolidarityTwoOps() public {
        bytes32 bundleOrg = keccak256("BUNDLE_SOLIDARITY_ORG");
        uint256 hatA = 900;
        uint256 hatO = 901;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(bundleOrg, hatA, hatO);

        vm.warp(block.timestamp + 91 days);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        // Deposit 0.005 ether - above minDeposit (0.003)
        vm.prank(owner);
        hub.depositForOrg{value: 0.005 ether}(bundleOrg);

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(bundleOrg, subjectKey, 10 ether, 1 days);
        vm.prank(orgAdmin);
        hub.setRule(bundleOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            bundleOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Op1: validate with maxCost = 0.004 ether (almost all deposits)
        vm.prank(address(entryPoint));
        (bytes memory ctx1,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.004 ether);

        // After op1 validation: org.spent = 0.004 ether (reservation), deposits = 0.005 ether
        // depositAvailable for op2's solidarity check = 0.005 - 0.004 = 0.001 ether
        // 0.001 ether < minDepositRequired (0.003 ether), so op2 should fail InsufficientDepositForSolidarity
        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.InsufficientDepositForSolidarity.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.004 ether);

        // But after op1's postOp settles, deposits are freed for the next validation
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx1, 50_000, 1);

        // Now op2 should succeed - deposits are available again
        vm.prank(address(entryPoint));
        (bytes memory ctx2, uint256 v2) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), 0.004 ether);
        assertEq(v2, 0, "Op2 should succeed after op1 postOp settled");

        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, ctx2, 50_000, 1);
    }

    /*══════════════════════════════════════════════════════════════════════
            FALLBACK PHANTOM DEBT FOR FUNDED POST-GRACE ORG
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice When fallback charges more than deposits, spent > deposited (phantom debt)
    function testFallback_PostGracePhantomDebt() public {
        bytes32 debtOrg = keccak256("PHANTOM_DEBT_ORG");
        uint256 hatA = 1000;
        uint256 hatO = 1001;
        hats.mintHat(hatA, orgAdmin);
        hats.mintHat(hatO, orgAdmin);

        vm.prank(poaManager);
        hub.registerOrg(debtOrg, hatA, hatO);

        vm.warp(block.timestamp + 91 days);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(90, 1 ether, 0.003 ether);

        vm.prank(owner);
        hub.donateToSolidarity{value: 1 ether}();
        vm.prank(poaManager);
        hub.unpauseSolidarityDistribution();

        // Small deposit: 0.003 ether (just at minDeposit)
        vm.prank(owner);
        hub.depositForOrg{value: 0.003 ether}(debtOrg);

        PasskeyAccount account = _createPasskeyAccount();
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes32(uint256(uint160(address(account))))));

        vm.prank(orgAdmin);
        hub.setBudget(debtOrg, subjectKey, 1 ether, 1 days);
        vm.prank(orgAdmin);
        hub.setRule(debtOrg, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory paymasterAndData = _buildPaymasterData(
            debtOrg, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Validate succeeds - solidarity covers the gap
        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.002 ether);

        // Fallback with actualGasCost much larger than deposits
        // Gas cost = 0.005 ether > deposited = 0.003 ether
        // This creates phantom debt: spent > deposited
        uint256 gasCost = 0.005 ether;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.postOpReverted, context, gasCost, 1);

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(debtOrg);
        PaymasterHub.SolidarityFund memory sol = hub.getSolidarityFund();
        uint256 fee = (gasCost * uint256(sol.feePercentageBps)) / 10000;

        // Phantom debt: spent > deposited
        assertTrue(fin.spent > fin.deposited, "Fallback should create phantom debt when actual > deposits");
        assertEq(fin.spent, gasCost + fee, "Spent = actualGasCost + fee");

        // Fallback does NOT revert - this is the key invariant
        // The phantom debt is the cost of the gas consumed. The paymaster was already charged by EntryPoint.
    }

    /*══════════════════════════════════════════════════════════════════════
            DISTRIBUTION-PAUSED POSTOP FEE COLLECTION
    ══════════════════════════════════════════════════════════════════════*/

    /// @notice When distribution is paused, postOp still collects solidarity fee from deposits
    function testPostOp_PausedDistributionStillCollectsFee() public {
        vm.warp(block.timestamp + 91 days);

        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Ensure distribution is paused (default)
        PaymasterHub.SolidarityFund memory solCheck = hub.getSolidarityFund();
        assertTrue(solCheck.distributionPaused, "Distribution should be paused by default");

        PaymasterHub.SolidarityFund memory solBefore = hub.getSolidarityFund();

        bytes memory paymasterAndData = _buildPaymasterData(
            ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes32(uint256(uint160(address(account)))), RULE_ID_GENERIC
        );
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        uint256 actualCost = 100_000;
        vm.prank(address(entryPoint));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, context, actualCost, 1);

        PaymasterHub.SolidarityFund memory solAfter = hub.getSolidarityFund();
        uint256 expectedFee = (actualCost * uint256(solBefore.feePercentageBps)) / 10000;

        assertEq(solAfter.balance - solBefore.balance, expectedFee, "Fee collected even when distribution paused");
        assertTrue(expectedFee > 0, "Fee should be nonzero");
    }
}

/*══════════════════════════════════════════════════════════════════════════
                            MOCK CONTRACTS
══════════════════════════════════════════════════════════════════════════*/

contract MockEntryPointIntegration is IEntryPoint {
    mapping(address => uint256) private _deposits;

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

    receive() external payable {}
}

contract MockHatsIntegration is IHats {
    mapping(address => mapping(uint256 => bool)) private _wearers;
    mapping(address => mapping(uint256 => bool)) private _eligibles;
    mapping(uint256 => bool) private _activeHats;
    mapping(uint256 => bool) private _hatExists;

    function mintHat(uint256 _hatId, address _wearer) external returns (bool success) {
        _wearers[_wearer][_hatId] = true;
        if (!_hatExists[_hatId]) {
            _hatExists[_hatId] = true;
            _activeHats[_hatId] = true;
        }
        return true;
    }

    function setEligible(address _wearer, uint256 _hatId, bool _eligible) external {
        _eligibles[_wearer][_hatId] = _eligible;
        if (!_hatExists[_hatId]) {
            _hatExists[_hatId] = true;
            _activeHats[_hatId] = true;
        }
    }

    function setActive(uint256 _hatId, bool _active) external {
        _activeHats[_hatId] = _active;
    }

    function isWearerOfHat(address _wearer, uint256 _hatId) external view returns (bool) {
        return _wearers[_wearer][_hatId];
    }

    // Stub implementations
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

    function setHatStatus(uint256 _hatId, bool _active) external returns (bool) {
        _activeHats[_hatId] = _active;
        return true;
    }

    function checkHatStatus(uint256 _hatId) external view returns (bool) {
        return _activeHats[_hatId];
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

    function viewHat(uint256 _hatId)
        external
        view
        returns (string memory, uint32, uint32, address, address, string memory, uint16, bool, bool)
    {
        return ("", 0, 0, address(0), address(0), "", 0, false, _activeHats[_hatId]);
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

    function isEligible(address _wearer, uint256 _hatId) external view returns (bool) {
        return _wearers[_wearer][_hatId] || _eligibles[_wearer][_hatId];
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

/// @notice Mock target contract for testing execute() calls
contract MockTarget {
    uint256 public value;

    event SomethingDone(address caller);
    event SomethingElseDone(address caller);

    function doSomething() external returns (bool) {
        value += 1;
        emit SomethingDone(msg.sender);
        return true;
    }

    function doSomethingElse() external returns (bool) {
        value += 10;
        emit SomethingElseDone(msg.sender);
        return true;
    }

    function doWithValue() external payable returns (bool) {
        value += msg.value;
        return true;
    }
}

/// @notice Mock org contracts for testing onboarding and org operation batch selectors
contract MockRegistry {
    function registerAccount(string calldata) external {}
}

contract MockQuickJoin {
    function quickJoinWithUser() external {}
}

contract MockEligibility {
    function claimVouchedHat(uint256) external {}
    function vouchFor(address, uint256) external {}
}

contract MockVoting {
    function vote(uint256, uint8) external {}
    function createProposal(bytes calldata, bytes32, uint32, uint8) external {}
}

contract MockTaskManager {
    function claimTask(uint256) external {}
    function submitTask(uint256, bytes32) external {}
    function applyForTask(uint256, bytes32) external {}
}
