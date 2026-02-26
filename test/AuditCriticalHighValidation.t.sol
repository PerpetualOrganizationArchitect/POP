// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";
import {TaskPerm} from "../src/libs/TaskPerm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AuditMockHats {
    mapping(uint256 => mapping(address => uint256)) internal _balances;

    function setWearer(uint256 hatId, address wearer, bool isWearer) external {
        _balances[hatId][wearer] = isWearer ? 1 : 0;
    }

    function isWearerOfHat(address wearer, uint256 hatId) external view returns (bool) {
        return _balances[hatId][wearer] > 0;
    }

    function balanceOfBatch(address[] calldata wearers, uint256[] calldata hatIds)
        external
        view
        returns (uint256[] memory out)
    {
        require(wearers.length == hatIds.length, "len mismatch");
        out = new uint256[](wearers.length);
        for (uint256 i = 0; i < wearers.length; i++) {
            out[i] = _balances[hatIds[i]][wearers[i]];
        }
    }
}

contract AuditTarget {
    function ping() external pure returns (uint256) {
        return 1;
    }
}

contract AuditEntryPointStub {
    mapping(address => uint256) internal _balances;

    function depositTo(address account) external payable {
        _balances[account] += msg.value;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}

contract AuditDummyToken is ERC20 {
    constructor() ERC20("AuditDummy", "ADUM") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract PaymasterCriticalHighValidationTest is Test {
    PaymasterHub internal hub;
    AuditMockHats internal hats;
    AuditEntryPointStub internal entryPointStub;

    address internal constant POA_MANAGER = address(0xA001);
    address internal constant ORG_ADMIN = address(0xA002);
    address internal voucher;

    uint256 internal constant ADMIN_HAT = 1;
    uint256 internal constant OPERATOR_HAT = 2;
    uint256 internal constant VOUCHER_HAT = 3;

    bytes32 internal constant ORG_ID = keccak256("AUDIT_ORG");

    uint8 internal constant PAYMASTER_DATA_VERSION = 1;
    uint8 internal constant SUBJECT_TYPE_ACCOUNT = 0x00;
    uint8 internal constant SUBJECT_TYPE_VOUCHED = 0x02;
    uint8 internal constant SUBJECT_TYPE_POA_ONBOARDING = 0x03;
    uint32 internal constant RULE_ID_COARSE = 0x000000FF;
    uint256 internal constant MAX_COST = 100_000; // Must be <= maxGasPerCreation

    uint256 internal constant VOUCHER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function setUp() public {
        hats = new AuditMockHats();
        entryPointStub = new AuditEntryPointStub();
        voucher = vm.addr(VOUCHER_PK);
        PaymasterHub hubImpl = new PaymasterHub();
        bytes memory initData = abi.encodeWithSelector(
            PaymasterHub.initialize.selector, address(entryPointStub), address(hats), POA_MANAGER
        );
        hub = PaymasterHub(payable(address(new ERC1967Proxy(address(hubImpl), initData))));

        hats.setWearer(ADMIN_HAT, ORG_ADMIN, true);
        hats.setWearer(OPERATOR_HAT, ORG_ADMIN, true);
        hats.setWearer(VOUCHER_HAT, voucher, true);

        vm.prank(POA_MANAGER);
        hub.registerOrgWithVoucher(ORG_ID, ADMIN_HAT, OPERATOR_HAT, VOUCHER_HAT);

        vm.prank(POA_MANAGER);
        hub.unpauseSolidarityDistribution();

        vm.deal(address(this), 10 ether);
        hub.donateToSolidarity{value: 1 ether}();
    }

    function _buildPaymasterData(
        bytes32 orgId,
        uint8 subjectType,
        bytes20 subjectId,
        uint32 ruleId,
        uint64 mailboxCommit8
    ) internal view returns (bytes memory) {
        return abi.encodePacked(
            address(hub), PAYMASTER_DATA_VERSION, orgId, subjectType, subjectId, ruleId, mailboxCommit8
        );
    }

    function _buildVouchedPaymasterData(address account, uint48 expiry, bytes memory initCode, bytes memory callData)
        internal
        view
        returns (bytes memory)
    {
        bytes32 vouchHash = keccak256(
            abi.encodePacked(
                ORG_ID, account, keccak256(initCode), keccak256(callData), expiry, block.chainid, address(hub)
            )
        );
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", vouchHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(VOUCHER_PK, ethSignedHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        return abi.encodePacked(
            address(hub),
            PAYMASTER_DATA_VERSION,
            ORG_ID,
            SUBJECT_TYPE_VOUCHED,
            bytes20(voucher),
            RULE_ID_COARSE,
            uint64(0),
            expiry,
            signature
        );
    }

    function _buildUserOp(address sender, bytes memory callData, bytes memory paymasterAndData)
        internal
        pure
        returns (PackedUserOperation memory userOp)
    {
        userOp = PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: UserOpLib.packAccountGasLimits(100_000, 100_000),
            preVerificationGas: 100_000,
            maxFeePerGas: 1,
            maxPriorityFeePerGas: 1,
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    function testFix_OnboardingRejectsNonZeroOrgId() public {
        bytes memory paymasterAndData = _buildPaymasterData(ORG_ID, SUBJECT_TYPE_POA_ONBOARDING, bytes20(0), 0, 0);
        PackedUserOperation memory userOp = _buildUserOp(address(0xBEEF), "", paymasterAndData);
        userOp.initCode = hex"01";

        vm.prank(address(entryPointStub));
        vm.expectRevert(PaymasterHub.InvalidOnboardingRequest.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(1)), MAX_COST);
    }

    function testFix_OnboardingRejectsNonCreationUserOp() public {
        AuditTarget deployedSender = new AuditTarget();
        assertGt(address(deployedSender).code.length, 0, "sender should be deployed code-bearing account");

        bytes memory paymasterAndData = _buildPaymasterData(bytes32(0), SUBJECT_TYPE_POA_ONBOARDING, bytes20(0), 0, 0);
        PackedUserOperation memory userOp =
            _buildUserOp(address(deployedSender), abi.encodeWithSelector(AuditTarget.ping.selector), paymasterAndData);

        vm.prank(address(entryPointStub));
        vm.expectRevert(PaymasterHub.InvalidOnboardingRequest.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(2)), MAX_COST);
    }

    function testFix_OnboardingRevertedOpDoesNotEmitCreationEvent() public {
        bytes memory paymasterAndData = _buildPaymasterData(bytes32(0), SUBJECT_TYPE_POA_ONBOARDING, bytes20(0), 0, 0);
        PackedUserOperation memory userOp = _buildUserOp(address(0xCAFE), "", paymasterAndData);
        userOp.initCode = hex"01";

        vm.prank(address(entryPointStub));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(3)), MAX_COST);

        // A reverted op should NOT emit OnboardingAccountCreated
        vm.recordLogs();
        vm.prank(address(entryPointStub));
        hub.postOp(IPaymaster.PostOpMode.opReverted, context, MAX_COST);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 creationTopic = keccak256("OnboardingAccountCreated(address,uint256)");
        for (uint256 i; i < logs.length; i++) {
            assertFalse(logs[i].topics[0] == creationTopic, "failed op should not emit creation event");
        }
    }

    function testFix_OnboardingFailedOpsStillConsumeDailyThrottle() public {
        vm.prank(POA_MANAGER);
        hub.setOnboardingConfig(uint128(MAX_COST * 2), 1, true);

        bytes memory paymasterAndData = _buildPaymasterData(bytes32(0), SUBJECT_TYPE_POA_ONBOARDING, bytes20(0), 0, 0);

        PackedUserOperation memory firstUserOp = _buildUserOp(address(0xAAA1), "", paymasterAndData);
        firstUserOp.initCode = hex"01";

        vm.prank(address(entryPointStub));
        (bytes memory context,) = hub.validatePaymasterUserOp(firstUserOp, bytes32(uint256(30)), MAX_COST);

        vm.prank(address(entryPointStub));
        hub.postOp(IPaymaster.PostOpMode.opReverted, context, MAX_COST);

        PackedUserOperation memory secondUserOp = _buildUserOp(address(0xAAA2), "", paymasterAndData);
        secondUserOp.initCode = hex"02";

        vm.prank(address(entryPointStub));
        vm.expectRevert(PaymasterHub.OnboardingDailyLimitExceeded.selector);
        hub.validatePaymasterUserOp(secondUserOp, bytes32(uint256(31)), MAX_COST);
    }

    function testFix_VouchConsumedOnlyOnSuccessfulExecution() public {
        vm.prank(POA_MANAGER);
        hub.pauseSolidarityDistribution();

        hub.depositForOrg{value: 1 ether}(ORG_ID);

        address account = address(0xABCD);
        bytes4 selector = 0x12345678;

        bytes32 vouchedSubjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_VOUCHED, bytes20(voucher)));
        vm.prank(ORG_ADMIN);
        hub.setBudget(ORG_ID, vouchedSubjectKey, 1_000_000, 1 days);

        vm.prank(ORG_ADMIN);
        hub.setRule(ORG_ID, account, selector, true, 0);

        bytes memory callData = abi.encodePacked(selector);
        uint48 expiry = uint48(block.timestamp + 1 hours);
        bytes memory paymasterAndData = _buildVouchedPaymasterData(account, expiry, "", callData);
        PackedUserOperation memory userOp = _buildUserOp(account, callData, paymasterAndData);

        vm.prank(address(entryPointStub));
        (bytes memory context,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(4)), MAX_COST);

        assertFalse(hub.isVouchUsed(ORG_ID, account), "vouch should not be consumed during validation");

        vm.prank(address(entryPointStub));
        hub.postOp(IPaymaster.PostOpMode.opReverted, context, MAX_COST);
        assertFalse(hub.isVouchUsed(ORG_ID, account), "failed execution should not consume vouch");

        vm.prank(address(entryPointStub));
        (bytes memory successContext,) = hub.validatePaymasterUserOp(userOp, bytes32(uint256(5)), MAX_COST);
        vm.prank(address(entryPointStub));
        hub.postOp(IPaymaster.PostOpMode.opSucceeded, successContext, MAX_COST);
        assertTrue(hub.isVouchUsed(ORG_ID, account), "successful execution should consume vouch");
    }

    function testFix_RegisterOrgRejectsZeroOrgId() public {
        vm.prank(POA_MANAGER);
        vm.expectRevert(PaymasterHub.InvalidOrgId.selector);
        hub.registerOrg(bytes32(0), ADMIN_HAT, OPERATOR_HAT);
    }

    function testFix_GracePathChecksGlobalSolidarityLiquidity() public {
        vm.prank(POA_MANAGER);
        hub.setGracePeriodConfig(90, 100 ether, 0.003 ether);

        address account = address(0xAB11);
        bytes4 selector = 0x11111111;
        bytes memory callData = abi.encodePacked(selector);

        bytes32 subjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_ACCOUNT, bytes20(account)));
        vm.prank(ORG_ADMIN);
        hub.setBudget(ORG_ID, subjectKey, type(uint128).max, 1 days);

        vm.prank(ORG_ADMIN);
        hub.setRule(ORG_ID, account, selector, true, 0);

        bytes memory paymasterAndData =
            _buildPaymasterData(ORG_ID, SUBJECT_TYPE_ACCOUNT, bytes20(account), RULE_ID_COARSE, 0);
        PackedUserOperation memory userOp = _buildUserOp(account, callData, paymasterAndData);

        vm.prank(address(entryPointStub));
        vm.expectRevert(PaymasterHub.InsufficientFunds.selector);
        hub.validatePaymasterUserOp(userOp, bytes32(uint256(40)), 2 ether);
    }
}

