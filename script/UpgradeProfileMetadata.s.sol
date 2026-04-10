// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {OrgDeployer} from "../src/OrgDeployer.sol";

/*
 * ============================================================================
 * Profile Metadata Upgrade — 3 contracts, 2 chains
 * ============================================================================
 *
 * Contracts:
 *   1. UniversalAccountRegistry (v4) — new setProfileMetadata functions
 *   2. PaymasterHub (v12)            — accepts setProfileMetadata in onboarding
 *   3. OrgDeployer (v5)              — auto-whitelist setProfileMetadata (38 rules)
 *
 * IMPORTANT: PaymasterHub requires --optimizer-runs 100 to fit EIP-170 (24,576 bytes).
 *            UAR and OrgDeployer use the default production profile (optimizer_runs=200).
 *
 * Execution order:
 *   Step 1: Deploy UAR + OrgDeployer on Gnosis        (optimizer_runs=200)
 *   Step 2: Deploy PaymasterHub on Gnosis              (optimizer_runs=100)
 *   Step 3: Deploy all + upgrade cross-chain from Arb  (optimizer_runs=100, covers all 3)
 *   Step 4: Verify on Gnosis
 *
 * ============================================================================
 */

// ─── Shared constants ───
address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
address constant ARB_PM = 0xFF585Fae4A944cD173B19158C6FC5E08980b0815;

string constant UAR_VERSION = "v4";
string constant PM_VERSION = "v15"; // v12-v14 burned (v12-v13: old source; v14: missing initCode fix)
string constant OD_VERSION = "v5";

