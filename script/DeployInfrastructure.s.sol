// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

// Implementation contracts
import {HybridVoting} from "../src/HybridVoting.sol";
import {DirectDemocracyVoting} from "../src/DirectDemocracyVoting.sol";
import {Executor} from "../src/Executor.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {TaskManager} from "../src/TaskManager.sol";
import {EducationHub} from "../src/EducationHub.sol";
import {PaymentManager} from "../src/PaymentManager.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {ToggleModule} from "../src/ToggleModule.sol";

// Infrastructure
import {ImplementationRegistry} from "../src/ImplementationRegistry.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";
import {OrgDeployer} from "../src/OrgDeployer.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";

// Factories
import {GovernanceFactory} from "../src/factories/GovernanceFactory.sol";
import {AccessFactory} from "../src/factories/AccessFactory.sol";
import {ModulesFactory} from "../src/factories/ModulesFactory.sol";
import {HatsTreeSetup} from "../src/HatsTreeSetup.sol";

/**
 * @title DeployInfrastructure
 * @notice Deploys all protocol infrastructure contracts (one-time per chain)
 * @dev Outputs addresses for use by DeployOrg.s.sol
 *
 * Usage:
 *   forge script script/DeployInfrastructure.s.sol:DeployInfrastructure \
 *     --rpc-url $RPC_URL \
 *     --broadcast \
 *     --verify
 *
 * Environment Variables Required:
 *   - DEPLOYER_PRIVATE_KEY: Private key for deployment
 */
