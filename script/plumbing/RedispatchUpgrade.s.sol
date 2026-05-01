// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

import {HybridVoting} from "../../src/HybridVoting.sol";
import {DirectDemocracyVoting} from "../../src/DirectDemocracyVoting.sol";
import {QuickJoin} from "../../src/QuickJoin.sol";
import {ParticipationToken} from "../../src/ParticipationToken.sol";
import {OrgDeployer} from "../../src/OrgDeployer.sol";
import {PaymasterHub} from "../../src/PaymasterHub.sol";

/**
 * @title Step1_DeployImplsOnGnosis
 * @notice Deploy v7 implementations on Gnosis via DD.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/RedispatchUpgrade.s.sol:Step1_DeployImplsOnGnosis \
 *     --rpc-url gnosis --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step1_DeployImplsOnGnosis is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    string constant VERSION = "v7";

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 1: Deploy v7 impls on Gnosis ===");

        vm.startBroadcast(deployerKey);

        _deployIfNeeded(dd, "HybridVoting", type(HybridVoting).creationCode);
        _deployIfNeeded(dd, "DirectDemocracyVoting", type(DirectDemocracyVoting).creationCode);
        _deployIfNeeded(dd, "QuickJoin", type(QuickJoin).creationCode);
        _deployIfNeeded(dd, "ParticipationToken", type(ParticipationToken).creationCode);
        _deployIfNeeded(dd, "OrgDeployer", type(OrgDeployer).creationCode);
        _deployIfNeeded(dd, "PaymasterHub", type(PaymasterHub).creationCode);

        vm.stopBroadcast();
        console.log("\nNext: Run Step2_UpgradeFromArbitrum on Arbitrum");
    }

    function _deployIfNeeded(DeterministicDeployer dd, string memory name, bytes memory code) internal {
        bytes32 salt = dd.computeSalt(name, VERSION);
        address predicted = dd.computeAddress(salt);
        if (predicted.code.length > 0) {
            console.log("  Already deployed:", name, predicted);
        } else {
            dd.deploy(salt, code);
            console.log("  Deployed:", name, predicted);
        }
    }
}

/**
 * @title Step2_UpgradeFromArbitrum
 * @notice Deploy v7 on Arbitrum + upgrade all 6 beacons cross-chain.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/RedispatchUpgrade.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract Step2_UpgradeFromArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    uint256 constant HYPERLANE_FEE = 0.005 ether;
    string constant VERSION = "v7";

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade 6 beacons from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");

        string[6] memory names =
            ["HybridVoting", "DirectDemocracyVoting", "QuickJoin", "ParticipationToken", "OrgDeployer", "PaymasterHub"];
        bytes[6] memory codes = [
            type(HybridVoting).creationCode,
            type(DirectDemocracyVoting).creationCode,
            type(QuickJoin).creationCode,
            type(ParticipationToken).creationCode,
            type(OrgDeployer).creationCode,
            type(PaymasterHub).creationCode
        ];

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < 6; i++) {
            bytes32 salt = dd.computeSalt(names[i], VERSION);
            address predicted = dd.computeAddress(salt);

            if (predicted.code.length == 0) {
                dd.deploy(salt, codes[i]);
                console.log("  Deployed on Arb:", names[i]);
            }

            hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}(names[i], predicted, VERSION);
            console.log("  Upgraded:", names[i], "->", predicted);
        }

        vm.stopBroadcast();
        console.log("\nWait ~5 min, then run Step3_Verify on Gnosis.");
    }
}

/**
 * @title Step3_Verify
 * @notice Verify all 6 beacons point to v7 on Gnosis.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/RedispatchUpgrade.s.sol:Step3_Verify \
 *     --rpc-url gnosis
 */
contract Step3_Verify is Script {
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;

    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        string[6] memory names =
            ["HybridVoting", "DirectDemocracyVoting", "QuickJoin", "ParticipationToken", "OrgDeployer", "PaymasterHub"];

        console.log("\n=== Verify Gnosis v7 beacons ===");

        uint256 passed = 0;
        for (uint256 i = 0; i < 6; i++) {
            bytes32 salt = dd.computeSalt(names[i], "v7");
            address expected = dd.computeAddress(salt);
            address current = PoaManager(GNOSIS_PM).getCurrentImplementationById(keccak256(bytes(names[i])));

            bool ok = current == expected;
            if (ok) passed++;
            console.log(ok ? "  PASS:" : "  WAITING:", names[i]);
        }

        console.log("\nResult:", passed, "/ 6");
    }
}
