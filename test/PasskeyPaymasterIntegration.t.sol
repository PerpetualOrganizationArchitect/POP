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
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes20(account)));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 1 ether, 1 days);
    }

    function _buildPaymasterData(
        bytes32 orgId,
        uint8 subjectType,
        bytes20 subjectId,
        uint32 ruleId,
        uint64 mailboxCommit8
    ) internal view returns (bytes memory) {
        // ERC-4337 v0.7 format: paymaster(20) | verificationGasLimit(16) | postOpGasLimit(16) | version(1) | orgId(32) | subjectType(1) | subjectId(20) | ruleId(4) | mailboxCommit(8) = 118 bytes
        return abi.encodePacked(
            address(hub), // 20 bytes
            uint128(200_000), // paymasterVerificationGasLimit - 16 bytes
            uint128(100_000), // paymasterPostOpGasLimit - 16 bytes
            PAYMASTER_DATA_VERSION, // 1 byte
            orgId, // 32 bytes
            subjectType, // 1 byte
            subjectId, // 20 bytes
            ruleId, // 4 bytes
            mailboxCommit8 // 8 bytes
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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
                    EXECUTEBATCH() COMPATIBILITY TESTS
    ══════════════════════════════════════════════════════════════════════*/

    function testExecuteBatch_PasskeyAccountSelector_Recognized() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // For batch operations, PaymasterHub validates at account level
        // So we need to allow the executeBatch selector on the account itself
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(account), EXECUTE_BATCH_SELECTOR, true, 0);

        // Build executeBatch calldata
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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // Should succeed because we whitelisted the executeBatch selector
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "executeBatch should be allowed");
        assertTrue(context.length > 0);
    }

    function testExecuteBatch_PasskeyAccountSelector_Denied() public {
        PasskeyAccount account = _createPasskeyAccount();

        // Don't set any rules - executeBatch should be denied

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = abi.encodeWithSelector(MockTarget.doSomething.selector);

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(
            abi.encodeWithSelector(PaymasterHub.RuleDenied.selector, address(account), EXECUTE_BATCH_SELECTOR)
        );
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);
    }

    function testExecuteBatch_SelectorCorrectlyExtracted() public {
        PasskeyAccount account = _createPasskeyAccount();
        _setupDefaultBudget(address(account));

        // Verify that 0x47e1da2a (PasskeyAccount executeBatch) is correctly recognized
        // by allowing it and confirming validation passes

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(account), bytes4(0x47e1da2a), true, 0);

        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory datas = new bytes[](1);
        datas[0] = "";

        bytes memory callData = _buildExecuteBatchCalldata(targets, values, datas);

        // Verify the selector in calldata is what we expect
        bytes4 extractedSelector = bytes4(callData[0]) | (bytes4(callData[1]) >> 8) | (bytes4(callData[2]) >> 16)
            | (bytes4(callData[3]) >> 24);
        assertEq(extractedSelector, bytes4(0x47e1da2a), "Selector should be PasskeyAccount executeBatch");

        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) = hub.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether);

        assertEq(validationData, 0, "Should pass with correct selector whitelisted");
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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_COARSE, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes20(address(account))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.01 ether, 1 days);

        // Whitelist the call
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(0), bytes20(address(account))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, subjectKey, 0.001 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

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
        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

        PackedUserOperation memory userOp = _createUserOp(address(account), callData, paymasterAndData, "");

        // validatePaymasterUserOp should succeed for passkey accounts
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);
        assertEq(validationData, 0, "Validation should succeed");
        assertTrue(context.length > 0, "Context should be returned");

        // Verify context contains explicit onboarding flag + correct orgId.
        (bool isOnboarding, bytes32 decodedOrgId,,,,,) =
            abi.decode(context, (bool, bytes32, bytes32, uint32, bytes32, uint64, address));
        assertFalse(isOnboarding, "Regular org operation should not be flagged as onboarding");
        assertEq(decodedOrgId, ORG_ID, "Context should contain correct orgId");
    }

    /*══════════════════════════════════════════════════════════════════════
                    PAYMASTERANDDATA ENCODING TESTS
    ══════════════════════════════════════════════════════════════════════*/

    function testPaymasterAndData_CorrectFormat() public {
        PasskeyAccount account = _createPasskeyAccount();

        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(address(account)), RULE_ID_GENERIC, 0);

        // Should be exactly 118 bytes (86 + 32 for v0.7 gas limits)
        assertEq(paymasterAndData.length, 118, "paymasterAndData should be 118 bytes");

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

    /// @notice Test that a user who is eligible for a hat (but not yet wearing it) passes SUBJECT_TYPE_HAT validation
    function testHat_EligibleButNotWearing_Succeeds() public {
        // Use a new address that is NOT a hat wearer but IS eligible
        address eligibleUser = address(0xE119);

        // Set the user as eligible (but not wearing) via the mock
        MockHatsIntegration(address(hats)).setEligible(eligibleUser, USER_HAT, true);

        // Setup budget for hat-based subject
        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        // Set rule allowing execute on mockTarget
        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        // Build UserOp with SUBJECT_TYPE_HAT
        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

        PackedUserOperation memory userOp = _createUserOp(eligibleUser, callData, paymasterAndData, "");

        // Validate should succeed — user is eligible even though they don't wear the hat yet
        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        assertEq(validationData, 0, "Validation should succeed for eligible user");
        assertTrue(context.length > 0, "Context should be returned");
    }

    /// @notice Test that a user who is NOT eligible for a hat fails SUBJECT_TYPE_HAT validation
    function testHat_NotEligible_Fails() public {
        address ineligibleUser = address(0xBAD);

        // Do NOT set eligible — user is neither wearing nor eligible

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

        PackedUserOperation memory userOp = _createUserOp(ineligibleUser, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        vm.expectRevert(PaymasterHub.Ineligible.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(0), 0.01 ether);
    }

    /// @notice Test that an existing hat wearer still passes SUBJECT_TYPE_HAT validation
    function testHat_ExistingWearer_Succeeds() public {
        // `user` already wears USER_HAT from setUp (mintHat sets both wearer and active)
        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

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

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

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

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

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

        bytes32 hatSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT))));
        vm.prank(orgAdmin);
        hub.setBudget(ORG_ID, hatSubjectKey, 1 ether, 1 days);

        vm.prank(orgAdmin);
        hub.setRule(ORG_ID, address(mockTarget), MockTarget.doSomething.selector, true, 0);

        bytes memory innerCall = abi.encodeWithSelector(MockTarget.doSomething.selector);
        bytes memory callData = _buildExecuteCalldata(address(mockTarget), 0, innerCall);
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_HAT, bytes20(uint160(USER_HAT)), 0, 0);

        PackedUserOperation memory userOp = _createUserOp(eligibleUser, callData, paymasterAndData, "");

        vm.prank(address(entryPoint));
        (bytes memory context, uint256 validationData) =
            hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), 0.01 ether);

        assertEq(validationData, 0, "Validation should succeed after hat reactivation");
        assertTrue(context.length > 0, "Context should be returned");
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
