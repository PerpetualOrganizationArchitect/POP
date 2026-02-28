// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";

/**
 * @title CrossChainUpgrade
 * @notice Multi-step script for executing cross-chain beacon upgrades.
 *
 * Workflow:
 *   1. Deploy the new implementation to all chains via DeterministicDeployer
 *   2. Trigger the upgrade on the home chain (auto-propagates to satellites)
 *   3. Verify all chains have the new implementation
 *
 * Usage:
 *   # Step 1: Deploy impl to all chains
 *   DETERMINISTIC_DEPLOYER=0x... CREATION_CODE_FILE=out/HybridVoting.sol/HybridVoting.json \
 *   forge script script/CrossChainUpgrade.s.sol:DeployImplAllChains \
 *     --sig "run(string,string)" "HybridVoting" "v3" \
 *     --rpc-url $RPC_URL --broadcast
 *
 *   # Step 2: Trigger upgrade on home chain
 *   HUB=0x... DETERMINISTIC_DEPLOYER=0x... HYPERLANE_FEE=10000000000000000 \
 *   forge script script/CrossChainUpgrade.s.sol:TriggerUpgrade \
 *     --sig "run(string,string)" "HybridVoting" "v3" \
 *     --rpc-url $HOME_RPC_URL --broadcast --value $HYPERLANE_FEE
 *
 *   # Step 3: Verify (read-only)
 *   POAMANAGER=0x... \
 *   forge script script/CrossChainUpgrade.s.sol:VerifyUpgrade \
 *     --sig "run(string)" "HybridVoting" \
 *     --rpc-url $RPC_URL
 */

/// @notice Deploy a new implementation to a chain via DeterministicDeployer.
///         Run this on each target chain (or use --multi for parallel deployment).
contract DeployImplAllChains is Script {
    function run(string calldata typeName, string calldata version) public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        // Read creation code from environment (hex-encoded bytecode)
        bytes memory creationCode = vm.envBytes("CREATION_CODE");

        console.log("\n=== Deploying Implementation ===");
        console.log("Type:", typeName);
        console.log("Version:", version);

        vm.startBroadcast(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt(typeName, version);
        address predicted = dd.computeAddress(salt);

        if (predicted.code.length > 0) {
            console.log("Already deployed at:", predicted);
        } else {
            address deployed = dd.deploy(salt, creationCode);
            console.log("Deployed at:", deployed);
        }

        vm.stopBroadcast();
    }
}

/// @notice Trigger a cross-chain upgrade from the home chain Hub.
///         Set HYPERLANE_FEE (in wei) to cover Hyperlane protocol fees for all active satellites.
///         On testnets/local this can be 0; mainnet Hyperlane mailboxes require payment.
contract TriggerUpgrade is Script {
    function run(string calldata typeName, string calldata version) public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");
        uint256 fee = vm.envOr("HYPERLANE_FEE", uint256(0));

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt(typeName, version);
        address newImpl = dd.computeAddress(salt);

        console.log("\n=== Triggering Cross-Chain Upgrade ===");
        console.log("Type:", typeName);
        console.log("Version:", version);
        console.log("New impl:", newImpl);
        console.log("Hub:", hubAddr);
        console.log("Hyperlane fee:", fee);

        require(newImpl.code.length > 0, "Implementation not deployed on this chain");

        vm.startBroadcast(deployerKey);

        PoaManagerHub(payable(hubAddr)).upgradeBeaconCrossChain{value: fee}(typeName, newImpl, version);

        vm.stopBroadcast();

        console.log("Upgrade triggered. Hyperlane will relay to satellites.");
    }
}

/// @notice Read-only verification that a beacon points to the expected implementation.
contract VerifyUpgrade is Script {
    function run(string calldata typeName) public view {
        address pmAddr = vm.envAddress("POAMANAGER");

        PoaManager pm = PoaManager(pmAddr);
        bytes32 typeId = keccak256(bytes(typeName));
        address currentImpl = pm.getCurrentImplementationById(typeId);

        console.log("\n=== Upgrade Verification ===");
        console.log("Type:", typeName);
        console.log("PoaManager:", pmAddr);
        console.log("Current implementation:", currentImpl);
        console.log("Has code:", currentImpl.code.length > 0);
    }
}
