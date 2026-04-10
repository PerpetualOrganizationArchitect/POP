// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title Step1_DeployImplOnGnosis
 * @notice Deploy PaymasterHub v5 implementation on Gnosis via DeterministicDeployer.
 *         Must be run BEFORE the Arbitrum upgrade so the impl exists when
 *         the Hyperlane message arrives.
 *
 * NOTE: PaymasterHub exceeds EIP-170 at optimizer_runs=200. Use 150 runs:
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGrace.s.sol:Step1_DeployImplOnGnosis \
 *     --rpc-url gnosis --broadcast --slow --optimizer-runs 150
 */
contract Step1_DeployImplOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy PaymasterHub impl on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("PaymasterHub", "v5");
        address predicted = dd.computeAddress(salt);
        console.log("Predicted impl address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed. Skipping.");
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
 * @notice Deploy impl on Arbitrum via DD, upgradeBeaconCrossChain, update Arbitrum grace config.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGrace.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow --optimizer-runs 150
 */
contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    address constant ARB_PAYMASTER = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade PaymasterHub from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("PaymasterHub", "v5");
        address predicted = dd.computeAddress(salt);
        console.log("DD impl address:", predicted);

        vm.startBroadcast(deployerKey);

        // Deploy on Arbitrum via DD (same address as Gnosis)
        if (predicted.code.length == 0) {
            dd.deploy(salt, type(PaymasterHub).creationCode);
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already deployed on Arbitrum");
        }

        // Upgrade beacon on both chains
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("PaymasterHub", predicted, "v5");
        console.log("Beacon upgraded cross-chain");

        // Update Arbitrum grace config via adminCall
        // setGracePeriodConfig(90 days, 0.05 ETH maxSpend, 0.003 ETH minDeposit)
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
 * @title Step3_UpdateGnosisGraceConfig
 * @notice Update Gnosis PaymasterHub grace config. Since adminCallCrossChain
 *         can't target different addresses per chain, we update Gnosis config
 *         via a direct cast send from the deployer... but setGracePeriodConfig
 *         requires msg.sender == poaManager. So we verify the beacon upgrade
 *         landed and note that the CODE FIX itself resolves the issue for funded orgs.
 *         The grace config only matters for UNFUNDED orgs.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymasterGrace.s.sol:Step3_VerifyGnosis \
 *     --rpc-url gnosis
 */
contract Step3_VerifyGnosis is Script {
    address constant GNOSIS_PAYMASTER = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("PaymasterHub", "v5");
        address expectedImpl = dd.computeAddress(salt);

        address currentImpl = PoaManager(GNOSIS_POA_MANAGER).getCurrentImplementationById(keccak256("PaymasterHub"));

        console.log("\n=== Step 3: Verify Gnosis PaymasterHub Upgrade ===");
        console.log("Expected impl:", expectedImpl);
        console.log("Current impl:", currentImpl);

        if (currentImpl == expectedImpl) {
            console.log("PASS: Beacon upgraded on Gnosis");
            console.log("\nThe code fix (solidarity+deposit split during grace) is now live.");
            console.log("Funded orgs will no longer hit GracePeriodSpendLimitReached.");
            console.log("\nNote: maxSpendDuringGrace on Gnosis is still 0.001 xDAI for unfunded orgs.");
            console.log("This only affects unfunded orgs. To update, deploy a new Hub with");
            console.log("adminCallRemoteOnly support, or redeploy the Gnosis infrastructure.");
        } else {
            console.log("WAITING: Hyperlane message not yet relayed. Try again in a few minutes.");
        }
    }
}
