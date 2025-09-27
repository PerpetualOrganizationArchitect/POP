// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/HatsTreeSetup.sol";
import "@hats-protocol/src/Interfaces/IHats.sol";

contract VerifyHatsSetupTest is Test {
    HatsTreeSetup hatsSetup;
    address constant SEPOLIA_HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;
    
    function setUp() public {
        hatsSetup = new HatsTreeSetup();
    }
    
    function testHatsSetupAddress() public {
        console.log("HatsTreeSetup deployed at:", address(hatsSetup));
        assertTrue(address(hatsSetup) != address(0), "HatsSetup should be deployed");
    }
    
    function testHatsSetupSize() public {
        uint256 codeSize;
        address addr = address(hatsSetup);
        assembly {
            codeSize := extcodesize(addr)
        }
        console.log("HatsTreeSetup runtime bytecode size:", codeSize);
        assertTrue(codeSize > 0, "HatsSetup should have code");
    }
}