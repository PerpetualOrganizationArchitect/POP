// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*──────────── forge‑std helpers ───────────*/
import "forge-std/Test.sol";
import "forge-std/console.sol";

/*──────────── OpenZeppelin ───────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";

/*──────────── Local contracts ───────────*/
import {HybridVoting} from "../src/HybridVoting.sol";
import {DirectDemocracyVoting} from "../src/DirectDemocracyVoting.sol";
import {Executor} from "../src/Executor.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";
import {PaymentManager} from "../src/PaymentManager.sol";
import {IPaymentManager} from "../src/interfaces/IPaymentManager.sol";

import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import "../src/ImplementationRegistry.sol";
import "../src/PoaManager.sol";
import "../src/OrgRegistry.sol";
import {OrgDeployer} from "../src/OrgDeployer.sol";
import {GovernanceFactory} from "../src/factories/GovernanceFactory.sol";
import {AccessFactory} from "../src/factories/AccessFactory.sol";
import {RoleConfigStructs} from "../src/libs/RoleConfigStructs.sol";
import {ModulesFactory} from "../src/factories/ModulesFactory.sol";
import {HatsTreeSetup} from "../src/HatsTreeSetup.sol";
import {ModuleDeploymentLib, IHybridVotingInit} from "../src/libs/ModuleDeploymentLib.sol";
import {ModuleTypes} from "../src/libs/ModuleTypes.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {ToggleModule} from "../src/ToggleModule.sol";
import {IExecutor} from "../src/Executor.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";

// Define events for testing
interface IEligibilityModuleEvents {
    event WearerEligibilityUpdated(
        address indexed wearer, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );

    event DefaultEligibilityUpdated(uint256 indexed hatId, bool eligible, bool standing, address indexed admin);

    event SuperAdminTransferred(address indexed oldSuperAdmin, address indexed newSuperAdmin);