contract TaskManagerHighValidationTest is Test {
    TaskManager internal taskManager;
    AuditMockHats internal hats;
    AuditDummyToken internal token;

    address internal constant EXECUTOR = address(0xB001);
    address internal constant CREATOR = address(0xB002);
    address internal constant WORKER = address(0xB003);

    uint256 internal constant CREATOR_HAT = 11;
    uint256 internal constant PERMISSION_HAT = 22;

    function setUp() public {
        hats = new AuditMockHats();
        token = new AuditDummyToken();

        hats.setWearer(CREATOR_HAT, CREATOR, true);
        hats.setWearer(PERMISSION_HAT, WORKER, true);

        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT;

        TaskManager taskManagerImpl = new TaskManager();
        bytes memory initData = abi.encodeWithSelector(
            TaskManager.initialize.selector, address(token), address(hats), creatorHats, EXECUTOR, address(0)
        );
        taskManager = TaskManager(address(new ERC1967Proxy(address(taskManagerImpl), initData)));
    }

    function testFix_RemovingProjectMaskKeepsGlobalPermissionHat() public {
        address[] memory managers = new address[](0);
        uint256[] memory emptyHats = new uint256[](0);

        vm.prank(CREATOR);
        bytes32 pid = taskManager.createProject(
            bytes("audit-project"), bytes32(0), 0, managers, emptyHats, emptyHats, emptyHats, emptyHats
        );

        vm.prank(EXECUTOR);
        taskManager.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(PERMISSION_HAT, uint8(TaskPerm.CREATE)));

        vm.prank(WORKER);
        taskManager.createTask(1, bytes("before-remove"), bytes32(0), pid, address(0), 0, false);

        vm.prank(CREATOR);
        taskManager.setProjectRolePerm(pid, PERMISSION_HAT, 0);

        vm.prank(WORKER);
        taskManager.createTask(1, bytes("after-remove"), bytes32(0), pid, address(0), 0, false);
    }

    function testFix_RemovingGlobalMaskKeepsProjectPermissionHat() public {
        address[] memory managers = new address[](0);
        uint256[] memory emptyHats = new uint256[](0);

        vm.prank(CREATOR);
        bytes32 pid = taskManager.createProject(
            bytes("audit-project-2"), bytes32(0), 0, managers, emptyHats, emptyHats, emptyHats, emptyHats
        );

        vm.prank(EXECUTOR);
        taskManager.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(PERMISSION_HAT, uint8(TaskPerm.CREATE)));

        vm.prank(CREATOR);
        taskManager.setProjectRolePerm(pid, PERMISSION_HAT, uint8(TaskPerm.CREATE));

        vm.prank(EXECUTOR);
        taskManager.setConfig(TaskManager.ConfigKey.ROLE_PERM, abi.encode(PERMISSION_HAT, uint8(0)));

        vm.prank(WORKER);
        taskManager.createTask(1, bytes("project-only-perm"), bytes32(0), pid, address(0), 0, false);
    }
}
