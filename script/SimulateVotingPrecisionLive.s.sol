// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {HybridVoting} from "../src/HybridVoting.sol";
import {IExecutor} from "../src/Executor.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title SimulateVotingPrecisionLive
 * @notice Fork-simulates a proposal mirroring Argus proposal 65 ("Sprint 20
 *         Priorities") against the LIVE Gnosis v10 HybridVoting deployment.
 *         Verifies the N_SLICE_PRECISION fix now picks the option with the
 *         actually-higher raw-weighted score, which the old integer math
 *         tied and broke by iteration order.
 *
 *         Proposal 65 on-chain outcomes (pre-v10):
 *           Option 0: score 21 (tied), winningOption = 0, isValid = false
 *           Option 1: score 21 (tied) — actually had more support
 *
 *         Expected v10 outcomes (post-fix):
 *           Option 1 wins on raw score. isValid still false (21.68% < 51%
 *           threshold), but for the correct reason now.
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/SimulateVotingPrecisionLive.s.sol:SimulateVotingPrecisionLive \
 *     --rpc-url https://rpc.gnosischain.com
 *
 *   (No --broadcast — fork-only simulation.)
 */
contract SimulateVotingPrecisionLive is Script {
    address constant ARGUS_HV = 0xa9209AfAdF721C2a55eC5875CC4716a9F1C5b0b7;
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
    address constant ARGUS_TOKEN = 0x5cafc2FA0653b34BDC51d738D67E70409A4b4806; // ERC20 for class 1

    // Real voter addresses from proposal 65 (Gnosis subgraph)
    address constant VOTER_A = 0x451563aB9b5b4E8DFAA602F5E7890089eDf6Bf10; // argus_prime
    address constant VOTER_B = 0x7150AEE7139cb2AC19c98c33C861B99E998b9a8E;
    address constant VOTER_C = 0xC04C860454e73a9Ba524783aCbC7f7D6F5767eb6;

    // Argus class 1 is QUADRATIC ERC20_BAL with minBalance = 1e18. The contract
    // computes classRawPower = sqrt(balance) * 100. To reproduce the exact
    // classRawPowers from proposal 65, we need balance = (rawPower / 100)^2.
    //
    // Proposal 65's classRawPowers[1]:
    //   VOTER_A: 5_131_276_644_200  → balance = 51_312_766_442^2 ≈ 2.633e24 wei
    //   VOTER_B: 4_811_444_689_400  → balance = 48_114_446_894^2 ≈ 2.315e24 wei
    //   VOTER_C: 4_759_201_613_700  → balance = 47_592_016_137^2 ≈ 2.265e24 wei
    //
    // These are huge numbers but well within uint256. minBalance = 1e18 is
    // easily exceeded since each balance is >2e24.
    uint256 constant VOTER_A_TOKENS = 51_312_766_442 * 51_312_766_442;
    uint256 constant VOTER_B_TOKENS = 48_114_446_894 * 48_114_446_894;
    uint256 constant VOTER_C_TOKENS = 47_592_016_137 * 47_592_016_137;

    function run() public {
        HybridVoting hv = HybridVoting(ARGUS_HV);

        console.log("\n========================================");
        console.log("  Proposal 65 replay on LIVE v10 HybridVoting");
        console.log("========================================");
        console.log("Argus HV:   ", ARGUS_HV);
        console.log("thresholdPct:", hv.thresholdPct());
        console.log("Current impl (should be v10 = 0x105371E...):", _beaconImpl(ARGUS_HV));

        // Mock all hat checks to pass for the 3 voters + deployer so we can
        // create a proposal and vote without needing real hat wearers.
        _mockAllHats(VOTER_A);
        _mockAllHats(VOTER_B);
        _mockAllHats(VOTER_C);

        // Mock ERC20 balances so classRawPowers match proposal 65 exactly.
        _mockTokenBalance(VOTER_A, VOTER_A_TOKENS);
        _mockTokenBalance(VOTER_B, VOTER_B_TOKENS);
        _mockTokenBalance(VOTER_C, VOTER_C_TOKENS);

        // 1. Create a 6-option signal proposal as VOTER_A
        uint256 proposalId = hv.proposalsCount();
        console.log("\nCreating proposal as VOTER_A, id =", proposalId);

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](6);
        for (uint256 i; i < 6; i++) {
            batches[i] = new IExecutor.Call[](0); // signal-only
        }

        vm.prank(VOTER_A);
        hv.createProposal(bytes("Replay P65"), keccak256("replay-65"), 10, 6, batches, new uint256[](0));

        // 2. Cast the exact weights from proposal 65
        _castVote(hv, proposalId, VOTER_A, [uint8(15), 25, 5, 20, 20, 15]);
        _castVote(hv, proposalId, VOTER_B, [uint8(25), 20, 10, 20, 10, 15]);
        _castVote(hv, proposalId, VOTER_C, [uint8(25), 20, 15, 20, 10, 10]);

        // 3. Warp past voting window
        vm.warp(block.timestamp + 11 minutes);

        // 4. Announce winner — read the impl's verdict
        (uint256 winner, bool valid) = hv.announceWinner(proposalId);

        console.log("\n--- Result ---");
        console.log("winner:", winner);
        console.log("valid: ", valid);

        // 5. Assertions
        require(winner == 1, "Expected option 1 (pattern-sub-tier-n-3+) to win with precision fix");
        require(!valid, "Threshold 51% not met by ~21.68%, isValid still false");

        console.log("\nPASS: v10 precision fix picks option 1 (higher raw score)");
        console.log("      Old integer math tied at 21 and picked option 0 by iteration order.");
        console.log("      isValid=false for the right reason (threshold), not a bogus tie.");
    }

    // ── helpers ──

    function _beaconImpl(address proxy) internal view returns (address impl) {
        // ERC-1967 beacon slot: bytes32(uint256(keccak256("eip1967.proxy.beacon")) - 1)
        bytes32 beaconSlot = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;
        address beacon = address(uint160(uint256(vm.load(proxy, beaconSlot))));
        (bool ok, bytes memory data) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
        require(ok, "beacon read failed");
        impl = abi.decode(data, (address));
    }

    function _mockAllHats(address voter) internal {
        // Pass every hat check; simpler than targeting individual IDs
        vm.mockCall(HATS, abi.encodeWithSelector(IHats.isWearerOfHat.selector, voter), abi.encode(true));
    }

    function _mockTokenBalance(address holder, uint256 balance) internal {
        vm.mockCall(ARGUS_TOKEN, abi.encodeWithSelector(IERC20.balanceOf.selector, holder), abi.encode(balance));
    }

    function _castVote(HybridVoting hv, uint256 proposalId, address voter, uint8[6] memory weights) internal {
        uint8[] memory idxs = new uint8[](6);
        uint8[] memory wts = new uint8[](6);
        for (uint8 i; i < 6; i++) {
            idxs[i] = i;
            wts[i] = weights[i];
        }
        vm.prank(voter);
        hv.vote(proposalId, idxs, wts);
    }
}
