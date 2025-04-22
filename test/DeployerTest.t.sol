// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/*──────────── forge‑std helpers ───────────*/
import "forge-std/Test.sol";

/*──────────── OpenZeppelin ───────────*/
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

        vm.startPrank(poaAdmin);

        /*–– infra ––*/
        implRegistry = new ImplementationRegistry();
        poaManager = new PoaManager(address(implRegistry));
        orgRegistry = new OrgRegistry();
        deployer = new Deployer(address(poaManager), address(orgRegistry));

        /* transfer ownerships for registering later */
        implRegistry.transferOwnership(address(poaManager));
        orgRegistry.transferOwnership(address(deployer));

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
        address accRegBeacon = poaManager.getBeacon("UniversalAccountRegistry");
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
            address(0), // treasury unused in current flow
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
        string[] memory optNames = new string[](2);
        optNames[0] = "YES";
        optNames[1] = "NO";

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](0);
        batches[1] = new IExecutor.Call[](0);

        vm.prank(voter1);
        HybridVoting(hybridProxy).createProposal("ipfs://test", 60, optNames, batches);

        /* vote YES */
        uint16[] memory idxList = new uint16[](1);
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
}