contract DeployInfrastructure is Script {
    /*═══════════════════════════ CONSTANTS ═══════════════════════════*/

    // Hats Protocol on Sepolia (constant across deployments)
    address public constant HATS_PROTOCOL = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    // EntryPoint v0.7 (canonical address on all chains)
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /*═══════════════════════════ STORAGE ═══════════════════════════*/

    // Core infrastructure
    address public orgDeployer;
    address public globalAccountRegistry;
    address public poaManager;
    address public orgRegistry;
    address public implRegistry;
    address public paymasterHub;

    /*═══════════════════════════ MAIN DEPLOYMENT ═══════════════════════════*/

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        console.log("\n=== Starting POA Infrastructure Deployment ===");
        console.log("Deployer:", vm.addr(deployerPrivateKey));
        console.log("Hats Protocol:", HATS_PROTOCOL);

        vm.startBroadcast(deployerPrivateKey);

        _deployAll();

        vm.stopBroadcast();

        _outputAddresses();

        console.log("\n=== Infrastructure Deployment Complete ===\n");
    }

    function _deployAll() internal {
        // Deploy all implementations
        address hybridVotingImpl = address(new HybridVoting());
        address ddVotingImpl = address(new DirectDemocracyVoting());
        address executorImpl = address(new Executor());
        address quickJoinImpl = address(new QuickJoin());
        address pTokenImpl = address(new ParticipationToken());
        address taskMgrImpl = address(new TaskManager());
        address eduHubImpl = address(new EducationHub());
        address paymentMgrImpl = address(new PaymentManager());
        address accountRegImpl = address(new UniversalAccountRegistry());
        address eligibilityImpl = address(new EligibilityModule());
        address toggleImpl = address(new ToggleModule());
        address implRegImpl = address(new ImplementationRegistry());
        address orgRegImpl = address(new OrgRegistry());
        address deployerImpl = address(new OrgDeployer());

        console.log("\n--- Implementations Deployed ---");

        // Deploy PoaManager
        poaManager = address(new PoaManager(address(0)));
        console.log("PoaManager:", poaManager);

        // Setup ImplementationRegistry
        PoaManager(poaManager).addContractType("ImplementationRegistry", implRegImpl);
        address implRegBeacon = PoaManager(poaManager).getBeaconById(keccak256("ImplementationRegistry"));
        bytes memory implRegInit = abi.encodeWithSignature("initialize(address)", msg.sender);
        implRegistry = address(new BeaconProxy(implRegBeacon, implRegInit));

        PoaManager(poaManager).updateImplRegistry(implRegistry);
        ImplementationRegistry(implRegistry).registerImplementation("ImplementationRegistry", "v1", implRegImpl, true);
        ImplementationRegistry(implRegistry).transferOwnership(poaManager);
        console.log("ImplementationRegistry:", implRegistry);

        // Register OrgRegistry and OrgDeployer
        PoaManager(poaManager).addContractType("OrgRegistry", orgRegImpl);
        PoaManager(poaManager).addContractType("OrgDeployer", deployerImpl);

        // Deploy OrgRegistry proxy
        address orgRegBeacon = PoaManager(poaManager).getBeaconById(keccak256("OrgRegistry"));
        bytes memory orgRegInit = abi.encodeWithSignature("initialize(address)", msg.sender);
        orgRegistry = address(new BeaconProxy(orgRegBeacon, orgRegInit));
        console.log("OrgRegistry:", orgRegistry);

        // Deploy factories
        address govFactory = address(new GovernanceFactory());
        address accFactory = address(new AccessFactory());
        address modFactory = address(new ModulesFactory());
        address hatsSetup = address(new HatsTreeSetup());

        console.log("GovernanceFactory:", govFactory);
        console.log("AccessFactory:", accFactory);
        console.log("ModulesFactory:", modFactory);
        console.log("HatsTreeSetup:", hatsSetup);

        // Deploy PaymasterHub implementation and register
        address paymasterHubImpl = address(new PaymasterHub());
        PoaManager(poaManager).addContractType("PaymasterHub", paymasterHubImpl);

        // Deploy PaymasterHub proxy
        address paymasterHubBeacon = PoaManager(poaManager).getBeaconById(keccak256("PaymasterHub"));
        bytes memory paymasterHubInit =
            abi.encodeWithSignature("initialize(address,address,address)", ENTRY_POINT_V07, HATS_PROTOCOL, poaManager);
        paymasterHub = address(new BeaconProxy(paymasterHubBeacon, paymasterHubInit));
        console.log("PaymasterHub:", paymasterHub);

        // Deploy OrgDeployer proxy
        address deployerBeacon = PoaManager(poaManager).getBeaconById(keccak256("OrgDeployer"));
        bytes memory deployerInit = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address)",
            govFactory,
            accFactory,
            modFactory,
            poaManager,
            orgRegistry,
            HATS_PROTOCOL,
            hatsSetup,
            paymasterHub
        );
        orgDeployer = address(new BeaconProxy(deployerBeacon, deployerInit));
        console.log("OrgDeployer:", orgDeployer);

        // Transfer OrgRegistry ownership
        OrgRegistry(orgRegistry).transferOwnership(orgDeployer);

        // Register all contract types
        PoaManager pm = PoaManager(poaManager);
        pm.addContractType("HybridVoting", hybridVotingImpl);
        pm.addContractType("DirectDemocracyVoting", ddVotingImpl);
        pm.addContractType("Executor", executorImpl);
        pm.addContractType("QuickJoin", quickJoinImpl);
        pm.addContractType("ParticipationToken", pTokenImpl);
        pm.addContractType("TaskManager", taskMgrImpl);
        pm.addContractType("EducationHub", eduHubImpl);
        pm.addContractType("PaymentManager", paymentMgrImpl);
        pm.addContractType("UniversalAccountRegistry", accountRegImpl);
        pm.addContractType("EligibilityModule", eligibilityImpl);
        pm.addContractType("ToggleModule", toggleImpl);

        console.log("\n--- Contract Types Registered ---");

        // Deploy global account registry
        address accRegBeacon = pm.getBeaconById(keccak256("UniversalAccountRegistry"));
        bytes memory accRegInit = abi.encodeWithSignature("initialize(address)", msg.sender);
        globalAccountRegistry = address(new BeaconProxy(accRegBeacon, accRegInit));
        console.log("GlobalAccountRegistry:", globalAccountRegistry);
    }

    function _outputAddresses() internal {
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("\n--- Key Addresses for Org Deployment ---");
        console.log("OrgDeployer:", orgDeployer);
        console.log("GlobalAccountRegistry:", globalAccountRegistry);

        console.log("\n--- Infrastructure ---");
        console.log("PoaManager:", poaManager);
        console.log("OrgRegistry:", orgRegistry);
        console.log("ImplementationRegistry:", implRegistry);
        console.log("HatsProtocol:", HATS_PROTOCOL);

        // Write addresses to JSON file for easy org deployment
        string memory addressesJson = string.concat(
            "{\n",
            '  "orgDeployer": "',
            vm.toString(orgDeployer),
            '",\n',
            '  "globalAccountRegistry": "',
            vm.toString(globalAccountRegistry),
            '",\n',
            '  "paymasterHub": "',
            vm.toString(paymasterHub),
            '",\n',
            '  "poaManager": "',
            vm.toString(poaManager),
            '",\n',
            '  "orgRegistry": "',
            vm.toString(orgRegistry),
            '",\n',
            '  "implRegistry": "',
            vm.toString(implRegistry),
            '",\n',
            '  "hatsProtocol": "',
            vm.toString(HATS_PROTOCOL),
            '"\n',
            "}\n"
        );

        vm.writeFile("script/infrastructure.json", addressesJson);

        console.log("\n=== Addresses saved to script/infrastructure.json ===");
        console.log("\nTo deploy an org, simply run:");
        console.log("  forge script script/DeployOrg.s.sol:DeployOrg --rpc-url sepolia --broadcast");
        console.log("\n(No need to source anything - addresses are auto-loaded from infrastructure.json!)");
    }
}
