// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";

/**
 * @title RegisterSatellite
 * @notice Registers a satellite on the Hub. Run on the home chain.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, SATELLITE_DOMAIN, SATELLITE_ADDRESS
 */
contract RegisterSatellite is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        uint32 satDomain = uint32(vm.envUint("SATELLITE_DOMAIN"));
        address satAddr = vm.envAddress("SATELLITE_ADDRESS");

        console.log("\n=== Registering Satellite ===");
        console.log("Hub:", hubAddr);
        console.log("Satellite domain:", satDomain);
        console.log("Satellite address:", satAddr);

        vm.startBroadcast(deployerKey);
        PoaManagerHub(hubAddr).registerSatellite(satDomain, satAddr);
        vm.stopBroadcast();

        console.log("Satellite registered successfully");
    }
}
