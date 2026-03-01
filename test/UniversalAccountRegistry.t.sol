// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/UniversalAccountRegistry.sol";

contract UARTest is Test {
    UniversalAccountRegistry reg;
    address user = address(1);

    function setUp() public {
        UniversalAccountRegistry _regImpl = new UniversalAccountRegistry();
        UpgradeableBeacon _regBeacon = new UpgradeableBeacon(address(_regImpl), address(this));
        reg = UniversalAccountRegistry(address(new BeaconProxy(address(_regBeacon), "")));
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

    /*════════════════════════════════════════════════════════════════════
                    ACCESS CONTROL TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testQuickJoinUnauthorizedCallerReverts() public {
        address unauthorized = address(0x99);
        vm.prank(unauthorized);
        vm.expectRevert(UniversalAccountRegistry.UnauthorizedCaller.selector);
        reg.registerAccountQuickJoin("newuser", address(0x50));
    }

    function testQuickJoinAuthorizedCallerSucceeds() public {
        address quickJoin = address(0x10);
        address newUser = address(0x50);

        // Authorize the caller
        reg.setAuthorizedCaller(quickJoin, true);

        // Should succeed now
        vm.prank(quickJoin);
        reg.registerAccountQuickJoin("newuser", newUser);
        assertEq(reg.getUsername(newUser), "newuser");
    }

    function testSetAuthorizedCallerOnlyOwner() public {
        address random = address(0x99);
        vm.prank(random);
        vm.expectRevert();
        reg.setAuthorizedCaller(address(0x10), true);
    }

    function testDeauthorizeCallerReverts() public {
        address quickJoin = address(0x10);
        reg.setAuthorizedCaller(quickJoin, true);
        reg.setAuthorizedCaller(quickJoin, false);

        vm.prank(quickJoin);
        vm.expectRevert(UniversalAccountRegistry.UnauthorizedCaller.selector);
        reg.registerAccountQuickJoin("newuser", address(0x50));
    }

    function testRegisterBatchOnlyOwner() public {
        address random = address(0x99);
        address[] memory users = new address[](1);
        users[0] = address(0x50);
        string[] memory names = new string[](1);
        names[0] = "user1";

        vm.prank(random);
        vm.expectRevert();
        reg.registerBatch(users, names);
    }
}
