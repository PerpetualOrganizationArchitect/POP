// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

/**
 * @title VerifyUpgrade
 * @notice Read-only verification that the HybridVoting beacon points to the V2 implementation.
 *         Reverts if not yet upgraded (shell script checks exit code for polling).
 *
 * Required env vars:
 *   POAMANAGER, DETERMINISTIC_DEPLOYER
 */
contract VerifyUpgrade is Script {
    function run() public view {
        address pmAddr = vm.envAddress("POAMANAGER");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        PoaManager pm = PoaManager(pmAddr);
        DeterministicDeployer dd = DeterministicDeployer(ddAddr);

        bytes32 typeId = keccak256(bytes("HybridVoting"));
        address currentImpl = pm.getCurrentImplementationById(typeId);

        bytes32 salt = dd.computeSalt("HybridVoting", "v2");
        address expectedV2 = dd.computeAddress(salt);

        console.log("=== Verify Upgrade ===");
        console.log("PoaManager:", pmAddr);
        console.log("Current impl:", currentImpl);
        console.log("Expected V2:", expectedV2);

        if (currentImpl == expectedV2) {
            console.log("PASS: Beacon upgraded to V2");
        } else {
            revert("PENDING: Beacon not yet upgraded to V2");
        }
    }
}
