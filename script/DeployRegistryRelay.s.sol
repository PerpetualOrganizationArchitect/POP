// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {RegistryRelay} from "../src/crosschain/RegistryRelay.sol";

/**
 * @title DeployRegistryRelay
 * @notice Deploys a RegistryRelay on a satellite chain, pointed at the
 *         NameRegistryHub on Arbitrum.
 *
 * Usage:
 *   MAILBOX=0x... HUB_DOMAIN=42161 HUB_ADDRESS=0x... \
 *   forge script script/DeployRegistryRelay.s.sol:DeployRegistryRelay \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployRegistryRelay is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address mailboxAddr = vm.envAddress("MAILBOX");
        uint32 hubDomain = uint32(vm.envUint("HUB_DOMAIN"));
        address hubAddress = vm.envAddress("HUB_ADDRESS");

        console.log("\n=== Deploying RegistryRelay ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("Mailbox:", mailboxAddr);
        console.log("Hub domain:", hubDomain);
        console.log("Hub address:", hubAddress);

        vm.startBroadcast(deployerKey);

        RegistryRelay relay = new RegistryRelay(mailboxAddr, hubDomain, hubAddress);
        console.log("RegistryRelay deployed:", address(relay));

        vm.stopBroadcast();

        console.log("\n=== RegistryRelay Deployment Complete ===");
        console.log("Relay address:", address(relay));
        console.log("\nNext steps:");
        console.log("  1. Register on hub: hub.registerSatellite(<this_chain_domain>,", address(relay), ")");
    }
}
