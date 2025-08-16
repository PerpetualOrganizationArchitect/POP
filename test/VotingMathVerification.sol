// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/libs/VotingMath.sol";

/**
 * @title VotingMathVerification
 * @notice Simple contract to verify VotingMath library functions work correctly
 */
contract VotingMathVerification {
    
    // Test 1: Validate weights correctly
    function testValidateWeights() public pure returns (bool) {
        // Valid case
        uint8[] memory idxs = new uint8[](3);
        uint8[] memory weights = new uint8[](3);
        idxs[0] = 0;
        idxs[1] = 1;
        idxs[2] = 2;
        weights[0] = 50;
        weights[1] = 30;
        weights[2] = 20;
        
        VotingMath.validateWeights(VotingMath.Weights({
            idxs: idxs,
            weights: weights,
            optionsLen: 3
        }));
        
        return true;
    }
    
    // Test 2: Power calculation for PT
    function testPowerPT() public pure returns (bool) {
        // Test linear voting
        uint256 power1 = VotingMath.powerPT(1000 ether, 100 ether, false);
        require(power1 == 1000 ether, "Linear power incorrect");
        
        // Test quadratic voting
        uint256 power2 = VotingMath.powerPT(100 ether, 10 ether, true);
        require(power2 == 10 * 1e9, "Quadratic power incorrect");
        
        // Test below minimum
        uint256 power3 = VotingMath.powerPT(50 ether, 100 ether, false);
        require(power3 == 0, "Below min should be 0");
        
        return true;
    }
    
    // Test 3: Hybrid powers calculation
    function testPowersHybrid() public pure returns (bool) {
        // With democracy hat
        (uint256 ddRaw1, uint256 ptRaw1) = VotingMath.powersHybrid(true, 1000 ether, 100 ether, false);
        require(ddRaw1 == 100, "DD raw should be 100");
        require(ptRaw1 == 1000 ether * 100, "PT raw incorrect");
        
        // Without democracy hat
        (uint256 ddRaw2, uint256 ptRaw2) = VotingMath.powersHybrid(false, 1000 ether, 100 ether, false);
        require(ddRaw2 == 0, "DD raw should be 0");
        require(ptRaw2 == 1000 ether * 100, "PT raw incorrect");
        
        return true;
    }
    
    // Test 4: Delta calculations
    function testDeltas() public pure returns (bool) {
        uint8[] memory idxs = new uint8[](2);
        uint8[] memory weights = new uint8[](2);
        idxs[0] = 0;
        idxs[1] = 1;
        weights[0] = 60;
        weights[1] = 40;
        
        // Test PT deltas
        uint256[] memory ptDeltas = VotingMath.deltasPT(1000, idxs, weights);
        require(ptDeltas[0] == 60000, "PT delta 0 incorrect");
        require(ptDeltas[1] == 40000, "PT delta 1 incorrect");
        
        // Test hybrid deltas
        (uint256[] memory ddDeltas, uint256[] memory ptDeltas2) = 
            VotingMath.deltasHybrid(100, 10000, idxs, weights);
        require(ddDeltas[0] == 60, "DD delta 0 incorrect");
        require(ddDeltas[1] == 40, "DD delta 1 incorrect");
        require(ptDeltas2[0] == 6000, "PT delta 0 incorrect");
        require(ptDeltas2[1] == 4000, "PT delta 1 incorrect");
        
        return true;
    }
    
    // Test 5: Winner selection (majority)
    function testPickWinnerMajority() public pure returns (bool) {
        uint256[] memory scores = new uint256[](3);
        scores[0] = 30;
        scores[1] = 50;
        scores[2] = 20;
        
        (uint256 win, bool ok, uint256 hi, uint256 second) = 
            VotingMath.pickWinnerMajority(scores, 100, 40, true);
        
        require(win == 1, "Winner should be option 1");
        require(ok == true, "Should meet quorum");
        require(hi == 50, "Highest should be 50");
        require(second == 30, "Second should be 30");
        
        return true;
    }
    
    // Test 6: Winner selection (two-slice)
    function testPickWinnerTwoSlice() public pure returns (bool) {
        uint256[] memory ddRaw = new uint256[](3);
        uint256[] memory ptRaw = new uint256[](3);
        
        ddRaw[0] = 30;
        ddRaw[1] = 50;
        ddRaw[2] = 20;
        
        ptRaw[0] = 2000;
        ptRaw[1] = 1000;
        ptRaw[2] = 3000;
        
        (uint256 win, bool ok, , ) = 
            VotingMath.pickWinnerTwoSlice(ddRaw, ptRaw, 100, 6000, 50, 30);
        
        require(win == 2, "Winner should be option 2");
        require(ok == true, "Should meet quorum");
        
        return true;
    }
    
    // Test 7: Square root calculation
    function testSqrt() public pure returns (bool) {
        require(VotingMath.sqrt(0) == 0, "sqrt(0) != 0");
        require(VotingMath.sqrt(1) == 1, "sqrt(1) != 1");
        require(VotingMath.sqrt(4) == 2, "sqrt(4) != 2");
        require(VotingMath.sqrt(9) == 3, "sqrt(9) != 3");
        require(VotingMath.sqrt(100) == 10, "sqrt(100) != 10");
        require(VotingMath.sqrt(1 ether) == 1e9, "sqrt(1 ether) != 1e9");
        
        return true;
    }
    
    // Test 8: Overflow checks
    function testOverflowChecks() public pure returns (bool) {
        require(VotingMath.fitsUint128(type(uint128).max) == true, "uint128 max should fit");
        require(VotingMath.fitsUint128(uint256(type(uint128).max) + 1) == false, "uint128 max + 1 should not fit");
        
        require(VotingMath.fitsUint96(type(uint96).max) == true, "uint96 max should fit");
        require(VotingMath.fitsUint96(uint256(type(uint96).max) + 1) == false, "uint96 max + 1 should not fit");
        
        return true;
    }
    
    // Run all tests
    function runAllTests() public pure returns (string memory) {
        require(testValidateWeights(), "validateWeights failed");
        require(testPowerPT(), "powerPT failed");
        require(testPowersHybrid(), "powersHybrid failed");
        require(testDeltas(), "deltas failed");
        require(testPickWinnerMajority(), "pickWinnerMajority failed");
        require(testPickWinnerTwoSlice(), "pickWinnerTwoSlice failed");
        require(testSqrt(), "sqrt failed");
        require(testOverflowChecks(), "overflow checks failed");
        
        return "All tests passed!";
    }
}