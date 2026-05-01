// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PaymasterHub} from "../../src/PaymasterHub.sol";
import {QuickJoin} from "../../src/QuickJoin.sol";
import {OrgDeployer} from "../../src/OrgDeployer.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

// Upgrade QuickJoin + OrgDeployer + PaymasterHub to enable vouch-claim flow.
//
// QuickJoin v9:  adds registerAndClaimHatsWithPasskey, claimHatsWithUser, registerAndClaimHats
// OrgDeployer v9: updated _buildDefaultPaymasterRules to whitelist vouch-claim selectors
// PaymasterHub v9: onlyOrgOperator allows poaManager (enables adminCall rule migration)
//
// Existing orgs already have the vouch-claim selectors whitelisted in paymaster rules
// (the OrgDeployer that deployed them included them). Only QuickJoin impl is missing.
//
// Usage:
//   source .env && FOUNDRY_PROFILE=production forge script \
//     script/UpgradeVouchClaim.s.sol:<StepContract> \
//     --rpc-url <chain> --broadcast --slow --optimizer-runs 150

// Shared Constants
address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
uint256 constant HYPERLANE_FEE = 0.005 ether;
string constant VERSION = "v9";

/**
 * @title Step1_DeployImplsOnGnosis
 * @notice Deploy QuickJoin, OrgDeployer, and PaymasterHub v9 impls on Gnosis via DD.
 */
contract Step1_DeployImplsOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy v9 impls on Gnosis ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        _deployIfNeeded(dd, "QuickJoin", type(QuickJoin).creationCode);
        _deployIfNeeded(dd, "OrgDeployer", type(OrgDeployer).creationCode);
        _deployIfNeeded(dd, "PaymasterHub", type(PaymasterHub).creationCode);

        vm.stopBroadcast();

        console.log("\nNext: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }

    function _deployIfNeeded(DeterministicDeployer dd, string memory name, bytes memory creationCode) internal {
        bytes32 salt = dd.computeSalt(name, VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("");
        console.log(name);
        console.log("  Predicted:", predicted);

        if (predicted.code.length > 0) {
            console.log("  Already deployed. Skipping.");
            return;
        }

        address deployed = dd.deploy(salt, creationCode);
        require(deployed == predicted, "Address mismatch");
        console.log("  Deployed:", deployed);
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy impls on Arbitrum, upgrade all 3 beacons cross-chain.
 *         Needs 3 * 0.005 = 0.015 ETH for Hyperlane fees.
 */
contract Step2_UpgradeFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        string[3] memory names = ["QuickJoin", "OrgDeployer", "PaymasterHub"];
        bytes[3] memory creationCodes =
            [type(QuickJoin).creationCode, type(OrgDeployer).creationCode, type(PaymasterHub).creationCode];

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < 3; i++) {
            bytes32 salt = dd.computeSalt(names[i], VERSION);
            address predicted = dd.computeAddress(salt);

            // Deploy on Arbitrum via DD
            if (predicted.code.length == 0) {
                dd.deploy(salt, creationCodes[i]);
                console.log(string.concat(names[i], " deployed on Arbitrum"));
            } else {
                console.log(string.concat(names[i], " already deployed on Arbitrum"));
            }

            // Upgrade beacon cross-chain
            hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}(names[i], predicted, VERSION);
            console.log(string.concat(names[i], " beacon upgraded cross-chain"));
        }

        vm.stopBroadcast();

        console.log("\nWait ~5 min for Hyperlane relay, then run Step3.");
    }
}

/**
 * @title Step3_VerifyGnosis
 * @notice Verify all 3 beacons upgraded on Gnosis.
 */
contract Step3_VerifyGnosis is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        PoaManager pm = PoaManager(GNOSIS_POA_MANAGER);

        console.log("\n=== Step 3: Verify Gnosis Upgrades ===");

        string[3] memory names = ["QuickJoin", "OrgDeployer", "PaymasterHub"];
        bool allPassed = true;

        for (uint256 i = 0; i < 3; i++) {
            bytes32 salt = dd.computeSalt(names[i], VERSION);
            address expected = dd.computeAddress(salt);
            address current = pm.getCurrentImplementationById(keccak256(bytes(names[i])));

            if (current == expected) {
                console.log(string.concat("PASS: ", names[i], " upgraded to v9"));
            } else {
                console.log(string.concat("WAITING: ", names[i], " not yet upgraded"));
                console.log("  Expected:", expected);
                console.log("  Current:", current);
                allPassed = false;
            }
        }

        if (allPassed) {
            console.log("\nAll upgrades confirmed. Vouch-claim flow is now live.");
            console.log("Existing orgs already have vouch-claim selectors whitelisted.");
        }
    }
}
