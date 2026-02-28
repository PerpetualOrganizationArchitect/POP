// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";

/**
 * @title DeployHub
 * @notice Deploys PoaManagerHub on the home chain and transfers PoaManager ownership to it.
 * @dev    Requires existing infrastructure (PoaManager) and a Hyperlane Mailbox address.
 *
 * Usage:
 *   POAMANAGER=0x... MAILBOX=0x... \
 *   forge script script/DeployHub.s.sol:DeployHub \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployHub is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address poaManagerAddr = vm.envAddress("POAMANAGER");
        address mailboxAddr = vm.envAddress("MAILBOX");

        console.log("\n=== Deploying PoaManagerHub ===");
        console.log("Deployer:", vm.addr(deployerKey));
        console.log("PoaManager:", poaManagerAddr);
        console.log("Mailbox:", mailboxAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy Hub
        PoaManagerHub hub = new PoaManagerHub(poaManagerAddr, mailboxAddr);
        console.log("PoaManagerHub deployed:", address(hub));

        // 2. Transfer PoaManager ownership to Hub
        PoaManager(poaManagerAddr).transferOwnership(address(hub));
        console.log("PoaManager ownership transferred to Hub");

        vm.stopBroadcast();

        console.log("\n=== Hub Deployment Complete ===");
        console.log("Hub address:", address(hub));
        console.log("\nNext steps:");
        console.log("  1. Deploy satellite infrastructure on remote chains");
        console.log("  2. Register satellites: hub.registerSatellite(domain, satelliteAddr)");
    }
}
