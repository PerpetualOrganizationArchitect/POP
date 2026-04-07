// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";

/**
 * @title Step1_DeployOnGnosis
 * @notice Deploy PaymasterHub v8 on Gnosis via DD.
 *
 * NOTE: PaymasterHub requires optimizer_runs=100 to fit EIP-170.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterFee.s.sol:Step1_DeployOnGnosis \
 *     --rpc-url gnosis --broadcast --slow --optimizer-runs 100 \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step1_DeployOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        bytes32 salt = dd.computeSalt("PaymasterHub", "v8");
        address predicted = dd.computeAddress(salt);

        console.log("\n=== Step 1: Deploy PaymasterHub v8 on Gnosis ===");
        console.log("Predicted:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed.");
            return;
        }

        vm.startBroadcast(deployerKey);
        dd.deploy(salt, type(PaymasterHub).creationCode);
        vm.stopBroadcast();

        console.log("Deployed. Next: Run Step2 on Arbitrum.");
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy on Arbitrum + upgrade cross-chain.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterFee.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow --optimizer-runs 100 \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        bytes32 salt = dd.computeSalt("PaymasterHub", "v8");
        address predicted = dd.computeAddress(salt);

        console.log("\n=== Step 2: Upgrade PaymasterHub v8 from Arbitrum ===");
        require(hub.owner() == vm.addr(deployerKey), "Not owner");

        vm.startBroadcast(deployerKey);

        if (predicted.code.length == 0) {
            dd.deploy(salt, type(PaymasterHub).creationCode);
            console.log("Deployed on Arbitrum");
        }

        hub.upgradeBeaconCrossChain{value: 0.005 ether}("PaymasterHub", predicted, "v8");
        console.log("Upgraded cross-chain:", predicted);

        vm.stopBroadcast();
        console.log("Wait ~5 min, then verify on Gnosis.");
    }
}

/**
 * @title Step3_Verify
 */
contract Step3_Verify is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;

    function run() public view {
        address expected = DeterministicDeployer(DD).computeAddress(
            DeterministicDeployer(DD).computeSalt("PaymasterHub", "v8")
        );
        address current = PoaManager(GNOSIS_PM).getCurrentImplementationById(keccak256("PaymasterHub"));

        console.log("Expected:", expected);
        console.log("Current:", current);
        console.log(current == expected ? "PASS" : "WAITING");
    }
}
