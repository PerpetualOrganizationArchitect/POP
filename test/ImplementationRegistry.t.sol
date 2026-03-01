// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/ImplementationRegistry.sol";

contract ImplementationRegistryTest is Test {
    ImplementationRegistry reg;

    function setUp() public {
        ImplementationRegistry _regImpl = new ImplementationRegistry();
        UpgradeableBeacon _regBeacon = new UpgradeableBeacon(address(_regImpl), address(this));
        reg = ImplementationRegistry(address(new BeaconProxy(address(_regBeacon), "")));
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