/**
 * @title Step1_DeployUarAndOrgDeployerOnGnosis
 * @notice Deploy UniversalAccountRegistry v4 and OrgDeployer v5 on Gnosis via DD.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeProfileMetadata.s.sol:Step1_DeployUarAndOrgDeployerOnGnosis \
 *     --rpc-url gnosis --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step1_DeployUarAndOrgDeployerOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 1: Deploy UAR + OrgDeployer on Gnosis ===");

        // ── UAR ──
        bytes32 uarSalt = dd.computeSalt("UniversalAccountRegistry", UAR_VERSION);
        address uarPredicted = dd.computeAddress(uarSalt);
        console.log("UAR predicted:", uarPredicted);

        // ── OrgDeployer ──
        bytes32 odSalt = dd.computeSalt("OrgDeployer", OD_VERSION);
        address odPredicted = dd.computeAddress(odSalt);
        console.log("OrgDeployer predicted:", odPredicted);

        vm.startBroadcast(deployerKey);

        if (uarPredicted.code.length == 0) {
            dd.deploy(uarSalt, type(UniversalAccountRegistry).creationCode);
            console.log("UAR deployed");
        } else {
            console.log("UAR already deployed");
        }

        if (odPredicted.code.length == 0) {
            dd.deploy(odSalt, type(OrgDeployer).creationCode);
            console.log("OrgDeployer deployed");
        } else {
            console.log("OrgDeployer already deployed");
        }

        vm.stopBroadcast();
        console.log("Next: Run Step2 to deploy PaymasterHub on Gnosis with --optimizer-runs 100");
    }
}

/**
 * @title Step2_DeployPaymasterHubOnGnosis
 * @notice Deploy PaymasterHub v12 on Gnosis via DD.
 *
 * NOTE: PaymasterHub requires --optimizer-runs 100 to fit EIP-170.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeProfileMetadata.s.sol:Step2_DeployPaymasterHubOnGnosis \
 *     --rpc-url gnosis --broadcast --slow --optimizer-runs 100 \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step2_DeployPaymasterHubOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        bytes32 salt = dd.computeSalt("PaymasterHub", PM_VERSION);
        address predicted = dd.computeAddress(salt);

        console.log("\n=== Step 2: Deploy PaymasterHub on Gnosis ===");
        console.log("Predicted:", predicted);

        // Size check
        uint256 pmSize = type(PaymasterHub).creationCode.length;
        console.log("PaymasterHub creation code size:", pmSize);

        if (predicted.code.length > 0) {
            console.log("Already deployed.");
            return;
        }

        vm.startBroadcast(deployerKey);
        dd.deploy(salt, type(PaymasterHub).creationCode);
        vm.stopBroadcast();

        // Verify deployed size
        uint256 deployedSize = predicted.code.length;
        console.log("Deployed runtime size:", deployedSize);
        require(deployedSize <= 24576, "OVER EIP-170 LIMIT");
        console.log("EIP-170 margin:", 24576 - deployedSize, "bytes");

        console.log("Next: Run Step3 on Arbitrum with --optimizer-runs 100");
    }
}

/**
 * @title Step3_UpgradePaymasterHubFromArbitrum
 * @notice Deploy PaymasterHub v13 on Arbitrum + upgrade cross-chain.
 *         UAR (v4) and OrgDeployer (v5) are already upgraded — skipped to avoid SameImplementation revert.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeProfileMetadata.s.sol:Step3_UpgradePaymasterHubFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow --optimizer-runs 100 \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step3_UpgradePaymasterHubFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 3: Deploy + Upgrade PaymasterHub from Arbitrum ===");
        require(hub.owner() == vm.addr(deployerKey), "Not owner");

        bytes32 pmSalt = dd.computeSalt("PaymasterHub", PM_VERSION);
        address pmAddr = dd.computeAddress(pmSalt);
        console.log("PaymasterHub impl:", pmAddr);

        vm.startBroadcast(deployerKey);

        if (pmAddr.code.length == 0) {
            dd.deploy(pmSalt, type(PaymasterHub).creationCode);
            console.log("PaymasterHub deployed on Arbitrum");

            uint256 pmDeployedSize = pmAddr.code.length;
            console.log("PaymasterHub runtime size:", pmDeployedSize);
            require(pmDeployedSize <= 24576, "PaymasterHub OVER EIP-170 LIMIT");
        }

        hub.upgradeBeaconCrossChain{value: 0.005 ether}("PaymasterHub", pmAddr, PM_VERSION);
        console.log("PaymasterHub upgrade dispatched");

        vm.stopBroadcast();

        console.log("\nWait ~5 min for Hyperlane delivery, then run Step4_Verify on Gnosis.");
    }
}

/**
 * @title Step4_Verify
 * @notice Verify all 3 upgrades landed on Gnosis. Also tests profile metadata on fork.
 *
 * Usage:
 *   forge script script/UpgradeProfileMetadata.s.sol:Step4_Verify \
 *     --rpc-url gnosis
 */
contract Step4_Verify is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        PoaManager pm = PoaManager(GNOSIS_PM);

        console.log("\n=== Step 4: Verify Upgrades on Gnosis ===\n");

        // ── UAR ──
        address uarExpected = dd.computeAddress(dd.computeSalt("UniversalAccountRegistry", UAR_VERSION));
        address uarCurrent = pm.getCurrentImplementationById(keccak256("UniversalAccountRegistry"));
        console.log("UAR expected:", uarExpected);
        console.log("UAR current: ", uarCurrent);
        console.log(uarCurrent == uarExpected ? "  -> PASS" : "  -> WAITING");

        // ── PaymasterHub ──
        address pmExpected = dd.computeAddress(dd.computeSalt("PaymasterHub", PM_VERSION));
        address pmCurrent = pm.getCurrentImplementationById(keccak256("PaymasterHub"));
        console.log("PM expected: ", pmExpected);
        console.log("PM current:  ", pmCurrent);
        console.log(pmCurrent == pmExpected ? "  -> PASS" : "  -> WAITING");

        // ── OrgDeployer ──
        address odExpected = dd.computeAddress(dd.computeSalt("OrgDeployer", OD_VERSION));
        address odCurrent = pm.getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("OD expected: ", odExpected);
        console.log("OD current:  ", odCurrent);
        console.log(odCurrent == odExpected ? "  -> PASS" : "  -> WAITING");

        // ── Smoke test: call getProfileMetadata on the upgraded UAR proxy ──
        address gnosisUarProxy = 0x55F72CEB09cBC1fAAED734b6505b99b0a1DFA1cA;
        if (uarCurrent == uarExpected) {
            bytes32 meta =
                UniversalAccountRegistry(gnosisUarProxy).getProfileMetadata(0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9);
            console.log("\nSmoke test: getProfileMetadata(deployer) =", vm.toString(meta));
            console.log("  -> PASS (function exists and returns)");
        }
    }
}

