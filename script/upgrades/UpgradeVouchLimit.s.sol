// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {EligibilityModule} from "../../src/EligibilityModule.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

// UpgradeVouchLimit — EligibilityModule v10
//
// Changes:
//   - Increase default daily vouch limit from 3 to 20
//   - Add setMaxDailyVouches(uint32) setter (onlySuperAdmin)
//   - Add getMaxDailyVouches() view
//   - Backward compatible: existing deployments with unset storage default to 20
//
// Usage:
//   source .env && FOUNDRY_PROFILE=production forge script \
//     script/UpgradeVouchLimit.s.sol:<Step> \
//     --rpc-url <chain> --broadcast --slow --optimizer-runs 150 \
//     --private-key $DEPLOYER_PRIVATE_KEY

address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
uint256 constant HYPERLANE_FEE = 0.005 ether;
string constant VERSION = "v10";

contract Step1_DeployImplOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 1: Deploy EligibilityModule v10 impl on Gnosis ===");
        console.log("Deployer:", vm.addr(deployerKey));

        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("Predicted impl:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed. Skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(EligibilityModule).creationCode);
        vm.stopBroadcast();

        require(deployed == predicted, "Address mismatch");
        console.log("Deployed:", deployed);
        console.log("\nNext: Run Step2 on Arbitrum");
    }
}

contract Step2_UpgradeFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade EligibilityModule from Arbitrum ===");
        require(hub.owner() == vm.addr(deployerKey), "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("DD impl:", predicted);

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
        console.log("\nWait ~5 min for Hyperlane relay, then run Step3.");
    }
}

contract Step3_VerifyGnosis is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("EligibilityModule", VERSION);
        address expected = dd.computeAddress(salt);
        address current = PoaManager(GNOSIS_POA_MANAGER).getCurrentImplementationById(keccak256("EligibilityModule"));

        console.log("\n=== Step 3: Verify Gnosis ===");
        console.log("Expected:", expected);
        console.log("Current:", current);

        if (current == expected) {
            console.log("PASS: EligibilityModule v10 live on Gnosis");
            console.log("  - Default daily vouch limit: 20 (was 3)");
            console.log("  - Configurable via setMaxDailyVouches(uint32)");
        } else {
            console.log("WAITING: Hyperlane not yet relayed.");
        }
    }
}
