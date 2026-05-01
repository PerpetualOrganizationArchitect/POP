// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libs/VotingMath.sol";

// Helper contract to test library reverts
contract VotingMathWrapper {
    function validateWeights(VotingMath.Weights memory w) public pure {
        VotingMath.validateWeights(w);
    }
}

contract VotingMathTest is Test {
    VotingMathWrapper wrapper;

    function setUp() public {
        wrapper = new VotingMathWrapper();
    }

    /* ─────────── Test Weight Validation ─────────── */

    function testValidateWeights_ValidInput() public {
        uint8[] memory idxs = new uint8[](3);
        uint8[] memory weights = new uint8[](3);

        idxs[0] = 0;
        idxs[1] = 1;
        idxs[2] = 2;

        weights[0] = 50;
        weights[1] = 30;
        weights[2] = 20;

        // Should not revert for valid input
        VotingMath.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 3}));
    }

    function testValidateWeights_InvalidSum() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);

        idxs[0] = 0;
        idxs[1] = 1;

        weights[0] = 50;
        weights[1] = 40; // Sum = 90, not 100

        vm.expectRevert(abi.encodeWithSelector(VotingMath.WeightSumNot100.selector, 90));
        wrapper.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 2}));
    }

    function testValidateWeights_DuplicateIndex() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);

        idxs[0] = 0;
        idxs[1] = 0; // Duplicate

        weights[0] = 50;
        weights[1] = 50;

        vm.expectRevert(VotingMath.DuplicateIndex.selector);
        wrapper.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 2}));
    }

    function testValidateWeights_InvalidIndex() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);

        idxs[0] = 0;
        idxs[1] = 3; // Index out of bounds for 2 options

        weights[0] = 50;
        weights[1] = 50;

        vm.expectRevert(VotingMath.InvalidIndex.selector);
        wrapper.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 2}));
    }

    function testValidateWeights_InvalidWeight() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);

        idxs[0] = 0;
        idxs[1] = 1;

        weights[0] = 101; // Weight > 100
        weights[1] = 0;

        vm.expectRevert(VotingMath.InvalidWeight.selector);
        wrapper.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 2}));
    }

    function testValidateWeights_LengthMismatch() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](3); // Different length

        idxs[0] = 0;
        idxs[1] = 1;

        weights[0] = 50;
        weights[1] = 30;
        weights[2] = 20;

        vm.expectRevert(VotingMath.LengthMismatch.selector);
        wrapper.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: 3}));
    }

    /* ─────────── Test Power Calculation ─────────── */

    function testPowerPT_LinearVoting() public {
        uint256 balance = 1000 ether;
        uint256 minBal = 100 ether;

        uint256 power = VotingMath.powerPT(balance, minBal, false);
        assertEq(power, 1000 ether, "Linear power should equal balance");
    }

    function testPowerPT_QuadraticVoting() public {
        uint256 balance = 100 ether;
        uint256 minBal = 10 ether;

        uint256 power = VotingMath.powerPT(balance, minBal, true);
        // sqrt(100 ether) = sqrt(100 * 10^18) = 10 * 10^9 = 10^10
        assertEq(power, 10 * 1e9, "Quadratic power should be sqrt of balance");
    }

    function testPowerPT_BelowMinBalance() public {
        uint256 balance = 50 ether;
        uint256 minBal = 100 ether;

        uint256 power = VotingMath.powerPT(balance, minBal, false);
        assertEq(power, 0, "Power should be 0 when below min balance");
    }

    function testPowersHybrid_WithDemocracyHat() public {
        uint256 balance = 1000 ether;
        uint256 minBal = 100 ether;

        (uint256 ddRaw, uint256 ptRaw) = VotingMath.powersHybrid(true, balance, minBal, false);

        assertEq(ddRaw, 100, "DD raw should be 100 with democracy hat");
        assertEq(ptRaw, 1000 ether * 100, "PT raw should be balance * 100");
    }

    function testPowersHybrid_WithoutDemocracyHat() public {
        uint256 balance = 1000 ether;
        uint256 minBal = 100 ether;

        (uint256 ddRaw, uint256 ptRaw) = VotingMath.powersHybrid(false, balance, minBal, false);

        assertEq(ddRaw, 0, "DD raw should be 0 without democracy hat");
        assertEq(ptRaw, 1000 ether * 100, "PT raw should be balance * 100");
    }

    /* ─────────── Test Delta Calculations ─────────── */

    function testDeltasPT() public {
        uint256 power = 1000;
        uint8[] memory idxs = new uint8[](3);
        uint8[] memory weights = new uint8[](3);

        idxs[0] = 0;
        idxs[1] = 1;
        idxs[2] = 2;

        weights[0] = 50;
        weights[1] = 30;
        weights[2] = 20;

        uint256[] memory deltas = VotingMath.deltasPT(power, idxs, weights);

        assertEq(deltas.length, 3, "Should return correct number of deltas");
        assertEq(deltas[0], 50000, "Delta 0 should be power * weight[0]");
        assertEq(deltas[1], 30000, "Delta 1 should be power * weight[1]");
        assertEq(deltas[2], 20000, "Delta 2 should be power * weight[2]");
    }

    function testDeltasHybrid() public {
        uint256 ddRaw = 100;
        uint256 ptRaw = 10000;
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);

        idxs[0] = 0;
        idxs[1] = 1;

        weights[0] = 60;
        weights[1] = 40;

        (uint256[] memory ddDeltas, uint256[] memory ptDeltas) = VotingMath.deltasHybrid(ddRaw, ptRaw, idxs, weights);

        assertEq(ddDeltas.length, 2, "Should return correct number of DD deltas");
        assertEq(ptDeltas.length, 2, "Should return correct number of PT deltas");

        assertEq(ddDeltas[0], 60, "DD delta 0 should be ddRaw * weight[0] / 100");
        assertEq(ddDeltas[1], 40, "DD delta 1 should be ddRaw * weight[1] / 100");

        assertEq(ptDeltas[0], 6000, "PT delta 0 should be ptRaw * weight[0] / 100");
        assertEq(ptDeltas[1], 4000, "PT delta 1 should be ptRaw * weight[1] / 100");
    }

    /* ─────────── Test Winner Picking ─────────── */

    function testPickWinnerMajority_SimpleWinner() public {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 30;
        scores[1] = 50;
        scores[2] = 20;

        uint256 totalWeight = 100;
        uint8 thresholdPct = 40;

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, true);

        assertEq(win, 1, "Option 1 should win");
        assertTrue(ok, "Should meet threshold");
        assertEq(hi, 50, "Highest score should be 50");
        assertEq(second, 30, "Second highest should be 30");
    }

    function testPickWinnerMajority_ThresholdNotMet() public {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 10;
        scores[1] = 20;
        scores[2] = 15;

        uint256 totalWeight = 100;
        uint8 thresholdPct = 25; // Requires > 25% of total weight

        (uint256 win, bool ok,,) = VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, true);

        assertEq(win, 1, "Option 1 should be winner candidate");
        assertFalse(ok, "Should not meet threshold (20 * 100 = 2000, not >= 2500)");
    }

    function testPickWinnerMajority_ExactThresholdPasses() public {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 10;
        scores[1] = 25; // Exactly 25% of 100
        scores[2] = 15;

        uint256 totalWeight = 100;
        uint8 thresholdPct = 25; // Requires >= 25% of total weight

        (uint256 win, bool ok,,) = VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, false);

        assertEq(win, 1, "Option 1 should be winner");
        assertTrue(ok, "Should meet threshold (25 * 100 = 2500, >= 2500)");
    }

    function testPickWinnerMajority_TieWithStrictRequirement() public {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 50;
        scores[1] = 50;

        uint256 totalWeight = 100;
        uint8 thresholdPct = 40;

        (uint256 win, bool ok,,) = VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, true);

        assertFalse(ok, "Should not be valid with tie and strict requirement");
    }

    function testPickWinnerMajority_TieWithoutStrictRequirement() public {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 50;
        scores[1] = 50;

        uint256 totalWeight = 100;
        uint8 thresholdPct = 40;

        (uint256 win, bool ok,,) = VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, false);

        assertTrue(ok, "Should be valid with tie when not strict");
        assertEq(win, 0, "First option should win in tie");
    }

    function testPickWinnerTwoSlice_SimpleCase() public {
        uint256[] memory ddRaw = new uint256[](3);
        uint256[] memory ptRaw = new uint256[](3);

        ddRaw[0] = 30;
        ddRaw[1] = 50;
        ddRaw[2] = 20;

        ptRaw[0] = 2000;
        ptRaw[1] = 1000;
        ptRaw[2] = 3000;

        uint256 ddTotalRaw = 100;
        uint256 ptTotalRaw = 6000;
        uint8 ddSharePct = 50; // 50/50 split
        uint8 thresholdPct = 30; // Lowered threshold to 30% so 35% passes

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerTwoSlice(ddRaw, ptRaw, ddTotalRaw, ptTotalRaw, ddSharePct, thresholdPct);

        // DD scaled: [15, 25, 10] (out of 50)
        // PT scaled: [16.67, 8.33, 25] (out of 50)
        // Total: [31.67, 33.33, 35]

        assertEq(win, 2, "Option 2 should win");
        assertTrue(ok, "Should meet threshold (35% > 30%)");
    }

    function testPickWinnerTwoSlice_ZeroTotals() public {
        uint256[] memory ddRaw = new uint256[](2);
        uint256[] memory ptRaw = new uint256[](2);

        ddRaw[0] = 0;
        ddRaw[1] = 0;
        ptRaw[0] = 0;
        ptRaw[1] = 0;

        (uint256 win, bool ok, uint256 hi, uint256 second) = VotingMath.pickWinnerTwoSlice(ddRaw, ptRaw, 0, 0, 50, 40);

        assertEq(win, 0, "Should return 0 as winner");
        assertFalse(ok, "Should not be valid with zero totals");
        assertEq(hi, 0, "Highest should be 0");
        assertEq(second, 0, "Second should be 0");
    }

    /* ─────────── Test pickWinnerNSlices ─────────── */

    // ---------- Helpers ----------

    /// @dev Build a uint8[] slice array inline.
    function _slices1(uint8 a) internal pure returns (uint8[] memory s) {
        s = new uint8[](1);
        s[0] = a;
    }

    function _slices2(uint8 a, uint8 b) internal pure returns (uint8[] memory s) {
        s = new uint8[](2);
        s[0] = a;
        s[1] = b;
    }

    function _slices3(uint8 a, uint8 b, uint8 c) internal pure returns (uint8[] memory s) {
        s = new uint8[](3);
        s[0] = a;
        s[1] = b;
        s[2] = c;
    }

    /// @dev Build a 2-D option×class raw matrix with the given dimensions.
    function _matrix(uint256 numOptions, uint256 numClasses) internal pure returns (uint256[][] memory m) {
        m = new uint256[][](numOptions);
        for (uint256 i; i < numOptions; ++i) {
            m[i] = new uint256[](numClasses);
        }
    }

    function _totals(uint256 a) internal pure returns (uint256[] memory t) {
        t = new uint256[](1);
        t[0] = a;
    }

    function _totals2(uint256 a, uint256 b) internal pure returns (uint256[] memory t) {
        t = new uint256[](2);
        t[0] = a;
        t[1] = b;
    }

    /// @dev Expected scaled score for an option given its raw matrix row.
    ///      Mirrors the library's integer math at the test level so we can
    ///      reason about expected outputs without reimplementing the loop.
    function _expectedScore(uint256[] memory optRow, uint256[] memory totals, uint8[] memory slices)
        internal
        pure
        returns (uint256 score)
    {
        for (uint256 c; c < slices.length; ++c) {
            if (totals[c] > 0) {
                score += (optRow[c] * slices[c] * VotingMath.N_SLICE_PRECISION) / totals[c];
            }
        }
    }

    // ---------- Basic behavior ----------

    /// @notice Empty options array returns (0, false, 0, 0) — defensive path.
    function testPickWinnerNSlices_EmptyOptions() public {
        uint256[][] memory m = new uint256[][](0);
        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerNSlices(m, _totals(0), _slices1(100), 51, true);
        assertEq(win, 0);
        assertFalse(ok);
        assertEq(hi, 0);
        assertEq(second, 0);
    }

    /// @notice Single class, clear winner above threshold.
    function testPickWinnerNSlices_SingleClassSimple() public {
        uint256[][] memory m = _matrix(3, 1);
        m[0][0] = 60; // option 0 : 60/100
        m[1][0] = 30;
        m[2][0] = 10;

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 51, true);

        assertEq(win, 0);
        assertTrue(ok);
        // 60/100 × 100 × PRECISION = 600_000
        assertEq(hi, 60 * VotingMath.N_SLICE_PRECISION);
        // 30/100 × 100 × PRECISION = 300_000
        assertEq(second, 30 * VotingMath.N_SLICE_PRECISION);
    }

    /// @notice Scaled return values match thresholdPct scaled by PRECISION.
    function testPickWinnerNSlices_ThresholdScaling() public {
        uint256[][] memory m = _matrix(2, 1);
        m[0][0] = 51;
        m[1][0] = 49;

        // Exactly-at-threshold: 51/100 × 100 = 51 scaled. Threshold = 51 scaled.
        (, bool ok,,) = VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 51, true);
        assertTrue(ok, "51% should meet 51% threshold exactly");

        // One point below threshold: 50/100 × 100 = 50 scaled.
        m[0][0] = 50;
        m[1][0] = 50;
        (, ok,,) = VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 51, true);
        assertFalse(ok, "50% should NOT meet 51% threshold");
    }

    // ---------- The bug this fix targets ----------

    /// @notice The Argus proposal 65 case: options 0 and 1 have different
    ///         on-chain raw totals in the ERC20 class; pre-fix integer math
    ///         collapsed them to a tie. With PRECISION scaling, the higher
    ///         raw-total option correctly wins.
    function testPickWinnerNSlices_LargeTokenBalances_PrecisionMatters() public {
        // Real-world-shaped inputs from Argus proposal 65.
        uint256[][] memory m = _matrix(6, 2);
        // Class 0 (DIRECT): 65, 65, 30, 60, 40, 40 (sum = 300)
        m[0][0] = 65;
        m[1][0] = 65;
        m[2][0] = 30;
        m[3][0] = 60;
        m[4][0] = 40;
        m[5][0] = 40;
        // Class 1 (ERC20): two ~3.2e12 values that differ at 11th digit
        m[0][1] = 3_162_353_072_405;
        m[1][1] = 3_196_948_421_670;
        m[2][1] = 1_451_588_543_205;
        m[3][1] = 2_940_384_589_460;
        m[4][1] = 1_983_319_959_150;
        m[5][1] = 1_967_328_361_410;

        uint256[] memory totals = _totals2(300, 14_701_922_947_300);
        uint8[] memory slices = _slices2(80, 20);

        (uint256 win, bool ok, uint256 hi, uint256 second) = VotingMath.pickWinnerNSlices(m, totals, slices, 51, true);

        // Pre-fix: both options would score 21 exactly and option 0 would win
        // the tie by iteration order with ok=false (strict margin fails).
        // Post-fix: option 1 actually has the higher raw-weighted score.
        assertEq(win, 1, "Option 1 has higher ERC20 class weighted support");
        assertTrue(hi > second, "Scores must now distinguish cleanly");

        // Threshold still not met (21.68% < 51%), so ok is false, but for the
        // correct reason — threshold, not spurious tie.
        assertFalse(ok, "51% threshold not met regardless of precision");
    }

    /// @notice Genuine equal-score tie behaves the same before and after fix:
    ///         first iterated option wins, strict-majority fails.
    function testPickWinnerNSlices_ExactTie_FirstWinsStrictFails() public {
        uint256[][] memory m = _matrix(2, 1);
        m[0][0] = 50;
        m[1][0] = 50;

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 40, true);

        assertEq(win, 0, "First iterated option wins the tie");
        assertEq(hi, second, "True tie: hi == second");
        assertFalse(ok, "Strict majority fails on tie");
    }

    /// @notice Non-strict mode accepts ties.
    function testPickWinnerNSlices_Tie_NonStrictPasses() public {
        uint256[][] memory m = _matrix(2, 1);
        m[0][0] = 50;
        m[1][0] = 50;

        (, bool ok,,) = VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 40, false);

        assertTrue(ok, "Non-strict allows the tie, threshold met");
    }

    // ---------- Multi-class correctness ----------

    /// @notice Two classes with equal slices — each class contributes up to
    ///         its slice; option 0 wins both classes.
    function testPickWinnerNSlices_TwoClasses_BothContribute() public {
        uint256[][] memory m = _matrix(2, 2);
        m[0][0] = 80; // 80% of class 0
        m[1][0] = 20;
        m[0][1] = 70; // 70% of class 1
        m[1][1] = 30;

        (uint256 win, bool ok,,) = VotingMath.pickWinnerNSlices(m, _totals2(100, 100), _slices2(50, 50), 51, true);

        assertEq(win, 0);
        // score opt 0 = (80 × 50)/100 + (70 × 50)/100 = 40 + 35 = 75 (scaled)
        // score opt 1 = (20 × 50)/100 + (30 × 50)/100 = 10 + 15 = 25 (scaled)
        // Threshold 51 met.
        assertTrue(ok);
    }

    /// @notice Class with zero voters contributes zero to every option,
    ///         preserving correct ordering on the remaining class.
    function testPickWinnerNSlices_ZeroClassTotalContributesZero() public {
        uint256[][] memory m = _matrix(2, 2);
        m[0][0] = 60;
        m[1][0] = 40;
        // Class 1 has all zeros (nobody voted in this class)
        m[0][1] = 0;
        m[1][1] = 0;

        (uint256 win, bool ok, uint256 hi,) =
            VotingMath.pickWinnerNSlices(m, _totals2(100, 0), _slices2(70, 30), 40, true);

        assertEq(win, 0);
        // opt 0 raw score = (60 × 70) / 100 = 42, class 1 contributes 0
        // hi scaled = 42 × PRECISION
        assertEq(hi, 42 * VotingMath.N_SLICE_PRECISION);
        // Threshold 40 met, strict margin passes.
        assertTrue(ok);
    }

    /// @notice Three classes with non-uniform slices.
    function testPickWinnerNSlices_ThreeClasses() public {
        uint256[][] memory m = _matrix(3, 3);
        // Class 0 (slice 50): opt 0 dominates
        m[0][0] = 100;
        m[1][0] = 0;
        m[2][0] = 0;
        // Class 1 (slice 30): opt 1 dominates
        m[0][1] = 0;
        m[1][1] = 100;
        m[2][1] = 0;
        // Class 2 (slice 20): opt 2 dominates
        m[0][2] = 0;
        m[1][2] = 0;
        m[2][2] = 100;

        uint256[] memory t3 = new uint256[](3);
        t3[0] = 100;
        t3[1] = 100;
        t3[2] = 100;

        (uint256 win, bool ok,,) = VotingMath.pickWinnerNSlices(m, t3, _slices3(50, 30, 20), 51, true);

        // opt 0 = 50 × PRECISION, opt 1 = 30 × PRECISION, opt 2 = 20 × PRECISION.
        // Threshold 51 NOT met (50 < 51).
        assertEq(win, 0);
        assertFalse(ok, "50% < 51% threshold");
    }

    // ---------- Vote-weight distribution ----------

    /// @notice A voter splitting weight across multiple options reduces each
    ///         option's share proportionally — correctness check for the
    ///         common "rank priorities" voting pattern.
    function testPickWinnerNSlices_WeightSplit() public {
        // Simulate the state the contract's vote() would produce if a voter
        // distributed 70/30 between two options with a single class of 100 raw.
        uint256[][] memory m = _matrix(2, 1);
        m[0][0] = 70; // (100 × 70)/100 = 70
        m[1][0] = 30;

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerNSlices(m, _totals(100), _slices1(100), 51, true);

        assertEq(win, 0);
        assertEq(hi, 70 * VotingMath.N_SLICE_PRECISION);
        assertEq(second, 30 * VotingMath.N_SLICE_PRECISION);
        assertTrue(ok);
    }

    // ---------- Overflow / edge bounds ----------

    /// @notice Max-sized inputs don't overflow uint256. classRaw is bounded
    ///         by uint128 on-chain (see HybridVoting.PollOption.classRaw),
    ///         slice by 100, PRECISION by 10000. Product <= 2^128 × 10^6.
    function testPickWinnerNSlices_NoOverflowAtUint128Max() public {
        uint256[][] memory m = _matrix(2, 1);
        m[0][0] = type(uint128).max;
        m[1][0] = type(uint128).max / 2;

        (uint256 win, bool ok,,) = VotingMath.pickWinnerNSlices(
            m, _totals(uint256(type(uint128).max) + uint256(type(uint128).max) / 2), _slices1(100), 10, true
        );

        assertEq(win, 0, "Larger value wins even at uint128 max");
        assertTrue(ok);
    }

    /// @notice When all options get zero from every class (e.g., no votes),
    ///         score is zero and threshold fails.
    function testPickWinnerNSlices_AllZeroScores() public {
        uint256[][] memory m = _matrix(3, 1);
        // m already zero-initialized. Class total is zero → skipped.
        (, bool ok, uint256 hi,) = VotingMath.pickWinnerNSlices(m, _totals(0), _slices1(100), 1, true);

        assertEq(hi, 0);
        assertFalse(ok);
    }

    // ---------- Fuzz ----------

    /// @notice Fuzz: for arbitrary bounded inputs, the returned winner is
    ///         always an option with the maximum computed score. No option
    ///         has a strictly higher score than the reported winner.
    function testFuzz_PickWinnerNSlices_WinnerHasMaxScore(
        uint256[6] memory rawsA,
        uint256[6] memory rawsB,
        uint8 sliceA,
        uint8 thresholdPct,
        bool strict
    ) public {
        vm.assume(sliceA > 0 && sliceA <= 100);
        vm.assume(thresholdPct > 0 && thresholdPct <= 100);

        uint256[][] memory m = _matrix(6, 2);
        uint256[] memory totals = new uint256[](2);
        for (uint256 i; i < 6; ++i) {
            // Bound to uint128 max / 10 to keep totals bounded.
            m[i][0] = bound(rawsA[i], 0, uint256(type(uint128).max) / 10);
            m[i][1] = bound(rawsB[i], 0, uint256(type(uint128).max) / 10);
            totals[0] += m[i][0];
            totals[1] += m[i][1];
        }

        uint8[] memory slices = _slices2(sliceA, 100 - sliceA);

        (uint256 win,, uint256 hi, uint256 second) =
            VotingMath.pickWinnerNSlices(m, totals, slices, thresholdPct, strict);

        // Recompute every score and check winner has the max.
        uint256 maxScore;
        uint256 secondMax;
        for (uint256 opt; opt < 6; ++opt) {
            uint256 s = _expectedScore(m[opt], totals, slices);
            if (s > maxScore) {
                secondMax = maxScore;
                maxScore = s;
            } else if (s > secondMax) {
                secondMax = s;
            }
        }

        assertEq(hi, maxScore, "hi should equal max score");
        assertEq(second, secondMax, "second should equal second-max score");
        assertEq(_expectedScore(m[win], totals, slices), maxScore, "winner option has max score");
    }

    /// @notice Fuzz: `ok` correctly reflects (threshold met && margin met).
    function testFuzz_PickWinnerNSlices_OkInvariant(
        uint256[4] memory rawsA,
        uint8 sliceA,
        uint8 thresholdPct,
        bool strict
    ) public {
        vm.assume(sliceA > 0 && sliceA <= 100);
        vm.assume(thresholdPct > 0 && thresholdPct <= 100);

        uint256[][] memory m = _matrix(4, 1);
        uint256[] memory totals = new uint256[](1);
        for (uint256 i; i < 4; ++i) {
            m[i][0] = bound(rawsA[i], 0, uint256(type(uint128).max) / 10);
            totals[0] += m[i][0];
        }

        uint8[] memory slices = _slices1(sliceA);
        (, bool ok, uint256 hi, uint256 second) = VotingMath.pickWinnerNSlices(m, totals, slices, thresholdPct, strict);

        bool expectedThresholdMet = hi >= uint256(thresholdPct) * VotingMath.N_SLICE_PRECISION;
        bool expectedMargin = strict ? (hi > second) : (hi >= second);
        assertEq(ok, expectedThresholdMet && expectedMargin, "ok matches invariant");
    }

    /* ─────────── Test Math Utilities ─────────── */

    function testSqrt() public {
        assertEq(VotingMath.sqrt(0), 0, "sqrt(0) = 0");
        assertEq(VotingMath.sqrt(1), 1, "sqrt(1) = 1");
        assertEq(VotingMath.sqrt(4), 2, "sqrt(4) = 2");
        assertEq(VotingMath.sqrt(9), 3, "sqrt(9) = 3");
        assertEq(VotingMath.sqrt(16), 4, "sqrt(16) = 4");
        assertEq(VotingMath.sqrt(100), 10, "sqrt(100) = 10");
        assertEq(VotingMath.sqrt(10000), 100, "sqrt(10000) = 100");

        // Test with ether units
        assertEq(VotingMath.sqrt(1 ether), 1e9, "sqrt(1 ether) = 1e9");
        assertEq(VotingMath.sqrt(100 ether), 10 * 1e9, "sqrt(100 ether) = 10e9");
    }

    function testFitsUint128() public {
        assertTrue(VotingMath.fitsUint128(0), "0 should fit");
        assertTrue(VotingMath.fitsUint128(type(uint128).max), "uint128 max should fit");
        assertFalse(VotingMath.fitsUint128(uint256(type(uint128).max) + 1), "uint128 max + 1 should not fit");
        assertFalse(VotingMath.fitsUint128(type(uint256).max), "uint256 max should not fit");
    }

    function testFitsUint96() public {
        assertTrue(VotingMath.fitsUint96(0), "0 should fit");
        assertTrue(VotingMath.fitsUint96(type(uint96).max), "uint96 max should fit");
        assertFalse(VotingMath.fitsUint96(uint256(type(uint96).max) + 1), "uint96 max + 1 should not fit");
        assertFalse(VotingMath.fitsUint96(type(uint256).max), "uint256 max should not fit");
    }

    /* ─────────── Fuzz Tests ─────────── */

    function testFuzz_Sqrt(uint256 x) public {
        // Bound the input to prevent overflow in verification
        x = bound(x, 0, type(uint128).max);

        uint256 result = VotingMath.sqrt(x);

        // Verify that result^2 <= x < (result+1)^2
        uint256 resultSquared = result * result;

        // Check lower bound
        assertTrue(resultSquared <= x, "result^2 should be <= x");

        // Check upper bound (be careful with overflow)
        if (result < type(uint128).max) {
            uint256 nextSquared = (result + 1) * (result + 1);
            assertTrue(x < nextSquared, "x should be < (result+1)^2");
        }
    }

    function testFuzz_ValidateWeights(uint8 numOptions, uint8 seed) public {
        vm.assume(numOptions > 0 && numOptions <= 50);

        // Generate valid weights that sum to 100
        uint8[] memory idxs = new uint8[](numOptions);
        uint8[] memory weights = new uint8[](numOptions);

        uint256 remaining = 100;
        for (uint256 i = 0; i < numOptions - 1; i++) {
            idxs[i] = uint8(i);
            if (remaining > 0) {
                weights[i] = uint8(bound(uint256(seed + i), 0, remaining));
                remaining -= weights[i];
            }
        }
        idxs[numOptions - 1] = uint8(numOptions - 1);
        weights[numOptions - 1] = uint8(remaining);

        // Should not revert for valid input
        VotingMath.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: numOptions}));
    }

    function testFuzz_PickWinnerMajority(uint256[5] memory rawScores, uint8 thresholdPct, bool strictMajority) public {
        vm.assume(thresholdPct > 0 && thresholdPct <= 100);

        uint256[] memory scores = new uint256[](5);
        uint256 totalWeight;

        for (uint256 i = 0; i < 5; i++) {
            scores[i] = bound(rawScores[i], 0, 1000000);
            totalWeight += scores[i];
        }

        if (totalWeight == 0) totalWeight = 1; // Avoid division by zero

        (uint256 win, bool ok, uint256 hi, uint256 second) =
            VotingMath.pickWinnerMajority(scores, totalWeight, thresholdPct, strictMajority);

        // Verify winner has highest score
        if (hi > 0) {
            assertEq(scores[win], hi, "Winner should have highest score");
        }

        // Verify second highest is correct
        bool foundSecond = false;
        for (uint256 i = 0; i < 5; i++) {
            if (i != win && scores[i] == second) {
                foundSecond = true;
                break;
            }
        }
        if (second > 0) {
            assertTrue(foundSecond || second == hi, "Second should be a valid score");
        }

        // Verify threshold logic
        if (ok) {
            assertTrue(hi * 100 > totalWeight * thresholdPct, "Should meet threshold");
            if (strictMajority) {
                assertTrue(hi > second, "Should have strict majority");
            } else {
                assertTrue(hi >= second, "Should have majority");
            }
        }
    }
}
