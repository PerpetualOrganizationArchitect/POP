// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ImplementationRegistry.sol";

contract ImplementationRegistryTest is Test {
    ImplementationRegistry reg;

    function setUp() public {
        reg = new ImplementationRegistry();
        reg.initialize(address(this));
    }

    function testRegisterAndLatest() public {
        reg.registerImplementation("TypeA", "v1", address(0x1), true);
        assertEq(reg.getLatestImplementation("TypeA"), address(0x1));
        reg.registerImplementation("TypeA", "v2", address(0x2), true);
        assertEq(reg.getLatestImplementation("TypeA"), address(0x2));
        assertEq(reg.getImplementation("TypeA", "v1"), address(0x1));
        assertEq(reg.getVersionCount("TypeA"), 2);
    }
}
