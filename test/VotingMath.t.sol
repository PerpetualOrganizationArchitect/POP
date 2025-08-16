// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/libs/VotingMath.sol";

contract VotingMathTest is Test {
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
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 3
        }));
    }
    
    function testValidateWeights_InvalidSum() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);
        
        idxs[0] = 0;
        idxs[1] = 1;
        
        weights[0] = 50;
        weights[1] = 40; // Sum = 90, not 100
        
        vm.expectRevert(abi.encodeWithSelector(VotingMath.WeightSumNot100.selector, 90));
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 2
        }));
    }
    
    function testValidateWeights_DuplicateIndex() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);
        
        idxs[0] = 0;
        idxs[1] = 0; // Duplicate
        
        weights[0] = 50;
        weights[1] = 50;
        
        vm.expectRevert(VotingMath.DuplicateIndex.selector);
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 2
        }));
    }
    
    function testValidateWeights_InvalidIndex() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);
        
        idxs[0] = 0;
        idxs[1] = 3; // Index out of bounds for 2 options
        
        weights[0] = 50;
        weights[1] = 50;
        
        vm.expectRevert(VotingMath.InvalidIndex.selector);
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 2
        }));
    }
    
    function testValidateWeights_InvalidWeight() public {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);
        
        idxs[0] = 0;
        idxs[1] = 1;
        
        weights[0] = 101; // Weight > 100
        weights[1] = 0;
        
        vm.expectRevert(VotingMath.InvalidWeight.selector);
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 2
        }));
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
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 3
        }));
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
        // sqrt(100 ether) = 10 * sqrt(1 ether)
        assertEq(power, 10 ether, "Quadratic power should be sqrt of balance");
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
        
        (uint256[] memory ddDeltas, uint256[] memory ptDeltas) = 
            VotingMath.deltasHybrid(ddRaw, ptRaw, idxs, weights);
        
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
        uint8 quorumPct = 40;
        
        (uint256 win, bool ok, uint256 hi, uint256 second) = 
            VotingMath.pickWinnerMajority(scores, totalWeight, quorumPct, true);
        
        assertEq(win, 1, "Option 1 should win");
        assertTrue(ok, "Should meet quorum");
        assertEq(hi, 50, "Highest score should be 50");
        assertEq(second, 30, "Second highest should be 30");
    }
    
    function testPickWinnerMajority_QuorumNotMet() public {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 10;
        scores[1] = 20;
        scores[2] = 15;
        
        uint256 totalWeight = 100;
        uint8 quorumPct = 25; // Requires > 25% of total weight
        
        (uint256 win, bool ok, , ) = 
            VotingMath.pickWinnerMajority(scores, totalWeight, quorumPct, true);
        
        assertEq(win, 1, "Option 1 should be winner candidate");
        assertFalse(ok, "Should not meet quorum (20 * 100 = 2000, not > 2500)");
    }
    
    function testPickWinnerMajority_TieWithStrictRequirement() public {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 50;
        scores[1] = 50;
        
        uint256 totalWeight = 100;
        uint8 quorumPct = 40;
        
        (uint256 win, bool ok, , ) = 
            VotingMath.pickWinnerMajority(scores, totalWeight, quorumPct, true);
        
        assertFalse(ok, "Should not be valid with tie and strict requirement");
    }
    
    function testPickWinnerMajority_TieWithoutStrictRequirement() public {
        uint256[] memory scores = new uint256[](2);
        scores[0] = 50;
        scores[1] = 50;
        
        uint256 totalWeight = 100;
        uint8 quorumPct = 40;
        
        (uint256 win, bool ok, , ) = 
            VotingMath.pickWinnerMajority(scores, totalWeight, quorumPct, false);
        
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
        uint8 quorumPct = 40;
        
        (uint256 win, bool ok, uint256 hi, uint256 second) = 
            VotingMath.pickWinnerTwoSlice(ddRaw, ptRaw, ddTotalRaw, ptTotalRaw, ddSharePct, quorumPct);
        
        // DD scaled: [15, 25, 10] (out of 50)
        // PT scaled: [16.67, 8.33, 25] (out of 50)
        // Total: [31.67, 33.33, 35]
        
        assertEq(win, 2, "Option 2 should win");
        assertTrue(ok, "Should meet quorum");
    }
    
    function testPickWinnerTwoSlice_ZeroTotals() public {
        uint256[] memory ddRaw = new uint256[](2);
        uint256[] memory ptRaw = new uint256[](2);
        
        ddRaw[0] = 0;
        ddRaw[1] = 0;
        ptRaw[0] = 0;
        ptRaw[1] = 0;
        
        (uint256 win, bool ok, uint256 hi, uint256 second) = 
            VotingMath.pickWinnerTwoSlice(ddRaw, ptRaw, 0, 0, 50, 40);
        
        assertEq(win, 0, "Should return 0 as winner");
        assertFalse(ok, "Should not be valid with zero totals");
        assertEq(hi, 0, "Highest should be 0");
        assertEq(second, 0, "Second should be 0");
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
        uint256 result = VotingMath.sqrt(x);
        
        // Verify that result^2 <= x < (result+1)^2
        uint256 resultSquared = result * result;
        
        // Check lower bound
        assertTrue(resultSquared <= x, "result^2 should be <= x");
        
        // Check upper bound (be careful with overflow)
        if (result < type(uint256).max) {
            uint256 nextSquared = (result + 1) * (result + 1);
            if (nextSquared > resultSquared) { // Check for overflow
                assertTrue(x < nextSquared, "x should be < (result+1)^2");
            }
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
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: numOptions
        }));
    }
    
    function testFuzz_PickWinnerMajority(
        uint256[5] memory rawScores,
        uint8 quorumPct,
        bool strictMajority
    ) public {
        vm.assume(quorumPct > 0 && quorumPct <= 100);
        
        uint256[] memory scores = new uint256[](5);
        uint256 totalWeight;
        
        for (uint256 i = 0; i < 5; i++) {
            scores[i] = bound(rawScores[i], 0, 1000000);
            totalWeight += scores[i];
        }
        
        if (totalWeight == 0) totalWeight = 1; // Avoid division by zero
        
        (uint256 win, bool ok, uint256 hi, uint256 second) = 
            VotingMath.pickWinnerMajority(scores, totalWeight, quorumPct, strictMajority);
        
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
        
        // Verify quorum logic
        if (ok) {
            assertTrue(hi * 100 > totalWeight * quorumPct, "Should meet quorum threshold");
            if (strictMajority) {
                assertTrue(hi > second, "Should have strict majority");
            } else {
                assertTrue(hi >= second, "Should have majority");
            }
        }
    }
}