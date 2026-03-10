// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {DeployHelper} from "../helpers/DeployHelper.s.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {ImplementationRegistry} from "../../src/ImplementationRegistry.sol";
import {OrgRegistry} from "../../src/OrgRegistry.sol";
import {OrgDeployer} from "../../src/OrgDeployer.sol";
import {PaymasterHub} from "../../src/PaymasterHub.sol";
import {PoaManagerSatellite} from "../../src/crosschain/PoaManagerSatellite.sol";
import {RegistryRelay} from "../../src/crosschain/RegistryRelay.sol";
import {NameClaimAdapter} from "../../src/crosschain/NameClaimAdapter.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {HybridVoting} from "../../src/HybridVoting.sol";
import {GovernanceFactory} from "../../src/factories/GovernanceFactory.sol";
import {AccessFactory} from "../../src/factories/AccessFactory.sol";
import {ModulesFactory} from "../../src/factories/ModulesFactory.sol";
import {HatsTreeSetup} from "../../src/HatsTreeSetup.sol";

/**
 * @title TestnetE2ESatellite
 * @notice Deploys full satellite infrastructure for E2E cross-chain testing.
 *         Deploys: PoaManager, ImplementationRegistry, all contract types (via DD),
 *         PoaManagerSatellite, RegistryRelay, NameClaimAdapter, OrgRegistry, OrgDeployer,
 *         factories, PaymasterHub, and transfers PoaManager ownership to Satellite.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER, HUB_DOMAIN, HUB_ADDRESS, MAILBOX
 *
 * Reads:  script/e2e/e2e-state.json
 * Writes: script/e2e/e2e-state.json (full state with satellite section)
 */
