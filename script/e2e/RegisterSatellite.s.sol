// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {NameRegistryHub} from "../../src/crosschain/NameRegistryHub.sol";

/**
 * @title RegisterSatellite
 * @notice Registers a satellite on the PoaManagerHub and a RegistryRelay on the
 *         NameRegistryHub. Run on the home chain.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, NAME_HUB, SATELLITE_DOMAIN, SATELLITE_ADDRESS, RELAY_ADDRESS
 */
contract RegisterSatellite is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address nameHubAddr = vm.envAddress("NAME_HUB");
        uint32 satDomain = uint32(vm.envUint("SATELLITE_DOMAIN"));
        address satAddr = vm.envAddress("SATELLITE_ADDRESS");
        address relayAddr = vm.envAddress("RELAY_ADDRESS");

        console.log("\n=== Registering Satellite ===");
        console.log("PoaManagerHub:", hubAddr);
        console.log("NameRegistryHub:", nameHubAddr);
        console.log("Satellite domain:", satDomain);
        console.log("Satellite address:", satAddr);
        console.log("Relay address:", relayAddr);

        vm.startBroadcast(deployerKey);

        PoaManagerHub(payable(hubAddr)).registerSatellite(satDomain, satAddr);
        console.log("PoaManagerSatellite registered");

        NameRegistryHub(payable(nameHubAddr)).registerSatellite(satDomain, relayAddr);
        console.log("RegistryRelay registered");

        vm.stopBroadcast();

        console.log("Satellites registered successfully");
    }
}
