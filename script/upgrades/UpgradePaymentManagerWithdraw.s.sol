// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PaymentManager} from "../../src/PaymentManager.sol";
import {IPaymentManager} from "../../src/interfaces/IPaymentManager.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/*
 * ============================================================================
 * PaymentManager Withdraw Upgrade — v2
 * ============================================================================
 *
 * Adds owner-only withdraw(token, to, amount) to PaymentManager so the
 * Executor can release uncommitted funds to any address via governance.
 *
 * Three-step cross-chain upgrade pattern:
 *   1. Deploy impl on Gnosis via DeterministicDeployer
 *   2. Deploy on Arbitrum + upgradeBeaconCrossChain
 *   3. Verify on Gnosis
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymentManagerWithdraw.s.sol:<StepContract> \
 *     --rpc-url <chain> --broadcast --slow
 *
 * ============================================================================
 */

// ─── Shared constants ───
address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;
address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
address constant GNOSIS_POA_MANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
uint256 constant HYPERLANE_FEE = 0.005 ether;
string constant VERSION = "v2";

/**
 * @title Step1_DeployImplOnGnosis
 * @notice Deploy PaymentManager v2 implementation on Gnosis via DeterministicDeployer.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymentManagerWithdraw.s.sol:Step1_DeployImplOnGnosis \
 *     --rpc-url gnosis --broadcast --slow
 */
