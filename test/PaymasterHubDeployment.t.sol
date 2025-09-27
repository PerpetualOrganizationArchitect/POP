// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

// Import required contracts
import {Deployer} from "../src/Deployer.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {ModuleDeploymentLib, IHybridVotingInit} from "../src/libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../src/libs/ModuleTypes.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
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
import {SwitchableBeacon} from "../src/SwitchableBeacon.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";

// Mock EntryPoint for testing
contract MockEntryPoint is IEntryPoint {
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
}

// Test contract for PaymasterHub deployment
contract PaymasterHubDeploymentTest is Test {
    // Core contracts
    ImplementationRegistry implRegistry;
    PoaManager poaManager;
    OrgRegistry orgRegistry;
    Deployer deployer;
    address hatsTreeSetup;

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
    address public constant user1 = address(3);
    address public constant user2 = address(4);
    address public constant SEPOLIA_HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    // Test IDs
    bytes32 public constant ORG_ID = keccak256("PAYMASTER-TEST-ORG");
    bytes32 public constant GLOBAL_REG_ID = keccak256("POA-GLOBAL-ACCOUNT-REGISTRY");

    // Mock EntryPoint
    MockEntryPoint mockEntryPoint;

    function setUp() public {
        // Deploy mock EntryPoint
        mockEntryPoint = new MockEntryPoint();

        // Deploy core infrastructure
        implRegistry = new ImplementationRegistry();
        poaManager = new PoaManager();
        orgRegistry = new OrgRegistry();

        // Deploy and initialize Hats
        deployCodeTo("Hats.sol", SEPOLIA_HATS);
        IHats hats = IHats(SEPOLIA_HATS);

        // Deploy HatsTreeSetup
        hatsTreeSetup = address(new HatsTreeSetup());

        // Initialize PoaManager with ImplementationRegistry
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

        // Create beacons in PoaManager
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

        // Deploy and initialize OrgRegistry
        vm.prank(poaAdmin);
        orgRegistry.initialize(poaAdmin, address(poaManager));

        // Deploy global account registry proxy
        address accountRegProxy = address(accountRegImpl);

        // Deploy and initialize Deployer
        deployer = new Deployer();
        deployer.initialize(address(poaManager), address(orgRegistry), SEPOLIA_HATS, hatsTreeSetup);
    }

    function testDeployOrgWithoutPaymaster() public {
        vm.startPrank(orgOwner);

        // Prepare deployment parameters
        string[] memory roleNames = new string[](2);
        roleNames[0] = "DEFAULT";
        roleNames[1] = "EXECUTIVE";

        string[] memory roleImages = new string[](2);
        roleImages[0] = "ipfs://default";
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

        Deployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        // PaymasterConfig with disabled paymaster
        Deployer.PaymasterConfig memory pmConfig = Deployer.PaymasterConfig({
            enabled: false,
            entryPoint: address(0),
            initialDeposit: 0,
            initialBounty: 0,
            enableBounty: false,
            maxBountyPerOp: 0,
            bountyPctCap: 0
        });

        // Deploy organization without paymaster
        (address hybrid, address exec,,,,, address paymaster) = deployer.deployFullOrg(
            ORG_ID,
            "Test Org",
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

        // Verify deployment
        assertEq(paymaster, address(0), "Paymaster should not be deployed when disabled");
        assertTrue(hybrid != address(0), "HybridVoting should be deployed");
        assertTrue(exec != address(0), "Executor should be deployed");
    }

    function testDeployOrgWithPaymaster() public {
        vm.deal(orgOwner, 10 ether);
        vm.startPrank(orgOwner);

        // Prepare deployment parameters
        string[] memory roleNames = new string[](2);
        roleNames[0] = "DEFAULT";
        roleNames[1] = "EXECUTIVE";

        string[] memory roleImages = new string[](2);
        roleImages[0] = "ipfs://default";
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

        Deployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        // PaymasterConfig with enabled paymaster and funding
        Deployer.PaymasterConfig memory pmConfig = Deployer.PaymasterConfig({
            enabled: true,
            entryPoint: address(mockEntryPoint),
            initialDeposit: 1 ether,
            initialBounty: 0.5 ether,
            enableBounty: true,
            maxBountyPerOp: 0.01 ether,
            bountyPctCap: 1000 // 10%
        });

        // Deploy organization with paymaster
        (address hybrid, address exec,,,,, address paymaster) = deployer.deployFullOrg{value: 1.5 ether}(
            ORG_ID,
            "Test Org",
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

        // Verify deployment
        assertTrue(paymaster != address(0), "Paymaster should be deployed when enabled");
        assertTrue(hybrid != address(0), "HybridVoting should be deployed");
        assertTrue(exec != address(0), "Executor should be deployed");

        // Verify PaymasterHub configuration
        PaymasterHub paymasterHub = PaymasterHub(payable(paymaster));
        assertEq(paymasterHub.ENTRY_POINT(), address(mockEntryPoint), "EntryPoint should be set");

        // Verify funding
        assertEq(mockEntryPoint.balanceOf(paymaster), 1 ether, "EntryPoint deposit should be funded");
        assertEq(paymaster.balance, 0.5 ether, "Bounty pool should be funded");

        // Verify bounty configuration
        PaymasterHub.Bounty memory bounty = paymasterHub.bountyInfo();
        assertTrue(bounty.enabled, "Bounty should be enabled");
        assertEq(bounty.maxBountyWeiPerOp, 0.01 ether, "Max bounty per op should be set");
        assertEq(bounty.pctBpCap, 1000, "Bounty percentage cap should be set");
    }

    function testDeployOrgWithInsufficientFunding() public {
        vm.deal(orgOwner, 0.5 ether); // Not enough for requested funding
        vm.startPrank(orgOwner);

        // Prepare deployment parameters
        string[] memory roleNames = new string[](2);
        roleNames[0] = "DEFAULT";
        roleNames[1] = "EXECUTIVE";

        string[] memory roleImages = new string[](2);
        roleImages[0] = "ipfs://default";
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

        Deployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        // PaymasterConfig requesting more funds than available
        Deployer.PaymasterConfig memory pmConfig = Deployer.PaymasterConfig({
            enabled: true,
            entryPoint: address(mockEntryPoint),
            initialDeposit: 1 ether,
            initialBounty: 0.5 ether,
            enableBounty: true,
            maxBountyPerOp: 0.01 ether,
            bountyPctCap: 1000
        });

        // Should revert due to insufficient funding
        vm.expectRevert(abi.encodeWithSelector(Deployer.InsufficientFunding.selector));
        deployer.deployFullOrg{value: 0.5 ether}(
            ORG_ID,
            "Test Org",
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
    }

    function testPaymasterUpgradeability() public {
        vm.deal(orgOwner, 2 ether);
        vm.startPrank(orgOwner);

        // Deploy with auto-upgrade enabled
        string[] memory roleNames = new string[](1);
        roleNames[0] = "ADMIN";

        string[] memory roleImages = new string[](1);
        roleImages[0] = "ipfs://admin";

        bool[] memory roleCanVote = new bool[](1);
        roleCanVote[0] = true;

        IHybridVotingInit.ClassConfig[] memory votingClasses = new IHybridVotingInit.ClassConfig[](0);
        Deployer.RoleAssignments memory roleAssignments = _buildSingleRoleAssignments();

        Deployer.PaymasterConfig memory pmConfig = Deployer.PaymasterConfig({
            enabled: true,
            entryPoint: address(mockEntryPoint),
            initialDeposit: 0,
            initialBounty: 0,
            enableBounty: false,
            maxBountyPerOp: 0,
            bountyPctCap: 0
        });

        (, address exec,,,,, address paymaster) = deployer.deployFullOrg(
            ORG_ID,
            "Test Org",
            address(accountRegImpl),
            true, // auto-upgrade enabled
            50,
            votingClasses,
            roleNames,
            roleImages,
            roleCanVote,
            roleAssignments,
            pmConfig
        );

        vm.stopPrank();

        // Get the beacon from OrgRegistry
        address beacon = orgRegistry.getOrgBeacon(ORG_ID, ModuleTypes.PAYMASTER_HUB_ID);
        assertTrue(beacon != address(0), "Beacon should exist");

        // Verify beacon is in mirror mode (auto-upgrade)
        SwitchableBeacon switchableBeacon = SwitchableBeacon(beacon);
        assertTrue(switchableBeacon.isMirrorMode(), "Beacon should be in mirror mode for auto-upgrade");

        // Verify beacon owner is the executor
        assertEq(switchableBeacon.owner(), exec, "Beacon should be owned by executor");
    }

    // Helper function to build default role assignments
    function _buildDefaultRoleAssignments() internal pure returns (Deployer.RoleAssignments memory) {
        uint256[] memory defaultRole = new uint256[](1);
        defaultRole[0] = 0;

        uint256[] memory executiveRole = new uint256[](1);
        executiveRole[0] = 1;

        return Deployer.RoleAssignments({
            quickJoinRoles: defaultRole,
            tokenMemberRoles: defaultRole,
            tokenApproverRoles: executiveRole,
            taskCreatorRoles: executiveRole,
            educationCreatorRoles: executiveRole,
            educationMemberRoles: defaultRole,
            proposalCreatorRoles: executiveRole
        });
    }

    // Helper function for single role assignments
    function _buildSingleRoleAssignments() internal pure returns (Deployer.RoleAssignments memory) {
        uint256[] memory adminRole = new uint256[](1);
        adminRole[0] = 0;

        return Deployer.RoleAssignments({
            quickJoinRoles: adminRole,
            tokenMemberRoles: adminRole,
            tokenApproverRoles: adminRole,
            taskCreatorRoles: adminRole,
            educationCreatorRoles: adminRole,
            educationMemberRoles: adminRole,
            proposalCreatorRoles: adminRole
        });
    }
}
