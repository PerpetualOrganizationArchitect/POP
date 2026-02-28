// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title DeployDeterministicDeployer
 * @notice Deploys the DeterministicDeployer via CREATE2 for a deterministic address.
 * @dev    Run this once per chain. The deployer address will be the same on every chain
 *         as long as the same deployer EOA and salt are used.
 *
 * Usage:
 *   forge script script/DeployDeterministicDeployer.s.sol:DeployDeterministicDeployer \
 *     --rpc-url $RPC_URL --broadcast --verify
 */
contract DeployDeterministicDeployer is Script {
    /// @dev Fixed salt for deterministic CREATE2 deployment across all chains.
    bytes32 public constant DEPLOYER_SALT = keccak256("POA_DETERMINISTIC_DEPLOYER_V1");

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        console.log("\n=== Deploying DeterministicDeployer ===");
        console.log("Deployer:", vm.addr(deployerKey));

        address deployerAddr = vm.addr(deployerKey);

        // Predict address before deploying
        // creationCode includes constructor args (owner address)
        bytes memory creationCode = abi.encodePacked(type(DeterministicDeployer).creationCode, abi.encode(deployerAddr));
        address predicted = vm.computeCreate2Address(
            DEPLOYER_SALT, keccak256(creationCode), 0x4e59b44847b379578588920cA78FbF26c0B4956C
        );
        console.log("Predicted address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed at:", predicted);
            console.log("\n=== DeterministicDeployer Deployment Complete ===");
            return;
        }

        vm.startBroadcast(deployerKey);

        // Deploy via Forge's canonical CREATE2 deployer (0x4e59b...)
        DeterministicDeployer deployer = new DeterministicDeployer{salt: DEPLOYER_SALT}(deployerAddr);

        vm.stopBroadcast();

        console.log("Deployed at:", address(deployer));
        require(address(deployer) == predicted, "Address mismatch");

        console.log("\n=== DeterministicDeployer Deployment Complete ===");
    }
}
