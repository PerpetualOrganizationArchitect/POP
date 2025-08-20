// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/PoaManager.sol";
import "../src/ImplementationRegistry.sol";

contract DummyImpl {
    // Mock implementation for testing
}

contract PoaManagerTest is Test {
    PoaManager pm;
    ImplementationRegistry reg;
    address owner = address(this);

    function setUp() public {
        reg = new ImplementationRegistry();
        reg.initialize(owner);
        pm = new PoaManager(address(reg));
        reg.transferOwnership(address(pm));
    }

    function testAddTypeAndUpgrade() public {
        DummyImpl impl1 = new DummyImpl();
        DummyImpl impl2 = new DummyImpl();
        pm.addContractType("TypeA", address(impl1));
        address beacon = pm.getBeacon("TypeA");
        assertTrue(beacon != address(0));
        assertEq(pm.getCurrentImplementation("TypeA"), address(impl1));
        pm.upgradeBeacon("TypeA", address(impl2), "v2");
        assertEq(pm.getCurrentImplementation("TypeA"), address(impl2));
    }
}
