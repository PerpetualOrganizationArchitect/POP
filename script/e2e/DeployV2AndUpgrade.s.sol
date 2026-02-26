// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {HybridVoting} from "../../src/HybridVoting.sol";

/**
 * @title DeployV2Impl
 * @notice Deploys HybridVoting v2 via DeterministicDeployer on the current chain.
 *         Run on BOTH home and satellite chains before triggering the upgrade.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER
 */
contract DeployV2Impl is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("HybridVoting", "v2");
        address predicted = dd.computeAddress(salt);

        console.log("\n=== Deploying HybridVoting v2 ===");
        console.log("Predicted address:", predicted);

        vm.startBroadcast(deployerKey);

        if (predicted.code.length > 0) {
            console.log("Already deployed at:", predicted);
        } else {
            address deployed = dd.deploy(salt, type(HybridVoting).creationCode);
            console.log("Deployed at:", deployed);
        }

        vm.stopBroadcast();
    }
}

/**
 * @title TriggerCrossChainUpgrade
 * @notice Triggers a cross-chain upgrade from the Hub. Run on the home chain only.
 *         The Hub upgrades locally and dispatches Hyperlane messages to all satellites.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, DETERMINISTIC_DEPLOYER
 */
contract TriggerCrossChainUpgrade is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("HybridVoting", "v2");
        address newImpl = dd.computeAddress(salt);

        console.log("\n=== Triggering Cross-Chain Upgrade ===");
        console.log("Hub:", hubAddr);
        console.log("New impl:", newImpl);

        require(newImpl.code.length > 0, "V2 impl not deployed on this chain");

        // Send ETH to cover Hyperlane protocol fees (0.001 ETH per satellite, generous buffer)
        uint256 fee = 0.001 ether;
        console.log("Sending fee:", fee);

        vm.startBroadcast(deployerKey);
        PoaManagerHub(hubAddr).upgradeBeaconCrossChain{value: fee}("HybridVoting", newImpl, "v2");
        vm.stopBroadcast();

        console.log("Upgrade dispatched. Hyperlane will relay to satellites.");
    }
}
