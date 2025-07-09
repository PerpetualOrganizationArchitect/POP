// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*──────────── forge‑std helpers ───────────*/
import "forge-std/Test.sol";
import "forge-std/console.sol";

/*──────────── OpenZeppelin ───────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/*──────────── Local contracts ───────────*/
import {HybridVoting} from "../src/HybridVoting.sol";
import {Executor} from "../src/Executor.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";

import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import "../src/ImplementationRegistry.sol";
import "../src/PoaManager.sol";
import "../src/OrgRegistry.sol";
import {Deployer} from "../src/Deployer.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {ToggleModule} from "../src/ToggleModule.sol";
import {IExecutor} from "../src/Executor.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";

// Define events for testing
interface IEligibilityModuleEvents {
    event WearerEligibilityUpdated(
        address indexed wearer, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );

    event DefaultEligibilityUpdated(uint256 indexed hatId, bool eligible, bool standing, address indexed admin);

    event AdminHatUpdated(uint256 indexed hatId, bool isAdmin, address indexed admin);

    event AdminPermissionUpdated(
        uint256 indexed adminHatId, uint256 indexed targetHatId, bool canControl, address indexed admin
    );

    event SuperAdminTransferred(address indexed oldSuperAdmin, address indexed newSuperAdmin);

    event Vouched(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    event VouchRevoked(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    event VouchConfigSet(
        uint256 indexed hatId, uint32 quorum, uint256 membershipHatId, bool enabled, bool combineWithHierarchy
    );
}

/*────────────── Test contract ───────────*/
contract DeployerTest is Test, IEligibilityModuleEvents {
    /*–––– implementations ––––*/
    HybridVoting hybridImpl;
    Executor execImpl;
    UniversalAccountRegistry accountRegImpl;
    QuickJoin quickJoinImpl;
    ParticipationToken pTokenImpl;
    TaskManager taskMgrImpl;
    EducationHub eduHubImpl;

    ImplementationRegistry implRegistry;
    PoaManager poaManager;
    OrgRegistry orgRegistry;
    Deployer deployer;

    /*–––– addresses ––––*/
    address public constant poaAdmin = address(1);
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
        returns (address hybrid, address exec, address qj, address token, address tm, address hub)
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
        (hybrid, exec, qj, token, tm, hub) = deployer.deployFullOrg(
            ORG_ID, "Hybrid DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );
        vm.stopPrank();
    }

    /*–––– Test Helper Functions ––––*/

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

        (setup.hybrid, setup.exec, setup.qj, setup.token, setup.tm, setup.hub) = deployer.deployFullOrg(
            ORG_ID, orgName, accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module and role hat IDs
        setup.eligibilityModule = address(deployer.eligibilityModule());
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

        (setup.hybrid, setup.exec, setup.qj, setup.token, setup.tm, setup.hub) = deployer.deployFullOrg(
            ORG_ID, orgName, accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module and role hat IDs
        setup.eligibilityModule = address(deployer.eligibilityModule());
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

    /// @dev Mints an admin hat to a user and updates the admin tracking
    function _mintAdminHat(address executor, address eligibilityModule, uint256 hatId, address user) internal {
        vm.prank(executor);
        IHats(SEPOLIA_HATS).mintHat(hatId, user);

        // Update the admin hat tracking
        vm.prank(executor);
        EligibilityModule(eligibilityModule).updateUserAdminHat(user, hatId);
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
        vm.createSelectFork("sepolia");

        /*–– deploy bare implementations ––*/
        hybridImpl = new HybridVoting();
        execImpl = new Executor();
        accountRegImpl = new UniversalAccountRegistry();
        quickJoinImpl = new QuickJoin();
        pTokenImpl = new ParticipationToken();
        taskMgrImpl = new TaskManager();
        eduHubImpl = new EducationHub();

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

        // Deploy implementations for OrgRegistry and Deployer
        OrgRegistry orgRegistryImpl = new OrgRegistry();
        Deployer deployerImpl = new Deployer();

        // Register ImplementationRegistry implementation with PoaManager first
        poaManager.addContractType("ImplementationRegistry", address(implRegistryImpl));

        // Get the beacon for ImplementationRegistry
        address implRegBeacon = poaManager.getBeacon("ImplementationRegistry");

        // Create ImplementationRegistry proxy and initialize it with poaAdmin as owner
        bytes memory implRegistryInit = abi.encodeWithSignature("initialize(address)", poaAdmin);
        implRegistry = ImplementationRegistry(address(new BeaconProxy(implRegBeacon, implRegistryInit)));

        // Now update the PoaManager to use the correct ImplementationRegistry proxy
        poaManager.updateImplRegistry(address(implRegistry));

        // Register the implRegistryImpl in the registry now that it's connected
        implRegistry.registerImplementation("ImplementationRegistry", "v1", address(implRegistryImpl), true);

        // Transfer implRegistry ownership to poaManager
        implRegistry.transferOwnership(address(poaManager));

        // Register implementations for OrgRegistry and Deployer
        poaManager.addContractType("OrgRegistry", address(orgRegistryImpl));
        poaManager.addContractType("Deployer", address(deployerImpl));

        // Get beacons created by PoaManager
        address orgRegBeacon = poaManager.getBeacon("OrgRegistry");
        address deployerBeacon = poaManager.getBeacon("Deployer");

        // Create OrgRegistry proxy - initialize with poaAdmin as owner
        bytes memory orgRegistryInit = abi.encodeWithSignature("initialize(address)", poaAdmin);
        orgRegistry = OrgRegistry(address(new BeaconProxy(orgRegBeacon, orgRegistryInit)));

        // Debug to verify OrgRegistry owner
        console.log("OrgRegistry owner after init:", orgRegistry.owner());

        // Create Deployer proxy - initialize with msg.sender (poaAdmin) for proper ownership
        bytes memory deployerInit = abi.encodeWithSignature(
            "initialize(address,address,address)", address(poaManager), address(orgRegistry), SEPOLIA_HATS
        );
        deployer = Deployer(address(new BeaconProxy(deployerBeacon, deployerInit)));

        // Debug to verify Deployer owner
        console.log("Deployer owner after init:", deployer.owner());
        console.log("deployer address:", address(deployer));

        // Now transfer orgRegistry ownership to deployer after both are initialized
        // This is critical to get the ownership chain right
        orgRegistry.transferOwnership(address(deployer));
        console.log("OrgRegistry owner after transfer:", orgRegistry.owner());

        /*–– register implementation types ––*/
        poaManager.addContractType("HybridVoting", address(hybridImpl));
        poaManager.addContractType("Executor", address(execImpl));
        poaManager.addContractType("QuickJoin", address(quickJoinImpl));
        poaManager.addContractType("ParticipationToken", address(pTokenImpl));
        poaManager.addContractType("TaskManager", address(taskMgrImpl));
        poaManager.addContractType("EducationHub", address(eduHubImpl));
        poaManager.addContractType("UniversalAccountRegistry", address(accountRegImpl));
        poaManager.addContractType("EligibilityModule", address(eligibilityModuleImpl));
        poaManager.addContractType("ToggleModule", address(toggleModuleImpl));

        /*–– global account registry instance ––*/
        // Get the beacon created by PoaManager for account registry
        address accRegBeacon = poaManager.getBeacon("UniversalAccountRegistry");

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

        (address _hybrid, address _executor, address _quickJoin, address _token, address _taskMgr, address _eduHub) =
        deployer.deployFullOrg(
            ORG_ID, "Hybrid DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        /* store for later checks */
        hybridProxy = _hybrid;
        executorProxy = payable(_executor);
        quickJoinProxy = _quickJoin;
        pTokenProxy = _token;
        taskMgrProxy = _taskMgr;
        eduHubProxy = _eduHub;

        /* basic invariants */
        assertEq(abi.decode(HybridVoting(hybridProxy).getStorage(HybridVoting.StorageKey.VERSION, ""), (string)), "v1");
        assertEq(Executor(executorProxy).version(), "v1");

        /*—————————————————— quick smoke test: join + vote —————————————————*/
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("v1");
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
        HybridVoting(hybridProxy).createProposal("ipfs://test", 60, optNumber, batches);

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
        (address hybrid, address exec, address qj, address token, address tm, address hub) = _deployFullOrg();

        (address executorAddr, uint32 count, bool boot, bool exists) = orgRegistry.orgOf(ORG_ID);
        assertEq(executorAddr, exec); // Should be the Executor contract address, not orgOwner
        assertEq(count, 8); // Updated to 8 since we now deploy EligibilityModule and ToggleModule as beacon proxies
        assertFalse(boot);
        assertTrue(exists);

        bytes32 typeId = keccak256("QuickJoin");
        bytes32 contractId = keccak256(abi.encodePacked(ORG_ID, typeId));
        (address proxy, address beacon, bool autoUp, address owner) = orgRegistry.contractOf(contractId);
        assertEq(proxy, qj);
        assertTrue(autoUp);
        assertEq(owner, exec);

        address impl = deployer.getBeaconImplementation(beacon);
        assertEq(impl, poaManager.getCurrentImplementation("QuickJoin"));
        assertEq(deployer.poaManager(), address(poaManager));
        assertEq(deployer.orgRegistry(), address(orgRegistry));
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
        deployer.deployFullOrg(
            ORG_ID, "Hybrid DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );
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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Hybrid DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

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
        uint256 newRoleHatId = IHats(SEPOLIA_HATS).createHat(
            topHatId, // admin = parent Top Hat
            "NEW_ROLE", // details
            type(uint32).max, // unlimited supply
            address(deployer.eligibilityModule()), // eligibility module
            address(deployer.toggleModule()), // toggle module
            true, // mutable
            "NEW_ROLE" // data blob
        );

        // Configure the new role hat for the executor
        deployer.eligibilityModule().setWearerEligibility(exec, newRoleHatId, true, true);
        deployer.toggleModule().setHatStatus(newRoleHatId, true);

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Hybrid DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address directly
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

        // Verify executor is the super admin
        assertEq(EligibilityModule(eligibilityModuleAddr).superAdmin(), exec, "Executor should be the super admin");

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);

        // Verify executive role hat is an admin hat
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isAdminHat(executiveRoleHat),
            "Executive role hat should be an admin hat"
        );

        // Verify executive role hat can control default role hat
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(executiveRoleHat, defaultRoleHat),
            "Executive role hat should be able to control default role hat"
        );

        // Test that someone wearing the executive role hat can change eligibility
        // First, mint the executive role hat to voter1
        _mintAdminHat(exec, eligibilityModuleAddr, executiveRoleHat, voter1);

        // Verify voter1 is wearing the executive role hat
        assertTrue(IHats(SEPOLIA_HATS).isWearerOfHat(voter1, executiveRoleHat), "voter1 should wear executive role hat");

        // Now voter1 should be able to change eligibility for voter2's default role hat
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // Verify the eligibility was changed for voter2
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter2, defaultRoleHat);
        assertFalse(eligible, "voter2's default role hat should be ineligible");
        assertFalse(standing, "voter2's default role hat should have bad standing");

        // voter1's eligibility should be unaffected since it's per-wearer (should still have default eligibility)
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter1, defaultRoleHat);
        assertTrue(eligible, "voter1's default role hat should still be default (eligible)");
        assertTrue(standing, "voter1's default role hat should still be default (good standing)");

        // Change voter2 back to eligible
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, true, true);

        // Verify the eligibility was changed back for voter2
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(voter2, defaultRoleHat);
        assertTrue(eligible, "voter2's default role hat should be eligible");
        assertTrue(standing, "voter2's default role hat should have good standing");

        // Test that someone without the executive role hat cannot change eligibility
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(voter2, defaultRoleHat, false, false);

        // Test that executor (as super admin) can add new admin hats
        uint256 newAdminHatId = 999; // Example hat ID

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(newAdminHatId, true);

        // Verify the new admin hat was added
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isAdminHat(newAdminHatId), "New admin hat should be registered"
        );

