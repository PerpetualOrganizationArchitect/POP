// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {PoaManager} from "../../src/PoaManager.sol";
import {ImplementationRegistry} from "../../src/ImplementationRegistry.sol";
import {UniversalAccountRegistry} from "../../src/UniversalAccountRegistry.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {NameRegistryHub} from "../../src/crosschain/NameRegistryHub.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {HybridVoting} from "../../src/HybridVoting.sol";

/**
 * @title TestnetE2EHomeChain
 * @notice Deploys minimal home-chain infrastructure for E2E cross-chain testing.
 *         Deploys: PoaManager, ImplementationRegistry, HybridVoting v1 (via DeterministicDeployer),
 *         PoaManagerHub, UniversalAccountRegistry, NameRegistryHub, and transfers PoaManager
 *         ownership to Hub.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER, MAILBOX
 *
 * Writes: script/e2e/e2e-state.json
 */
contract TestnetE2EHomeChain is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");
        address mailboxAddr = vm.envAddress("MAILBOX");

        console.log("\n=== E2E Home Chain Setup ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("DeterministicDeployer:", ddAddr);
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

        // 3. Deploy HybridVoting v1 via DeterministicDeployer
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

        // 4. Deploy UniversalAccountRegistry behind beacon
        // (must happen before ownership transfer since addContractType is onlyOwner)
        address uarImpl = address(new UniversalAccountRegistry());
        pm.addContractType("UniversalAccountRegistry", uarImpl);
        address uarBeacon = pm.getBeaconById(keccak256("UniversalAccountRegistry"));
        bytes memory uarInit = abi.encodeWithSignature("initialize(address)", vm.addr(deployerKey));
        UniversalAccountRegistry uar = UniversalAccountRegistry(address(new BeaconProxy(uarBeacon, uarInit)));
        console.log("UniversalAccountRegistry:", address(uar));

        // 5. Deploy PoaManagerHub
        PoaManagerHub hub = new PoaManagerHub(address(pm), mailboxAddr);
        console.log("PoaManagerHub:", address(hub));

        // 6. Transfer PoaManager ownership to Hub
        pm.transferOwnership(address(hub));
        console.log("PoaManager ownership transferred to Hub");

        // 7. Deploy NameRegistryHub and wire to UAR
        NameRegistryHub nameHub = new NameRegistryHub(address(uar), mailboxAddr);
        uar.setNameRegistryHub(address(nameHub));
        console.log("NameRegistryHub:", address(nameHub));
        console.log("UAR wired to NameRegistryHub");

        vm.stopBroadcast();

        // 8. Write state JSON (step numbers above shifted: UAR=4, Hub=5, Transfer=6, NameHub=7)
        string memory json1 = string.concat(
            "{\n",
            '  "deterministicDeployer": "',
            vm.toString(ddAddr),
            '",\n',
            '  "homeChain": {\n',
            '    "poaManager": "',
            vm.toString(address(pm)),
            '",\n',
            '    "implRegistry": "',
            vm.toString(address(reg)),
            '",\n',
            '    "hub": "',
            vm.toString(address(hub)),
            '",\n'
        );

        string memory json2 = string.concat(
            '    "hybridVotingV1": "',
            vm.toString(hvImpl),
            '",\n',
            '    "uar": "',
            vm.toString(address(uar)),
            '",\n',
            '    "nameRegistryHub": "',
            vm.toString(address(nameHub)),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("script/e2e/e2e-state.json", string.concat(json1, json2));

        console.log("\n=== Home Chain E2E Setup Complete ===");
        console.log("State written to script/e2e/e2e-state.json");
    }
}
