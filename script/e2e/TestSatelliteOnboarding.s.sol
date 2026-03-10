// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {SatelliteOnboardingHelper} from "../../src/crosschain/SatelliteOnboardingHelper.sol";
import {RegistryRelay} from "../../src/crosschain/RegistryRelay.sol";
import {OrgRegistry} from "../../src/OrgRegistry.sol";

/**
 * @title TestSatelliteOnboarding
 * @notice Verifies the satellite org deployment and onboarding infrastructure is
 *         correctly wired, and dispatches a username claim via the direct relay path.
 *
 *         Checks:
 *         1. Org exists in OrgRegistry
 *         2. SatelliteOnboardingHelper is deployed and authorized on relay
 *         3. Dispatches a username claim from the satellite
 *
 *         NOTE: Full optimistic onboarding (helper.registerAndJoin) requires the
 *         helper to be set as QuickJoin's masterDeployAddress via governance.
 *         This script tests the relay dispatch path which is the cross-chain part.
 *
 * Required env vars:
 *   PRIVATE_KEY
 *
 * Reads: script/e2e/e2e-state.json
 */
contract TestSatelliteOnboarding is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory state = vm.readFile("script/e2e/e2e-state.json");
        address helperAddr = vm.parseJsonAddress(state, ".satelliteOrg.onboardingHelper");
        address relayAddr = vm.parseJsonAddress(state, ".satellite.registryRelay");
        address orgRegistryAddr = vm.parseJsonAddress(state, ".satellite.orgRegistry");
        address executorAddr = vm.parseJsonAddress(state, ".satelliteOrg.executor");

        console.log("\n=== Test Satellite Onboarding Infrastructure ===");

        // 1. Verify org exists
        OrgRegistry orgReg = OrgRegistry(orgRegistryAddr);
        bytes32 orgId = keccak256("e2e-sat-org");
        (address orgExecutor,,, bool exists) = orgReg.orgOf(orgId);
        console.log("Org executor from registry:", orgExecutor);
        require(exists, "Org not found in registry");
        require(orgExecutor == executorAddr, "Executor mismatch");
        console.log("[PASS] Org deployed and registered");

        // 2. Verify helper is authorized on relay
        RegistryRelay relay = RegistryRelay(payable(relayAddr));
        bool authorized = relay.authorizedCallers(helperAddr);
        require(authorized, "Helper not authorized on relay");
        console.log("[PASS] Helper authorized on relay");

        // 3. Verify helper addresses
        SatelliteOnboardingHelper helper = SatelliteOnboardingHelper(helperAddr);
        require(address(helper.relay()) == relayAddr, "Helper relay mismatch");
        console.log("[PASS] Helper wired to relay");

        // 4. Dispatch a username claim via direct relay path
        vm.startBroadcast(deployerKey);
        relay.registerAccountDirect{value: 0.01 ether}("e2esatorguser");
        vm.stopBroadcast();
        console.log("[PASS] Username claim dispatched from satellite: e2esatorguser");

        console.log("\nPASS: Satellite onboarding infrastructure verified");
    }
}
