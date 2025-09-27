// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {Deployer} from "../src/Deployer.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {PackedUserOperation} from "../src/interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {ModuleDeploymentLib, IHybridVotingInit} from "../src/libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../src/libs/ModuleTypes.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {HatsTreeSetup} from "../src/HatsTreeSetup.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {HybridVoting} from "../src/HybridVoting.sol";
import {Executor} from "../src/Executor.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {ToggleModule} from "../src/ToggleModule.sol";

// Mock contracts for integration testing
contract MockEntryPoint {
    mapping(address => uint256) private _deposits;
    address public lastPaymaster;

    function depositTo(address account) external payable {
        _deposits[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external {
        require(_deposits[msg.sender] >= withdrawAmount, "Insufficient deposit");
        _deposits[msg.sender] -= withdrawAmount;
        withdrawAddress.transfer(withdrawAmount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _deposits[account];
    }

    // Simulate UserOp validation
    function simulateValidation(
        address paymaster,
        PackedUserOperation memory userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        lastPaymaster = paymaster;
        return IPaymaster(paymaster).validatePaymasterUserOp(userOp, userOpHash, maxCost);
    }

    // Simulate postOp
    function simulatePostOp(address paymaster, IPaymaster.PostOpMode mode, bytes memory context, uint256 actualGasCost)
        external
    {
        IPaymaster(paymaster).postOp(mode, context, actualGasCost);
    }
}

contract MockAccount {
    address public owner;

    constructor(address _owner) {
        owner = _owner;
    }

    function execute(address target, uint256 value, bytes memory data) external returns (bytes memory) {
        require(msg.sender == owner, "Only owner");
        (bool success, bytes memory result) = target.call{value: value}(data);
        require(success, "Execution failed");
        return result;
    }
}

contract PaymasterHubIntegrationDeploymentTest is Test {
    // Core contracts
    ImplementationRegistry implRegistry;
    PoaManager poaManager;
    OrgRegistry orgRegistry;
    Deployer deployer;
    address hatsTreeSetup;
    MockEntryPoint mockEntryPoint;
    IHats hats;

    // Implementations
    PaymasterHub paymasterImpl;
    HybridVoting hybridImpl;
    Executor execImpl;
    ParticipationToken pTokenImpl;
    QuickJoin quickJoinImpl;
    TaskManager taskMgrImpl;
    EducationHub eduHubImpl;
    EligibilityModule eligModuleImpl;
    ToggleModule toggleModuleImpl;
    UniversalAccountRegistry accountRegImpl;

    // Test addresses
    address public constant poaAdmin = address(1);
    address public constant orgOwner = address(2);
    address public constant memberUser = address(3);
    address public constant executiveUser = address(4);
    address public constant bundler = address(5);
    address public constant SEPOLIA_HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    // Test IDs
    bytes32 public constant ORG_ID = keccak256("INTEGRATION-TEST-ORG");

    // DAO contracts
    address paymaster;
    address executor;
    address hybrid;
    uint256 memberHatId;
    uint256 executiveHatId;

    function setUp() public {
        // Deploy mock EntryPoint
        mockEntryPoint = new MockEntryPoint();

        // Deploy core infrastructure
        implRegistry = new ImplementationRegistry();
        poaManager = new PoaManager();
        orgRegistry = new OrgRegistry();

        // Deploy and initialize Hats
        deployCodeTo("Hats.sol", SEPOLIA_HATS);
        hats = IHats(SEPOLIA_HATS);

        // Deploy HatsTreeSetup
        hatsTreeSetup = address(new HatsTreeSetup());

        // Initialize PoaManager
        vm.prank(poaAdmin);
        poaManager.initialize(address(implRegistry), poaAdmin);

        // Deploy implementations
        paymasterImpl = new PaymasterHub();
        hybridImpl = new HybridVoting();
        execImpl = new Executor();
        pTokenImpl = new ParticipationToken();
        quickJoinImpl = new QuickJoin();
        taskMgrImpl = new TaskManager();
        eduHubImpl = new EducationHub();
        eligModuleImpl = new EligibilityModule();
        toggleModuleImpl = new ToggleModule();
        accountRegImpl = new UniversalAccountRegistry();

        // Register implementations
        vm.startPrank(poaAdmin);
        implRegistry.registerImplementation("PaymasterHub", address(paymasterImpl));
        implRegistry.registerImplementation("HybridVoting", address(hybridImpl));
        implRegistry.registerImplementation("Executor", address(execImpl));
        implRegistry.registerImplementation("ParticipationToken", address(pTokenImpl));
        implRegistry.registerImplementation("QuickJoin", address(quickJoinImpl));
        implRegistry.registerImplementation("TaskManager", address(taskMgrImpl));
        implRegistry.registerImplementation("EducationHub", address(eduHubImpl));
        implRegistry.registerImplementation("EligibilityModule", address(eligModuleImpl));
        implRegistry.registerImplementation("ToggleModule", address(toggleModuleImpl));

        // Create beacons
        poaManager.createBeacon("PaymasterHub");
        poaManager.createBeacon("HybridVoting");
        poaManager.createBeacon("Executor");
        poaManager.createBeacon("ParticipationToken");
        poaManager.createBeacon("QuickJoin");
        poaManager.createBeacon("TaskManager");
        poaManager.createBeacon("EducationHub");
        poaManager.createBeacon("EligibilityModule");
        poaManager.createBeacon("ToggleModule");
        vm.stopPrank();

        // Initialize OrgRegistry
        vm.prank(poaAdmin);
        orgRegistry.initialize(poaAdmin, address(poaManager));

        // Deploy and initialize Deployer
        deployer = new Deployer();
        deployer.initialize(address(poaManager), address(orgRegistry), SEPOLIA_HATS, hatsTreeSetup);

        // Deploy a full DAO with PaymasterHub
        _deployDAOWithPaymaster();
    }

    function _deployDAOWithPaymaster() internal {
        vm.deal(orgOwner, 10 ether);
        vm.startPrank(orgOwner);

        // Prepare deployment parameters
        string[] memory roleNames = new string[](2);
        roleNames[0] = "MEMBER";
        roleNames[1] = "EXECUTIVE";

        string[] memory roleImages = new string[](2);
        roleImages[0] = "ipfs://member";
        roleImages[1] = "ipfs://executive";

        bool[] memory roleCanVote = new bool[](2);
        roleCanVote[0] = true;
        roleCanVote[1] = true;

        IHybridVotingInit.ClassConfig[] memory votingClasses = new IHybridVotingInit.ClassConfig[](1);
        uint256[] memory hatIds = new uint256[](0);
        votingClasses[0] = IHybridVotingInit.ClassConfig({
            strategy: IHybridVotingInit.ClassStrategy.DIRECT,
            slicePct: 100,
            quadratic: false,
            minBalance: 0,
            asset: address(0),
            hatIds: hatIds
        });

        // Role assignments
        uint256[] memory memberRole = new uint256[](1);
        memberRole[0] = 0;

        uint256[] memory executiveRole = new uint256[](1);
        executiveRole[0] = 1;

        Deployer.RoleAssignments memory roleAssignments = Deployer.RoleAssignments({
            quickJoinRoles: memberRole,
            tokenMemberRoles: memberRole,
            tokenApproverRoles: executiveRole,
            taskCreatorRoles: executiveRole,
            educationCreatorRoles: executiveRole,
            educationMemberRoles: memberRole,
            proposalCreatorRoles: executiveRole
        });

        // PaymasterConfig with funding
        Deployer.PaymasterConfig memory pmConfig = Deployer.PaymasterConfig({
            enabled: true,
            entryPoint: address(mockEntryPoint),
            initialDeposit: 2 ether,
            initialBounty: 1 ether,
            enableBounty: true,
            maxBountyPerOp: 0.01 ether,
            bountyPctCap: 1000 // 10%
        });

        // Deploy DAO
        address quickJoin;
        address token;
        address taskManager;
        address educationHub;
        (hybrid, executor, quickJoin, token, taskManager, educationHub, paymaster) = deployer.deployFullOrg{
            value: 3 ether
        }(
            ORG_ID,
            "Integration Test DAO",
            address(accountRegImpl),
            true,
            50,
            votingClasses,
            roleNames,
            roleImages,
            roleCanVote,
            roleAssignments,
            pmConfig
        );

        vm.stopPrank();

        // Get hat IDs
        memberHatId = orgRegistry.getRoleHat(ORG_ID, 0);
        executiveHatId = orgRegistry.getRoleHat(ORG_ID, 1);

        // Mint hats to test users
        vm.startPrank(executor);
        hats.mintHat(memberHatId, memberUser);
        hats.mintHat(executiveHatId, executiveUser);
        vm.stopPrank();
    }

    function testPaymasterValidatesUserOpForMember() public {
        // Setup: Create a mock account for the member
        MockAccount account = new MockAccount(memberUser);

        // Configure PaymasterHub rules
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setRule(
            address(account), bytes4(keccak256("execute(address,uint256,bytes)")), true, 100000
        );

        // Configure budget for member hat
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(memberHatId))));
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setBudget(subjectKey, 1 ether, 1 days);

        // Create UserOperation
        PackedUserOperation memory userOp = _createUserOp(
            address(account),
            address(account),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(0), 0, ""),
            memberHatId
        );

        // Validate UserOperation as EntryPoint
        vm.prank(address(mockEntryPoint));
        (bytes memory context, uint256 validationData) =
            PaymasterHub(payable(paymaster)).validatePaymasterUserOp(userOp, keccak256("test"), 0.1 ether);

        // Verify validation passed
        assertEq(validationData, 0, "Validation should pass");
        assertTrue(context.length > 0, "Context should be returned");
    }

    function testPaymasterRejectsUserOpForNonMember() public {
        // Setup: Create a mock account for a non-member
        address nonMember = address(999);
        MockAccount account = new MockAccount(nonMember);

        // Configure PaymasterHub rules
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setRule(
            address(account), bytes4(keccak256("execute(address,uint256,bytes)")), true, 100000
        );

        // Configure budget for member hat
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(memberHatId))));
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setBudget(subjectKey, 1 ether, 1 days);

        // Create UserOperation with member hat but non-member sender
        PackedUserOperation memory userOp = _createUserOp(
            address(account),
            address(account),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(0), 0, ""),
            memberHatId
        );

        // Should revert for ineligible user
        vm.prank(address(mockEntryPoint));
        vm.expectRevert(abi.encodeWithSelector(PaymasterHub.Ineligible.selector));
        PaymasterHub(payable(paymaster)).validatePaymasterUserOp(userOp, keccak256("test"), 0.1 ether);
    }

    function testPaymasterBountyPayment() public {
        // Setup account and rules
        MockAccount account = new MockAccount(executiveUser);

        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setRule(
            address(account), bytes4(keccak256("execute(address,uint256,bytes)")), true, 100000
        );

        // Configure budget for executive hat
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(executiveHatId))));
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setBudget(subjectKey, 1 ether, 1 days);

        // Create UserOperation with mailbox commit (indicating bounty)
        PackedUserOperation memory userOp = _createUserOpWithBounty(
            address(account),
            address(account),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(0), 0, ""),
            executiveHatId,
            uint64(block.timestamp)
        );

        // Validate as EntryPoint
        vm.prank(address(mockEntryPoint));
        (bytes memory context,) =
            PaymasterHub(payable(paymaster)).validatePaymasterUserOp(userOp, keccak256("test"), 0.1 ether);

        // Record bundler balance before
        uint256 bundlerBalanceBefore = bundler.balance;

        // Simulate postOp with bundler as tx.origin
        vm.prank(address(mockEntryPoint), bundler);
        PaymasterHub(payable(paymaster)).postOp(
            IPaymaster.PostOpMode.opSucceeded,
            context,
            0.05 ether // actual gas cost
        );

        // Verify bounty was paid
        uint256 expectedBounty = (0.05 ether * 1000) / 10000; // 10% of gas cost
        assertEq(bundler.balance - bundlerBalanceBefore, expectedBounty, "Bounty should be paid to bundler");
    }

    function testPaymasterBudgetEnforcement() public {
        // Setup account
        MockAccount account = new MockAccount(memberUser);

        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setRule(
            address(account), bytes4(keccak256("execute(address,uint256,bytes)")), true, 100000
        );

        // Set a small budget
        bytes32 subjectKey = keccak256(abi.encodePacked(uint8(1), bytes20(uint160(memberHatId))));
        vm.prank(executor);
        PaymasterHub(payable(paymaster)).setBudget(subjectKey, 0.01 ether, 1 days);

        // Create UserOperation
        PackedUserOperation memory userOp = _createUserOp(
            address(account),
            address(account),
            abi.encodeWithSignature("execute(address,uint256,bytes)", address(0), 0, ""),
            memberHatId
        );

        // First operation should succeed
        vm.prank(address(mockEntryPoint));
        (bytes memory context1,) =
            PaymasterHub(payable(paymaster)).validatePaymasterUserOp(userOp, keccak256("test1"), 0.005 ether);

        // Update usage via postOp
        vm.prank(address(mockEntryPoint));
        PaymasterHub(payable(paymaster)).postOp(IPaymaster.PostOpMode.opSucceeded, context1, 0.005 ether);

        // Second operation should fail due to budget exceeded
        vm.prank(address(mockEntryPoint));
        vm.expectRevert(abi.encodeWithSelector(PaymasterHub.BudgetExceeded.selector));
        PaymasterHub(payable(paymaster)).validatePaymasterUserOp(
            userOp,
            keccak256("test2"),
            0.01 ether // This would exceed the budget
        );
    }

    // Helper functions
    function _createUserOp(address sender, address target, bytes memory callData, uint256 hatId)
        internal
        pure
        returns (PackedUserOperation memory)
    {
        // Encode paymaster data
        bytes memory paymasterAndData = abi.encodePacked(
            address(0), // paymaster address placeholder (20 bytes)
            uint8(1), // version
            uint8(1), // subject type (hat)
            bytes20(uint160(hatId)), // subject ID
            uint32(0), // rule ID (generic)
            uint64(0) // no mailbox commit
        );

        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(100000) << 128 | 50000),
            preVerificationGas: 21000,
            gasFees: bytes32(uint256(10 gwei) << 128 | 1 gwei),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }

    function _createUserOpWithBounty(
        address sender,
        address target,
        bytes memory callData,
        uint256 hatId,
        uint64 mailboxCommit
    ) internal pure returns (PackedUserOperation memory) {
        // Encode paymaster data with mailbox commit
        bytes memory paymasterAndData = abi.encodePacked(
            address(0), // paymaster address placeholder (20 bytes)
            uint8(1), // version
            uint8(1), // subject type (hat)
            bytes20(uint160(hatId)), // subject ID
            uint32(0), // rule ID (generic)
            mailboxCommit // mailbox commit for bounty
        );

        return PackedUserOperation({
            sender: sender,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(uint256(100000) << 128 | 50000),
            preVerificationGas: 21000,
            gasFees: bytes32(uint256(10 gwei) << 128 | 1 gwei),
            paymasterAndData: paymasterAndData,
            signature: ""
        });
    }
}
