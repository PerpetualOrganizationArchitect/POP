// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {EligibilityModule} from "../../src/EligibilityModule.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";

/**
 * @title FixEligibilityDeadlock
 * @notice Upgrades EligibilityModule to v2 and fixes the CONTRIBUTOR hat vouch config.
 *
 * Problem: CONTRIBUTOR hat has vouching enabled with combineWithHierarchy=false,
 *          so only vouching determines eligibility. Nobody can vouch because no
 *          CONTRIBUTOR exists yet (chicken-and-egg). The deployer was minted the hat
 *          but the eligibility module reports them as ineligible.
 *
 * Fix: Upgrade EligibilityModule to accept PoaManager as governanceAdmin,
 *      then reconfigure vouching with combineWithHierarchy=true.
 *
 * Prerequisites:
 *   - Deployer still owns the Hub (Ownable2Step transfer not accepted)
 *   - EligibilityModule.sol has been patched with governanceAdmin + initializeV2
 *   - Built with FOUNDRY_PROFILE=production
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixEligibilityDeadlock.s.sol:FixEligibilityDeadlock \
 *     --rpc-url arbitrum --broadcast --slow
 */
contract FixEligibilityDeadlock is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        // --- Addresses from deployment ---
        address hubAddr = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
        address eligibilityModule = 0xE4F9CB9C843D0A5bd5D52e3266138B13A635743b;

        // CONTRIBUTOR hat ID
        uint256 contributorHatId = 0x0000005d00010002000000000000000000000000000000000000000000000000;

        PoaManagerHub hub = PoaManagerHub(payable(hubAddr));

        console.log("\n=== Fix Eligibility Deadlock ===");
        console.log("Deployer:", deployer);
        console.log("Hub:", hubAddr);
        console.log("EligibilityModule:", eligibilityModule);

        // Verify deployer owns the Hub
        require(hub.owner() == deployer, "Deployer must own Hub");
        console.log("Hub owner verified:", deployer);

        // Get PoaManager address from Hub
        address poaManager = address(hub.poaManager());
        console.log("PoaManager:", poaManager);

        vm.startBroadcast(deployerKey);

        // Step 1: Deploy new EligibilityModule implementation
        EligibilityModule newImpl = new EligibilityModule();
        console.log("New EligibilityModule impl:", address(newImpl));

        // Step 2: Upgrade beacon (local only — Gnosis doesn't need this fix)
        hub.upgradeBeaconLocal("EligibilityModule", address(newImpl), "v2");
        console.log("Beacon upgraded to v2");

        // Step 3: Set PoaManager as governanceAdmin via initializeV2
        // Call path: Hub.adminCall -> PoaManager.adminCall -> EligibilityModule.initializeV2
        hub.adminCall(eligibilityModule, abi.encodeWithSignature("initializeV2(address)", poaManager));
        console.log("governanceAdmin set to PoaManager:", poaManager);

        // Step 4: Fix CONTRIBUTOR vouch config — set combineWithHierarchy=true
        // This means: eligible = hierarchyEligible OR vouchEligible
        // The deployer has hierarchyEligible=true, so they'll be eligible immediately
        hub.adminCall(
            eligibilityModule,
            abi.encodeWithSignature(
                "configureVouching(uint256,uint32,uint256,bool)",
                contributorHatId,
                uint32(1), // quorum: 1 vouch still required for NEW contributors
                contributorHatId, // voucherHatId: contributors vouch for each other
                true // combineWithHierarchy: hierarchy OR vouching determines eligibility
            )
        );
        console.log("CONTRIBUTOR vouch config fixed: combineWithHierarchy=true");

        vm.stopBroadcast();

        console.log("\n=== Fix Complete ===");
        console.log("The deployer should now be eligible for the CONTRIBUTOR hat.");
        console.log("Verify with: cast call", eligibilityModule);
        console.log('  "getWearerStatus(address,uint256)(bool,bool)"', deployer, contributorHatId);
    }
}

/**
 * @title VerifyEligibilityFix
 * @notice Read-only verification that the fix was applied correctly.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/FixEligibilityDeadlock.s.sol:VerifyEligibilityFix \
 *     --rpc-url arbitrum
 */
contract VerifyEligibilityFix is Script {
    function run() public view {
        address deployer = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;
        address eligibilityModule = 0xE4F9CB9C843D0A5bd5D52e3266138B13A635743b;
        address hats = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
        uint256 contributorHatId = 0x0000005d00010002000000000000000000000000000000000000000000000000;

        console.log("\n=== Verify Eligibility Fix ===");

        // Check wearer status
        (bool eligible, bool standing) =
            EligibilityModule(eligibilityModule).getWearerStatus(deployer, contributorHatId);
        console.log("Deployer eligible:", eligible);
        console.log("Deployer standing:", standing);

        // Check isWearerOfHat via Hats Protocol
        (bool success, bytes memory data) =
            hats.staticcall(abi.encodeWithSignature("isWearerOfHat(address,uint256)", deployer, contributorHatId));
        bool isWearer = success && abi.decode(data, (bool));
        console.log("Deployer wears CONTRIBUTOR hat:", isWearer);

        // Check vouch config
        bool vouchEnabled = EligibilityModule(eligibilityModule).isVouchingEnabled(contributorHatId);
        console.log("Vouching still enabled:", vouchEnabled);

        // Summary
        uint256 passed = 0;
        if (eligible) passed++;
        if (standing) passed++;
        if (isWearer) passed++;
        if (vouchEnabled) passed++;

        console.log("\nPassed:", passed, "/ 4");
        if (passed == 4) {
            console.log("ALL CHECKS PASSED - Deployer can now use the CONTRIBUTOR hat");
        } else {
            console.log("SOME CHECKS FAILED - review above");
        }
    }
}