/**
 * @title DryRun_SimulateUpgrade
 * @notice Simulate the full upgrade on a Gnosis fork to verify everything works.
 *         Does NOT broadcast — read-only safety check.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeProfileMetadata.s.sol:DryRun_SimulateUpgrade \
 *     --rpc-url gnosis --optimizer-runs 100
 */
contract DryRun_SimulateUpgrade is Script {
    function run() public {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        PoaManager pm = PoaManager(GNOSIS_PM);
        address owner = pm.owner();

        console.log("\n=== DRY RUN: Simulating upgrades on Gnosis fork ===\n");
        console.log("PoaManager owner:", owner);

        // Deploy new implementations locally (no broadcast)
        UniversalAccountRegistry uarImpl = new UniversalAccountRegistry();
        PaymasterHub pmImpl = new PaymasterHub();
        OrgDeployer odImpl = new OrgDeployer();

        console.log("UAR impl size:", address(uarImpl).code.length);
        console.log("PM impl size:", address(pmImpl).code.length);
        console.log("OD impl size:", address(odImpl).code.length);
        require(address(pmImpl).code.length <= 24576, "PaymasterHub OVER EIP-170 LIMIT");

        // Simulate beacon upgrades
        vm.startPrank(owner);
        pm.upgradeBeacon("UniversalAccountRegistry", address(uarImpl), "dry-run");
        pm.upgradeBeacon("PaymasterHub", address(pmImpl), "dry-run");
        pm.upgradeBeacon("OrgDeployer", address(odImpl), "dry-run");
        vm.stopPrank();

        // ── Test UAR profile metadata on upgraded proxy ──
        address uarProxy = 0x55F72CEB09cBC1fAAED734b6505b99b0a1DFA1cA;
        address deployer = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;
        UniversalAccountRegistry uar = UniversalAccountRegistry(uarProxy);

        // Verify existing state preserved
        string memory username = uar.getUsername(deployer);
        console.log("\nDeployer username:", username);
        require(keccak256(bytes(username)) == keccak256(bytes("hudsonhrh")), "Username corrupted!");

        // Verify new function works
        bytes32 defaultMeta = uar.getProfileMetadata(deployer);
        console.log("Default metadata:", vm.toString(defaultMeta));
        require(defaultMeta == bytes32(0), "Default not zero");

        // Set profile metadata
        vm.prank(deployer);
        uar.setProfileMetadata(keccak256("test-profile"));
        bytes32 stored = uar.getProfileMetadata(deployer);
        require(stored == keccak256("test-profile"), "Set failed");
        console.log("setProfileMetadata: PASS");

        // Clear it
        vm.prank(deployer);
        uar.setProfileMetadata(bytes32(0));
        require(uar.getProfileMetadata(deployer) == bytes32(0), "Clear failed");
        console.log("Clear metadata: PASS");

        // Verify unregistered user reverts
        try uar.setProfileMetadata(keccak256("x")) {
            revert("Should have reverted for unregistered user");
        } catch {
            console.log("Unregistered revert: PASS");
        }

        console.log("\n=== ALL DRY RUN CHECKS PASSED ===");
    }
}
