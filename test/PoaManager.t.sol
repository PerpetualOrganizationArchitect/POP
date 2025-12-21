// SPDX-License-Identifier: AGPL-3.0-only
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
        address beacon = pm.getBeaconById(keccak256("TypeA"));
        assertTrue(beacon != address(0));
        assertEq(pm.getCurrentImplementationById(keccak256("TypeA")), address(impl1));
        pm.upgradeBeacon("TypeA", address(impl2), "v2");
        assertEq(pm.getCurrentImplementationById(keccak256("TypeA")), address(impl2));
    }

    function testRegisterInfrastructure() public {
        address orgDeployer = makeAddr("orgDeployer");
        address orgRegistry = makeAddr("orgRegistry");
        address implRegistry = makeAddr("implRegistry");
        address paymasterHub = makeAddr("paymasterHub");
        address globalAccountRegistry = makeAddr("globalAccountRegistry");
        address passkeyAccountFactoryBeacon = makeAddr("passkeyAccountFactoryBeacon");

        vm.expectEmit(true, true, true, true);
        emit PoaManager.InfrastructureDeployed(
            orgDeployer, orgRegistry, implRegistry, paymasterHub, globalAccountRegistry, passkeyAccountFactoryBeacon
        );

        pm.registerInfrastructure(
            orgDeployer, orgRegistry, implRegistry, paymasterHub, globalAccountRegistry, passkeyAccountFactoryBeacon
        );
    }

    function testRegisterInfrastructureOnlyOwner() public {
        address nonOwner = makeAddr("nonOwner");
        address orgDeployer = makeAddr("orgDeployer");
        address orgRegistry = makeAddr("orgRegistry");
        address implRegistry = makeAddr("implRegistry");
        address paymasterHub = makeAddr("paymasterHub");
        address globalAccountRegistry = makeAddr("globalAccountRegistry");
        address passkeyAccountFactoryBeacon = makeAddr("passkeyAccountFactoryBeacon");

        vm.prank(nonOwner);
        vm.expectRevert();
        pm.registerInfrastructure(
            orgDeployer, orgRegistry, implRegistry, paymasterHub, globalAccountRegistry, passkeyAccountFactoryBeacon
        );
    }
}
