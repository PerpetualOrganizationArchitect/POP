// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";

/// @dev Minimal contract deployed at the same address on every chain via DD.
///      Used by the E2E test to verify cross-chain admin calls.
contract AdminCallTarget {
    uint256 public value;
    uint256 public callCount;

    function setValue(uint256 _val) external {
        value = _val;
        callCount++;
    }
}

/**
 * @title DeployAdminCallTarget
 * @notice Deploys AdminCallTarget via DeterministicDeployer on the current chain.
 *         Run on BOTH home and satellite chains before triggering the admin call.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER
 */
contract DeployAdminCallTarget is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("AdminCallTarget", "v1");
        address predicted = dd.computeAddress(salt);

        console.log("\n=== Deploying AdminCallTarget ===");
        console.log("Predicted address:", predicted);

        vm.startBroadcast(deployerKey);

        if (predicted.code.length > 0) {
            console.log("Already deployed at:", predicted);
        } else {
            address deployed = dd.deploy(salt, type(AdminCallTarget).creationCode);
            console.log("Deployed at:", deployed);
        }

        vm.stopBroadcast();
    }
}

/**
 * @title TriggerAdminCall
 * @notice Triggers a cross-chain admin call from the Hub.
 *         Calls AdminCallTarget.setValue(42) on home chain and all satellites.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, DETERMINISTIC_DEPLOYER
 */
contract TriggerAdminCall is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("AdminCallTarget", "v1");
        address target = dd.computeAddress(salt);

        console.log("\n=== Triggering Cross-Chain Admin Call ===");
        console.log("Hub:", hubAddr);
        console.log("Target:", target);

        require(target.code.length > 0, "AdminCallTarget not deployed on this chain");

        bytes memory data = abi.encodeWithSignature("setValue(uint256)", 42);

        // Send ETH to cover Hyperlane protocol fees (0.001 ETH per satellite, generous buffer)
        uint256 fee = 0.001 ether;
        console.log("Sending fee:", fee);

        vm.startBroadcast(deployerKey);
        PoaManagerHub(payable(hubAddr)).adminCallCrossChain{value: fee}(target, data);
        vm.stopBroadcast();

        console.log("Admin call dispatched. Hyperlane will relay to satellites.");
    }
}
