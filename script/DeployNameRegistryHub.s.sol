// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {NameRegistryHub} from "../src/crosschain/NameRegistryHub.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";

/**
 * @title DeployNameRegistryHub
 * @notice Deploys NameRegistryHub on Arbitrum (home chain) and wires it to the
 *         existing UniversalAccountRegistry.
 *
 * Usage:
 *   UAR=0x... MAILBOX=0x... \
 *   forge script script/DeployNameRegistryHub.s.sol:DeployNameRegistryHub \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployNameRegistryHub is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address uarAddr = vm.envAddress("UAR");
        address mailboxAddr = vm.envAddress("MAILBOX");

        console.log("\n=== Deploying NameRegistryHub ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("UAR:", uarAddr);
        console.log("Mailbox:", mailboxAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy NameRegistryHub
        NameRegistryHub hub = new NameRegistryHub(uarAddr, mailboxAddr);
        console.log("NameRegistryHub deployed:", address(hub));

        // 2. Wire UAR to hub (enables global uniqueness checks)
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