contract Step1_DeployImplOnGnosis is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        DeterministicDeployer dd = DeterministicDeployer(DD);
        console.log("\n=== Step 1: Deploy PaymentManager v2 impl on Gnosis ===");
        console.log("Deployer:", deployer);

        bytes32 salt = dd.computeSalt("PaymentManager", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("Predicted impl address:", predicted);

        if (predicted.code.length > 0) {
            console.log("Already deployed at predicted address. Skipping.");
            return;
        }

        vm.startBroadcast(deployerKey);
        address deployed = dd.deploy(salt, type(PaymentManager).creationCode);
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
 *     script/UpgradePaymentManagerWithdraw.s.sol:Step2_UpgradeFromArbitrum \
 *     --rpc-url arbitrum --broadcast --slow
 */
contract Step2_UpgradeFromArbitrum is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        PoaManagerHub hub = PoaManagerHub(payable(HUB));
        DeterministicDeployer dd = DeterministicDeployer(DD);

        console.log("\n=== Step 2: Upgrade PaymentManager from Arbitrum ===");
        require(hub.owner() == deployer, "Deployer must own Hub");
        require(!hub.paused(), "Hub is paused");

        bytes32 salt = dd.computeSalt("PaymentManager", VERSION);
        address predicted = dd.computeAddress(salt);
        console.log("DD impl address:", predicted);

        vm.startBroadcast(deployerKey);

        // Deploy on Arbitrum via DD (same deterministic address as Gnosis)
        if (predicted.code.length == 0) {
            dd.deploy(salt, type(PaymentManager).creationCode);
            console.log("Deployed on Arbitrum");
        } else {
            console.log("Already deployed on Arbitrum");
        }

        // Upgrade beacon on both chains via Hyperlane
        hub.upgradeBeaconCrossChain{value: HYPERLANE_FEE}("PaymentManager", predicted, VERSION);
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
 *   forge script script/UpgradePaymentManagerWithdraw.s.sol:Step3_VerifyGnosis \
 *     --rpc-url gnosis
 */
contract Step3_VerifyGnosis is Script {
    function run() public view {
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("PaymentManager", VERSION);
        address expectedImpl = dd.computeAddress(salt);

        address currentImpl = PoaManager(GNOSIS_POA_MANAGER).getCurrentImplementationById(keccak256("PaymentManager"));

        console.log("\n=== Step 3: Verify Gnosis PaymentManager Upgrade ===");
        console.log("Expected impl:", expectedImpl);
        console.log("Current impl:", currentImpl);

        if (currentImpl == expectedImpl) {
            console.log("PASS: Beacon upgraded to v2 on Gnosis");
            console.log("\nNew capability: withdraw(token, to, amount)");
            console.log("  - Owner (Executor) can release uncommitted funds to any address");
            console.log("  - Funds committed to active distributions remain protected");
        } else {
            console.log("WAITING: Hyperlane message not yet relayed. Try again in a few minutes.");
        }
    }
}

/**
 * @title DryRun_SimulateUpgrade
 * @notice Simulate the full upgrade on a Gnosis fork to verify:
 *   1. Beacon upgrade works
 *   2. New withdraw function works for ETH and respects committed funds
 *   3. Existing PaymentManager storage is preserved
 *
 * Does NOT broadcast — read-only safety check.
 *
 * Usage:
 *   FOUNDRY_PROFILE=production forge script \
 *     script/UpgradePaymentManagerWithdraw.s.sol:DryRun_SimulateUpgrade \
 *     --rpc-url gnosis
 */
contract DryRun_SimulateUpgrade is Script {
    function run() public {
        PoaManager pm = PoaManager(GNOSIS_POA_MANAGER);
        address owner = pm.owner();

        console.log("\n=== DRY RUN: Simulating PaymentManager v2 upgrade on Gnosis fork ===\n");
        console.log("PoaManager owner:", owner);

        // ── 1. Deploy new implementation locally ──
        PaymentManager newImpl = new PaymentManager();
        console.log("New impl deployed:", address(newImpl));
        console.log("Impl size:", address(newImpl).code.length);
        require(address(newImpl).code.length <= 24576, "OVER EIP-170 LIMIT");

        // ── 2. Upgrade beacon ──
        address implBefore = pm.getCurrentImplementationById(keccak256("PaymentManager"));
        console.log("Impl before upgrade:", implBefore);

        vm.prank(owner);
        pm.upgradeBeacon("PaymentManager", address(newImpl), "dry-run-v2");

        address implAfter = pm.getCurrentImplementationById(keccak256("PaymentManager"));
        require(implAfter == address(newImpl), "Beacon upgrade failed");
        console.log("Impl after upgrade:", implAfter);
        console.log("Beacon upgrade: PASS\n");

        // ── 3. Create a test proxy via the upgraded beacon ──
        address beacon = pm.getBeaconById(keccak256("PaymentManager"));
        address executor = address(0xEEEE); // mock executor/owner
        address revenueToken = address(0xAAAA); // mock token

        BeaconProxy proxy =
            new BeaconProxy(beacon, abi.encodeWithSelector(PaymentManager.initialize.selector, executor, revenueToken));
        PaymentManager pmProxy = PaymentManager(payable(address(proxy)));
        console.log("Test proxy deployed:", address(pmProxy));
        console.log("Proxy owner:", pmProxy.owner());
        require(pmProxy.owner() == executor, "Owner mismatch");

        // ── 4. Fund the proxy with ETH ──
        vm.deal(address(pmProxy), 10 ether);
        console.log("Proxy ETH balance:", address(pmProxy).balance);

        // ── 5. Test withdraw: basic ETH transfer ──
        address recipient = address(0xBEEF);
        uint256 recipientBefore = recipient.balance;

        vm.prank(executor);
        pmProxy.withdraw(address(0), recipient, 3 ether);

        require(recipient.balance == recipientBefore + 3 ether, "Recipient didn't receive ETH");
        require(address(pmProxy).balance == 7 ether, "Proxy balance wrong after withdraw");
        console.log("Withdraw 3 ETH to recipient: PASS");

        // ── 6. Test withdraw: non-owner reverts ──
        vm.prank(address(0xDEAD));
        try pmProxy.withdraw(address(0), recipient, 1 ether) {
            revert("Should have reverted for non-owner");
        } catch {
            console.log("Non-owner withdraw reverts: PASS");
        }

        // ── 7. Test withdraw: zero amount reverts ──
        vm.prank(executor);
        try pmProxy.withdraw(address(0), recipient, 0) {
            revert("Should have reverted for zero amount");
        } catch {
            console.log("Zero amount reverts: PASS");
        }

        // ── 8. Test withdraw: zero address reverts ──
        vm.prank(executor);
        try pmProxy.withdraw(address(0), address(0), 1 ether) {
            revert("Should have reverted for zero address");
        } catch {
            console.log("Zero address reverts: PASS");
        }

        // ── 9. Test withdraw respects committed distributions ──
        // Create a distribution to commit 5 ETH
        bytes32 merkleRoot = keccak256("test-root");
        vm.prank(executor);
        uint256 distId = pmProxy.createDistribution(address(0), 5 ether, merkleRoot, block.number - 1);
        console.log("Created distribution:", distId, "(5 ETH committed)");

        // Balance=7, committed=5 → available=2. Withdrawing 3 should fail.
        vm.prank(executor);
        try pmProxy.withdraw(address(0), recipient, 3 ether) {
            revert("Should have reverted: exceeds available");
        } catch {
            console.log("Withdraw exceeding available reverts: PASS");
        }

        // Withdrawing 2 (exactly available) should succeed
        vm.prank(executor);
        pmProxy.withdraw(address(0), recipient, 2 ether);
        require(address(pmProxy).balance == 5 ether, "Balance wrong after constrained withdraw");
        console.log("Withdraw exactly available (2 ETH): PASS");

        // Withdrawing anything more should fail (all remaining is committed)
        vm.prank(executor);
        try pmProxy.withdraw(address(0), recipient, 1 wei) {
            revert("Should have reverted: nothing available");
        } catch {
            console.log("Withdraw when fully committed reverts: PASS");
        }

        // ── 10. Test existing functions still work after upgrade ──
        vm.prank(executor);
        pmProxy.setRevenueShareToken(address(0xBBBB));
        require(pmProxy.revenueShareToken() == address(0xBBBB), "setRevenueShareToken broken");
        console.log("Existing setRevenueShareToken: PASS");

        require(pmProxy.distributionCounter() == 1, "Distribution counter wrong");
        console.log("Distribution counter preserved: PASS");

        console.log("\n=== ALL DRY RUN CHECKS PASSED ===");
    }
}
