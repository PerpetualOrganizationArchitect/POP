// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title ParticipationToken v2 cross-chain beacon upgrade
 * @notice Adds executor-gated `setName(string)` and `setSymbol(string)` so
 *         governance proposals can rename the org's participation token.
 *
 * Three steps mirroring UpgradeVotingSelfTarget.s.sol:
 *   1. Step1_DeployOnGnosis        — deploy v2 impl on Gnosis via DD
 *   2. Step2_UpgradeFromArbitrum   — deploy v2 impl on Arbitrum via DD,
 *                                    upgrade the beacon cross-chain
 *   3. Step3_Verify                — confirm Gnosis beacon picked up the impl
 *                                    after Hyperlane relay (~5 min)
 *
 * Commands:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeParticipationToken.s.sol:Step1_DeployOnGnosis \
 *     --rpc-url https://rpc.gnosischain.com --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 *
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeParticipationToken.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 *
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeParticipationToken.s.sol:Step3_Verify \
 *     --rpc-url https://rpc.gnosischain.com
 */
contract Step1_DeployOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 1: Deploy ParticipationToken v2 on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("ParticipationToken", "v2");
        address predicted = dd.computeAddress(salt);
        console.log("Predicted v2 address:", predicted);

        if (predicted.code.length > 0) {
            console.log("ParticipationToken v2 already deployed at this address");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(ParticipationToken).creationCode);
        vm.stopBroadcast();

        require(deployed == predicted, "address mismatch");
        console.log("Deployed:", deployed);
        console.log("\nNext: run Step2_UpgradeFromArbitrum on Arbitrum");
    }
}

contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);
        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Deploy on Arbitrum + upgrade beacons cross-chain ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("ParticipationToken", "v2");
        address impl = dd.computeAddress(salt);
        console.log("ParticipationToken v2 impl:", impl);

        vm.startBroadcast(deployerKey);

        if (impl.code.length == 0) {
            address deployed = dd.deploy(salt, type(ParticipationToken).creationCode);
            require(deployed == impl, "Address mismatch on Arbitrum");
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already on Arbitrum");
        }

        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("ParticipationToken", impl, "v2");
        console.log("ParticipationToken beacon upgraded (Arbitrum local + Gnosis cross-chain)");

        vm.stopBroadcast();

        // Verify Arbitrum-side immediately. Gnosis follows after Hyperlane relay.
        address pm = address(hub.poaManager());
        address current = PoaManager(pm).getCurrentImplementationById(keccak256("ParticipationToken"));
        require(current == impl, "Arbitrum beacon not updated");
        console.log("Arbitrum upgrade: PASS");
        console.log("\nWait ~5 min for Hyperlane relay, then run Step3_Verify on Gnosis.");
    }
}

contract Step3_Verify is Script {
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        address expected = dd.computeAddress(dd.computeSalt("ParticipationToken", "v2"));
        address current = PoaManager(GNOSIS_PM).getCurrentImplementationById(keccak256("ParticipationToken"));

        console.log("\n=== Verify Gnosis ParticipationToken Upgrade ===");
        console.log("Expected:", expected);
        console.log("Current: ", current);
        console.log("Status:  ", current == expected ? "PASS" : "WAITING (Hyperlane not relayed yet)");
    }
}