contract TestnetE2ESatellite is DeployHelper {
    address public constant HATS_PROTOCOL = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
    address public constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    uint256 public constant INITIAL_SOLIDARITY_FUND = 0.01 ether;

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");
        uint32 hubDomain = uint32(vm.envUint("HUB_DOMAIN"));
        address hubAddress = vm.envAddress("HUB_ADDRESS");
        address mailboxAddr = vm.envAddress("MAILBOX");

        // Read home chain state for NameRegistryHub address
        string memory existing = vm.readFile("script/e2e/e2e-state.json");
        address nameHubAddress = vm.parseJsonAddress(existing, ".homeChain.nameRegistryHub");

        console.log("\n=== E2E Satellite Setup ===");
        console.log("Deployer:", deployer);
        console.log("Hub domain:", hubDomain);
        console.log("Hub address:", hubAddress);
        console.log("NameRegistryHub:", nameHubAddress);
        console.log("Mailbox:", mailboxAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy PoaManager with temp zero registry
        PoaManager pm = new PoaManager(address(0));
        console.log("PoaManager:", address(pm));

        // 2. Deploy ImplementationRegistry behind beacon
        ImplementationRegistry regImpl = new ImplementationRegistry();
        pm.addContractType("ImplementationRegistry", address(regImpl));
        address regBeacon = pm.getBeaconById(keccak256("ImplementationRegistry"));
        bytes memory regInit = abi.encodeWithSignature("initialize(address)", deployer);
        ImplementationRegistry reg = ImplementationRegistry(address(new BeaconProxy(regBeacon, regInit)));
        pm.updateImplRegistry(address(reg));
        reg.registerImplementation("ImplementationRegistry", "v1", address(regImpl), true);
        reg.transferOwnership(address(pm));
        console.log("ImplementationRegistry:", address(reg));

        // 3. Deploy all application types via DeterministicDeployer
        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        _deployAndRegisterTypesDD(pm, dd);

        // Also deploy HybridVoting v1 via DD for cross-chain upgrade testing
        bytes32 hvSalt = dd.computeSalt("HybridVoting", "v1");
        address hvPredicted = dd.computeAddress(hvSalt);
        address hvImpl;
        if (hvPredicted.code.length > 0) {
            hvImpl = hvPredicted;
            console.log("HybridVoting v1 already deployed:", hvImpl);
        } else {
            hvImpl = dd.deploy(hvSalt, type(HybridVoting).creationCode);
            console.log("HybridVoting v1 deployed:", hvImpl);
        }

        // 4. Deploy PoaManagerSatellite via BeaconProxy
        address satImpl = address(new PoaManagerSatellite());
        pm.addContractType("PoaManagerSatellite", satImpl);
        address satBeacon = pm.getBeaconById(keccak256("PoaManagerSatellite"));
        bytes memory satInit =
            abi.encodeCall(PoaManagerSatellite.initialize, (deployer, address(pm), mailboxAddr, hubDomain, hubAddress));
        PoaManagerSatellite satellite = PoaManagerSatellite(payable(address(new BeaconProxy(satBeacon, satInit))));
        console.log("PoaManagerSatellite:", address(satellite));

        // 5. Deploy RegistryRelay via BeaconProxy (points to NameRegistryHub on home chain)
        address relayImpl = address(new RegistryRelay());
        pm.addContractType("RegistryRelay", relayImpl);
        address relayBeacon = pm.getBeaconById(keccak256("RegistryRelay"));
        bytes memory relayInit =
            abi.encodeCall(RegistryRelay.initialize, (deployer, mailboxAddr, hubDomain, nameHubAddress));
        RegistryRelay relay = RegistryRelay(payable(address(new BeaconProxy(relayBeacon, relayInit))));
        console.log("RegistryRelay:", address(relay));

        // 6. Deploy NameClaimAdapter (bridges OrgRegistry to RegistryRelay)
        address adapterBeacon = pm.getBeaconById(keccak256("NameClaimAdapter"));
        bytes memory adapterInit = abi.encodeCall(NameClaimAdapter.initialize, (deployer, address(relay)));
        NameClaimAdapter nameClaimAdapter = NameClaimAdapter(address(new BeaconProxy(adapterBeacon, adapterInit)));
        console.log("NameClaimAdapter:", address(nameClaimAdapter));

        // 7. Deploy OrgRegistry + OrgDeployer for satellite org creation
        address orgRegBeacon = pm.getBeaconById(keccak256("OrgRegistry"));
        bytes memory orgRegInit = abi.encodeWithSignature("initialize(address,address)", deployer, HATS_PROTOCOL);
        OrgRegistry satOrgRegistry = OrgRegistry(address(new BeaconProxy(orgRegBeacon, orgRegInit)));
        satOrgRegistry.setNameRegistryHub(address(nameClaimAdapter));
        nameClaimAdapter.setAuthorizedCaller(address(satOrgRegistry), true);
        relay.setAuthorizedCaller(address(nameClaimAdapter), true);
        console.log("OrgRegistry:", address(satOrgRegistry));
        console.log("NameClaimAdapter authorized on relay for optimistic org name dispatch");

        // 8. Deploy factories (stateless)
        address govFactory = address(new GovernanceFactory());
        address accFactory = address(new AccessFactory());
        address modFactory = address(new ModulesFactory());
        address hatsSetup = address(new HatsTreeSetup());
        console.log("Factories deployed");

        // 9. Deploy PaymasterHub
        address paymasterHubImpl = address(new PaymasterHub());
        pm.addContractType("PaymasterHub", paymasterHubImpl);
        address paymasterHubBeacon = pm.getBeaconById(keccak256("PaymasterHub"));
        bytes memory paymasterHubInit =
            abi.encodeWithSignature("initialize(address,address,address)", ENTRY_POINT_V07, HATS_PROTOCOL, address(pm));
        address satPaymasterHub = address(new BeaconProxy(paymasterHubBeacon, paymasterHubInit));
        PaymasterHub(payable(satPaymasterHub)).donateToSolidarity{value: INITIAL_SOLIDARITY_FUND}();
        console.log("PaymasterHub:", satPaymasterHub);

        // 10. Deploy OrgDeployer
        address deployerBeacon = pm.getBeaconById(keccak256("OrgDeployer"));
        address orgDeployerImpl = address(new OrgDeployer());
        pm.addContractType("OrgDeployer", orgDeployerImpl);
        deployerBeacon = pm.getBeaconById(keccak256("OrgDeployer"));
        bytes memory orgDeployerInit = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address)",
            govFactory,
            accFactory,
            modFactory,
            address(pm),
            address(satOrgRegistry),
            HATS_PROTOCOL,
            hatsSetup,
            satPaymasterHub
        );
        address satOrgDeployer = address(new BeaconProxy(deployerBeacon, orgDeployerInit));
        console.log("OrgDeployer:", satOrgDeployer);

        // Transfer OrgRegistry ownership to OrgDeployer
        satOrgRegistry.transferOwnership(satOrgDeployer);

        // Authorize OrgDeployer on PaymasterHub
        pm.adminCall(satPaymasterHub, abi.encodeWithSignature("setOrgRegistrar(address)", satOrgDeployer));

        // Deploy PasskeyAccountFactory
        address passkeyAccountBeacon = pm.getBeaconById(keccak256("PasskeyAccount"));
        address passkeyFactoryBeaconAddr = pm.getBeaconById(keccak256("PasskeyAccountFactory"));
        bytes memory passkeyFactoryInit = abi.encodeWithSignature(
            "initialize(address,address,address,uint48)",
            address(pm),
            passkeyAccountBeacon,
            address(0), // no guardian
            uint48(7 days)
        );
        address satPasskeyFactory = address(new BeaconProxy(passkeyFactoryBeaconAddr, passkeyFactoryInit));
        pm.adminCall(satOrgDeployer, abi.encodeWithSignature("setUniversalPasskeyFactory(address)", satPasskeyFactory));
        console.log("PasskeyAccountFactory:", satPasskeyFactory);

        // Register infrastructure for subgraph indexing
        pm.registerInfrastructure(
            satOrgDeployer, address(satOrgRegistry), address(reg), satPaymasterHub, address(relay), satPasskeyFactory
        );
        console.log("Infrastructure registered for indexing");

        // 11. Transfer PoaManager ownership to Satellite (after all types registered)
        pm.transferOwnership(address(satellite));
        console.log("PoaManager ownership transferred to Satellite");

        vm.stopBroadcast();

        // 12. Write state JSON (merge with home chain)
        _writeState(
            existing, ddAddr, pm, reg, satellite, relay, nameClaimAdapter, satOrgRegistry, satOrgDeployer, hvImpl
        );

        console.log("\n=== Satellite E2E Setup Complete ===");
        console.log("State written to script/e2e/e2e-state.json");
    }

    function _writeState(
        string memory existing,
        address ddAddr,
        PoaManager pm,
        ImplementationRegistry reg,
        PoaManagerSatellite satellite,
        RegistryRelay relay,
        NameClaimAdapter nameClaimAdapter,
        OrgRegistry satOrgRegistry,
        address satOrgDeployer,
        address hvImpl
    ) internal {
        address homePm = vm.parseJsonAddress(existing, ".homeChain.poaManager");
        address homeReg = vm.parseJsonAddress(existing, ".homeChain.implRegistry");
        address homeHub = vm.parseJsonAddress(existing, ".homeChain.hub");
        address homeHv = vm.parseJsonAddress(existing, ".homeChain.hybridVotingV1");
        address homeUar = vm.parseJsonAddress(existing, ".homeChain.uar");
        address nameHubAddress = vm.parseJsonAddress(existing, ".homeChain.nameRegistryHub");

        string memory json1 = string.concat(
            "{\n",
            '  "deterministicDeployer": "',
            vm.toString(ddAddr),
            '",\n',
            '  "homeChain": {\n',
            '    "poaManager": "',
            vm.toString(homePm),
            '",\n',
            '    "implRegistry": "',
            vm.toString(homeReg),
            '",\n',
            '    "hub": "',
            vm.toString(homeHub),
            '",\n'
        );

        string memory json2 = string.concat(
            '    "hybridVotingV1": "',
            vm.toString(homeHv),
            '",\n',
            '    "uar": "',
            vm.toString(homeUar),
            '",\n',
            '    "nameRegistryHub": "',
            vm.toString(nameHubAddress),
            '"\n',
            "  },\n"
        );

        string memory json3 = string.concat(
            '  "satellite": {\n',
            '    "poaManager": "',
            vm.toString(address(pm)),
            '",\n',
            '    "implRegistry": "',
            vm.toString(address(reg)),
            '",\n',
            '    "satellite": "',
            vm.toString(address(satellite)),
            '",\n'
        );

        string memory json4 = string.concat(
            '    "registryRelay": "',
            vm.toString(address(relay)),
            '",\n',
            '    "nameClaimAdapter": "',
            vm.toString(address(nameClaimAdapter)),
            '",\n',
            '    "orgRegistry": "',
            vm.toString(address(satOrgRegistry)),
            '",\n'
        );

        string memory json5 = string.concat(
            '    "orgDeployer": "',
            vm.toString(satOrgDeployer),
            '",\n',
            '    "hybridVotingV1": "',
            vm.toString(hvImpl),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("script/e2e/e2e-state.json", string.concat(json1, json2, json3, json4, json5));
    }
}
