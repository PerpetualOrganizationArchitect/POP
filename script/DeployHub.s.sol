// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";

/**
 * @title DeployHub
 * @notice Deploys PoaManagerHub on the home chain via BeaconProxy and transfers
 *         PoaManager ownership to it.
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
        address deployer = vm.addr(deployerKey);

        console.log("\n=== Deploying PoaManagerHub ===");
        console.log("Deployer:", deployer);
        console.log("PoaManager:", poaManagerAddr);
        console.log("Mailbox:", mailboxAddr);

        vm.startBroadcast(deployerKey);

        // 1. Deploy PoaManagerHub implementation and register type
        PoaManager pm = PoaManager(poaManagerAddr);
        address hubImpl = address(new PoaManagerHub());
        pm.addContractType("PoaManagerHub", hubImpl);

        // 2. Deploy PoaManagerHub behind BeaconProxy
        address hubBeacon = pm.getBeaconById(keccak256("PoaManagerHub"));
        bytes memory hubInit = abi.encodeCall(PoaManagerHub.initialize, (deployer, poaManagerAddr, mailboxAddr));
        PoaManagerHub hub = PoaManagerHub(payable(address(new BeaconProxy(hubBeacon, hubInit))));
        console.log("PoaManagerHub deployed:", address(hub));

        // 3. Transfer PoaManager ownership to Hub
        pm.transferOwnership(address(hub));
        console.log("PoaManager ownership transferred to Hub");

        vm.stopBroadcast();

        console.log("\n=== Hub Deployment Complete ===");
        console.log("Hub address:", address(hub));
        console.log("\nNext steps:");
        console.log("  1. Deploy satellite infrastructure on remote chains");
        console.log("  2. Register satellites: hub.registerSatellite(domain, satelliteAddr)");
    }
}
