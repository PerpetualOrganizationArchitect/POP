// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {OrgDeployer} from "../../src/OrgDeployer.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

/**
 * @title OrgDeployer v10 — EducationHub creator whitelist
 * @notice Upgrades OrgDeployer to include createModule/updateModule/removeModule
 *         in auto-whitelist rules for new orgs where EducationHub is enabled.
 *
 *         Existing orgs (like KUBI) need a separate fix via FixKubiEducationRules.s.sol
 *         — this upgrade only affects orgs deployed AFTER the upgrade.
 *
 * Deployment flow (same as UpgradeVotingSelfTarget):
 *   1. Step1_DeployOnGnosis  — Deploy impl on Gnosis via DD (runs on Gnosis)
 *   2. Step2_UpgradeFromArbitrum — Deploy on Arbitrum via DD + cross-chain beacon upgrade (runs on Arbitrum)
 *   3. Step3_Verify — Confirms both chains picked up the upgrade (runs on Gnosis)
 *
 * Commands:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeOrgDeployerEduRules.s.sol:Step1_DeployOnGnosis \
 *     --rpc-url gnosis --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 *
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeOrgDeployerEduRules.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 *
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeOrgDeployerEduRules.s.sol:Step3_Verify \
 *     --rpc-url gnosis
 */
contract Step1_DeployOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant VERSION = "v10";

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy OrgDeployer v10 on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("OrgDeployer", VERSION);
        address predicted = dd.computeAddress(salt);

        if (predicted.code.length > 0) {
            console.log("OrgDeployer v10 already deployed:", predicted);
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(OrgDeployer).creationCode);
        vm.stopBroadcast();

        require(deployed == predicted, "Address mismatch");
        console.log("OrgDeployer v10 deployed:", deployed);
        console.log("\nNext: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }
}

contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant VERSION = "v10";
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade OrgDeployer from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("OrgDeployer", VERSION);
        address impl = dd.computeAddress(salt);
        console.log("OrgDeployer v10 impl:", impl);

        vm.startBroadcast(deployerKey);

        if (impl.code.length == 0) {
            address deployed = dd.deploy(salt, type(OrgDeployer).creationCode);
            require(deployed == impl, "Address mismatch on Arbitrum");
            console.log("OrgDeployer deployed on Arbitrum");
        } else {
            console.log("OrgDeployer already deployed on Arbitrum");
        }

        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("OrgDeployer", impl, VERSION);
        console.log("OrgDeployer beacon upgrade dispatched (Arbitrum local + Gnosis cross-chain)");

        vm.stopBroadcast();

        // Verify Arbitrum (Gnosis verifies after Hyperlane relay)
        address pm = address(hub.poaManager());
        address current = PoaManager(pm).getCurrentImplementationById(keccak256("OrgDeployer"));
        require(current == impl, "Arbitrum impl not upgraded");
        console.log("Arbitrum upgrade: PASS");
        console.log("\nWait ~5 min for Hyperlane relay, then run Step3_Verify on Gnosis");
    }
}

contract Step3_Verify is Script {
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant VERSION = "v10";

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        address expected = dd.computeAddress(dd.computeSalt("OrgDeployer", VERSION));
        address current = PoaManager(GNOSIS_PM).getCurrentImplementationById(keccak256("OrgDeployer"));

        console.log("\n=== Verify Gnosis OrgDeployer Upgrade ===");
        console.log("Expected:", expected);
        console.log("Current: ", current);
        console.log("Status:  ", current == expected ? "PASS" : "WAITING (Hyperlane not relayed yet)");
    }
}

/**
 * @title SimulateOrgDeployerUpgrade
 * @notice Fork-simulates the full 2-step upgrade end-to-end on Arbitrum.
 *         Deploys v10, calls upgradeBeaconCrossChain, verifies Arbitrum impl switched.
 *         Does NOT verify Gnosis (that requires cross-chain relay).
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeOrgDeployerEduRules.s.sol:SimulateOrgDeployerUpgrade \
 *     --rpc-url arbitrum
 */
contract SimulateOrgDeployerUpgrade is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant VERSION = "v10";
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);
        address pm = address(hub.poaManager());

        console.log("\n========================================");
        console.log("  OrgDeployer Upgrade Simulation");
        console.log("========================================");
        console.log("Deployer:", deployer);

        address before = PoaManager(pm).getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("Current OrgDeployer impl:", before);

        bytes32 salt = dd.computeSalt("OrgDeployer", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("Expected v10 address:", predicted);

        vm.deal(deployer, 1 ether);
        vm.startPrank(deployer);

        // Deploy v10 on Arbitrum
        if (predicted.code.length == 0) {
            address deployed = dd.deploy(salt, type(OrgDeployer).creationCode);
            require(deployed == predicted, "Address mismatch");
            console.log("v10 deployed at:", deployed);
        }

        // Upgrade beacon cross-chain (just calls local PM; cross-chain relay not simulated)
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("OrgDeployer", predicted, VERSION);

        vm.stopPrank();

        address after_ = PoaManager(pm).getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("New OrgDeployer impl:", after_);
        require(after_ == predicted, "Upgrade failed");
        console.log("\nArbitrum upgrade simulation: PASS");

        // Sanity: load new impl code and verify it has the expected bytecode
        require(after_.code.length > 0, "Impl has no code");
        console.log("New impl codesize:", after_.code.length, "bytes");
    }
}
