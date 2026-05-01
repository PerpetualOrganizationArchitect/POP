// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {EOADelegation} from "../../src/EOADelegation.sol";

/**
 * @title DeployEOADelegation
 * @notice Deploy EOADelegation via DeterministicDeployer (same address on all chains).
 *         No constructor args, no proxy, no upgradeability.
 *
 * Usage (run on each chain):
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/DeployEOADelegation.s.sol:DeployEOADelegation \
 *     --rpc-url gnosis --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract DeployEOADelegation is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant TYPE_NAME = "EOADelegation";
    string constant VERSION = "v1";

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        bytes32 salt = dd.computeSalt(TYPE_NAME, VERSION);
        address predicted = dd.computeAddress(salt);

        console.log("=== Deploy EOADelegation ===");
        console.log("Predicted address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed.");
            return;
        }

        vm.startBroadcast(deployerKey);
        dd.deploy(salt, type(EOADelegation).creationCode);
        vm.stopBroadcast();

        console.log("Deployed. Size:", predicted.code.length, "bytes");
        console.log("Run on other chains with same script to get same address.");
    }
}
