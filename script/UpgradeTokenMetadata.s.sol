// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title Step1_DeployTokenImplOnGnosis
 * @notice Deploy ParticipationToken v6 impl on Gnosis via DD.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeTokenMetadata.s.sol:Step1_DeployTokenImplOnGnosis \
 *     --rpc-url gnosis --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step1_DeployTokenImplOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy ParticipationToken v6 on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("ParticipationToken", "v6");
        address predicted = dd.computeAddress(salt);
        console.log("Predicted impl:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed. Skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(ParticipationToken).creationCode);
        vm.stopBroadcast();

        require(deployed == predicted, "Address mismatch");
        console.log("Deployed:", deployed);
        console.log("\nNext: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy impl on Arbitrum via DD, upgrade beacon cross-chain.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeTokenMetadata.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade ParticipationToken from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("ParticipationToken", "v6");
        address impl = dd.computeAddress(salt);
        console.log("DD impl address:", impl);

        vm.startBroadcast(deployerKey);

        // Deploy on Arbitrum via DD
        if (impl.code.length == 0) {
            dd.deploy(salt, type(ParticipationToken).creationCode);
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already on Arbitrum");
        }

        // Upgrade beacon cross-chain
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("ParticipationToken", impl, "v6");
        console.log("Beacon upgraded cross-chain");

        vm.stopBroadcast();

        console.log("\n=== Arbitrum complete ===");
        console.log("Wait ~5 min for Hyperlane relay, then run Step3_Verify on Gnosis.");
    }
}

/**
 * @title Step3_Verify
 * @notice Verify beacon upgraded on Gnosis. Also tests setName/setSymbol exist on an existing token.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeTokenMetadata.s.sol:Step3_Verify \
 *     --rpc-url gnosis
 */
contract Step3_Verify is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        address expected = dd.computeAddress(dd.computeSalt("ParticipationToken", "v6"));
        address current = PoaManager(GNOSIS_PM).getCurrentImplementationById(keccak256("ParticipationToken"));

        console.log("\n=== Verify ParticipationToken Upgrade (Gnosis) ===");
        console.log("Expected:", expected);
        console.log("Current:", current);
        console.log("Beacon:", current == expected ? "PASS" : "WAITING");

        if (current == expected) {
            console.log("\nParticipationToken v6 is live.");
            console.log("Existing orgs can now change token name/symbol via governance proposals.");
            console.log("  - setName(string) - onlyExecutor");
            console.log("  - setSymbol(string) - onlyExecutor");
        }
    }
}
