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
import {PasskeyAccount} from "../src/PasskeyAccount.sol";
import {PasskeyAccountFactory} from "../src/PasskeyAccountFactory.sol";

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
 *   - PRIVATE_KEY: Private key for deployment
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

    // Factories
    address public governanceFactory;
    address public accessFactory;
    address public modulesFactory;
    address public hatsTreeSetup;

    /*═══════════════════════════ MAIN DEPLOYMENT ═══════════════════════════*/

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

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
        address passkeyAccountImpl = address(new PasskeyAccount());
        address passkeyAccountFactoryImpl = address(new PasskeyAccountFactory());
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
        governanceFactory = address(new GovernanceFactory());
        accessFactory = address(new AccessFactory());
        modulesFactory = address(new ModulesFactory());
        hatsTreeSetup = address(new HatsTreeSetup());

        console.log("GovernanceFactory:", governanceFactory);
        console.log("AccessFactory:", accessFactory);
        console.log("ModulesFactory:", modulesFactory);
        console.log("HatsTreeSetup:", hatsTreeSetup);

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
            governanceFactory,
            accessFactory,
            modulesFactory,
            poaManager,
            orgRegistry,
            HATS_PROTOCOL,
            hatsTreeSetup,
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
        pm.addContractType("PasskeyAccount", passkeyAccountImpl);
        pm.addContractType("PasskeyAccountFactory", passkeyAccountFactoryImpl);

        console.log("\n--- Contract Types Registered ---");

        // Deploy global account registry
        address accRegBeacon = pm.getBeaconById(keccak256("UniversalAccountRegistry"));
        bytes memory accRegInit = abi.encodeWithSignature("initialize(address)", msg.sender);
        globalAccountRegistry = address(new BeaconProxy(accRegBeacon, accRegInit));
        console.log("GlobalAccountRegistry:", globalAccountRegistry);

        // Emit InfrastructureDeployed event for subgraph dynamic discovery
        address passkeyFactoryBeacon = pm.getBeaconById(keccak256("PasskeyAccountFactory"));
        pm.registerInfrastructure(
            orgDeployer, orgRegistry, implRegistry, paymasterHub, globalAccountRegistry, passkeyFactoryBeacon
        );
        console.log("\n--- Infrastructure Registered (for subgraph indexing) ---");
    }

    function _outputAddresses() internal {
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("\n--- Start Block (for subgraph indexing) ---");
        console.log("START_BLOCK:", block.number);

        console.log("\n--- Key Addresses for Org Deployment ---");
        console.log("OrgDeployer:", orgDeployer);
        console.log("GlobalAccountRegistry:", globalAccountRegistry);

        console.log("\n--- Infrastructure ---");
        console.log("PoaManager:", poaManager);
        console.log("OrgRegistry:", orgRegistry);
        console.log("ImplementationRegistry:", implRegistry);
        console.log("HatsProtocol:", HATS_PROTOCOL);

        // Log all beacon addresses for subgraph indexing
        console.log("\n--- Beacon Addresses (for subgraph indexing) ---");
        PoaManager pm = PoaManager(poaManager);
        console.log("BEACON_ImplementationRegistry:", pm.getBeaconById(keccak256("ImplementationRegistry")));
        console.log("BEACON_OrgRegistry:", pm.getBeaconById(keccak256("OrgRegistry")));
        console.log("BEACON_OrgDeployer:", pm.getBeaconById(keccak256("OrgDeployer")));
        console.log("BEACON_PaymasterHub:", pm.getBeaconById(keccak256("PaymasterHub")));
        console.log("BEACON_HybridVoting:", pm.getBeaconById(keccak256("HybridVoting")));
        console.log("BEACON_DirectDemocracyVoting:", pm.getBeaconById(keccak256("DirectDemocracyVoting")));
        console.log("BEACON_Executor:", pm.getBeaconById(keccak256("Executor")));
        console.log("BEACON_QuickJoin:", pm.getBeaconById(keccak256("QuickJoin")));
        console.log("BEACON_ParticipationToken:", pm.getBeaconById(keccak256("ParticipationToken")));
        console.log("BEACON_TaskManager:", pm.getBeaconById(keccak256("TaskManager")));
        console.log("BEACON_EducationHub:", pm.getBeaconById(keccak256("EducationHub")));
        console.log("BEACON_PaymentManager:", pm.getBeaconById(keccak256("PaymentManager")));
        console.log("BEACON_UniversalAccountRegistry:", pm.getBeaconById(keccak256("UniversalAccountRegistry")));
        console.log("BEACON_EligibilityModule:", pm.getBeaconById(keccak256("EligibilityModule")));
        console.log("BEACON_ToggleModule:", pm.getBeaconById(keccak256("ToggleModule")));
        console.log("BEACON_PasskeyAccount:", pm.getBeaconById(keccak256("PasskeyAccount")));
        console.log("BEACON_PasskeyAccountFactory:", pm.getBeaconById(keccak256("PasskeyAccountFactory")));

        // Write addresses to JSON file for easy org deployment
        // Split into parts to avoid stack depth issues
        string memory part1 = string.concat(
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
            '",\n'
        );

        string memory part2 = string.concat(
            '  "orgRegistry": "',
            vm.toString(orgRegistry),
            '",\n',
            '  "implRegistry": "',
            vm.toString(implRegistry),
            '",\n',
            '  "hatsProtocol": "',
            vm.toString(HATS_PROTOCOL),
            '",\n',
            '  "governanceFactory": "',
            vm.toString(governanceFactory),
            '",\n'
        );

        string memory part3 = string.concat(
            '  "accessFactory": "',
            vm.toString(accessFactory),
            '",\n',
            '  "modulesFactory": "',
            vm.toString(modulesFactory),
            '",\n',
            '  "hatsTreeSetup": "',
            vm.toString(hatsTreeSetup),
            '",\n',
            '  "passkeyAccountBeacon": "',
            vm.toString(pm.getBeaconById(keccak256("PasskeyAccount"))),
            '",\n',
            '  "passkeyAccountFactoryBeacon": "',
            vm.toString(pm.getBeaconById(keccak256("PasskeyAccountFactory"))),
            '"\n',
            "}\n"
        );

        string memory addressesJson = string.concat(part1, part2, part3);

        vm.writeFile("script/infrastructure.json", addressesJson);

        console.log("\n=== Addresses saved to script/infrastructure.json ===");
        console.log("\nTo deploy an org, simply run:");
        console.log("  forge script script/DeployOrg.s.sol:DeployOrg --rpc-url sepolia --broadcast");
        console.log("\n(No need to source anything - addresses are auto-loaded from infrastructure.json!)");
    }
}
