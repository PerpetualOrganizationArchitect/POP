// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

// UpgradePaymasterGraceFix
//
// Upgrade PaymasterHub to fix grace period solidarity logic:
//   - Funded grace orgs use tier system (bypass maxSpendDuringGrace)
//   - Unfunded grace orgs still get solidarity subsidy
//   - PostOp fallback: no phantom debt, correct solidarity tracking
//   - depositForOrg: threshold uses depositAvailable not lifetime deposited
//
// Three-step cross-chain upgrade pattern (same as RedispatchUpgrade):
//   1. Deploy impl on Gnosis via DeterministicDeployer
//   2. Deploy on Arbitrum + upgradeBeaconCrossChain + update Arbitrum grace config
//   3. Verify Gnosis beacon
//
// Usage:
//   source .env && FOUNDRY_PROFILE=production forge script \
//     script/UpgradePaymasterGraceFix.s.sol:<StepContract> \
//     --rpc-url <chain> --broadcast --slow --optimizer-runs 200

// Shared Constants
address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant ARB_PAYMASTER = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;
address constant GNOSIS_PAYMASTER = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
uint256 constant HYPERLANE_FEE = 0.005 ether;
string constant VERSION = "v8";

/**
 * @title Step1_DeployImplOnGnosis
 * @notice Deploy PaymasterHub v8 implementation on Gnosis via DeterministicDeployer.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGraceFix.s.sol:Step1_DeployImplOnGnosis \
 *     --rpc-url gnosis --broadcast --slow --optimizer-runs 200
 */
contract Step1_DeployImplOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy PaymasterHub v8 impl on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("PaymasterHub", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("Predicted impl address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed at predicted address. Skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(PaymasterHub).creationCode);
        vm.stopBroadcast();

        require(deployed == predicted, "Address mismatch");
        console.log("Deployed:", deployed);
        console.log("\nNext: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy impl on Arbitrum via DD, upgrade beacon cross-chain, update Arbitrum grace config.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGraceFix.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow --optimizer-runs 200
 */
contract Step2_UpgradeFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade PaymasterHub from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("PaymasterHub", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("DD impl address:", predicted);

        vm.startBroadcast(deployerKey);

        // Deploy on Arbitrum via DD (same deterministic address as Gnosis)
        if (predicted.code.length == 0) {
            dd.deploy(salt, type(PaymasterHub).creationCode);
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already deployed on Arbitrum");
        }

        // Upgrade beacon on both chains via Hyperlane
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("PaymasterHub", predicted, VERSION);
        console.log("Beacon upgraded cross-chain");

        // Update Arbitrum grace config via adminCall
        // Increase maxSpendDuringGrace to 0.05 ETH (~$150 at ETH=$3000)
        // Keep minDepositRequired at 0.003 ETH (~$10)
        hub.adminCall(
            ARB_PAYMASTER,
            abi.encodeWithSignature(
                "setGracePeriodConfig(uint32,uint128,uint128)", 90, uint128(0.05 ether), uint128(0.003 ether)
            )
        );
        console.log("Arbitrum grace config updated");

        vm.stopBroadcast();

        console.log("\nWait ~5 min for Hyperlane relay, then run Step3 on Gnosis.");
    }
}

/**
 * @title Step3_VerifyGnosis
 * @notice Verify the Gnosis beacon upgrade landed and report grace config status.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGraceFix.s.sol:Step3_VerifyGnosis \
 *     --rpc-url gnosis
 */
contract Step3_VerifyGnosis is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("PaymasterHub", VERSION);
        address expectedImpl = dd.computeAddress(salt);

        address currentImpl = PoaManager(GNOSIS_POA_MANAGER).getCurrentImplementationById(keccak256("PaymasterHub"));

        console.log("\n=== Step 3: Verify Gnosis PaymasterHub Upgrade ===");
        console.log("Expected impl:", expectedImpl);
        console.log("Current impl:", currentImpl);

        if (currentImpl == expectedImpl) {
            console.log("PASS: Beacon upgraded to v8 on Gnosis");
            console.log("\nGrace period fix is now live:");
            console.log("  - Funded orgs use tier system during grace (bypass maxSpendDuringGrace)");
            console.log("  - Unfunded orgs still get grace subsidy");
            console.log("  - PostOp fallback: no phantom debt");
            console.log("  - depositForOrg: threshold uses depositAvailable");

            // Read current Gnosis grace config
            PaymasterHub pm = PaymasterHub(payable(GNOSIS_PAYMASTER));
            PaymasterHub.GracePeriodConfig memory grace = pm.getGracePeriodConfig();
            console.log("\nGnosis grace config (unchanged by this upgrade):");
            console.log("  initialGraceDays:", grace.initialGraceDays);
            console.log("  maxSpendDuringGrace:", grace.maxSpendDuringGrace);
            console.log("  minDepositRequired:", grace.minDepositRequired);
            console.log("\nNote: maxSpendDuringGrace on Gnosis only affects UNFUNDED orgs now.");
            console.log("Funded orgs bypass it via the tier system.");
        } else {
            console.log("WAITING: Hyperlane message not yet relayed. Try again in a few minutes.");
        }
    }
}
