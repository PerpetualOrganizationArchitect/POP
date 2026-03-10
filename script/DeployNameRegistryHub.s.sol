// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {NameRegistryHub} from "../src/crosschain/NameRegistryHub.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {PoaManager} from "../src/PoaManager.sol";

/**
 * @title DeployNameRegistryHub
 * @notice Deploys NameRegistryHub on Arbitrum (home chain) via BeaconProxy and wires
 *         it to the existing UniversalAccountRegistry.
 *
 * Usage:
 *   UAR=0x... MAILBOX=0x... POA_MANAGER=0x... \
 *   forge script script/DeployNameRegistryHub.s.sol:DeployNameRegistryHub \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployNameRegistryHub is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address uarAddr = vm.envAddress("UAR");
        address mailboxAddr = vm.envAddress("MAILBOX");
        address poaManagerAddr = vm.envAddress("POA_MANAGER");
        address deployer = vm.addr(deployerKey);

        console.log("\n=== Deploying NameRegistryHub ===");
        console.log("Deployer:", deployer);
        console.log("UAR:", uarAddr);
        console.log("Mailbox:", mailboxAddr);
        console.log("PoaManager:", poaManagerAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy NameRegistryHub implementation and register type
        PoaManager pm = PoaManager(poaManagerAddr);
        address nameHubImpl = address(new NameRegistryHub());
        pm.addContractType("NameRegistryHub", nameHubImpl);

        // 2. Deploy NameRegistryHub behind BeaconProxy
        address nameHubBeacon = pm.getBeaconById(keccak256("NameRegistryHub"));
        bytes memory nameHubInit = abi.encodeCall(NameRegistryHub.initialize, (deployer, uarAddr, mailboxAddr));
        NameRegistryHub hub = NameRegistryHub(payable(address(new BeaconProxy(nameHubBeacon, nameHubInit))));
        console.log("NameRegistryHub deployed:", address(hub));

        // 3. Wire UAR to hub (enables global uniqueness checks)
        UniversalAccountRegistry(uarAddr).setNameRegistryHub(address(hub));
        console.log("UAR.nameRegistryHub set to hub");

        vm.stopBroadcast();

        console.log("\n=== NameRegistryHub Deployment Complete ===");
        console.log("Hub address:", address(hub));
        console.log("\nNext steps:");
        console.log("  1. Fund hub with ETH for return-trip Hyperlane fees");
        console.log("  2. Set return fee: hub.setReturnFee(fee)");
        console.log("  3. Deploy RegistryRelay on satellite chains");
        console.log("  4. Register relays: hub.registerSatellite(domain, relayAddr)");
    }
}