        // Set permissions for the new admin hat
        uint256[] memory targetHats = new uint256[](1);
        targetHats[0] = defaultRoleHat;
        bool[] memory permissions = new bool[](1);
        permissions[0] = true;

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(newAdminHatId, targetHats, permissions);

        // Verify the permissions were set
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(newAdminHatId, defaultRoleHat),
            "New admin hat should be able to control default role hat"
        );

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

    function testMultipleAdminHatsWithRoleManagement() public {
        vm.startPrank(orgOwner);
        string[] memory names = new string[](4);
        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";
        names[2] = "MODERATOR";
        names[3] = "CONTRIBUTOR";
        string[] memory images = new string[](4);
        images[0] = "ipfs://default-role-image";
        images[1] = "ipfs://executive-role-image";
        images[2] = "ipfs://moderator-role-image";
        images[3] = "ipfs://contributor-role-image";
        bool[] memory voting = new bool[](4);
        voting[0] = true;
        voting[1] = true;
        voting[2] = true;
        voting[3] = true;

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Multi-Admin DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 moderatorRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);
        uint256 contributorRoleHat = orgRegistry.getRoleHat(ORG_ID, 3);

        // Set up admin hat permissions:
        // - EXECUTIVE can control DEFAULT and CONTRIBUTOR
        // - MODERATOR can control DEFAULT and CONTRIBUTOR
        // - CONTRIBUTOR can only control DEFAULT

        // Set EXECUTIVE as admin hat
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(executiveRoleHat, true);

        // Set MODERATOR as admin hat
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(moderatorRoleHat, true);

        // Set CONTRIBUTOR as admin hat
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(contributorRoleHat, true);

        // Give EXECUTIVE permission to control DEFAULT and CONTRIBUTOR
        uint256[] memory executiveTargets = new uint256[](2);
        executiveTargets[0] = defaultRoleHat;
        executiveTargets[1] = contributorRoleHat;
        bool[] memory executivePermissions = new bool[](2);
        executivePermissions[0] = true;
        executivePermissions[1] = true;

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(
            executiveRoleHat, executiveTargets, executivePermissions
        );

        // Give MODERATOR permission to control DEFAULT and CONTRIBUTOR
        uint256[] memory moderatorTargets = new uint256[](2);
        moderatorTargets[0] = defaultRoleHat;
        moderatorTargets[1] = contributorRoleHat;
        bool[] memory moderatorPermissions = new bool[](2);
        moderatorPermissions[0] = true;
        moderatorPermissions[1] = true;

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(
            moderatorRoleHat, moderatorTargets, moderatorPermissions
        );

        // Give CONTRIBUTOR permission to control only DEFAULT
        uint256[] memory contributorTargets = new uint256[](1);
        contributorTargets[0] = defaultRoleHat;
        bool[] memory contributorPermissions = new bool[](1);
        contributorPermissions[0] = true;

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(
            contributorRoleHat, contributorTargets, contributorPermissions
        );

        // Verify admin hat setup
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isAdminHat(executiveRoleHat), "EXECUTIVE should be admin hat"
        );
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isAdminHat(moderatorRoleHat), "MODERATOR should be admin hat"
        );
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).isAdminHat(contributorRoleHat), "CONTRIBUTOR should be admin hat"
        );

        // Verify permissions
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(executiveRoleHat, defaultRoleHat),
            "EXECUTIVE should control DEFAULT"
        );
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(executiveRoleHat, contributorRoleHat),
            "EXECUTIVE should control CONTRIBUTOR"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(executiveRoleHat, executiveRoleHat),
            "EXECUTIVE should not control itself"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(executiveRoleHat, moderatorRoleHat),
            "EXECUTIVE should not control MODERATOR"
        );

        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(moderatorRoleHat, defaultRoleHat),
            "MODERATOR should control DEFAULT"
        );
        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(moderatorRoleHat, contributorRoleHat),
            "MODERATOR should control CONTRIBUTOR"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(moderatorRoleHat, executiveRoleHat),
            "MODERATOR should not control EXECUTIVE"
        );

        assertTrue(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(contributorRoleHat, defaultRoleHat),
            "CONTRIBUTOR should control DEFAULT"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(contributorRoleHat, contributorRoleHat),
            "CONTRIBUTOR should not control itself"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(contributorRoleHat, executiveRoleHat),
            "CONTRIBUTOR should not control EXECUTIVE"
        );
        assertFalse(
            EligibilityModule(eligibilityModuleAddr).canAdminControlHat(contributorRoleHat, moderatorRoleHat),
            "CONTRIBUTOR should not control MODERATOR"
        );

        // Mint admin hats to test users
        _mintAdminHat(exec, eligibilityModuleAddr, executiveRoleHat, voter1);
        _mintAdminHat(exec, eligibilityModuleAddr, moderatorRoleHat, voter2);
        _mintAdminHat(exec, eligibilityModuleAddr, contributorRoleHat, address(5));

        // Test EXECUTIVE (voter1) can control DEFAULT and CONTRIBUTOR for a test user
        address testUser = address(6);
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, false, false);

        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, contributorRoleHat, false, false);

        // Verify the changes took effect
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertFalse(eligible, "DEFAULT should be ineligible after EXECUTIVE change");
        assertFalse(standing, "DEFAULT should have bad standing after EXECUTIVE change");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, contributorRoleHat);
        assertFalse(eligible, "CONTRIBUTOR should be ineligible after EXECUTIVE change");
        assertFalse(standing, "CONTRIBUTOR should have bad standing after EXECUTIVE change");

        // Test EXECUTIVE cannot control EXECUTIVE or MODERATOR
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, executiveRoleHat, false, false);

        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, moderatorRoleHat, false, false);

        // Test MODERATOR (voter2) can control DEFAULT and CONTRIBUTOR
        vm.prank(voter2);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, true, true);

        vm.prank(voter2);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, contributorRoleHat, true, true);

        // Verify the changes took effect
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertTrue(eligible, "DEFAULT should be eligible after MODERATOR change");
        assertTrue(standing, "DEFAULT should have good standing after MODERATOR change");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, contributorRoleHat);
        assertTrue(eligible, "CONTRIBUTOR should be eligible after MODERATOR change");
        assertTrue(standing, "CONTRIBUTOR should have good standing after MODERATOR change");

        // Test MODERATOR cannot control EXECUTIVE
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, executiveRoleHat, false, false);

        // Test CONTRIBUTOR (voter3) can only control DEFAULT
        vm.prank(address(5));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, false, false);

        // Verify the change took effect
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertFalse(eligible, "DEFAULT should be ineligible after CONTRIBUTOR change");
        assertFalse(standing, "DEFAULT should have bad standing after CONTRIBUTOR change");

        // Test CONTRIBUTOR cannot control other roles
        vm.prank(address(5));
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, contributorRoleHat, false, false);

        vm.prank(address(5));
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, executiveRoleHat, false, false);

        vm.prank(address(5));
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, moderatorRoleHat, false, false);

        // Test that non-admin users cannot control any roles
        vm.prank(address(6));
        vm.expectRevert(abi.encodeWithSelector(EligibilityModule.NotAuthorizedAdmin.selector));
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, true, true);

        // Test full workflow: EXECUTIVE makes someone eligible, they get the hat, then MODERATOR revokes it
        address hatRecipient = address(7);
        // EXECUTIVE makes DEFAULT eligible for address(7)
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(hatRecipient, defaultRoleHat, true, true);

        // Mint DEFAULT hat to the new user
        vm.prank(exec);
        bool success = IHats(SEPOLIA_HATS).mintHat(defaultRoleHat, hatRecipient);
        assertTrue(success, "Should successfully mint DEFAULT hat when eligible");

        // Verify the user is wearing the hat
        assertTrue(
            IHats(SEPOLIA_HATS).isWearerOfHat(hatRecipient, defaultRoleHat), "User should be wearing DEFAULT hat"
        );

        // MODERATOR revokes eligibility for address(7)
        vm.prank(voter2);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(hatRecipient, defaultRoleHat, false, false);

        // Verify the user is no longer wearing the hat
        assertFalse(
            IHats(SEPOLIA_HATS).isWearerOfHat(hatRecipient, defaultRoleHat),
            "User should no longer be wearing DEFAULT hat when ineligible"
        );

        // Test that the super admin can still control all hats for testUser
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, true, true);
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, executiveRoleHat, false, false);
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, moderatorRoleHat, false, false);
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, contributorRoleHat, false, false);

        // Verify all hats are now controlled by super admin for testUser
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertTrue(eligible, "DEFAULT should be eligible after super admin change");
        assertTrue(standing, "DEFAULT should have good standing after super admin change");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, executiveRoleHat);
        assertFalse(eligible, "EXECUTIVE should be ineligible after super admin change");
        assertFalse(standing, "EXECUTIVE should have bad standing after super admin change");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, moderatorRoleHat);
        assertFalse(eligible, "MODERATOR should be ineligible after super admin change");
        assertFalse(standing, "MODERATOR should have bad standing after super admin change");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, contributorRoleHat);
        assertFalse(eligible, "CONTRIBUTOR should be ineligible after super admin change");
        assertFalse(standing, "CONTRIBUTOR should have bad standing after super admin change");
    }

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Events Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

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

        // Test that events are emitted when setting admin hat
        vm.expectEmit(true, false, false, true);
        emit AdminHatUpdated(999, true, exec);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(999, true);

        // Test that events are emitted when setting admin permissions
        uint256[] memory targetHats = new uint256[](1);
        targetHats[0] = defaultRoleHat;
        bool[] memory permissions = new bool[](1);
        permissions[0] = true;

        vm.expectEmit(true, true, false, true);
        emit AdminPermissionUpdated(999, defaultRoleHat, true, exec);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(999, targetHats, permissions);

        // Test that events are emitted when transferring super admin
        vm.expectEmit(true, true, false, false);
        emit SuperAdminTransferred(exec, voter1);

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).transferSuperAdmin(voter1);
    }

    function testVouchingSystemBasic() public {
        TestOrgSetup memory setup = _createTestOrg("Vouch Test DAO");
        address candidate = address(0x200);

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

        // Test that candidate is automatically wearing the hat after reaching quorum
        _assertWearingHat(candidate, setup.defaultRoleHat, true, "Candidate after auto-mint");
    }

    function testVouchingSystemHybridMode() public {
        TestOrgSetup memory setup = _createTestOrg("Hybrid Vouch Test DAO");
        address candidate1 = address(0x201);
        address candidate2 = address(0x202);
        address voucher2 = address(0x203);

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Vouch Error Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

        address candidate = address(0x300);

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Vouch Events Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

        // Get role hat IDs
        uint256 defaultRoleHat = orgRegistry.getRoleHat(ORG_ID, 0);
        uint256 executiveRoleHat = orgRegistry.getRoleHat(ORG_ID, 1);
        uint256 memberRoleHat = orgRegistry.getRoleHat(ORG_ID, 2);

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

        address candidate = address(0x500);

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Vouch Disable Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

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
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(candidate, defaultRoleHat);
        assertTrue(eligible, "Should be eligible via hierarchy");
        assertTrue(standing, "Should have good standing via hierarchy");

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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "SuperAdmin Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

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

        // Verify all settings took effect
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertTrue(eligible, "Should be eligible for DEFAULT");
        assertTrue(standing, "Should have good standing for DEFAULT");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, executiveRoleHat);
        assertTrue(eligible, "Should be eligible for EXECUTIVE");
        assertTrue(standing, "Should have good standing for EXECUTIVE");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, memberRoleHat);
        assertTrue(eligible, "Should be eligible for MEMBER");
        assertTrue(standing, "Should have good standing for MEMBER");

        // Test that super admin can configure vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).configureVouching(memberRoleHat, 3, defaultRoleHat, true);

        // Test that super admin can add new admin hats
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminHat(memberRoleHat, true);

        // Test that super admin can set admin permissions
        uint256[] memory targetHats = new uint256[](1);
        targetHats[0] = executiveRoleHat;
        bool[] memory permissions = new bool[](1);
        permissions[0] = true;

        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setAdminPermissions(memberRoleHat, targetHats, permissions);

        // Test that super admin can reset vouches
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).resetVouches(memberRoleHat);

        // Test that super admin can transfer super admin
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).transferSuperAdmin(voter1);

        // Verify the transfer worked
        assertEq(EligibilityModule(eligibilityModuleAddr).superAdmin(), voter1, "Super admin should be transferred");

        // Test that the new super admin now has full control
        vm.prank(voter1);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(testUser, defaultRoleHat, false, false);

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(testUser, defaultRoleHat);
        assertFalse(eligible, "Should not be eligible after new super admin revokes");
        assertFalse(standing, "Should not have good standing after new super admin revokes");
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

        (address hybrid, address exec, address qj, address token, address tm, address hub) = deployer.deployFullOrg(
            ORG_ID, "Unrestricted Hat Test DAO", accountRegProxy, true, 50, 50, false, 4 ether, names, images, voting
        );

        vm.stopPrank();

        // Get the eligibility module address
        address eligibilityModuleAddr = address(deployer.eligibilityModule());

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

        // Check that anyone can be eligible for the open hat
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser1, openRoleHat);
        assertTrue(eligible, "Random user 1 should be eligible for open hat");
        assertTrue(standing, "Random user 1 should have good standing for open hat");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser2, openRoleHat);
        assertTrue(eligible, "Random user 2 should be eligible for open hat");
        assertTrue(standing, "Random user 2 should have good standing for open hat");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser3, openRoleHat);
        assertTrue(eligible, "Random user 3 should be eligible for open hat");
        assertTrue(standing, "Random user 3 should have good standing for open hat");

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
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser1, openRoleHat);
        assertFalse(eligible, "Random user 1 should now be ineligible after specific rule");
        assertFalse(standing, "Random user 1 should have bad standing after specific rule");

        // But randomUser2 and randomUser3 should still be eligible (using default rules)
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser2, openRoleHat);
        assertTrue(eligible, "Random user 2 should still be eligible via default rules");
        assertTrue(standing, "Random user 2 should still have good standing via default rules");

        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser3, openRoleHat);
        assertTrue(eligible, "Random user 3 should still be eligible via default rules");
        assertTrue(standing, "Random user 3 should still have good standing via default rules");

        // 5. Test that the super admin can make it even more open by removing the specific restriction
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setWearerEligibility(randomUser1, openRoleHat, true, true);

        // Now randomUser1 should be eligible again
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(randomUser1, openRoleHat);
        assertTrue(eligible, "Random user 1 should be eligible again");
        assertTrue(standing, "Random user 1 should have good standing again");

        // 6. Demonstrate that we can create a hat that's completely unrestricted
        // by ensuring default eligibility is true and no specific rules or vouching
        vm.prank(exec);
        EligibilityModule(eligibilityModuleAddr).setDefaultEligibility(openRoleHat, true, true);

        // Any address should be eligible
        address veryRandomUser = address(0x999);
        (eligible, standing) = EligibilityModule(eligibilityModuleAddr).getWearerStatus(veryRandomUser, openRoleHat);
        assertTrue(eligible, "Any random user should be eligible for unrestricted hat");
        assertTrue(standing, "Any random user should have good standing for unrestricted hat");
    }
}
