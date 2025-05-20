// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UniversalAccountRegistry.sol";

contract UARTest is Test {
    UniversalAccountRegistry reg;
    address user = address(1);

    function setUp() public {
        reg = new UniversalAccountRegistry();
        reg.initialize(address(this));
    }

    function testRegisterAndChange() public {
        vm.prank(user);
        reg.registerAccount("alice");
        assertEq(reg.getUsername(user), "alice");
        vm.prank(user);
        reg.changeUsername("bob");
        assertEq(reg.getUsername(user), "bob");
    }

    function testDeleteAccount() public {
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.deleteAccount();
        assertEq(reg.getUsername(user), "");
    }
}
