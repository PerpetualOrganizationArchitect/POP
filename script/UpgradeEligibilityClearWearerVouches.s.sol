// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/*
 * ============================================================================
 * EligibilityModule Upgrade — clearWearerVouches (v2)
 * ============================================================================
 *
 * Adds `clearWearerVouches(address wearer, uint256 hatId)` so the org's
 * superAdmin (the Executor) can surgically invalidate ONE wearer's vouches
 * for ONE hat — without the system-wide blast radius of `resetVouches`.
 *
 * Why: election losers on vouching-gated hats with available supply can
 * currently re-claim via `claimVouchedHat` because their vouches survive a
 * `setWearerEligibility(false, false)` revoke (the eligibility module ORs
 * vouching with hierarchy when combineWithHierarchy=true). The previous
 * workaround required `resetVouches` + `setBulkWearerEligibility` for every
 * other current holder + `configureVouching` to restore — a 6-call batch
 * with significant collateral damage. With `clearWearerVouches` the
 * election batch becomes 4 calls and touches ONLY the loser's state.
 *
 * Three-step cross-chain upgrade pattern:
 *   1. Deploy impl on Gnosis via DeterministicDeployer
 *   2. Deploy on Arbitrum + upgradeBeaconCrossChain
 *   3. Verify on Gnosis
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeEligibilityClearWearerVouches.s.sol:<StepContract> \
 *     --rpc-url <chain> --broadcast --slow
 * ============================================================================
 */

address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
uint256 constant HYPERLANE_FEE = 0.005 ether;
string constant VERSION = "v2";

/**
 * @title Step1_DeployImplOnGnosis
 * @notice Deploy EligibilityModule v2 implementation on Gnosis via DD.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeEligibilityClearWearerVouches.s.sol:Step1_DeployImplOnGnosis \
 *     --rpc-url gnosis --broadcast --slow
 */
contract Step1_DeployImplOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("\n=== Step 1: Deploy EligibilityModule v2 impl on Gnosis ===");
        console.log("Predicted:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed. Skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(EligibilityModule).creationCode);
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
 *     script/UpgradeEligibilityClearWearerVouches.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow
 */
contract Step2_UpgradeFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("\n=== Step 2: Upgrade EligibilityModule from Arbitrum ===");
        console.log("DD impl address:", predicted);

        vm.startBroadcast(deployerKey);

        if (predicted.code.length == 0) {
            dd.deploy(salt, type(EligibilityModule).creationCode);
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already deployed on Arbitrum");
        }

        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("EligibilityModule", predicted, VERSION);
        console.log("Beacon upgraded cross-chain");

        vm.stopBroadcast();
        console.log("\nWait ~5 min for Hyperlane relay, then run Step3 on Gnosis.");
    }
}

/**
 * @title Step3_VerifyGnosis
 * @notice Verify the Gnosis beacon upgrade landed.
 *
 * Usage:
 *   forge script script/UpgradeEligibilityClearWearerVouches.s.sol:Step3_VerifyGnosis \
 *     --rpc-url gnosis
 */
contract Step3_VerifyGnosis is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address expectedImpl = dd.computeAddress(salt);

        address currentImpl =
            PoaManager(GNOSIS_POA_MANAGER).getCurrentImplementationById(keccak256("EligibilityModule"));

        console.log("\n=== Step 3: Verify Gnosis EligibilityModule Upgrade ===");
        console.log("Expected impl:", expectedImpl);
        console.log("Current impl: ", currentImpl);

        if (currentImpl == expectedImpl) {
            console.log("PASS: EligibilityModule upgraded to v2 on Gnosis");
            console.log("\nNew capability: clearWearerVouches(address wearer, uint256 hatId)");
            console.log("  - Surgical per-wearer vouch invalidation");
            console.log("  - Used by election batches to prevent loser re-claim");
        } else {
            console.log("WAITING: Hyperlane message not yet relayed.");
        }
    }
}
