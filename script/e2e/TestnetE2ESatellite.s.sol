// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {PoaManager} from "../../src/PoaManager.sol";
import {ImplementationRegistry} from "../../src/ImplementationRegistry.sol";
import {PoaManagerSatellite} from "../../src/crosschain/PoaManagerSatellite.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {HybridVoting} from "../../src/HybridVoting.sol";

/**
 * @title TestnetE2ESatellite
 * @notice Deploys minimal satellite infrastructure for E2E cross-chain testing.
 *         Deploys: PoaManager, ImplementationRegistry, HybridVoting v1 (via DeterministicDeployer),
 *         PoaManagerSatellite, and transfers PoaManager ownership to Satellite.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER, HUB_DOMAIN, HUB_ADDRESS, MAILBOX
 *
 * Reads:  script/e2e/e2e-state.json
 * Writes: script/e2e/e2e-state.json (full state with satellite section)
 */
contract TestnetE2ESatellite is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");
        uint32 hubDomain = uint32(vm.envUint("HUB_DOMAIN"));
        address hubAddress = vm.envAddress("HUB_ADDRESS");
        address mailboxAddr = vm.envAddress("MAILBOX");

        console.log("\n=== E2E Satellite Setup ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("Hub domain:", hubDomain);
        console.log("Hub address:", hubAddress);
        console.log("Mailbox:", mailboxAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy PoaManager with temp zero registry
        PoaManager pm = new PoaManager(address(0));
        console.log("PoaManager:", address(pm));

        // 2. Deploy ImplementationRegistry behind beacon
        ImplementationRegistry regImpl = new ImplementationRegistry();
        pm.addContractType("ImplementationRegistry", address(regImpl));
        address regBeacon = pm.getBeaconById(keccak256("ImplementationRegistry"));
        bytes memory regInit = abi.encodeWithSignature("initialize(address)", vm.addr(deployerKey));
        ImplementationRegistry reg = ImplementationRegistry(address(new BeaconProxy(regBeacon, regInit)));
        pm.updateImplRegistry(address(reg));
        reg.registerImplementation("ImplementationRegistry", "v1", address(regImpl), true);
        reg.transferOwnership(address(pm));
        console.log("ImplementationRegistry:", address(reg));

        // 3. Deploy HybridVoting v1 via DeterministicDeployer (same address as home chain)
        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("HybridVoting", "v1");
        address predicted = dd.computeAddress(salt);
        address hvImpl;
        if (predicted.code.length > 0) {
            hvImpl = predicted;
            console.log("HybridVoting v1 already deployed:", hvImpl);
        } else {
            hvImpl = dd.deploy(salt, type(HybridVoting).creationCode);
            console.log("HybridVoting v1 deployed:", hvImpl);
        }
        pm.addContractType("HybridVoting", hvImpl);

        // 4. Deploy PoaManagerSatellite
        PoaManagerSatellite satellite = new PoaManagerSatellite(address(pm), mailboxAddr, hubDomain, hubAddress);
        console.log("PoaManagerSatellite:", address(satellite));

        // 5. Transfer PoaManager ownership to Satellite
        pm.transferOwnership(address(satellite));
        console.log("PoaManager ownership transferred to Satellite");

        vm.stopBroadcast();

        // 6. Read existing home chain state and merge
        string memory existing = vm.readFile("script/e2e/e2e-state.json");
        address homePm = vm.parseJsonAddress(existing, ".homeChain.poaManager");
        address homeReg = vm.parseJsonAddress(existing, ".homeChain.implRegistry");
        address homeHub = vm.parseJsonAddress(existing, ".homeChain.hub");
        address homeHv = vm.parseJsonAddress(existing, ".homeChain.hybridVotingV1");

        string memory json = string.concat(
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
            '",\n',
            '    "hybridVotingV1": "',
            vm.toString(homeHv),
            '"\n',
            "  },\n"
        );

        string memory json2 = string.concat(
            '  "satellite": {\n',
            '    "poaManager": "',
            vm.toString(address(pm)),
            '",\n',
            '    "implRegistry": "',
            vm.toString(address(reg)),
            '",\n',
            '    "satellite": "',
            vm.toString(address(satellite)),
            '",\n',
            '    "hybridVotingV1": "',
            vm.toString(hvImpl),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("script/e2e/e2e-state.json", string.concat(json, json2));

        console.log("\n=== Satellite E2E Setup Complete ===");
        console.log("State written to script/e2e/e2e-state.json");
    }
}
