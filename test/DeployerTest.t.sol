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
import {Membership} from "../src/Membership.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";

import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import "../src/ImplementationRegistry.sol";
import "../src/PoaManager.sol";
import "../src/OrgRegistry.sol";
import {Deployer} from "../src/Deployer.sol";
import {IExecutor} from "../src/Executor.sol";

/*────────────── Test contract ───────────*/
contract DeployerTest is Test {
    /*–––– implementations ––––*/
    HybridVoting hybridImpl;
    Executor execImpl;
    Membership membershipImpl;
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

    /*–––– ids ––––*/
    bytes32 public constant ORG_ID = keccak256("AUTO-UPGRADE-ORG");
    bytes32 public constant GLOBAL_REG_ID = keccak256("POA-GLOBAL-ACCOUNT-REGISTRY");

    /*–––– deployed proxies ––––*/
    address membershipProxy;
    address quickJoinProxy;
    address pTokenProxy;
    address payable executorProxy;
    address hybridProxy;
    address taskMgrProxy;
    address eduHubProxy;
    address accountRegProxy;

    function _deployFullOrg()
        internal
        returns (address hybrid, address exec, address member, address qj, address token, address tm, address hub)
    {
        vm.startPrank(orgOwner);
        (hybrid, exec, member, qj, token, tm, hub) =
            deployer.deployFullOrg(ORG_ID, orgOwner, "Hybrid DAO", accountRegProxy, true);
        vm.stopPrank();
    }

    /*══════════════════════════════════════════ SET‑UP ══════════════════════════════════════════*/
    function setUp() public {
        /*–– deploy bare implementations ––*/
        hybridImpl = new HybridVoting();
        execImpl = new Executor();
        membershipImpl = new Membership();
        accountRegImpl = new UniversalAccountRegistry();
        quickJoinImpl = new QuickJoin();
        pTokenImpl = new ParticipationToken();
        taskMgrImpl = new TaskManager();
        eduHubImpl = new EducationHub();

        // Deploy the implementation contract for ImplementationRegistry
        ImplementationRegistry implRegistryImpl = new ImplementationRegistry();

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
        bytes memory deployerInit =
            abi.encodeWithSignature("initialize(address,address)", address(poaManager), address(orgRegistry));
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
        poaManager.addContractType("Membership", address(membershipImpl));
        poaManager.addContractType("QuickJoin", address(quickJoinImpl));
        poaManager.addContractType("ParticipationToken", address(pTokenImpl));
        poaManager.addContractType("TaskManager", address(taskMgrImpl));
        poaManager.addContractType("EducationHub", address(eduHubImpl));
        poaManager.addContractType("UniversalAccountRegistry", address(accountRegImpl));

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

        (
            address _hybrid,
            address _executor,
            address _membership,
            address _quickJoin,
            address _token,
            address _taskMgr,
            address _eduHub
        ) = deployer.deployFullOrg(
            ORG_ID,
            orgOwner,
            "Hybrid DAO",
            accountRegProxy,
            true // auto‑upgrade
        );

        vm.stopPrank();

        /* store for later checks */
        hybridProxy = _hybrid;
        executorProxy = payable(_executor);
        membershipProxy = _membership;
        quickJoinProxy = _quickJoin;
        pTokenProxy = _token;
        taskMgrProxy = _taskMgr;
        eduHubProxy = _eduHub;

        /* basic invariants */
        assertEq(HybridVoting(hybridProxy).version(), "v1");
        assertEq(Executor(executorProxy).version(), "v1");

        /*—————————————————— quick smoke test: join + vote —————————————————*/
        vm.prank(voter1);
        QuickJoin(quickJoinProxy).quickJoinNoUser("v1");
        vm.prank(voter2);
        QuickJoin(quickJoinProxy).quickJoinNoUser("v2");

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
        (address hybrid, address exec, address member, address qj, address token, address tm, address hub) =
            _deployFullOrg();

        (address executorAddr, uint32 count, bool boot, bool exists) = orgRegistry.orgOf(ORG_ID);
        assertEq(executorAddr, orgOwner);
        assertEq(count, 7);
        assertFalse(boot);
        assertTrue(exists);

        bytes32 typeId = keccak256("Membership");
        bytes32 contractId = keccak256(abi.encodePacked(ORG_ID, typeId));
        (address proxy, address beacon, bool autoUp, address owner) = orgRegistry.contractOf(contractId);
        assertEq(proxy, member);
        assertTrue(autoUp);
        assertEq(owner, exec);

        address impl = deployer.getBeaconImplementation(beacon);
        assertEq(impl, poaManager.getCurrentImplementation("Membership"));
        assertEq(deployer.poaManager(), address(poaManager));
        assertEq(deployer.orgRegistry(), address(orgRegistry));
    }

    function testDeployFullOrgMismatchExecutorReverts() public {
        _deployFullOrg();
        address other = address(99);
        vm.startPrank(other);
        vm.expectRevert(abi.encodeWithSignature("OrgExistsMismatch()"));
        deployer.deployFullOrg(ORG_ID, other, "Hybrid DAO", accountRegProxy, true);
        vm.stopPrank();
    }
}
