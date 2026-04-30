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
// EligibilityModule has been versioned v1..v10 already; current live Gnosis
// impl is at the v10 salt address (0x56EbB6a5...). Versions v2 and v3 are
// occupied by stale deployments missing getMaxDailyVouches — pointing the
// beacon there would regress the rate limiter. Bump to "v11" for a fresh
// deterministic address with BOTH live functionality AND clearWearerVouches.
string constant VERSION = "v11";

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

/**
 * @title DryRun_GnosisUpgrade
 * @notice Pre-flight test on a Gnosis fork. Runs the entire upgrade flow
 *         (deploy impl via DD, upgrade beacon, exercise the new selector
 *         against KUBI's live proxy) without broadcasting.
 *
 *         Asserts:
 *           1. DD-predicted address matches deployed address.
 *           2. PoaManager beacon updates to the new impl.
 *           3. Existing storage (vouchConfig) survives the impl swap.
 *           4. New `clearWearerVouches` selector is callable post-upgrade
 *              and zeros the target wearer's vouch count.
 *           5. Auth gate: non-superAdmin call reverts.
 *           6. Input validation: zero-address reverts.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeEligibilityClearWearerVouches.s.sol:DryRun_GnosisUpgrade \
 *     --rpc-url gnosis
 */
contract DryRun_GnosisUpgrade is Script {
    address constant KUBI_ELIG_MODULE = 0x27114Cb757BeDF77E30EeB0Ca635e3368d8C2914;
    address constant KUBI_EXECUTOR = 0x23f90B3859818A843C3a848627A304Bc53947342;
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
    address constant CALEB = 0x439831a0C10F834D6Bc6f62917834DdCaa203dCf;
    uint256 constant EXECUTIVE_HAT = 0x0000043700010001000000000000000000000000000000000000000000000000;

    function run() public {
        console.log("\n=== DRY RUN: EligibilityModule v2 upgrade on Gnosis fork ===\n");

        DeterministicDeployer dd = DeterministicDeployer(DD);
        PoaManager pm = PoaManager(GNOSIS_POA_MANAGER);

        // 1. Pre-state snapshot.
        address implBefore = pm.getCurrentImplementationById(keccak256("EligibilityModule"));
        console.log("Impl before:", implBefore);

        (bool okCfg, bytes memory cfgBytes) =
            KUBI_ELIG_MODULE.staticcall(abi.encodeWithSignature("getVouchConfig(uint256)", EXECUTIVE_HAT));
        require(okCfg, "DryRun: pre-upgrade getVouchConfig failed");
        bytes32 cfgHashBefore = keccak256(cfgBytes);
        console.log("VouchConfig hash before:", vm.toString(cfgHashBefore));

        (, bytes memory wearsBytes) =
            HATS.staticcall(abi.encodeWithSignature("isWearerOfHat(address,uint256)", CALEB, EXECUTIVE_HAT));
        require(abi.decode(wearsBytes, (bool)), "DryRun.pre: caleb wears Executive");

        // 2. Step1 simulation: deploy v2 impl via DD.
        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("\nDD predicted impl:", predicted);

        address deployed;
        if (predicted.code.length == 0) {
            // DD's deploy is onlyOwner — prank as the deployer EOA.
            vm.prank(0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9);
            deployed = dd.deploy(salt, type(EligibilityModule).creationCode);
        } else {
            console.log("Already deployed at predicted (skipping deploy)");
            deployed = predicted;
        }
        require(deployed == predicted, "DryRun: DD address mismatch");
        require(deployed.code.length > 0, "DryRun: impl code missing");
        console.log("Deployed impl:", deployed);

        // 3. Step2 simulation: upgrade beacon as PoaManager owner.
        address pmOwner = pm.owner();
        vm.prank(pmOwner);
        pm.upgradeBeacon("EligibilityModule", deployed, VERSION);
        address implAfter = pm.getCurrentImplementationById(keccak256("EligibilityModule"));
        require(implAfter == deployed, "DryRun: beacon upgrade did not stick");
        console.log("Impl after :", implAfter);

        // 4. Storage preservation check.
        (, bytes memory cfgBytesAfter) =
            KUBI_ELIG_MODULE.staticcall(abi.encodeWithSignature("getVouchConfig(uint256)", EXECUTIVE_HAT));
        require(keccak256(cfgBytesAfter) == cfgHashBefore, "DryRun: vouch config drifted across upgrade");
        console.log("VouchConfig preserved across upgrade");

        // 4b. REGRESSION CHECK: live `getMaxDailyVouches` selector must still
        // work post-upgrade. If an impl is rebuilt off a stale base (i.e.
        // missing the `maxDailyVouches` storage + getter that's already on
        // the deployed Gnosis impl), this call would revert post-upgrade and
        // the daily-vouch rate limiter would silently fall back to the older
        // hardcoded value of 3. Catch that here.
        (bool okLimit, bytes memory limitBytes) =
            KUBI_ELIG_MODULE.staticcall(abi.encodeWithSignature("getMaxDailyVouches()"));
        require(okLimit, "DryRun: getMaxDailyVouches reverted post-upgrade (REGRESSION)");
        uint32 limit = abi.decode(limitBytes, (uint32));
        require(limit > 0, "DryRun: getMaxDailyVouches returned 0");
        console.log("getMaxDailyVouches preserved (returns):", limit);

        // 5. New selector is callable + zeros the target wearer's count.
        (, bytes memory vcBefore) = KUBI_ELIG_MODULE.staticcall(
            abi.encodeWithSignature("currentVouchCount(uint256,address)", EXECUTIVE_HAT, CALEB)
        );
        uint32 calebVouchesBefore = abi.decode(vcBefore, (uint32));
        console.log("\ncaleb's Executive vouch count BEFORE clearWearerVouches:", calebVouchesBefore);
        require(calebVouchesBefore >= 1, "DryRun.pre: caleb should have an Executive vouch");

        vm.prank(KUBI_EXECUTOR);
        (bool okClear,) =
            KUBI_ELIG_MODULE.call(abi.encodeWithSignature("clearWearerVouches(address,uint256)", CALEB, EXECUTIVE_HAT));
        require(okClear, "DryRun: clearWearerVouches reverted unexpectedly");

        (, bytes memory vcAfter) = KUBI_ELIG_MODULE.staticcall(
            abi.encodeWithSignature("currentVouchCount(uint256,address)", EXECUTIVE_HAT, CALEB)
        );
        uint32 calebVouchesAfter = abi.decode(vcAfter, (uint32));
        console.log("caleb's Executive vouch count AFTER  clearWearerVouches:", calebVouchesAfter);
        require(calebVouchesAfter == 0, "DryRun: stored vouch count not zeroed");

        // 6. Auth gate.
        vm.prank(address(0xDEAD));
        (bool okBadAuth,) =
            KUBI_ELIG_MODULE.call(abi.encodeWithSignature("clearWearerVouches(address,uint256)", CALEB, EXECUTIVE_HAT));
        require(!okBadAuth, "DryRun: non-superAdmin call must revert");

        // 7. Input validation.
        vm.prank(KUBI_EXECUTOR);
        (bool okZero,) = KUBI_ELIG_MODULE.call(
            abi.encodeWithSignature("clearWearerVouches(address,uint256)", address(0), EXECUTIVE_HAT)
        );
        require(!okZero, "DryRun: zero-address must revert");

        console.log("\n=== ALL DRY-RUN CHECKS PASSED ===");
        console.log("Safe to broadcast Step1/Step2/Step3 against mainnet.");
    }
}
