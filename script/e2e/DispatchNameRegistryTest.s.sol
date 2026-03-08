// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {RegistryRelay} from "../../src/crosschain/RegistryRelay.sol";

/**
 * @title DispatchNameRegistryTest
 * @notice Dispatches test username + org name claims from the satellite relay.
 *         After Hyperlane relays these messages, VerifyNameRegistry checks results
 *         on the home chain.
 *
 * Required env vars:
 *   PRIVATE_KEY, RELAY
 */
contract DispatchNameRegistryTest is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address relayAddr = vm.envAddress("RELAY");

        RegistryRelay relay = RegistryRelay(relayAddr);

        console.log("\n=== Dispatching Name Registry Tests ===");
        console.log("Relay:", relayAddr);
        console.log("User:", vm.addr(deployerKey));

        vm.startBroadcast(deployerKey);

        // 1. Register a username via direct registration
        relay.registerAccountDirect{value: 0.01 ether}("e2etestuser");
        console.log("Username claim dispatched: e2etestuser");

        // 2. Claim an org name (deployer is relay owner)
        relay.claimOrgName{value: 0.01 ether}("E2ETestOrg");
        console.log("Org name claim dispatched: E2ETestOrg");

        vm.stopBroadcast();

        console.log("\n=== Name Registry Tests Dispatched ===");
    }
}
