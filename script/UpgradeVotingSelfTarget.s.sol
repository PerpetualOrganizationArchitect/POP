// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {HybridVoting} from "../src/HybridVoting.sol";
import {DirectDemocracyVoting} from "../src/DirectDemocracyVoting.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title Step1_DeployVotingImplsOnGnosis
 * @notice Deploy HybridVoting v6 and DirectDemocracyVoting v6 impls on Gnosis via DD.
 *         Must run BEFORE the Arbitrum upgrade so impls exist when Hyperlane arrives.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeVotingSelfTarget.s.sol:Step1_DeployVotingImplsOnGnosis \
 *     --rpc-url gnosis --broadcast --slow
 */
contract Step1_DeployVotingImplsOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy voting impls on Gnosis ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // HybridVoting v6
        bytes32 hvSalt = dd.computeSalt("HybridVoting", "v8");
        address hvPredicted = dd.computeAddress(hvSalt);
        if (hvPredicted.code.length == 0) {
            address hvDeployed = dd.deploy(hvSalt, type(HybridVoting).creationCode);
            require(hvDeployed == hvPredicted, "HV address mismatch");
            console.log("HybridVoting v6:", hvDeployed);
        } else {
            console.log("HybridVoting v6 already deployed:", hvPredicted);
        }

        // DirectDemocracyVoting v6
        bytes32 ddvSalt = dd.computeSalt("DirectDemocracyVoting", "v8");
        address ddvPredicted = dd.computeAddress(ddvSalt);
        if (ddvPredicted.code.length == 0) {
            address ddvDeployed = dd.deploy(ddvSalt, type(DirectDemocracyVoting).creationCode);
            require(ddvDeployed == ddvPredicted, "DDV address mismatch");
            console.log("DirectDemocracyVoting v6:", ddvDeployed);
        } else {
            console.log("DirectDemocracyVoting v6 already deployed:", ddvPredicted);
        }

        vm.stopBroadcast();

        console.log("\n=== Gnosis impl deployment complete ===");
        console.log("Next: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy impls on Arbitrum via DD, upgrade both beacons cross-chain.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeVotingSelfTarget.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow
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

        console.log("\n=== Step 2: Upgrade voting beacons from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        // Compute DD addresses
        bytes32 hvSalt = dd.computeSalt("HybridVoting", "v8");
        address hvImpl = dd.computeAddress(hvSalt);
        bytes32 ddvSalt = dd.computeSalt("DirectDemocracyVoting", "v8");
        address ddvImpl = dd.computeAddress(ddvSalt);

        console.log("HybridVoting v6 impl:", hvImpl);
        console.log("DirectDemocracyVoting v6 impl:", ddvImpl);

        vm.startBroadcast(deployerKey);

        // Deploy on Arbitrum via DD
        if (hvImpl.code.length == 0) {
            dd.deploy(hvSalt, type(HybridVoting).creationCode);
            console.log("HybridVoting deployed on Arbitrum");
        } else {
            console.log("HybridVoting already on Arbitrum");
        }

        if (ddvImpl.code.length == 0) {
            dd.deploy(ddvSalt, type(DirectDemocracyVoting).creationCode);
            console.log("DirectDemocracyVoting deployed on Arbitrum");
        } else {
            console.log("DirectDemocracyVoting already on Arbitrum");
        }

        // Upgrade HybridVoting beacon cross-chain
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("HybridVoting", hvImpl, "v8");
        console.log("HybridVoting beacon upgraded cross-chain");

        // Upgrade DirectDemocracyVoting beacon cross-chain
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("DirectDemocracyVoting", ddvImpl, "v8");
        console.log("DirectDemocracyVoting beacon upgraded cross-chain");

        vm.stopBroadcast();

        console.log("\n=== Arbitrum complete ===");
        console.log("Wait ~5 min for Hyperlane relay, then run Step3_Verify on Gnosis.");
    }
}

/**
 * @title Step3_Verify
 * @notice Verify both beacons upgraded on both chains.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeVotingSelfTarget.s.sol:Step3_Verify \
 *     --rpc-url gnosis
 */
contract Step3_Verify is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);

        address hvExpected = dd.computeAddress(dd.computeSalt("HybridVoting", "v8"));
        address ddvExpected = dd.computeAddress(dd.computeSalt("DirectDemocracyVoting", "v8"));

        PoaManager pm = PoaManager(GNOSIS_PM);
        address hvCurrent = pm.getCurrentImplementationById(keccak256("HybridVoting"));
        address ddvCurrent = pm.getCurrentImplementationById(keccak256("DirectDemocracyVoting"));

        console.log("\n=== Verify Gnosis Voting Upgrade ===");
        console.log("HybridVoting expected:", hvExpected);
        console.log("HybridVoting current:", hvCurrent);
        console.log("HybridVoting:", hvCurrent == hvExpected ? "PASS" : "WAITING");

        console.log("DirectDemocracyVoting expected:", ddvExpected);
        console.log("DirectDemocracyVoting current:", ddvCurrent);
        console.log("DirectDemocracyVoting:", ddvCurrent == ddvExpected ? "PASS" : "WAITING");

        if (hvCurrent == hvExpected && ddvCurrent == ddvExpected) {
            console.log("\nAll beacons upgraded. Governance can now target voting contracts.");
        } else {
            console.log("\nHyperlane message not yet relayed. Try again in a few minutes.");
        }
    }
}
