// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {RegistryRelay} from "../../src/crosschain/RegistryRelay.sol";

/**
 * @title VerifySatelliteOrgName
 * @notice Read-only verification that a cross-chain org name claim was confirmed
 *         back on the satellite relay via Hyperlane round-trip. The org deploys
 *         optimistically before this confirmation arrives. Reverts if not yet
 *         confirmed (shell script checks exit code for polling).
 *
 * Required env vars:
 *   RELAY, ORG_NAME
 */
contract VerifySatelliteOrgName is Script {
    function run() public view {
        address relayAddr = vm.envAddress("RELAY");
        string memory orgName = vm.envString("ORG_NAME");

        RegistryRelay relay = RegistryRelay(payable(relayAddr));

        bool confirmed = relay.isOrgNameConfirmed(orgName);

        console.log("=== Verify Satellite Org Name ===");
        console.log("Relay:", relayAddr);
        console.log("Org name:", orgName);
        console.log("Confirmed:", confirmed);

        if (confirmed) {
            console.log("PASS: Org name confirmed on satellite");
        } else {
            revert("PENDING: Org name not yet confirmed on satellite");
        }
    }
}