    event Vouched(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    event VouchRevoked(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    event HatClaimed(address indexed wearer, uint256 indexed hatId);

    event VouchConfigSet(
        uint256 indexed hatId, uint32 quorum, uint256 membershipHatId, bool enabled, bool combineWithHierarchy
    );

    event HatCreatedWithEligibility(
        address indexed creator,
        uint256 indexed parentHatId,
        uint256 indexed newHatId,
        bool defaultEligible,
        bool defaultStanding,
        uint256 mintedCount
    );
}

/*────────────── Test contract ───────────*/
contract DeployerTest is Test, IEligibilityModuleEvents {
    /*–––– implementations ––––*/
    HybridVoting hybridImpl;
    DirectDemocracyVoting ddVotingImpl;
    Executor execImpl;
    UniversalAccountRegistry accountRegImpl;
    QuickJoin quickJoinImpl;
    ParticipationToken pTokenImpl;
    TaskManager taskMgrImpl;
    EducationHub eduHubImpl;
    PaymentManager paymentManagerImpl;

    ImplementationRegistry implRegistry;
    PoaManager poaManager;
    OrgRegistry orgRegistry;
    OrgDeployer deployer;
    GovernanceFactory governanceFactory;
    AccessFactory accessFactory;
    ModulesFactory modulesFactory;
    PaymasterHub paymasterHub;

    /*–––– addresses ––––*/
    address public constant poaAdmin = address(1);
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address public constant orgOwner = address(2);
    address public constant voter1 = address(3);
    address public constant voter2 = address(4);
    address public constant SEPOLIA_HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    /*–––– ids ––––*/
    bytes32 public constant ORG_ID = keccak256("AUTO-UPGRADE-ORG");
    bytes32 public constant GLOBAL_REG_ID = keccak256("POA-GLOBAL-ACCOUNT-REGISTRY");

    /*–––– deployed proxies ––––*/
    address quickJoinProxy;
    address pTokenProxy;
    address payable executorProxy;
    address hybridProxy;
    address taskMgrProxy;
    address eduHubProxy;
    address accountRegProxy;

    /*–––– Test Helper Structs ––––*/
    struct TestOrgSetup {
        address hybrid;
        address exec;
        address qj;
        address token;
        address tm;
        address hub;
        address eligibilityModule;
        uint256 defaultRoleHat;
        uint256 executiveRoleHat;
        uint256 memberRoleHat;
    }

    struct EligibilityStatus {
        bool eligible;
        bool standing;
    }

    function _deployFullOrg()
        internal
        returns (address hybrid, address exec, address qj, address token, address tm, address hub, address pm)
    {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0); // Empty for now

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Hybrid DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        vm.stopPrank();
        return (
            result.hybridVoting,
            result.executor,
            result.quickJoin,
            result.participationToken,
            result.taskManager,
            result.educationHub,
            result.paymentManager
        );
    }

    /*–––– Test Helper Functions ––––*/

    /// @dev Helper to build role configs from simple arrays with sensible defaults
    /// @param names Role names
    /// @param images Role images
    /// @param canVote Whether each role can vote
    /// @return Role configs with default settings (no vouching, all eligible, linear hierarchy)
    function _buildSimpleRoleConfigs(string[] memory names, string[] memory images, bool[] memory canVote)
        internal
        pure
        returns (RoleConfigStructs.RoleConfig[] memory)
    {
        RoleConfigStructs.RoleConfig[] memory roles = new RoleConfigStructs.RoleConfig[](names.length);

        for (uint256 i = 0; i < names.length; i++) {
            // Last role (highest index) is top of hierarchy, minted to deployer
            bool isTopRole = (i == names.length - 1);

            roles[i] = RoleConfigStructs.RoleConfig({
                name: names[i],
                image: images[i],
                canVote: canVote[i],
                vouching: RoleConfigStructs.RoleVouchingConfig({
                    enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false
                }),
                defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
                hierarchy: RoleConfigStructs.RoleHierarchyConfig({
                    adminRoleIndex: isTopRole ? type(uint256).max : i + 1
                }),
                distribution: RoleConfigStructs.RoleDistributionConfig({
                    mintToDeployer: isTopRole && canVote[i],
                    mintToExecutor: !isTopRole && canVote[i],
                    additionalWearers: new address[](0)
                }),
                hatConfig: RoleConfigStructs.HatConfig({
                    maxSupply: type(uint32).max, // Default: unlimited
                    mutableHat: true // Default: mutable
                })
            });
        }

        return roles;
    }

    /// @dev Helper to build default role assignments (index 0 = members, index 1 = executives)
    function _buildDefaultRoleAssignments() internal pure returns (OrgDeployer.RoleAssignments memory) {
        // Bitmap encoding: bit 0 = role 0, bit 1 = role 1
        // 1 = 0b001 (role 0 only)
        // 2 = 0b010 (role 1 only)

        return OrgDeployer.RoleAssignments({
            quickJoinRolesBitmap: 1, // Role 0: new members
            tokenMemberRolesBitmap: 1, // Role 0: can hold tokens
            tokenApproverRolesBitmap: 2, // Role 1: can approve transfers
            taskCreatorRolesBitmap: 2, // Role 1: can create tasks
            educationCreatorRolesBitmap: 2, // Role 1: can create education
            educationMemberRolesBitmap: 1, // Role 0: can access education
            hybridProposalCreatorRolesBitmap: 2, // Role 1: can create proposals
            ddVotingRolesBitmap: 1, // Role 0: can vote in polls
            ddCreatorRolesBitmap: 2 // Role 1: can create polls
        });
    }

    /// @dev Helper to build legacy-style voting classes
    function _buildLegacyClasses(uint8 ddSplit, uint8 ptSplit, bool quadratic, uint256 minBal)
        internal
        pure
        returns (IHybridVotingInit.ClassConfig[] memory)
    {
        // Build classes with empty hat arrays - they'll be filled in during deployment
        uint256[] memory emptyHats = new uint256[](0);

        IHybridVotingInit.ClassConfig[] memory classes;

        if (ddSplit == 100) {
            // Pure Direct Democracy
            classes = new IHybridVotingInit.ClassConfig[](1);
            classes[0] = IHybridVotingInit.ClassConfig({
                strategy: IHybridVotingInit.ClassStrategy.DIRECT,
                slicePct: 100,
                quadratic: false,
                minBalance: 0,
                asset: address(0),
                hatIds: emptyHats
            });
        } else if (ddSplit == 0) {
            // Pure Token Voting
            classes = new IHybridVotingInit.ClassConfig[](1);
            classes[0] = IHybridVotingInit.ClassConfig({
                strategy: IHybridVotingInit.ClassStrategy.ERC20_BAL,
                slicePct: 100,
                quadratic: quadratic,
                minBalance: minBal,
                asset: address(0), // Will be set during deployment
                hatIds: emptyHats
            });
        } else {
            // Hybrid (two classes)
            classes = new IHybridVotingInit.ClassConfig[](2);

            // Class 0: Direct Democracy
            classes[0] = IHybridVotingInit.ClassConfig({
                strategy: IHybridVotingInit.ClassStrategy.DIRECT,
                slicePct: ddSplit,
                quadratic: false,
                minBalance: 0,
                asset: address(0),
                hatIds: emptyHats
            });

            // Class 1: Participation Token
            classes[1] = IHybridVotingInit.ClassConfig({
                strategy: IHybridVotingInit.ClassStrategy.ERC20_BAL,
                slicePct: ptSplit,
                quadratic: quadratic,
                minBalance: minBal,
                asset: address(0), // Will be set during deployment
                hatIds: emptyHats
            });
        }

        return classes;
    }

    /// @dev Creates a standardized test organization with 3 roles: DEFAULT, EXECUTIVE, MEMBER
    function _createTestOrg(string memory orgName) internal returns (TestOrgSetup memory setup) {
        vm.startPrank(orgOwner);

        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MEMBER";

        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://member-role-image";

        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: orgName,
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        setup.hybrid = result.hybridVoting;
        setup.exec = result.executor;
        setup.qj = result.quickJoin;
        setup.token = result.participationToken;
        setup.tm = result.taskManager;
        setup.hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module and role hat IDs
        setup.eligibilityModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);
        setup.defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        setup.executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        setup.memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);
    }

    /// @dev Creates a test organization with 2 roles (for backward compatibility)
    function _createSimpleTestOrg(string memory orgName) internal returns (TestOrgSetup memory setup) {
        vm.startPrank(orgOwner);

        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";

        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";

        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();
        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: orgName,
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        setup.hybrid = result.hybridVoting;
        setup.exec = result.executor;
        setup.qj = result.quickJoin;
        setup.token = result.participationToken;
        setup.tm = result.taskManager;
        setup.hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module and role hat IDs
        setup.eligibilityModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);
        setup.defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        setup.executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        setup.memberRoleHat = 0; // Not applicable for 2-role setup
    }

    /// @dev Configures vouching for a hat and optionally sets default eligibility to false
    function _configureVouching(
        address eligibilityModule,
        address executor,
        uint256 targetHat,
        uint32 quorum,
        uint256 membershipHat,
        bool combineWithHierarchy,
        bool setDefaultToFalse
    ) internal {
        vm.prank(executor);
        EligibilityModule(eligibilityModule).configureVouching(targetHat, quorum, membershipHat, combineWithHierarchy);

        if (setDefaultToFalse) {
            vm.prank(executor);
            EligibilityModule(eligibilityModule).setDefaultEligibility(targetHat, false, false);
        }
    }

    /// @dev Mints a hat to a user
    function _mintHat(address executor, uint256 hatId, address user) internal {
        vm.prank(executor);
        IHats(SEPOLIA_HATS).mintHat(hatId, user);
    }

    /// @dev Mints a hat to a user and sets up vouching join time
    function _mintAdminHat(address executor, address eligibilityModule, uint256 hatId, address user) internal {
        // Mint the hat to the user
        vm.prank(executor);
        IHats(SEPOLIA_HATS).mintHat(hatId, user);

        // Set user join time for vouching tests
        vm.prank(executor);
        EligibilityModule(eligibilityModule).setUserJoinTime(user, block.timestamp - 3 days);
    }

    /// @dev Checks eligibility status for a user and hat
    function _getEligibilityStatus(address eligibilityModule, address user, uint256 hatId)
        internal
        view
        returns (EligibilityStatus memory status)
    {
        (status.eligible, status.standing) = EligibilityModule(eligibilityModule).getWearerStatus(user, hatId);
    }

    /// @dev Asserts eligibility status
    function _assertEligibilityStatus(
        address eligibilityModule,
        address user,
        uint256 hatId,
        bool expectedEligible,
        bool expectedStanding,
        string memory message
    ) internal {
        EligibilityStatus memory status = _getEligibilityStatus(eligibilityModule, user, hatId);
        if (expectedEligible) {
            assertTrue(status.eligible, string(abi.encodePacked(message, " - should be eligible")));
        } else {
            assertFalse(status.eligible, string(abi.encodePacked(message, " - should not be eligible")));
        }
        if (expectedStanding) {
            assertTrue(status.standing, string(abi.encodePacked(message, " - should have good standing")));
        } else {
            assertFalse(status.standing, string(abi.encodePacked(message, " - should not have good standing")));
        }
    }

    /// @dev Sets up user for vouching by setting their join time
    function _setupUserForVouching(address eligibilityModule, address executor, address user) internal {
        vm.prank(executor);
        EligibilityModule(eligibilityModule).setUserJoinTime(user, block.timestamp - 3 days);
    }

    /// @dev Performs a vouch and returns the new count
    function _vouchFor(address voucher, address eligibilityModule, address wearer, uint256 hatId)
        internal
        returns (uint32 newCount)
    {
        vm.prank(voucher);
        EligibilityModule(eligibilityModule).vouchFor(wearer, hatId);
        newCount = EligibilityModule(eligibilityModule).currentVouchCount(hatId, wearer);
    }

    /// @dev Revokes a vouch and returns the new count
    function _revokeVouch(address voucher, address eligibilityModule, address wearer, uint256 hatId)
        internal
        returns (uint32 newCount)
    {
        vm.prank(voucher);
        EligibilityModule(eligibilityModule).revokeVouch(wearer, hatId);
        newCount = EligibilityModule(eligibilityModule).currentVouchCount(hatId, wearer);
    }

    /// @dev Asserts vouch count and approval status
    function _assertVouchStatus(
        address eligibilityModule,
        address wearer,
        uint256 hatId,
        uint32 expectedCount,
        bool expectedApproval,
        string memory message
    ) internal {
        uint32 actualCount = EligibilityModule(eligibilityModule).currentVouchCount(hatId, wearer);
        // Calculate approval status based on quorum
        EligibilityModule.VouchConfig memory config = EligibilityModule(eligibilityModule).getVouchConfig(hatId);
        bool actualApproval = actualCount >= config.quorum;

        assertEq(actualCount, expectedCount, string(abi.encodePacked(message, " - vouch count")));
        if (expectedApproval) {
            assertTrue(actualApproval, string(abi.encodePacked(message, " - should be approved")));
        } else {
            assertFalse(actualApproval, string(abi.encodePacked(message, " - should not be approved")));
        }
    }

    /// @dev Asserts that a user is wearing a hat
    function _assertWearingHat(address user, uint256 hatId, bool shouldBeWearing, string memory message) internal {
        bool isWearing = IHats(SEPOLIA_HATS).isWearerOfHat(user, hatId);
        if (shouldBeWearing) {
            assertTrue(isWearing, string(abi.encodePacked(message, " - should be wearing hat")));
        } else {
            assertFalse(isWearing, string(abi.encodePacked(message, " - should not be wearing hat")));
        }
    }

    /// @dev Gets vouch configuration for a hat
    function _getVouchConfig(address eligibilityModule, uint256 hatId)
        internal
        view
        returns (EligibilityModule.VouchConfig memory)
    {
        return EligibilityModule(eligibilityModule).getVouchConfig(hatId);
    }

    /*══════════════════════════════════════════ SET‑UP ══════════════════════════════════════════*/
    function setUp() public {
        // Fork Sepolia using the RPC URL from foundry.toml
        vm.createSelectFork("hoodi");

        /*–– deploy bare implementations ––*/
        hybridImpl = new HybridVoting();
        ddVotingImpl = new DirectDemocracyVoting();
        execImpl = new Executor();
        accountRegImpl = new UniversalAccountRegistry();
        quickJoinImpl = new QuickJoin();
        pTokenImpl = new ParticipationToken();
        taskMgrImpl = new TaskManager();
        eduHubImpl = new EducationHub();
        paymentManagerImpl = new PaymentManager();

        // Deploy the implementation contract for ImplementationRegistry
        ImplementationRegistry implRegistryImpl = new ImplementationRegistry();

        // Deploy EligibilityModule implementation
        EligibilityModule eligibilityModuleImpl = new EligibilityModule();

        // Deploy ToggleModule implementation
        ToggleModule toggleModuleImpl = new ToggleModule();

        vm.startPrank(poaAdmin);
        console.log("Current msg.sender:", msg.sender);

        /*–– infra ––*/
        // Deploy PoaManager first without the actual registry address
        // We'll update it later after we create the proxy
        poaManager = new PoaManager(address(0)); // Temporary zero address

        // Deploy implementations for OrgRegistry and OrgDeployer
        OrgRegistry orgRegistryImpl = new OrgRegistry();
        OrgDeployer deployerImpl = new OrgDeployer();

        // Register ImplementationRegistry implementation with PoaManager first
        poaManager.addContractType("ImplementationRegistry", address(implRegistryImpl));

        // Get the beacon for ImplementationRegistry
        bytes32 implRegTypeId = keccak256("ImplementationRegistry");
        address implRegBeacon = poaManager.getBeaconById(implRegTypeId);

        // Create ImplementationRegistry proxy and initialize it with poaAdmin as owner
        bytes memory implRegistryInit = abi.encodeWithSignature("initialize(address)", poaAdmin);
        implRegistry = ImplementationRegistry(address(new BeaconProxy(implRegBeacon, implRegistryInit)));

        // Now update the PoaManager to use the correct ImplementationRegistry proxy
        poaManager.updateImplRegistry(address(implRegistry));

        // Register the implRegistryImpl in the registry now that it's connected
        implRegistry.registerImplementation("ImplementationRegistry", "v1", address(implRegistryImpl), true);

        // Transfer implRegistry ownership to poaManager
        implRegistry.transferOwnership(address(poaManager));

        // Register implementations for OrgRegistry and OrgDeployer
        poaManager.addContractType("OrgRegistry", address(orgRegistryImpl));
        poaManager.addContractType("OrgDeployer", address(deployerImpl));

        // Get beacons created by PoaManager
        address orgRegBeacon = poaManager.getBeaconById(keccak256("OrgRegistry"));
        address deployerBeacon = poaManager.getBeaconById(keccak256("OrgDeployer"));

        // Create OrgRegistry proxy - initialize with poaAdmin as owner
        bytes memory orgRegistryInit = abi.encodeWithSignature("initialize(address)", poaAdmin);
        orgRegistry = OrgRegistry(address(new BeaconProxy(orgRegBeacon, orgRegistryInit)));

        // Debug to verify OrgRegistry owner
        console.log("OrgRegistry owner after init:", orgRegistry.owner());

        // Deploy HatsTreeSetup helper contract
        HatsTreeSetup hatsTreeSetup = new HatsTreeSetup();

        // Mock EntryPoint address for PaymasterHub (not actually used in tests, but required for initialization)
        address mockEntryPoint = address(0x5FF137D4b0FDCD49DcA30c7CF57E578a026d2789); // ERC-4337 EntryPoint v0.6

        // Deploy factory contracts
        governanceFactory = new GovernanceFactory();
        accessFactory = new AccessFactory();
        modulesFactory = new ModulesFactory();

        // Deploy PaymasterHub as beacon proxy
        PaymasterHub paymasterHubImpl = new PaymasterHub();
        poaManager.addContractType("PaymasterHub", address(paymasterHubImpl));
        address paymasterHubBeacon = poaManager.getBeaconById(keccak256("PaymasterHub"));
        bytes memory paymasterHubInit = abi.encodeWithSignature(
            "initialize(address,address,address)", ENTRY_POINT_V07, SEPOLIA_HATS, address(poaManager)
        );
        paymasterHub = PaymasterHub(payable(address(new BeaconProxy(paymasterHubBeacon, paymasterHubInit))));

        // Create OrgDeployer proxy - initialize with factory addresses
        bytes memory deployerInit = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address)",
            address(governanceFactory),
            address(accessFactory),
            address(modulesFactory),
            address(poaManager),
            address(orgRegistry),
            SEPOLIA_HATS,
            address(hatsTreeSetup),
            address(paymasterHub)
        );
        deployer = OrgDeployer(address(new BeaconProxy(deployerBeacon, deployerInit)));

        // Debug to verify Deployer initialization
        console.log("deployer address:", address(deployer));

        // Now transfer orgRegistry ownership to deployer after both are initialized
        // This is critical to get the ownership chain right
        orgRegistry.transferOwnership(address(deployer));
        console.log("OrgRegistry owner after transfer:", orgRegistry.owner());

        /*–– register implementation types ––*/
        poaManager.addContractType("HybridVoting", address(hybridImpl));
        poaManager.addContractType("DirectDemocracyVoting", address(ddVotingImpl));
        poaManager.addContractType("Executor", address(execImpl));
        poaManager.addContractType("QuickJoin", address(quickJoinImpl));
        poaManager.addContractType("ParticipationToken", address(pTokenImpl));
        poaManager.addContractType("TaskManager", address(taskMgrImpl));
        poaManager.addContractType("EducationHub", address(eduHubImpl));
        poaManager.addContractType("UniversalAccountRegistry", address(accountRegImpl));
        poaManager.addContractType("EligibilityModule", address(eligibilityModuleImpl));
        poaManager.addContractType("ToggleModule", address(toggleModuleImpl));
        poaManager.addContractType("PaymentManager", address(paymentManagerImpl));

        /*–– global account registry instance ––*/
        // Get the beacon created by PoaManager for account registry
        address accRegBeacon = poaManager.getBeaconById(keccak256("UniversalAccountRegistry"));

        // Create a proxy using the beacon with proper initialization data
        bytes memory accRegInit = abi.encodeWithSignature("initialize(address)", poaAdmin);
        accountRegProxy = address(new BeaconProxy(accRegBeacon, accRegInit));

        vm.stopPrank();
    }

    /*══════════════════════════════════════════ TESTS ══════════════════════════════════════════*/
    function testFullOrgDeployment() public {
        /*–––– deploy a full org via the new flow ––––*/
        vm.startPrank(orgOwner);

        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();
        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Hybrid DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);

        vm.stopPrank();

        /* store for later checks */
        hybridProxy = result.hybridVoting;
        executorProxy = payable(result.executor);
        quickJoinProxy = result.quickJoin;
        pTokenProxy = result.participationToken;
        taskMgrProxy = result.taskManager;
        eduHubProxy = result.educationHub;

        /* basic invariants */
        // Version getters removed - contracts are upgradeable via beacon pattern

        /*—————————————————— quick smoke test: join + vote —————————————————*/
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("testUser1");
        vm.prank(voter2);
        QuickJoin(quickJoinProxy).quickJoinNoUser("v2");

        // Give voter1 the EXECUTIVE role hat for creating proposals
        // (voter1 already has DEFAULT hat from QuickJoin, but needs EXECUTIVE for creating)
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1); // EXECUTIVE role hat
        vm.prank(executorProxy);
        IHats(SEPOLIA_HATS).mintHat(executiveRoleHat, voter1);

        // voter2 already has DEFAULT hat from QuickJoin, which is sufficient for voting

        /* create proposal */
        uint8 optNumber = 2;

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](0);
        batches[1] = new IExecutor.Call[](0);

        vm.prank(voter1);
        uint256[] memory hatIds = new uint256[](0);
        HybridVoting(hybridProxy).createProposal(bytes("ipfs://test"), bytes32(0), 60, optNumber, batches, hatIds);

        /* vote YES */
        uint8[] memory idxList = new uint8[](1);
        idxList[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;

        vm.prank(voter1);
        HybridVoting(hybridProxy).vote(0, idxList, w);

        /* fast‑forward and finalise */
        vm.warp(block.timestamp + 61 minutes);
        (uint256 winner, bool valid) = HybridVoting(hybridProxy).announceWinner(0);

        assertTrue(valid, "quorum not reached");
        assertEq(winner, 0, "YES should win");
    }

    function testFullOrgDeploymentRegistersContracts() public {
        (address hybrid, address exec, address qj, address token, address tm, address hub, address pm) =
            _deployFullOrg();

        (address executorAddr, uint32 count, bool boot, bool exists) = orgRegistry.orgOf(ORG_ID);
        assertEq(executorAddr, exec); // Should be the Executor contract address, not orgOwner
        assertEq(count, 10); // Updated to 10: now includes PaymentManager, EligibilityModule, ToggleModule, HybridVoting, and DirectDemocracyVoting
        assertFalse(boot);
        assertTrue(exists);

        bytes32 typeId = keccak256("QuickJoin");
        bytes32 contractId = keccak256(abi.encodePacked(ORG_ID, typeId));
        (address proxy, address beacon, bool autoUp, address owner) = orgRegistry.contractOf(contractId);
        assertEq(proxy, qj);
        assertTrue(autoUp);
        assertEq(owner, exec);

        address impl = IBeacon(beacon).implementation();
        assertEq(impl, poaManager.getCurrentImplementationById(ModuleTypes.QUICK_JOIN_ID));

        // Verify PaymentManager is deployed and registered
        bytes32 pmTypeId = keccak256("PaymentManager");
        bytes32 pmContractId = keccak256(abi.encodePacked(ORG_ID, pmTypeId));
        (address pmProxy, address pmBeacon, bool pmAutoUp, address pmOwner) = orgRegistry.contractOf(pmContractId);
        assertEq(pmProxy, pm, "PaymentManager proxy should match");
        assertTrue(pmAutoUp, "PaymentManager should have auto-upgrade enabled");
        assertEq(pmOwner, exec, "PaymentManager owner should be executor");

        // Verify PaymentManager is properly initialized
        PaymentManager paymentManager = PaymentManager(payable(pm));
        assertEq(paymentManager.revenueShareToken(), token, "Revenue share token should be the participation token");
        assertEq(paymentManager.owner(), exec, "PaymentManager owner should be executor");
    }

    function testDeployFullOrgMismatchExecutorReverts() public {
        _deployFullOrg();
        address other = address(99);
        vm.startPrank(other);
        vm.expectRevert(abi.encodeWithSignature("OrgExistsMismatch()"));
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Hybrid DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        deployer.deployFullOrg(params);
        vm.stopPrank();
    }

    function testHatsTreeDeployment() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();
        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Hybrid DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        // Verify Hats tree registration
        uint256 topHatId = orgRegistry.getTopHat(ORG_ID);
        assertTrue(topHatId != 0, "Top hat should be registered");

        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        assertTrue(defaultRoleHat != 0, "Default role hat should be registered");
        assertTrue(executiveRoleHat != 0, "Executive role hat should be registered");

        // Test creating a new role as executor
        vm.stopPrank();
        vm.startPrank(exec); // Switch to executor

        // Create a new role hat
        uint256 newRoleHatId = IHats(SEPOLIA_HATS)
            .createHat(
                topHatId, // admin = parent Top Hat
                "NEW_ROLE", // details
                type(uint32).max, // unlimited supply
                orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID), // eligibility module
                orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID), // toggle module
                true, // mutable
                "NEW_ROLE" // data blob
            );

        // Configure the new role hat for the executor
        EligibilityModule(orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID))
            .setWearerEligibility(exec, newRoleHatId, true, true);
        ToggleModule(orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID)).setHatStatus(newRoleHatId, true);

        // Mint the new role hat to the executor
        IHats(SEPOLIA_HATS).mintHat(newRoleHatId, exec);

        // Verify the new role hat was created and minted
        assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(exec, newRoleHatId), "Executor should wear the new role hat");

        vm.stopPrank();
    }

    function testEligibilityModuleAdminHatSystem() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();
        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Hybrid DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address directly
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Verify executor is the super admin
        assertEq(EligibilityModule(eligibilityModuleAddr).superAdmin(), exec, "Executor should be the super admin");

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);

        // In the new system, admin permissions are handled natively by the Hats tree structure
        // The eligibility admin hat (created by deployer) is the admin of all role hats

        // Test admin relationships via Hats contract
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(exec, defaultRoleHat), "Executor should be admin of default role hat"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(exec, executiveRoleHat), "Executor should be admin of executive role hat"
        );

        // Test that someone wearing the executive role hat can change eligibility
        // First, mint the executive role hat to voter1
        _mintAdminHat(exec, eligibilityModuleAddr, executiveRoleHat, voter1);

        // Verify voter1 is wearing the executive role hat
        assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(voter1, executiveRoleHat), "voter1 should wear executive role hat");

        // Verify admin hierarchy: voter1 wearing executive hat should be admin of default hat
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(voter1, defaultRoleHat),
            "voter1 wearing executive hat should be admin of default hat"
        );

        // Now voter1 should be able to change eligibility for voter2's default role hat
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // Verify the eligibility was changed for voter2
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter2, defaultRoleHat);
        assertFalse(
            IHats(SEPOLIA_HATS).isEligible(voter2, defaultRoleHat), "voter2's default role hat should be ineligible"
        );
        assertFalse(
            IHats(SEPOLIA_HATS).isInGoodStanding(voter2, defaultRoleHat),
            "voter2's default role hat should have bad standing"
        );

        // voter1's eligibility should be unaffected since it's per-wearer (should still have default eligibility)
        // Check eligibility via Hats contract for voter1 and defaultRoleHat
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(voter1, defaultRoleHat),
            "voter1's default role hat should still be default (eligible)"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(voter1, defaultRoleHat),
            "voter1's default role hat should still be default (good standing)"
        );

        // Change voter2 back to eligible
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, true, true);

        // Verify the eligibility was changed back for voter2
        // Check eligibility via Hats contract for voter2 and defaultRoleHat
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(voter2, defaultRoleHat), "voter2's default role hat should be eligible"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(voter2, defaultRoleHat),
            "voter2's default role hat should have good standing"
        );

        // Test that someone without the executive role hat cannot change eligibility
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // In the new system, admin permissions are handled natively by the Hats tree structure
        // The EligibilityAdminHat is admin of all role hats created under it

        // Test full flow: Executive makes someone eligible and they claim the hat
        // First, make voter2 ineligible for the default role hat
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // Verify voter2 cannot mint the default role hat when ineligible
        vm.prank(exec);
        vm.expectRevert();
        IHats(SEPOLIA_HATS).mintHat(defaultRoleHat, voter2);

        // Executive (voter1) makes voter2 eligible for the default role hat
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, true, true);

        // Now exec should be able to mint the default role hat for voter2
        vm.prank(exec);
        bool success = IHats(SEPOLIA_HATS).mintHat(defaultRoleHat, voter2);
        assertTrue(success, "Should successfully mint hat when eligible");

        // Verify voter2 is now wearing the default role hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(voter2, defaultRoleHat), "voter2 should be wearing the default role hat"
        );

        // Verify voter2 is eligible and in good standing
        (bool eligible2, bool standing2) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter2, defaultRoleHat);
        assertTrue(eligible2, "voter2 should be eligible for default role hat");
        assertTrue(standing2, "voter2 should have good standing for default role hat");

        // Test revoking eligibility while wearing the hat
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // Verify voter2 is now ineligible (and thus no longer wearing the hat)
        // The Hats protocol integrates eligibility checking into isWearerOfHat
        assertFalse(
            IHats(SEPOLIA_HATS).isWearerOfHat(voter2, defaultRoleHat),
            "voter2 should no longer be wearing the hat when ineligible"
        );

        // Verify voter2 is now ineligible
        (bool eligible3, bool standing3) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter2, defaultRoleHat);
        assertFalse(eligible3, "voter2 should now be ineligible for default role hat");
        assertFalse(standing3, "voter2 should now have bad standing for default role hat");
    }

    // The old testMultipleAdminHatsWithRoleManagement test has been removed
    // since the new system relies on native Hats admin hierarchy instead of custom ACL

    function testExecutiveGivesHatsToTwoPeopleThenTurnsOffOne() public {
        TestOrgSetup memory setup = _createSimpleTestOrg("Executive Hat Test DAO");
        address person1 = address(0x100);
        address person2 = address(0x101);

        // First, mint the executive role hat to voter1 so they can act as an executive
        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, voter1);
        _assertWearingHat(voter1, setup.executiveRoleHat, true, "voter1 executive hat");

        // Executive (voter1) makes both people eligible for the DEFAULT role hat
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person1, setup.defaultRoleHat, true, true);
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person2, setup.defaultRoleHat, true, true);

        // Verify both people are eligible for the DEFAULT role hat
        _assertEligibilityStatus(setup.eligibilityModule, person1, setup.defaultRoleHat, true, true, "person1 initial");
        _assertEligibilityStatus(setup.eligibilityModule, person2, setup.defaultRoleHat, true, true, "person2 initial");

        // The executor mints the DEFAULT role hat to both people
        vm.prank(setup.exec);
        bool success1 = IHats(SEPOLIA_HATS).mintHat(setup.defaultRoleHat, person1);
        assertTrue(success1, "Should successfully mint DEFAULT hat to person1");

        vm.prank(setup.exec);
        bool success2 = IHats(SEPOLIA_HATS).mintHat(setup.defaultRoleHat, person2);
        assertTrue(success2, "Should successfully mint DEFAULT hat to person2");

        // Verify both people are wearing the DEFAULT role hat
        _assertWearingHat(person1, setup.defaultRoleHat, true, "person1 after minting");
        _assertWearingHat(person2, setup.defaultRoleHat, true, "person2 after minting");

        // Executive (voter1) turns off person1's hat but leaves person2's hat on
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person1, setup.defaultRoleHat, false, false);

        // Verify person1 is no longer eligible and not wearing the hat
        _assertEligibilityStatus(
            setup.eligibilityModule, person1, setup.defaultRoleHat, false, false, "person1 after revocation"
        );
        _assertWearingHat(person1, setup.defaultRoleHat, false, "person1 after revocation");

        // Verify person2 is still eligible and wearing the hat
        _assertEligibilityStatus(
            setup.eligibilityModule, person2, setup.defaultRoleHat, true, true, "person2 still eligible"
        );
        _assertWearingHat(person2, setup.defaultRoleHat, true, "person2 still wearing");

        // Executive can turn person1's hat back on
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person1, setup.defaultRoleHat, true, true);

        // Verify person1 is eligible again
        _assertEligibilityStatus(setup.eligibilityModule, person1, setup.defaultRoleHat, true, true, "person1 restored");
        _assertWearingHat(person1, setup.defaultRoleHat, true, "person1 restored");

        // Executive can also turn off person2's hat
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person2, setup.defaultRoleHat, false, false);

        // Verify person2 is no longer eligible and not wearing the hat
        _assertEligibilityStatus(
            setup.eligibilityModule, person2, setup.defaultRoleHat, false, false, "person2 revoked"
        );
        _assertWearingHat(person2, setup.defaultRoleHat, false, "person2 revoked");

        // Test that only the executive can control these hats - person1 cannot control person2's hat
        vm.prank(person1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person2, setup.defaultRoleHat, true, true);

        // Test that the super admin (executor) can still control all hats
        vm.prank(setup.exec);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person1, setup.defaultRoleHat, false, false);
        vm.prank(setup.exec);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(person2, setup.defaultRoleHat, true, true);

        // Verify the super admin changes took effect
        _assertEligibilityStatus(
            setup.eligibilityModule, person1, setup.defaultRoleHat, false, false, "person1 super admin control"
        );
        _assertEligibilityStatus(
            setup.eligibilityModule, person2, setup.defaultRoleHat, true, true, "person2 super admin control"
        );

        // Final check: person1 should not be wearing the hat, person2 should be wearing it
        _assertWearingHat(person1, setup.defaultRoleHat, false, "person1 final");
        _assertWearingHat(person2, setup.defaultRoleHat, true, "person2 final");
    }

    function testEligibilityModuleEvents() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Events Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);

        // Test that events are emitted when setting wearer eligibility
        vm.expectEmit(true, true, false, true);
        emit WearerEligibilityUpdated(voter1, defaultRoleHat, true, true, exec);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter1, defaultRoleHat, true, true);

        // Test that events are emitted when setting default eligibility
        vm.expectEmit(true, false, false, true);
        emit DefaultEligibilityUpdated(defaultRoleHat, false, false, exec);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(defaultRoleHat, false, false);

        // The old ACL events are no longer supported since admin permissions
        // are now handled natively by the Hats tree structure

        // Test that events are emitted when transferring super admin
        vm.expectEmit(true, true, false, false);
        emit SuperAdminTransferred(exec, voter1);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).transferSuperAdmin(voter1);
    }

    function testVouchingSystemBasic() public {
        TestOrgSetup memory setup = _createTestOrg("Vouch Test DAO");
        address candidate = address(0x200);

        // Set up users for vouching (need join times set)
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate);

        // Configure vouching for DEFAULT hat: require 2 vouches from MEMBER hat wearers
        _configureVouching(
            setup.eligibilityModule, setup.exec, setup.defaultRoleHat, 2, setup.memberRoleHat, false, true
        );

        // Verify vouching configuration
        EligibilityModule.VouchConfig memory config = _getVouchConfig(setup.eligibilityModule, setup.defaultRoleHat);
        assertEq(config.quorum, 2, "Quorum should be 2");
        assertEq(config.membershipHatId, setup.memberRoleHat, "Membership hat should be MEMBER");
        assertTrue(
            EligibilityModule(setup.eligibilityModule).isVouchingEnabled(setup.defaultRoleHat),
            "Vouching should be enabled"
        );
        assertFalse(
            EligibilityModule(setup.eligibilityModule).combinesWithHierarchy(setup.defaultRoleHat),
            "Should not combine with hierarchy"
        );

        // Mint MEMBER hats to vouchers
        _mintHat(setup.exec, setup.memberRoleHat, voter1);
        _mintHat(setup.exec, setup.memberRoleHat, voter2);

        // Initially, candidate should not be eligible
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, false, false, "Initial state"
        );

        // First vouch from voter1
        uint32 count1 = _vouchFor(voter1, setup.eligibilityModule, candidate, setup.defaultRoleHat);
        assertEq(count1, 1, "Vouch count should be 1");
        assertTrue(
            EligibilityModule(setup.eligibilityModule).hasVouched(setup.defaultRoleHat, candidate, voter1),
            "voter1 should have vouched"
        );
        _assertVouchStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, 1, false, "After first vouch");
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, false, false, "After first vouch"
        );

        // Second vouch from voter2
        uint32 count2 = _vouchFor(voter2, setup.eligibilityModule, candidate, setup.defaultRoleHat);
        assertEq(count2, 2, "Vouch count should be 2");
        assertTrue(
            EligibilityModule(setup.eligibilityModule).hasVouched(setup.defaultRoleHat, candidate, voter2),
            "voter2 should have vouched"
        );
        _assertVouchStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, 2, true, "After second vouch");
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, true, true, "After reaching quorum"
        );

        // Test that candidate must explicitly claim the hat after reaching quorum
        _assertWearingHat(candidate, setup.defaultRoleHat, false, "Candidate before claiming");

        // Candidate claims the hat
        vm.prank(candidate);
        EligibilityModule(setup.eligibilityModule).claimVouchedHat(setup.defaultRoleHat);

        _assertWearingHat(candidate, setup.defaultRoleHat, true, "Candidate after claiming");
    }

    function testVouchingSystemHybridMode() public {
        TestOrgSetup memory setup = _createTestOrg("Hybrid Vouch Test DAO");
        address candidate1 = address(0x201);
        address candidate2 = address(0x202);
        address voucher2 = address(0x203);

        // Set up users for vouching (need join times set)
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voucher2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate2);

        // Configure vouching for DEFAULT hat: require 2 vouches from MEMBER hat wearers, BUT also allow hierarchy
        _configureVouching(
            setup.eligibilityModule, setup.exec, setup.defaultRoleHat, 2, setup.memberRoleHat, true, true
        );

        // Mint EXECUTIVE hat to voter1 so they can use admin powers
        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, voter1);
        // Mint MEMBER hats for vouching
        _mintHat(setup.exec, setup.memberRoleHat, voter2);
        _mintHat(setup.exec, setup.memberRoleHat, voucher2);

        // Test 1: Admin can directly make someone eligible (hierarchy path)
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(candidate1, setup.defaultRoleHat, true, true);
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate1, setup.defaultRoleHat, true, true, "Candidate1 via hierarchy"
        );

        // Test 2: Someone else can become eligible via vouching path
        _vouchFor(voter2, setup.eligibilityModule, candidate2, setup.defaultRoleHat);
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate2, setup.defaultRoleHat, false, false, "Candidate2 with 1 vouch"
        );

        // Second vouch
        _vouchFor(voucher2, setup.eligibilityModule, candidate2, setup.defaultRoleHat);
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate2, setup.defaultRoleHat, true, true, "Candidate2 via vouching"
        );

        // Test 3: Admin can revoke hierarchy eligibility, but vouching still works
        vm.prank(voter1);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(candidate2, setup.defaultRoleHat, false, false);
        _assertEligibilityStatus(
            setup.eligibilityModule,
            candidate2,
            setup.defaultRoleHat,
            true,
            true,
            "Candidate2 after hierarchy revocation"
        );

        // Test 4: If vouching is revoked, hierarchy takes over
        _revokeVouch(voter2, setup.eligibilityModule, candidate2, setup.defaultRoleHat);
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate2, setup.defaultRoleHat, false, false, "Candidate2 after vouch revocation"
        );
    }

    function testVouchingErrors() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MEMBER";
        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://member-role-image";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Vouch Error Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        address candidate = address(0x300);

        // Set up users for vouching (need join times set)
        _setupUserForVouching(eligibilityModuleAddr, exec, voter1);
        _setupUserForVouching(eligibilityModuleAddr, exec, voter2);
        _setupUserForVouching(eligibilityModuleAddr, exec, candidate);

        // Test 1: Vouching without configuration should fail
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.VouchingNotEnabled.selector));
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);

        // Configure vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(defaultRoleHat, 2, memberRoleHat, false);

        // Set default eligibility to false to test vouching behavior properly
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(defaultRoleHat, false, false);

        // Test 2: Vouching without proper hat should fail
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedToVouch.selector));
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);

        // Give voter1 the member hat
        vm.prank(exec);
        IHats(SEPOLIA_HATS).mintHat(memberRoleHat, voter1);

        // Test 3: Vouching should work now
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);

        // Test 4: Double vouching should fail
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.AlreadyVouched.selector));
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);

        // Test 5: Revoking non-existent vouch should fail
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.HasNotVouched.selector));
        EligibilityModule(eligibilityModuleAddr).revokeVouch(candidate, defaultRoleHat);

        // Test 6: Only super admin can configure vouching
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotSuperAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).configureVouching(defaultRoleHat, 3, memberRoleHat, true);
    }

    function testVouchingRevocation() public {
        TestOrgSetup memory setup = _createTestOrg("Vouch Revocation Test DAO");
        address candidate = address(0x400);

        // Set up users for vouching (need join times set)
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate);

        // Configure vouching for DEFAULT hat
        _configureVouching(
            setup.eligibilityModule, setup.exec, setup.defaultRoleHat, 2, setup.memberRoleHat, false, true
        );

        // Mint MEMBER hats to vouchers
        _mintHat(setup.exec, setup.memberRoleHat, voter1);
        _mintHat(setup.exec, setup.memberRoleHat, voter2);

        // Get both vouches
        _vouchFor(voter1, setup.eligibilityModule, candidate, setup.defaultRoleHat);
        _vouchFor(voter2, setup.eligibilityModule, candidate, setup.defaultRoleHat);

        // Verify candidate is approved
        _assertVouchStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, 2, true, "After 2 vouches");
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, true, true, "After 2 vouches"
        );

        // Revoke one vouch
        _revokeVouch(voter1, setup.eligibilityModule, candidate, setup.defaultRoleHat);

        // Verify counts and approval status
        _assertVouchStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, 1, false, "After revocation");
        assertFalse(
            EligibilityModule(setup.eligibilityModule).hasVouched(setup.defaultRoleHat, candidate, voter1),
            "voter1 should not have vouched"
        );
        assertTrue(
            EligibilityModule(setup.eligibilityModule).hasVouched(setup.defaultRoleHat, candidate, voter2),
            "voter2 should still have vouched"
        );
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, false, false, "After revocation"
        );

        // Add the vouch back
        _vouchFor(voter1, setup.eligibilityModule, candidate, setup.defaultRoleHat);

        // Verify candidate is eligible again
        _assertVouchStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, 2, true, "After re-vouching");
        _assertEligibilityStatus(
            setup.eligibilityModule, candidate, setup.defaultRoleHat, true, true, "After re-vouching"
        );
    }

    function testVouchingEvents() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MEMBER";
        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://member-role-image";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Vouch Events Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        address candidate = address(0x500);

        // Set up users for vouching (need join times set)
        _setupUserForVouching(eligibilityModuleAddr, exec, voter1);
        _setupUserForVouching(eligibilityModuleAddr, exec, candidate);

        // Test VouchConfigSet event
        vm.expectEmit(true, false, false, true);
        emit VouchConfigSet(defaultRoleHat, 2, memberRoleHat, true, false);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(defaultRoleHat, 2, memberRoleHat, false);

        // Set default eligibility to false to test vouching behavior properly
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(defaultRoleHat, false, false);

        // Mint MEMBER hat to voter1
        vm.prank(exec);
        IHats(SEPOLIA_HATS).mintHat(memberRoleHat, voter1);

        // Test Vouched event
        vm.expectEmit(true, true, true, true);
        emit Vouched(voter1, candidate, defaultRoleHat, 1);

        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);

        // Test VouchRevoked event
        vm.expectEmit(true, true, true, true);
        emit VouchRevoked(voter1, candidate, defaultRoleHat, 0);

        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).revokeVouch(candidate, defaultRoleHat);
    }

    function testVouchingWithClaim() public {
        TestOrgSetup memory setup = _createTestOrg("Claim Test DAO");
        address candidate = address(0x300);

        // Set up users for vouching
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, voter2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate);

        // Configure vouching for DEFAULT hat: require 2 vouches
        _configureVouching(
            setup.eligibilityModule, setup.exec, setup.defaultRoleHat, 2, setup.memberRoleHat, false, true
        );

        // Mint MEMBER hats to vouchers
        _mintHat(setup.exec, setup.memberRoleHat, voter1);
        _mintHat(setup.exec, setup.memberRoleHat, voter2);

        // Vouch twice to reach quorum
        _vouchFor(voter1, setup.eligibilityModule, candidate, setup.defaultRoleHat);
        _vouchFor(voter2, setup.eligibilityModule, candidate, setup.defaultRoleHat);

        // Verify eligible but not wearing hat yet
        _assertEligibilityStatus(setup.eligibilityModule, candidate, setup.defaultRoleHat, true, true, "After vouching");
        _assertWearingHat(candidate, setup.defaultRoleHat, false, "Before claiming");

        // Test HatClaimed event
        vm.expectEmit(true, true, false, false);
        emit HatClaimed(candidate, setup.defaultRoleHat);

        // Claim the hat
        vm.prank(candidate);
        EligibilityModule(setup.eligibilityModule).claimVouchedHat(setup.defaultRoleHat);

        // Verify now wearing the hat
        _assertWearingHat(candidate, setup.defaultRoleHat, true, "After claiming");
    }

    function testClaimWithoutVouch() public {
        TestOrgSetup memory setup = _createTestOrg("Claim Error Test DAO");
        address candidate = address(0x301);

        // Set up user
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidate);

        // Configure vouching for DEFAULT hat: require 2 vouches
        _configureVouching(
            setup.eligibilityModule, setup.exec, setup.defaultRoleHat, 2, setup.memberRoleHat, false, true
        );

        // Try to claim without being vouched - should fail
        vm.prank(candidate);
        vm.expectRevert("Not eligible to claim hat");
        EligibilityModule(setup.eligibilityModule).claimVouchedHat(setup.defaultRoleHat);
    }

    function testRoleConfigValidation() public {
        vm.startPrank(orgOwner);

        // Test 1: Empty roles array should revert
        RoleConfigStructs.RoleConfig[] memory emptyRoles = new RoleConfigStructs.RoleConfig[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Invalid Org",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: new IHybridVotingInit.ClassConfig[](0),
            ddInitialTargets: new address[](0),
            roles: emptyRoles,
            roleAssignments: _buildDefaultRoleAssignments(),
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        vm.expectRevert(OrgDeployer.InvalidRoleConfiguration.selector);
        deployer.deployFullOrg(params);

        // Test 2: Invalid voucher role index
        RoleConfigStructs.RoleConfig[] memory invalidVoucherRoles = new RoleConfigStructs.RoleConfig[](2);
        invalidVoucherRoles[0] = RoleConfigStructs.RoleConfig({
            name: "MEMBER",
            image: "ipfs://member",
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: true,
                quorum: 1,
                voucherRoleIndex: 5, // Invalid: out of bounds
                combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: false, mintToExecutor: true, additionalWearers: new address[](0)
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });
        invalidVoucherRoles[1] = RoleConfigStructs.RoleConfig({
            name: "ADMIN",
            image: "ipfs://admin",
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: true, mintToExecutor: false, additionalWearers: new address[](0)
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });

        params.roles = invalidVoucherRoles;
        vm.expectRevert(OrgDeployer.InvalidRoleConfiguration.selector);
        deployer.deployFullOrg(params);

        // Test 3: Zero quorum with vouching enabled
        RoleConfigStructs.RoleConfig[] memory zeroQuorumRoles = new RoleConfigStructs.RoleConfig[](1);
        zeroQuorumRoles[0] = RoleConfigStructs.RoleConfig({
            name: "MEMBER",
            image: "ipfs://member",
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: true,
                quorum: 0, // Invalid: must be > 0 if enabled
                voucherRoleIndex: 0,
                combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: true, mintToExecutor: false, additionalWearers: new address[](0)
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });

        params.roles = zeroQuorumRoles;
        vm.expectRevert(OrgDeployer.InvalidRoleConfiguration.selector);
        deployer.deployFullOrg(params);

        // Test 4: Self-referential hierarchy
        RoleConfigStructs.RoleConfig[] memory selfRefRoles = new RoleConfigStructs.RoleConfig[](1);
        selfRefRoles[0] = RoleConfigStructs.RoleConfig({
            name: "MEMBER",
            image: "ipfs://member",
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: 0}), // Self-reference
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: true, mintToExecutor: false, additionalWearers: new address[](0)
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });

        params.roles = selfRefRoles;
        vm.expectRevert(OrgDeployer.InvalidRoleConfiguration.selector);
        deployer.deployFullOrg(params);

        vm.stopPrank();
    }

    //     function skip_testComplexHierarchy() public {
    //         vm.startPrank(orgOwner);
    //
    //         // Test non-linear hierarchy: ELIGIBILITY_ADMIN -> ADMIN -> [MANAGER, COORDINATOR] -> MEMBER
    //         // This creates a tree structure rather than linear chain
    //         RoleConfigStructs.RoleConfig[] memory complexRoles = new RoleConfigStructs.RoleConfig[](4);
    //
    //         // MEMBER (index 0) - child of MANAGER (index 1)
    //         complexRoles[0] = RoleConfigStructs.RoleConfig({
    //             name: "MEMBER",
    //             image: "ipfs://member",
    //             canVote: true,
    //             vouching: RoleConfigStructs.RoleVouchingConfig({enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false}),
    //             defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
    //             hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: 1}), // Parent is MANAGER
    //             distribution: RoleConfigStructs.RoleDistributionConfig({mintToDeployer: false, mintToExecutor: true, additionalWearers: new address[](0)})
    //         });
    //
    //         // MANAGER (index 1) - child of ADMIN (index 3)
    //         complexRoles[1] = RoleConfigStructs.RoleConfig({
    //             name: "MANAGER",
    //             image: "ipfs://manager",
    //             canVote: true,
    //             vouching: RoleConfigStructs.RoleVouchingConfig({enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false}),
    //             defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
    //             hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: 3}), // Parent is ADMIN
    //             distribution: RoleConfigStructs.RoleDistributionConfig({mintToDeployer: false, mintToExecutor: true, additionalWearers: new address[](0)})
    //         });
    //
    //         // COORDINATOR (index 2) - also child of ADMIN (index 3), sibling to MANAGER
    //         complexRoles[2] = RoleConfigStructs.RoleConfig({
    //             name: "COORDINATOR",
    //             image: "ipfs://coordinator",
    //             canVote: true,
    //             vouching: RoleConfigStructs.RoleVouchingConfig({enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false}),
    //             defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
    //             hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: 3}), // Parent is ADMIN
    //             distribution: RoleConfigStructs.RoleDistributionConfig({mintToDeployer: false, mintToExecutor: true, additionalWearers: new address[](0)})
    //         });
    //
    //         // ADMIN (index 3) - top level
    //         complexRoles[3] = RoleConfigStructs.RoleConfig({
    //             name: "ADMIN",
    //             image: "ipfs://admin",
    //             canVote: true,
    //             vouching: RoleConfigStructs.RoleVouchingConfig({enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false}),
    //             defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
    //             hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}), // Top level
    //             distribution: RoleConfigStructs.RoleDistributionConfig({mintToDeployer: true, mintToExecutor: false, additionalWearers: new address[](0)})
    //         });
    //
    //         IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
    //         address[] memory ddTargets = new address[](0);
    //
    //         OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
    //             orgId: ORG_ID,
    //             orgName: "Complex Hierarchy DAO",
    //             registryAddr: accountRegProxy,
    //             deployerAddress: orgOwner,
    //             deployerUsername: "",
    //             autoUpgrade: true,
    //             hybridQuorumPct: 50,
    //             ddQuorumPct: 50,
    //             hybridClasses: classes,
    //             ddInitialTargets: ddTargets,
    //             roles: complexRoles,
    //             roleAssignments: _buildDefaultRoleAssignments()
    //         });
    //
    //         OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
    //
    //         // Verify all hats were created
    //         uint256[] memory roleHats = orgRegistry.getRoleHats(ORG_ID);
    //         assertEq(roleHats.length, 4, "Should have 4 role hats");
    //
    //         // Verify hierarchy: check that MEMBER's admin is MANAGER, etc.
    //         uint256 memberHat = roleHats[0];
    //         uint256 managerHat = roleHats[1];
    //         uint256 coordinatorHat = roleHats[2];
    //         uint256 adminHat = roleHats[3];
    //
    //         // Admin should be wearer of admin hat
    //         assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(orgOwner, adminHat), "Deployer should have ADMIN hat");
    //
    //         vm.stopPrank();
    //     }

    //     function skip_testMultipleInitialWearers() public {
    //         vm.startPrank(orgOwner);
    //
    //         address founder1 = address(0x1111);
    //         address founder2 = address(0x2222);
    //         address[] memory additionalWearers = new address[](2);
    //         additionalWearers[0] = founder1;
    //         additionalWearers[1] = founder2;
    //
    //         RoleConfigStructs.RoleConfig[] memory multiWearerRoles = new RoleConfigStructs.RoleConfig[](1);
    //         multiWearerRoles[0] = RoleConfigStructs.RoleConfig({
    //             name: "FOUNDER",
    //             image: "ipfs://founder",
    //             canVote: true,
    //             vouching: RoleConfigStructs.RoleVouchingConfig({enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false}),
    //             defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
    //             hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
    //             distribution: RoleConfigStructs.RoleDistributionConfig({
    //                 mintToDeployer: true,
    //                 mintToExecutor: false,
    //                 additionalWearers: additionalWearers
    //             })
    //         });
    //
    //         IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(100, 0, false, 0);
    //         address[] memory ddTargets = new address[](0);
    //
    //         OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
    //             orgId: ORG_ID,
    //             orgName: "Multi-Founder DAO",
    //             registryAddr: accountRegProxy,
    //             deployerAddress: orgOwner,
    //             deployerUsername: "",
    //             autoUpgrade: true,
    //             hybridQuorumPct: 50,
    //             ddQuorumPct: 50,
    //             hybridClasses: classes,
    //             ddInitialTargets: ddTargets,
    //             roles: multiWearerRoles,
    //             roleAssignments: _buildDefaultRoleAssignments()
    //         });
    //
    //         OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
    //
    //         // Verify all three founders have the hat
    //         uint256[] memory roleHats = orgRegistry.getRoleHats(ORG_ID);
    //         uint256 founderHat = roleHats[0];
    //
    //         assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(orgOwner, founderHat), "Deployer should have FOUNDER hat");
    //         assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(founder1, founderHat), "Founder1 should have FOUNDER hat");
    //         assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(founder2, founderHat), "Founder2 should have FOUNDER hat");
    //
    //         vm.stopPrank();
    //     }

    function testVouchingDisabling() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MEMBER";
        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://member-role-image";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Vouch Disable Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        // Enable vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(defaultRoleHat, 2, memberRoleHat, false);

        // Set default eligibility to false initially to test vouching behavior properly
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(defaultRoleHat, false, false);

        // Verify vouching is enabled
        EligibilityModule.VouchConfig memory config =
            EligibilityModule(eligibilityModuleAddr).getVouchConfig(defaultRoleHat);
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isVouchingEnabled(defaultRoleHat), "Vouching should be enabled"
        );

        // Disable vouching by setting quorum to 0
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(defaultRoleHat, 0, memberRoleHat, false);

        // Verify vouching is disabled
        config = EligibilityModule(eligibilityModuleAddr).getVouchConfig(defaultRoleHat);
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).isVouchingEnabled(defaultRoleHat), "Vouching should be disabled"
        );
        assertEq(config.quorum, 0, "Quorum should be 0");

        // Set default eligibility to test hierarchy-only mode
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(defaultRoleHat, true, true);

        address candidate = address(0x600);

        // Should now work via hierarchy (default eligibility)
        assertTrue(IHats(SEPOLIA_HATS).isEligible(candidate, defaultRoleHat), "Should be eligible via hierarchy");
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(candidate, defaultRoleHat), "Should have good standing via hierarchy"
        );

        // Vouching should fail when disabled
        vm.prank(exec);
        IHats(SEPOLIA_HATS).mintHat(memberRoleHat, voter1);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.VouchingNotEnabled.selector));
        EligibilityModule(eligibilityModuleAddr).vouchFor(candidate, defaultRoleHat);
    }

    function testSuperAdminFullControl() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MEMBER";
        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://member-role-image";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "SuperAdmin Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        // Verify executor is the super admin
        assertEq(EligibilityModule(eligibilityModuleAddr).superAdmin(), exec, "Executor should be the super admin");

        // Test that super admin can control ANY hat without needing admin permissions
        address testUser = address(0x700);

        // Super admin can control DEFAULT hat (already has admin permissions)
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, true, true);

        // Super admin can control EXECUTIVE hat (even though no admin permissions set)
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, executiveRoleHat, true, true);

        // Super admin can control MEMBER hat (even though no admin permissions set)
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, memberRoleHat, true, true);

        // Verify all settings took effect - check via Hats contract
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(testUser, defaultRoleHat), "Should be eligible for DEFAULT via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(testUser, defaultRoleHat),
            "Should have good standing for DEFAULT via Hats contract"
        );

        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(testUser, executiveRoleHat),
            "Should be eligible for EXECUTIVE via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(testUser, executiveRoleHat),
            "Should have good standing for EXECUTIVE via Hats contract"
        );

        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(testUser, memberRoleHat), "Should be eligible for MEMBER via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(testUser, memberRoleHat),
            "Should have good standing for MEMBER via Hats contract"
        );

        // Test that super admin can configure vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(memberRoleHat, 3, defaultRoleHat, true);

        // Test that super admin can reset vouches
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).resetVouches(memberRoleHat);

        // Test that users can be eligible for hats when properly set up
        vm.prank(exec);
        bool mintSuccess = IHats(SEPOLIA_HATS).mintHat(defaultRoleHat, testUser);
        assertTrue(mintSuccess, "Should be able to mint hat to eligible user");

        // Verify the user is wearing the hat via Hats contract
        assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(testUser, defaultRoleHat), "User should be wearing the hat");

        // Test that eligibility is checked via Hats contract when minting
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(testUser, defaultRoleHat),
            "User should be eligible according to Hats contract"
        );

        // Test admin relationships via Hats contract
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(exec, defaultRoleHat),
            "Executor should be admin of DEFAULT hat via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(exec, executiveRoleHat),
            "Executor should be admin of EXECUTIVE hat via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isAdminOfHat(exec, memberRoleHat),
            "Executor should be admin of MEMBER hat via Hats contract"
        );

        // Test that super admin can transfer super admin
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).transferSuperAdmin(voter1);

        // Verify the transfer worked
        assertEq(EligibilityModule(eligibilityModuleAddr).superAdmin(), voter1, "Super admin should be transferred");

        // Test that the new super admin now has full control
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, false, false);

        // Check via Hats contract
        assertFalse(
            IHats(SEPOLIA_HATS).isEligible(testUser, defaultRoleHat),
            "Should not be eligible after new super admin revokes"
        );
        assertFalse(
            IHats(SEPOLIA_HATS).isInGoodStanding(testUser, defaultRoleHat),
            "Should not have good standing after new super admin revokes"
        );

        // Also verify that the user is no longer wearing the hat
        assertFalse(
            IHats(SEPOLIA_HATS).isWearerOfHat(testUser, defaultRoleHat),
            "Should not be wearing hat after eligibility revoked"
        );
    }

    function testUnrestrictedHat() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](3);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "OPEN"; // This will be our unrestricted hat
        string[] memory images = new string[](3);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://open-role-image";
        bool[] memory voting = new bool[](3);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        address[] memory ddTargets = new address[](0);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: ORG_ID,
            orgName: "Unrestricted Hat Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);
        address hybrid = result.hybridVoting;
        address exec = result.executor;
        address qj = result.quickJoin;
        address token = result.participationToken;
        address tm = result.taskManager;
        address hub = result.educationHub;

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.ELIGIBILITY_MODULE_ID);

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 openRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        // The open hat should already have default eligibility set to true, true
        // by the deployer, but let's verify and ensure it's unrestricted:

        // 1. Make sure vouching is NOT enabled (default state)
        EligibilityModule.VouchConfig memory config =
            EligibilityModule(eligibilityModuleAddr).getVouchConfig(openRoleHat);
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).isVouchingEnabled(openRoleHat),
            "Vouching should be disabled by default"
        );

        // 2. Make sure default eligibility is true (should be set by deployer)
        address randomUser1 = address(0x800);
        address randomUser2 = address(0x801);
        address randomUser3 = address(0x802);

        // Check that anyone can be eligible for the open hat via Hats contract
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(randomUser1, openRoleHat),
            "Random user 1 should be eligible for open hat via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser1, openRoleHat),
            "Random user 1 should have good standing for open hat via Hats contract"
        );

        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(randomUser2, openRoleHat),
            "Random user 2 should be eligible for open hat via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser2, openRoleHat),
            "Random user 2 should have good standing for open hat via Hats contract"
        );

        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(randomUser3, openRoleHat),
            "Random user 3 should be eligible for open hat via Hats contract"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser3, openRoleHat),
            "Random user 3 should have good standing for open hat via Hats contract"
        );

        // 3. Test that the executor can mint the open hat to anyone
        vm.prank(exec);
        bool success1 = IHats(SEPOLIA_HATS).mintHat(openRoleHat, randomUser1);
        assertTrue(success1, "Should successfully mint open hat to random user 1");

        vm.prank(exec);
        bool success2 = IHats(SEPOLIA_HATS).mintHat(openRoleHat, randomUser2);
        assertTrue(success2, "Should successfully mint open hat to random user 2");

        vm.prank(exec);
        bool success3 = IHats(SEPOLIA_HATS).mintHat(openRoleHat, randomUser3);
        assertTrue(success3, "Should successfully mint open hat to random user 3");

        // Verify all users are wearing the open hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(randomUser1, openRoleHat), "Random user 1 should be wearing open hat"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(randomUser2, openRoleHat), "Random user 2 should be wearing open hat"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(randomUser3, openRoleHat), "Random user 3 should be wearing open hat"
        );

        // 4. Test that the super admin can still control the open hat if needed
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(randomUser1, openRoleHat, false, false);

        // randomUser1 should now be ineligible
        assertFalse(
            IHats(SEPOLIA_HATS).isEligible(randomUser1, openRoleHat),
            "Random user 1 should now be ineligible after specific rule"
        );
        assertFalse(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser1, openRoleHat),
            "Random user 1 should have bad standing after specific rule"
        );

        // But randomUser2 and randomUser3 should still be eligible (using default rules)
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(randomUser2, openRoleHat),
            "Random user 2 should still be eligible via default rules"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser2, openRoleHat),
            "Random user 2 should still have good standing via default rules"
        );

        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(randomUser3, openRoleHat),
            "Random user 3 should still be eligible via default rules"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser3, openRoleHat),
            "Random user 3 should still have good standing via default rules"
        );

        // 5. Test that the super admin can make it even more open by removing the specific restriction
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(randomUser1, openRoleHat, true, true);

        // Now randomUser1 should be eligible again
        assertTrue(IHats(SEPOLIA_HATS).isEligible(randomUser1, openRoleHat), "Random user 1 should be eligible again");
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser1, openRoleHat),
            "Random user 1 should have good standing again"
        );

        // 6. Demonstrate that we can create a hat that's completely unrestricted
        // by ensuring default eligibility is true and no specific rules or vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(openRoleHat, true, true);

        // Any address should be eligible
        address veryRandomUser = address(0x999);
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(veryRandomUser, openRoleHat),
            "Any random user should be eligible for unrestricted hat"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(veryRandomUser, openRoleHat),
            "Any random user should have good standing for unrestricted hat"
        );
    }

    function testCreateHatWithEligibilityAndBatchMinting() public {
        // Create a test organization with marketing executive
        TestOrgSetup memory setup = _createTestOrg("Marketing DAO");

        // Marketing executive is voter1
        address marketingExecutive = voter1;
        address marketingMember1 = voter2;
        address marketingMember2 = address(0x5);
        address marketingMember3 = address(0x6);

        // Set up users for vouching
        _setupUserForVouching(setup.eligibilityModule, setup.exec, marketingExecutive);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, marketingMember1);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, marketingMember2);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, marketingMember3);

        // First, mint the executive role hat to the marketing executive
        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, marketingExecutive);

        // Verify the marketing executive is wearing the executive role hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingExecutive, setup.executiveRoleHat),
            "Marketing executive should wear executive role hat"
        );

        // Marketing executive creates a new marketing hat for their team
        // (Executive role wearers are admins of the default role, so they can create child hats under it)
        vm.prank(marketingExecutive);
        uint256 marketingHatId = EligibilityModule(setup.eligibilityModule)
            .createHatWithEligibility(
                EligibilityModule.CreateHatParams({
                    parentHatId: setup.defaultRoleHat,
                    details: "Marketing Team",
                    maxSupply: 10,
                    _mutable: true,
                    imageURI: "ipfs://marketing-hat-image",
                    defaultEligible: true,
                    defaultStanding: true,
                    mintToAddresses: new address[](0),
                    wearerEligibleFlags: new bool[](0),
                    wearerStandingFlags: new bool[](0)
                })
            );

        // Verify the marketing hat was created
        assertTrue(marketingHatId > 0, "Marketing hat should be created");

        // Test that the marketing hat has the correct default eligibility
        assertTrue(
            IHats(SEPOLIA_HATS).isEligible(marketingMember1, marketingHatId),
            "Marketing members should be eligible by default"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(marketingMember1, marketingHatId),
            "Marketing members should have good standing by default"
        );

        // Test single eligibility setting and minting separately
        address[] memory singleMember = new address[](1);
        singleMember[0] = marketingMember1;
        bool[] memory singleEligible = new bool[](1);
        singleEligible[0] = true;
        bool[] memory singleStanding = new bool[](1);
        singleStanding[0] = true;

        // First set eligibility
        vm.prank(marketingExecutive);
        EligibilityModule(setup.eligibilityModule)
            .batchSetWearerEligibility(marketingHatId, singleMember, singleEligible, singleStanding);

        // Then mint the hat directly (marketing executive has admin rights)
        vm.prank(marketingExecutive);
        bool success = IHats(SEPOLIA_HATS).mintHat(marketingHatId, marketingMember1);
        assertTrue(success, "Hat minting should succeed");

        // Verify member1 is wearing the marketing hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember1, marketingHatId),
            "Marketing member 1 should be wearing marketing hat"
        );

        // Test batch minting multiple members with different eligibility settings
        address[] memory multipleMembers = new address[](2);
        multipleMembers[0] = marketingMember2;
        multipleMembers[1] = marketingMember3;

        bool[] memory multipleEligible = new bool[](2);
        multipleEligible[0] = true; // Member2 is eligible
        multipleEligible[1] = false; // Member3 is not eligible (maybe new hire)

        bool[] memory multipleStanding = new bool[](2);
        multipleStanding[0] = true; // Member2 has good standing
        multipleStanding[1] = false; // Member3 has poor standing

        // First set eligibility for multiple members
        vm.prank(marketingExecutive);
        EligibilityModule(setup.eligibilityModule)
            .batchSetWearerEligibility(marketingHatId, multipleMembers, multipleEligible, multipleStanding);

        // Then mint hats individually (only for eligible members)
        vm.prank(marketingExecutive);
        bool success2 = IHats(SEPOLIA_HATS).mintHat(marketingHatId, marketingMember2);
        assertTrue(success2, "Hat minting should succeed for eligible member");

        // Try to mint for ineligible member3 - should fail
        vm.prank(marketingExecutive);
        vm.expectRevert(); // Should revert because member3 is not eligible
        IHats(SEPOLIA_HATS).mintHat(marketingHatId, marketingMember3);

        // Verify member2 is wearing the marketing hat (eligible and good standing)
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember2, marketingHatId),
            "Marketing member 2 should be wearing marketing hat"
        );

        // Verify member3 is NOT wearing the marketing hat (ineligible)
        assertFalse(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember3, marketingHatId),
            "Marketing member 3 should NOT be wearing marketing hat (ineligible)"
        );

        // Test creating another hat with initial batch minting
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = marketingMember1;
        initialMembers[1] = marketingMember2;

        bool[] memory initialEligible = new bool[](2);
        initialEligible[0] = true;
        initialEligible[1] = true;

        bool[] memory initialStanding = new bool[](2);
        initialStanding[0] = true;
        initialStanding[1] = true;

        vm.prank(marketingExecutive);
        uint256 campaignHatId = EligibilityModule(setup.eligibilityModule)
            .createHatWithEligibility(
                EligibilityModule.CreateHatParams({
                    parentHatId: setup.defaultRoleHat,
                    details: "Campaign Team",
                    maxSupply: 5,
                    _mutable: true,
                    imageURI: "ipfs://campaign-hat-image",
                    defaultEligible: false,
                    defaultStanding: true,
                    mintToAddresses: initialMembers,
                    wearerEligibleFlags: initialEligible,
                    wearerStandingFlags: initialStanding
                })
            );

        // Verify the campaign hat was created
        assertTrue(campaignHatId > 0, "Campaign hat should be created");

        // Verify both initial members are wearing the campaign hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember1, campaignHatId),
            "Marketing member 1 should be wearing campaign hat"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember2, campaignHatId),
            "Marketing member 2 should be wearing campaign hat"
        );

        // Verify member3 is NOT eligible for the campaign hat (default eligibility is false)
        (bool eligible3, bool standing3) =
            EligibilityModule(setup.eligibilityModule).getWearerStatus(marketingMember3, campaignHatId);
        assertFalse(eligible3, "Member 3 should not be eligible for campaign hat by default");
        assertTrue(standing3, "Member 3 should have good standing by default");

        // Test that only the marketing executive can create hats under their role
        vm.prank(marketingMember1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(setup.eligibilityModule)
            .createHatWithEligibility(
                EligibilityModule.CreateHatParams({
                    parentHatId: setup.defaultRoleHat,
                    details: "Unauthorized Hat",
                    maxSupply: 1,
                    _mutable: true,
                    imageURI: "",
                    defaultEligible: true,
                    defaultStanding: true,
                    mintToAddresses: new address[](0),
                    wearerEligibleFlags: new bool[](0),
                    wearerStandingFlags: new bool[](0)
                })
            );

        // Test that marketing executive can manage eligibility of their created hats
        vm.prank(marketingExecutive);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(marketingMember3, campaignHatId, true, true);

        // Verify member3 is now eligible for the campaign hat
        (bool eligible3Updated, bool standing3Updated) =
            EligibilityModule(setup.eligibilityModule).getWearerStatus(marketingMember3, campaignHatId);
        assertTrue(eligible3Updated, "Member 3 should now be eligible for campaign hat");
        assertTrue(standing3Updated, "Member 3 should have good standing for campaign hat");

        // Now marketing executive can set eligibility and mint the campaign hat to member3
        address[] memory member3Array = new address[](1);
        member3Array[0] = marketingMember3;
        bool[] memory member3Eligible = new bool[](1);
        member3Eligible[0] = true;
        bool[] memory member3Standing = new bool[](1);
        member3Standing[0] = true;

        // Set eligibility first
        vm.prank(marketingExecutive);
        EligibilityModule(setup.eligibilityModule)
            .batchSetWearerEligibility(campaignHatId, member3Array, member3Eligible, member3Standing);

        // Then mint the hat
        vm.prank(marketingExecutive);
        bool success3 = IHats(SEPOLIA_HATS).mintHat(campaignHatId, marketingMember3);
        assertTrue(success3, "Hat minting should succeed for member3");

        // Verify member3 is now wearing the campaign hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(marketingMember3, campaignHatId),
            "Marketing member 3 should now be wearing campaign hat"
        );
    }

    // Test Option 1: Single transaction with initial minting
    function testOption1SingleTransactionCreateAndMint() public {
        TestOrgSetup memory setup = _createTestOrg("Option1 DAO");
        address executive = voter1;
        address member1 = voter2;
        address member2 = address(0x7);

        // Setup executive
        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        // Option 1: Create hat and mint to members in ONE transaction
        address[] memory initialMembers = new address[](2);
        initialMembers[0] = member1;
        initialMembers[1] = member2;

        bool[] memory initialEligible = new bool[](2);
        initialEligible[0] = true;
        initialEligible[1] = true;

        bool[] memory initialStanding = new bool[](2);
        initialStanding[0] = true;
        initialStanding[1] = true;

        vm.prank(executive);
        uint256 teamHatId = EligibilityModule(setup.eligibilityModule)
            .createHatWithEligibility(
                EligibilityModule.CreateHatParams({
                    parentHatId: setup.defaultRoleHat,
                    details: "Team Hat",
                    maxSupply: 10,
                    _mutable: true,
                    imageURI: "ipfs://team-image",
                    defaultEligible: false,
                    defaultStanding: true,
                    mintToAddresses: initialMembers,
                    wearerEligibleFlags: initialEligible,
                    wearerStandingFlags: initialStanding
                })
            );

        // Verify both members are immediately wearing the hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(member1, teamHatId),
            "Member1 should be wearing hat after single transaction"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(member2, teamHatId),
            "Member2 should be wearing hat after single transaction"
        );

        // Verify default eligibility is false for others
        address randomUser = address(0x999);
        assertFalse(
            IHats(SEPOLIA_HATS).isEligible(randomUser, teamHatId), "Random user should not be eligible by default"
        );
        assertTrue(
            IHats(SEPOLIA_HATS).isInGoodStanding(randomUser, teamHatId),
            "Random user should have good standing by default"
        );
    }

    function testPaymentManagerFunctionality() public {
        // Deploy a full org
        (address hybrid, address exec, address qj, address token, address tm, address hub, address pm) =
            _deployFullOrg();

        PaymentManager paymentManager = PaymentManager(payable(pm));
        ParticipationToken participationToken = ParticipationToken(token);

        // Setup test users with participation tokens
        address holder1 = voter1;
        address holder2 = voter2;
        address holder3 = address(0x5);
        address nonHolder = address(0x999);

        // Give the executor permission to mint tokens (it should already have this as owner)
        vm.startPrank(exec);

        // Mint participation tokens to holders
        participationToken.mint(holder1, 100 ether);
        participationToken.mint(holder2, 200 ether);
        participationToken.mint(holder3, 300 ether);

        vm.stopPrank();

        // Test 1: ETH payment reception via receive function
        uint256 paymentAmount = 6 ether;
        vm.deal(address(this), paymentAmount);
        (bool success,) = payable(pm).call{value: paymentAmount}("");
        assertTrue(success, "ETH payment should succeed");
        assertEq(pm.balance, paymentAmount, "PaymentManager should have received ETH");

        // Test 2: ETH payment reception via pay function
        uint256 additionalPayment = 3 ether;
        address payer = address(0x6);
        vm.deal(payer, additionalPayment);
        vm.prank(payer);
        paymentManager.pay{value: additionalPayment}();
        assertEq(pm.balance, paymentAmount + additionalPayment, "PaymentManager should have all ETH");

        // Test 3: E2E merkle distribution with deployed org
        // Take checkpoint of current token balances
        uint256 checkpointBlock = block.number;

        // Calculate distribution amounts based on token holdings
        // Total supply: 600 ether, Distribution: 6 ether
        // holder1 (100/600 = 1/6) -> 1 ether
        // holder2 (200/600 = 2/6) -> 2 ether
        // holder3 (300/600 = 3/6) -> 3 ether
        uint256 holder1Amount = 1 ether;
        uint256 holder2Amount = 2 ether;
        uint256 holder3Amount = 3 ether;
        uint256 distributionAmount = 6 ether;

        // Build merkle tree (same logic as in PaymentManagerMerkle.t.sol)
        bytes32 leaf1 = keccak256(bytes.concat(keccak256(abi.encode(holder1, holder1Amount))));
        bytes32 leaf2 = keccak256(bytes.concat(keccak256(abi.encode(holder2, holder2Amount))));
        bytes32 leaf3 = keccak256(bytes.concat(keccak256(abi.encode(holder3, holder3Amount))));

        bytes32 node1 = _hashPair(leaf1, leaf2);
        bytes32 merkleRoot = _hashPair(node1, leaf3);

        // Advance block so checkpoint is in the past
        vm.roll(block.number + 1);

        // Create distribution (only executor can do this)
        vm.prank(exec);
        uint256 distributionId = paymentManager.createDistribution(
            address(0), // ETH
            distributionAmount,
            merkleRoot,
            checkpointBlock
        );

        assertEq(distributionId, 1, "First distribution should have ID 1");

        // Holders claim their shares
        // holder1 claims
        bytes32[] memory proof1 = new bytes32[](2);
        proof1[0] = leaf2;
        proof1[1] = leaf3;

        uint256 holder1BalBefore = holder1.balance;
        vm.prank(holder1);
        paymentManager.claimDistribution(distributionId, holder1Amount, proof1);
        assertEq(holder1.balance - holder1BalBefore, holder1Amount, "holder1 should receive 1 ETH");

        // holder2 claims
        bytes32[] memory proof2 = new bytes32[](2);
        proof2[0] = leaf1;
        proof2[1] = leaf3;

        uint256 holder2BalBefore = holder2.balance;
        vm.prank(holder2);
        paymentManager.claimDistribution(distributionId, holder2Amount, proof2);
        assertEq(holder2.balance - holder2BalBefore, holder2Amount, "holder2 should receive 2 ETH");

        // holder3 claims
        bytes32[] memory proof3 = new bytes32[](1);
        proof3[0] = node1;

        uint256 holder3BalBefore = holder3.balance;
        vm.prank(holder3);
        paymentManager.claimDistribution(distributionId, holder3Amount, proof3);
        assertEq(holder3.balance - holder3BalBefore, holder3Amount, "holder3 should receive 3 ETH");

        // Verify all claimed
        assertTrue(paymentManager.hasClaimed(distributionId, holder1), "holder1 should have claimed");
        assertTrue(paymentManager.hasClaimed(distributionId, holder2), "holder2 should have claimed");
        assertTrue(paymentManager.hasClaimed(distributionId, holder3), "holder3 should have claimed");

        // Test 4: ERC20 payment and distribution
        MockERC20 paymentToken = new MockERC20("Payment Token", "PAY");
        paymentToken.mint(address(this), 1000 ether);

        // Approve and pay with ERC20
        uint256 erc20Payment = 120 ether;
        paymentToken.approve(pm, erc20Payment);
        paymentManager.payERC20(address(paymentToken), erc20Payment);
        assertEq(paymentToken.balanceOf(pm), erc20Payment, "PaymentManager should have received ERC20");

        // ERC20 distribution (covered in test/PaymentManagerMerkle.t.sol)

        // Test 5: Opt-out functionality
        vm.prank(address(0x123)); // Use arbitrary address
        paymentManager.optOut(true);
        assertTrue(paymentManager.isOptedOut(address(0x123)), "Address should be opted out");

        // Distribution with opt-out (covered in test/PaymentManagerMerkle.t.sol::test_RevertClaimDistribution_OptedOut)

        // Test 6: Opt back in
        vm.prank(address(0x123));
        paymentManager.optOut(false);
        assertFalse(paymentManager.isOptedOut(address(0x123)), "Address should be opted back in");

        // Test 7: Only owner can distribute (covered in test/PaymentManagerMerkle.t.sol::test_RevertCreateDistribution_OnlyOwner)
        // Test 8: Incomplete holders vulnerability fix (covered in test/PaymentManagerMerkle.t.sol::test_VulnerabilityFix_MintAfterCheckpoint)

        // Test 9: Revenue share token is correctly set
        assertEq(paymentManager.revenueShareToken(), token, "Revenue share token should be the participation token");
    }

    /// @notice Comprehensive test for hierarchy-based vouching authorization
    /// @dev This test ensures admins can vouch when combineWithHierarchy is enabled
    function testVouchingWithHierarchyAuthorization() public {
        TestOrgSetup memory setup = _createTestOrg("Hierarchy Vouch Test DAO");
        address adminUser = address(0x300);
        address memberUser = address(0x301);
        address candidateUser = address(0x302);
        address unauthorizedUser = address(0x303);

        // Set up users for vouching
        _setupUserForVouching(setup.eligibilityModule, setup.exec, adminUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, memberUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidateUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, unauthorizedUser);

        // Configure vouching WITH hierarchy: admins should be able to vouch
        _configureVouching(
            setup.eligibilityModule,
            setup.exec,
            setup.defaultRoleHat, // target hat
            1, // quorum
            setup.memberRoleHat, // membership hat
            true, // combineWithHierarchy = TRUE
            true
        );

        // Verify configuration
        assertTrue(
            EligibilityModule(setup.eligibilityModule).combinesWithHierarchy(setup.defaultRoleHat),
            "Should combine with hierarchy"
        );

        // Mint EXECUTIVE hat to adminUser (executive is admin of both default and member)
        _mintHat(setup.exec, setup.executiveRoleHat, adminUser);

        // Mint MEMBER hat to memberUser
        _mintHat(setup.exec, setup.memberRoleHat, memberUser);

        // TEST 1: Admin (EXECUTIVE hat wearer) should be able to vouch
        vm.prank(adminUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Admin vouch should be counted"
        );

        // Reset vouch count for next test
        vm.prank(adminUser);
        EligibilityModule(setup.eligibilityModule).revokeVouch(candidateUser, setup.defaultRoleHat);

        // TEST 2: Member should still be able to vouch
        vm.prank(memberUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Member vouch should be counted"
        );

        // Reset again
        vm.prank(memberUser);
        EligibilityModule(setup.eligibilityModule).revokeVouch(candidateUser, setup.defaultRoleHat);

        // TEST 3: Unauthorized user (no hat) should NOT be able to vouch
        vm.prank(unauthorizedUser);
        vm.expectRevert(EligibilityModule.NotAuthorizedToVouch.selector);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
    }

    /// @notice Test that admins CANNOT vouch when combineWithHierarchy is disabled
    /// @dev This ensures the flag properly controls vouching authorization
    function testVouchingWithoutHierarchyAuthorization() public {
        TestOrgSetup memory setup = _createTestOrg("No Hierarchy Vouch Test DAO");
        address adminUser = address(0x400);
        address memberUser = address(0x401);
        address candidateUser = address(0x402);

        // Set up users
        _setupUserForVouching(setup.eligibilityModule, setup.exec, adminUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, memberUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidateUser);

        // Configure vouching WITHOUT hierarchy: only members can vouch
        _configureVouching(
            setup.eligibilityModule,
            setup.exec,
            setup.defaultRoleHat, // target hat
            1, // quorum
            setup.memberRoleHat, // membership hat
            false, // combineWithHierarchy = FALSE
            true
        );

        // Verify configuration
        assertFalse(
            EligibilityModule(setup.eligibilityModule).combinesWithHierarchy(setup.defaultRoleHat),
            "Should NOT combine with hierarchy"
        );

        // Mint EXECUTIVE hat to adminUser
        _mintHat(setup.exec, setup.executiveRoleHat, adminUser);

        // Mint MEMBER hat to memberUser
        _mintHat(setup.exec, setup.memberRoleHat, memberUser);

        // TEST 1: Admin should NOT be able to vouch (no combineWithHierarchy)
        vm.prank(adminUser);
        vm.expectRevert(EligibilityModule.NotAuthorizedToVouch.selector);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);

        // TEST 2: Member should still be able to vouch
        vm.prank(memberUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Member vouch should be counted"
        );
    }

    /// @notice Test complex hierarchy where multiple admin levels can vouch
    /// @dev Ensures hierarchy checking works at multiple levels
    /// @dev Hierarchy: MEMBER (top) -> EXECUTIVE -> DEFAULT
    function testVouchingMultiLevelHierarchy() public {
        TestOrgSetup memory setup = _createTestOrg("Multi-Level Hierarchy Test DAO");
        address executiveUser = address(0x500);
        address defaultUser = address(0x501);
        address candidateUser = address(0x502);

        // Set up users
        _setupUserForVouching(setup.eligibilityModule, setup.exec, executiveUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, defaultUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidateUser);

        // Configure vouching with hierarchy on DEFAULT hat
        // Hierarchy: DEFAULT's admin is EXECUTIVE
        _configureVouching(
            setup.eligibilityModule,
            setup.exec,
            setup.defaultRoleHat, // target hat (DEFAULT)
            1, // quorum
            setup.defaultRoleHat, // membership hat (DEFAULT role holders can vouch)
            true, // combineWithHierarchy = true (so EXECUTIVE can also vouch)
            true
        );

        // Set users as eligible for their hats before minting
        vm.startPrank(setup.exec);
        EligibilityModule(setup.eligibilityModule)
            .setWearerEligibility(executiveUser, setup.executiveRoleHat, true, true);
        EligibilityModule(setup.eligibilityModule).setWearerEligibility(defaultUser, setup.defaultRoleHat, true, true);
        vm.stopPrank();

        // Give users hats
        _mintHat(setup.exec, setup.executiveRoleHat, executiveUser); // Admin of DEFAULT
        _mintHat(setup.exec, setup.defaultRoleHat, defaultUser); // Has membership hat

        // TEST 1: EXECUTIVE (admin of DEFAULT) should be able to vouch with combineWithHierarchy
        vm.prank(executiveUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Admin vouch should work with combineWithHierarchy"
        );

        // Reset
        vm.prank(executiveUser);
        EligibilityModule(setup.eligibilityModule).revokeVouch(candidateUser, setup.defaultRoleHat);

        // TEST 2: DEFAULT role holder should be able to vouch (has membership hat)
        vm.prank(defaultUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Membership hat holder vouch should work"
        );
    }

    /// @notice Test edge case: user with both member and admin hat
    /// @dev Ensures vouching works correctly when user has multiple hats
    function testVouchingWithMultipleHats() public {
        TestOrgSetup memory setup = _createTestOrg("Multi-Hat Test DAO");
        address dualHatUser = address(0x600);
        address candidateUser = address(0x601);

        _setupUserForVouching(setup.eligibilityModule, setup.exec, dualHatUser);
        _setupUserForVouching(setup.eligibilityModule, setup.exec, candidateUser);

        // Configure vouching with hierarchy
        _configureVouching(
            setup.eligibilityModule,
            setup.exec,
            setup.defaultRoleHat,
            1,
            setup.memberRoleHat,
            true, // combineWithHierarchy
            true
        );

        // Give user both MEMBER and EXECUTIVE hats
        _mintHat(setup.exec, setup.memberRoleHat, dualHatUser);
        _mintHat(setup.exec, setup.executiveRoleHat, dualHatUser);

        // User should be able to vouch (has member hat)
        vm.prank(dualHatUser);
        EligibilityModule(setup.eligibilityModule).vouchFor(candidateUser, setup.defaultRoleHat);
        assertEq(
            EligibilityModule(setup.eligibilityModule).currentVouchCount(setup.defaultRoleHat, candidateUser),
            1,
            "Dual hat user should be able to vouch"
        );
    }

    // Helper function for merkle tree construction
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /*═══════════════════════════════════ REGISTER HAT CREATION TESTS ═══════════════════════════════════════*/

    // Test that registerHatCreation emits the correct HatCreatedWithEligibility event
    function testRegisterHatCreationEvents() public {
        TestOrgSetup memory setup = _createTestOrg("Register Hat Test DAO");
        address executive = voter1;

        // Get toggle module address from org registry (uses ORG_ID constant)
        address toggleModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID);

        // Mint executive hat to voter1
        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        // Create a new hat using createHat directly (simulating external hat creation)
        vm.prank(executive);
        uint256 newHatId = IHats(SEPOLIA_HATS)
            .createHat(
                setup.defaultRoleHat, // parent
                "Test Hat",
                100, // maxSupply
                setup.eligibilityModule,
                toggleModule,
                true, // mutable
                "ipfs://test-hat"
            );

        // Now register this hat creation - should emit HatCreatedWithEligibility event
        vm.expectEmit(true, true, true, true);
        emit HatCreatedWithEligibility(
            executive, // creator
            setup.defaultRoleHat, // parentHatId
            newHatId, // newHatId
            true, // defaultEligible
            true, // defaultStanding
            0 // mintedCount (registerHatCreation doesn't mint)
        );

        vm.prank(executive);
        EligibilityModule(setup.eligibilityModule).registerHatCreation(newHatId, setup.defaultRoleHat, true, true);
    }

    // Test that registerHatCreation emits DefaultEligibilityUpdated event
    function testRegisterHatCreationEmitsDefaultEligibilityUpdated() public {
        TestOrgSetup memory setup = _createTestOrg("Register Hat Eligibility Test DAO");
        address executive = voter1;

        address toggleModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID);

        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        vm.prank(executive);
        uint256 newHatId = IHats(SEPOLIA_HATS)
            .createHat(
                setup.defaultRoleHat,
                "Test Hat 2",
                100,
                setup.eligibilityModule,
                toggleModule,
                true,
                "ipfs://test-hat-2"
            );

        // Expect DefaultEligibilityUpdated event
        vm.expectEmit(true, false, false, true);
        emit DefaultEligibilityUpdated(newHatId, false, true, executive);

        vm.prank(executive);
        EligibilityModule(setup.eligibilityModule)
            .registerHatCreation(
                newHatId,
                setup.defaultRoleHat,
                false, // not eligible by default
                true // good standing by default
            );
    }

    // Test authorization - only superAdmin or hat admin can call registerHatCreation
    function testRegisterHatCreationAuthorization() public {
        TestOrgSetup memory setup = _createTestOrg("Auth Test DAO");
        address executive = voter1;
        address unauthorized = address(0x999);

        address toggleModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID);

        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        // Create a hat that we'll try to register
        vm.prank(executive);
        uint256 newHatId = IHats(SEPOLIA_HATS)
            .createHat(
                setup.defaultRoleHat,
                "Auth Test Hat",
                100,
                setup.eligibilityModule,
                toggleModule,
                true,
                "ipfs://auth-test"
            );

        // Unauthorized user should not be able to register
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(setup.eligibilityModule).registerHatCreation(newHatId, setup.defaultRoleHat, true, true);

        // Hat admin (executive) should be able to register
        vm.prank(executive);
        EligibilityModule(setup.eligibilityModule).registerHatCreation(newHatId, setup.defaultRoleHat, true, true);
    }

    // Test that registerHatCreation sets default eligibility correctly
    function testRegisterHatCreationSetsDefaultEligibility() public {
        TestOrgSetup memory setup = _createTestOrg("Default Eligibility Test DAO");
        address executive = voter1;
        address testWearer = address(0x888);

        address toggleModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID);

        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        vm.prank(executive);
        uint256 newHatId = IHats(SEPOLIA_HATS)
            .createHat(
                setup.defaultRoleHat,
                "Eligibility Test Hat",
                100,
                setup.eligibilityModule,
                toggleModule,
                true,
                "ipfs://eligibility-test"
            );

        // Register with specific eligibility settings (not eligible, good standing)
        vm.prank(executive);
        EligibilityModule(setup.eligibilityModule)
            .registerHatCreation(
                newHatId,
                setup.defaultRoleHat,
                false, // not eligible by default
                true // good standing by default
            );

        // Check that the default eligibility was set correctly
        (bool eligible, bool standing) =
            EligibilityModule(setup.eligibilityModule).getWearerStatus(testWearer, newHatId);
        assertFalse(eligible, "Wearer should not be eligible by default");
        assertTrue(standing, "Wearer should have good standing by default");
    }

    // Test that HatsTreeSetup correctly emits events during org deployment
    function testHatsTreeSetupEmitsRegisterHatCreationEvents() public {
        // This test verifies that HatsTreeSetup calls registerHatCreation
        // by checking that HatCreatedWithEligibility events are emitted during deployment

        vm.startPrank(orgOwner);
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        string[] memory images = new string[](2);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 4 ether);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();
        address[] memory ddTargets = new address[](0);
        RoleConfigStructs.RoleConfig[] memory roles = _buildSimpleRoleConfigs(names, images, voting);

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: keccak256("EVENTS_TEST_ORG"),
            orgName: "Events Test DAO",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: orgOwner,
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: roles,
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: true})
        });

        // Record logs to verify HatCreatedWithEligibility events were emitted
        vm.recordLogs();

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        vm.stopPrank();

        // Count HatCreatedWithEligibility events
        // Event signature: HatCreatedWithEligibility(address,uint256,uint256,bool,bool,uint256)
        bytes32 eventSig = keccak256("HatCreatedWithEligibility(address,uint256,uint256,bool,bool,uint256)");
        uint256 hatCreatedEventCount = 0;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                hatCreatedEventCount++;
            }
        }

        // Should have at least 3 events: 1 for eligibility admin hat + 2 for role hats (DEFAULT, EXECUTIVE)
        assertGe(hatCreatedEventCount, 3, "Should emit HatCreatedWithEligibility events for all created hats");
    }

    // Test that superAdmin can call registerHatCreation
    function testRegisterHatCreationBySuperAdmin() public {
        TestOrgSetup memory setup = _createTestOrg("SuperAdmin Test DAO");
        address executive = voter1;

        address toggleModule = orgRegistry.getOrgContract(ORG_ID, ModuleTypes.TOGGLE_MODULE_ID);

        _mintAdminHat(setup.exec, setup.eligibilityModule, setup.executiveRoleHat, executive);

        // Create a hat
        vm.prank(executive);
        uint256 newHatId = IHats(SEPOLIA_HATS)
            .createHat(
                setup.defaultRoleHat,
                "SuperAdmin Test Hat",
                100,
                setup.eligibilityModule,
                toggleModule,
                true,
                "ipfs://superadmin-test"
            );

        // SuperAdmin (executor) should be able to register even without being hat admin
        vm.prank(setup.exec);
        EligibilityModule(setup.eligibilityModule).registerHatCreation(newHatId, setup.defaultRoleHat, true, true);

        // Verify eligibility was set
        (bool eligible, bool standing) =
            EligibilityModule(setup.eligibilityModule).getWearerStatus(address(0x777), newHatId);
        assertTrue(eligible, "Wearer should be eligible by default after registration");
        assertTrue(standing, "Wearer should have good standing by default after registration");
    }

    /*══════════════════════════════════════════════════════════════════════════════
                           OPTIONAL EDUCATIONHUB TESTS
    ══════════════════════════════════════════════════════════════════════════════*/

    // Test: Deploy org without EducationHub
    function testDeployOrgWithoutEducationHub() public {
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "ADMIN";

        string[] memory images = new string[](2);
        images[0] = "ipfs://default";
        images[1] = "ipfs://admin";

        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 0);
        address[] memory ddTargets = new address[](0);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        bytes32 orgIdNoEdu = keccak256("no-education-hub-org");

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: orgIdNoEdu,
            orgName: "No EducationHub Org",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: address(this),
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: false})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);

        // Verify educationHub is address(0)
        assertEq(result.educationHub, address(0), "EducationHub should be address(0) when disabled");

        // Verify other contracts are still deployed
        assertTrue(result.executor != address(0), "Executor should be deployed");
        assertTrue(result.taskManager != address(0), "TaskManager should be deployed");
        assertTrue(result.paymentManager != address(0), "PaymentManager should be deployed");
        assertTrue(result.participationToken != address(0), "ParticipationToken should be deployed");
        assertTrue(result.hybridVoting != address(0), "HybridVoting should be deployed");
        assertTrue(result.quickJoin != address(0), "QuickJoin should be deployed");

        // Verify ParticipationToken.educationHub() returns address(0)
        assertEq(ParticipationToken(result.participationToken).educationHub(), address(0),
            "ParticipationToken.educationHub() should return address(0)");
    }

    // Test: TaskManager can still mint tokens when EducationHub is disabled
    function testMintingWorksWithoutEducationHub() public {
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "ADMIN";

        string[] memory images = new string[](2);
        images[0] = "ipfs://default";
        images[1] = "ipfs://admin";

        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 0);
        address[] memory ddTargets = new address[](0);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        bytes32 orgIdMint = keccak256("mint-without-edu-org");

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: orgIdMint,
            orgName: "Mint Without Edu Org",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: address(this),
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: false})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);

        // Verify TaskManager can still mint tokens
        ParticipationToken token = ParticipationToken(result.participationToken);
        TaskManager tm = TaskManager(result.taskManager);

        // Create a project and task to test minting
        address[] memory managers = new address[](0);
        uint256[] memory emptyHats = new uint256[](0);

        vm.prank(result.executor);
        bytes32 projectId = tm.createProject(
            abi.encode("Test Project"),
            bytes32(0),
            1000 ether,
            managers,
            emptyHats,
            emptyHats,
            emptyHats,
            emptyHats
        );

        // Mint directly via executor (which is allowed)
        address recipient = address(0x123);
        vm.prank(result.executor);
        token.mint(recipient, 100 ether);

        assertEq(token.balanceOf(recipient), 100 ether, "Executor should be able to mint tokens");
    }

    // Test: EducationHub can be set later via governance
    function testEducationHubCanBeSetLater() public {
        string[] memory names = new string[](2);
        names[0] = "DEFAULT";
        names[1] = "ADMIN";

        string[] memory images = new string[](2);
        images[0] = "ipfs://default";
        images[1] = "ipfs://admin";

        bool[] memory voting = new bool[](2);
        voting[0] = true;
        voting[1] = true;

        IHybridVotingInit.ClassConfig[] memory classes = _buildLegacyClasses(50, 50, false, 0);
        address[] memory ddTargets = new address[](0);
        OrgDeployer.RoleAssignments memory roleAssignments = _buildDefaultRoleAssignments();

        bytes32 orgIdSetLater = keccak256("set-edu-later-org");

        OrgDeployer.DeploymentParams memory params = OrgDeployer.DeploymentParams({
            orgId: orgIdSetLater,
            orgName: "Set Edu Later Org",
            metadataHash: bytes32(0),
            registryAddr: accountRegProxy,
            deployerAddress: address(this),
            deployerUsername: "",
            autoUpgrade: true,
            hybridQuorumPct: 50,
            ddQuorumPct: 50,
            hybridClasses: classes,
            ddInitialTargets: ddTargets,
            roles: _buildSimpleRoleConfigs(names, images, voting),
            roleAssignments: roleAssignments,
            passkeyConfig: AccessFactory.PasskeyConfig({
                enabled: false, maxCredentialsPerAccount: 0, defaultGuardian: address(0), recoveryDelay: 0
            }),
            educationHubConfig: ModulesFactory.EducationHubConfig({enabled: false})
        });

        OrgDeployer.DeploymentResult memory result = deployer.deployFullOrg(params);

        // Verify educationHub is initially address(0)
        ParticipationToken token = ParticipationToken(result.participationToken);
        assertEq(token.educationHub(), address(0), "EducationHub should initially be address(0)");

        // Set EducationHub later (first setter can set it)
        address newEducationHub = address(0x456);
        token.setEducationHub(newEducationHub);

        assertEq(token.educationHub(), newEducationHub, "EducationHub should be set to new address");
    }

    // Test: Executor can clear EducationHub by setting to address(0)
    function testExecutorCanClearEducationHub() public {
        TestOrgSetup memory setup = _createTestOrg("Clear EducationHub Test");

        ParticipationToken token = ParticipationToken(setup.token);

        // Verify educationHub is initially set
        assertTrue(token.educationHub() != address(0), "EducationHub should initially be set");

        // Executor clears the educationHub
        vm.prank(setup.exec);
        token.setEducationHub(address(0));

        assertEq(token.educationHub(), address(0), "EducationHub should be cleared to address(0)");
    }
}
