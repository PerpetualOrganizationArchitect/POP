// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {PoaManagerSatellite} from "../../src/crosschain/PoaManagerSatellite.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

/// @dev Dummy implementation used to register infra types in the E2E test.
///      The cross-chain upgrade mechanism is identical regardless of contract content.
contract DummyInfraV1 {
    function version() external pure returns (string memory) {
        return "v1";
    }
}

/// @dev Dummy v2 implementation for infra upgrade testing.
contract DummyInfraV2 {
    function version() external pure returns (string memory) {
        return "v2";
    }
}

/**
 * @title RegisterInfraTypesHome
 * @notice Registers OrgDeployer, PaymasterHub, and UniversalAccountRegistry
 *         as contract types on the home chain PoaManager (via Hub).
 *         Deploys v1 implementations via DeterministicDeployer.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, DETERMINISTIC_DEPLOYER
 */
contract RegisterInfraTypesHome is Script {
    string[3] internal INFRA_TYPES = ["OrgDeployer", "PaymasterHub", "UniversalAccountRegistry"];

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        PoaManagerHub hub = PoaManagerHub(payable(hubAddr));

        console.log("\n=== Register Infra Types on Home Chain ===");

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < INFRA_TYPES.length; i++) {
            bytes32 salt = dd.computeSalt(INFRA_TYPES[i], "v1");
            address predicted = dd.computeAddress(salt);
            if (predicted.code.length == 0) {
                dd.deploy(salt, type(DummyInfraV1).creationCode);
            }
            hub.addContractType(INFRA_TYPES[i], predicted);
            console.log("  Registered:", INFRA_TYPES[i], "->", predicted);
        }

        vm.stopBroadcast();
        console.log("Home chain infra types registered.");
    }
}

/**
 * @title RegisterInfraTypesSatellite
 * @notice Registers infra types on the satellite PoaManager (via Satellite).
 *         Uses the same DD-predicted addresses (same on both chains).
 *
 * Required env vars:
 *   PRIVATE_KEY, SATELLITE, DETERMINISTIC_DEPLOYER
 */
contract RegisterInfraTypesSatellite is Script {
    string[3] internal INFRA_TYPES = ["OrgDeployer", "PaymasterHub", "UniversalAccountRegistry"];

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address satAddr = vm.envAddress("SATELLITE");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        PoaManagerSatellite satellite = PoaManagerSatellite(payable(satAddr));

        console.log("\n=== Register Infra Types on Satellite ===");

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < INFRA_TYPES.length; i++) {
            bytes32 salt = dd.computeSalt(INFRA_TYPES[i], "v1");
            address predicted = dd.computeAddress(salt);
            if (predicted.code.length == 0) {
                dd.deploy(salt, type(DummyInfraV1).creationCode);
            }
            satellite.addContractType(INFRA_TYPES[i], predicted);
            console.log("  Registered:", INFRA_TYPES[i], "->", predicted);
        }

        vm.stopBroadcast();
        console.log("Satellite infra types registered.");
    }
}

/**
 * @title DeployInfraV2
 * @notice Deploys v2 implementations for all 3 infra types via DD on the current chain.
 *         Run on BOTH home and satellite chains before triggering upgrades.
 *
 * Required env vars:
 *   PRIVATE_KEY, DETERMINISTIC_DEPLOYER
 */
contract DeployInfraV2 is Script {
    string[3] internal INFRA_TYPES = ["OrgDeployer", "PaymasterHub", "UniversalAccountRegistry"];

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);

        console.log("\n=== Deploying Infra V2 Implementations ===");

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < INFRA_TYPES.length; i++) {
            bytes32 salt = dd.computeSalt(INFRA_TYPES[i], "v2");
            address predicted = dd.computeAddress(salt);
            if (predicted.code.length > 0) {
                console.log("  Already deployed:", INFRA_TYPES[i], "v2 ->", predicted);
            } else {
                dd.deploy(salt, type(DummyInfraV2).creationCode);
                console.log("  Deployed:", INFRA_TYPES[i], "v2 ->", predicted);
            }
        }

        vm.stopBroadcast();
    }
}

/**
 * @title TriggerCrossChainInfraUpgrade
 * @notice Triggers cross-chain beacon upgrades for all 3 infra types from the Hub.
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, DETERMINISTIC_DEPLOYER
 */
contract TriggerCrossChainInfraUpgrade is Script {
    string[3] internal INFRA_TYPES = ["OrgDeployer", "PaymasterHub", "UniversalAccountRegistry"];

    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        PoaManagerHub hub = PoaManagerHub(payable(hubAddr));

        console.log("\n=== Triggering Cross-Chain Infra Upgrades ===");

        // 0.001 ETH per type per satellite (generous buffer)
        uint256 feePerType = 0.001 ether;

        vm.startBroadcast(deployerKey);

        for (uint256 i = 0; i < INFRA_TYPES.length; i++) {
            bytes32 salt = dd.computeSalt(INFRA_TYPES[i], "v2");
            address newImpl = dd.computeAddress(salt);
            require(newImpl.code.length > 0, "V2 impl not deployed");

            hub.upgradeBeaconCrossChain{value: feePerType}(INFRA_TYPES[i], newImpl, "v2");
            console.log("  Upgrade dispatched:", INFRA_TYPES[i], "->", newImpl);
        }

        vm.stopBroadcast();
        console.log("All infra upgrades dispatched. Hyperlane will relay.");
    }
}

/**
 * @title VerifyInfraUpgrade
 * @notice Read-only verification that infra type beacons point to v2 implementations.
 *         Reverts if any type is not yet upgraded (for shell script polling).
 *
 * Required env vars:
 *   POAMANAGER, DETERMINISTIC_DEPLOYER
 */
contract VerifyInfraUpgrade is Script {
    string[3] internal INFRA_TYPES = ["OrgDeployer", "PaymasterHub", "UniversalAccountRegistry"];

    function run() public view {
        address pmAddr = vm.envAddress("POAMANAGER");
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        PoaManager pm = PoaManager(pmAddr);
        DeterministicDeployer dd = DeterministicDeployer(ddAddr);

        console.log("=== Verify Infra Upgrades ===");

        uint256 upgraded;
        for (uint256 i = 0; i < INFRA_TYPES.length; i++) {
            bytes32 typeId = keccak256(bytes(INFRA_TYPES[i]));
            address currentImpl = pm.getCurrentImplementationById(typeId);

            bytes32 salt = dd.computeSalt(INFRA_TYPES[i], "v2");
            address expectedV2 = dd.computeAddress(salt);

            console.log(INFRA_TYPES[i]);
            console.log("  Current:", currentImpl);
            console.log("  Expected:", expectedV2);

            if (currentImpl == expectedV2) {
                console.log("  OK");
                upgraded++;
            } else {
                console.log("  PENDING");
            }
        }

        if (upgraded == 3) {
            console.log("PASS: All 3 infra types upgraded to v2");
        } else {
            revert("PENDING: Not all infra types upgraded yet");
        }
    }
}
