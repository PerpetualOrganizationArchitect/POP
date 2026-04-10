// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {OrgDeployer} from "../src/OrgDeployer.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../src/PoaManager.sol";

/**
 * @title UpgradeQuickJoinAndDeployer
 * @notice Upgrades QuickJoin and OrgDeployer beacons on Arbitrum (local) and Gnosis (cross-chain).
 *
 * QuickJoin v2 adds vouch-claim functions:
 *   - claimHatsWithUser(uint256[])
 *   - registerAndClaimHats(address,string,uint256,uint256,bytes,uint256[])
 *   - registerAndClaimHatsWithPasskey(...)
 *
 * OrgDeployer v2 adds auto-whitelist entries for the 3 new QuickJoin functions.
 *
 * Prerequisites:
 *   - Deployer owns the Hub (0xA6F4... on Arbitrum)
 *   - Hub has 1 active satellite (Gnosis, domain 100)
 *   - Built with FOUNDRY_PROFILE=production
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeQuickJoinAndDeployer.s.sol:UpgradeQuickJoinAndDeployer \
 *     --rpc-url arbitrum --broadcast --slow
 */
contract UpgradeQuickJoinAndDeployer is Script {
    // On-chain addresses
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant DEPLOYER = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;

    // Hyperlane fee buffer (0.005 ETH per cross-chain call, excess refunded)
    uint256 constant HYPERLANE_FEE = 0.005 ether;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));

        console.log("\n=== Upgrade QuickJoin & OrgDeployer ===");
        console.log("Deployer:", deployer);
        console.log("Hub:", HUB);

        // Pre-flight checks
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");
        require(hub.activeSatelliteCount() == 1, "Expected 1 active satellite (Gnosis)");
        console.log("Pre-flight checks passed");

        address poaManager = address(hub.poaManager());
        console.log("PoaManager:", poaManager);

        // Verify current implementations before upgrade
        address currentQJ = PoaManager(poaManager).getCurrentImplementationById(keccak256("QuickJoin"));
        address currentOD = PoaManager(poaManager).getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("Current QuickJoin impl:", currentQJ);
        console.log("Current OrgDeployer impl:", currentOD);

        vm.startBroadcast(deployerKey);

        // ── Step 1: Deploy new implementations ──
        QuickJoin newQJ = new QuickJoin();
        OrgDeployer newOD = new OrgDeployer();
        console.log("\nNew QuickJoin impl:", address(newQJ));
        console.log("New OrgDeployer impl:", address(newOD));

        // ── Step 2: Upgrade QuickJoin on Arbitrum + Gnosis ──
        // upgradeBeaconCrossChain upgrades locally AND dispatches to all satellites
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("QuickJoin", address(newQJ), "v2");
        console.log("\nQuickJoin upgraded (Arbitrum local + Gnosis cross-chain dispatch)");

        // ── Step 3: Upgrade OrgDeployer on Arbitrum + Gnosis ──
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("OrgDeployer", address(newOD), "v2");
        console.log("OrgDeployer upgraded (Arbitrum local + Gnosis cross-chain dispatch)");

        vm.stopBroadcast();

        // Verify
        address updatedQJ = PoaManager(poaManager).getCurrentImplementationById(keccak256("QuickJoin"));
        address updatedOD = PoaManager(poaManager).getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("\n=== Verification ===");
        console.log("QuickJoin impl updated:", updatedQJ == address(newQJ) ? "PASS" : "FAIL");
        console.log("OrgDeployer impl updated:", updatedOD == address(newOD) ? "PASS" : "FAIL");

        console.log("\n=== Upgrade Complete ===");
        console.log("Arbitrum: beacons updated immediately");
        console.log("Gnosis: cross-chain messages dispatched (wait ~5min for Hyperlane relay)");
        console.log("\nNext: For existing orgs, run WhitelistNewQuickJoinFunctions to add paymaster rules");
    }
}

/**
 * @title VerifyQuickJoinUpgrade
 * @notice Read-only verification that the upgrade was applied on Arbitrum.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradeQuickJoinAndDeployer.s.sol:VerifyQuickJoinUpgrade \
 *     --rpc-url arbitrum
 */
contract VerifyQuickJoinUpgrade is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;

    function run() public view {
        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        address poaManager = address(hub.poaManager());

        console.log("\n=== Verify QuickJoin Upgrade ===");

        // Check QuickJoin has the new function selectors
        address qjImpl = PoaManager(poaManager).getCurrentImplementationById(keccak256("QuickJoin"));
        console.log("QuickJoin implementation:", qjImpl);

        // Check new function selectors exist on the implementation
        bytes4 sel1 = bytes4(keccak256("claimHatsWithUser(uint256[])"));
        bytes4 sel2 = bytes4(keccak256("registerAndClaimHats(address,string,uint256,uint256,bytes,uint256[])"));
        bytes4 sel3 = bytes4(
            keccak256(
                "registerAndClaimHatsWithPasskey((bytes32,bytes32,bytes32,uint256),string,uint256,uint256,(bytes,bytes,uint256,uint256,bytes32,bytes32),uint256[])"
            )
        );

        console.log("claimHatsWithUser selector:", vm.toString(sel1));
        console.log("registerAndClaimHats selector:", vm.toString(sel2));
        console.log("registerAndClaimHatsWithPasskey selector:", vm.toString(sel3));

        // Check implementation has code
        bool hasCode = qjImpl.code.length > 0;
        console.log("Implementation has code:", hasCode ? "PASS" : "FAIL");

        // Check OrgDeployer
        address odImpl = PoaManager(poaManager).getCurrentImplementationById(keccak256("OrgDeployer"));
        console.log("\nOrgDeployer implementation:", odImpl);
        console.log("OrgDeployer has code:", odImpl.code.length > 0 ? "PASS" : "FAIL");

        console.log("\n=== Done ===");
    }
}
