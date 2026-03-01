// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/PoaManager.sol";
import "../src/ImplementationRegistry.sol";

contract DummyImpl {
    // Mock implementation for testing

    }

/// @dev Mock target that gates a function behind msg.sender == poaManager
contract MockAdminTarget {
    address public poaManager;
    uint256 public value;

    constructor(address _pm) {
        poaManager = _pm;
    }

    function setValueOnlyPM(uint256 _val) external {
        require(msg.sender == poaManager, "not pm");
        value = _val;
    }

    function alwaysReverts() external pure {
        revert("always reverts");
    }
}

contract PoaManagerTest is Test {
    PoaManager pm;
    ImplementationRegistry reg;
    address owner = address(this);

    function setUp() public {
        ImplementationRegistry _regImpl = new ImplementationRegistry();
        UpgradeableBeacon _regBeacon = new UpgradeableBeacon(address(_regImpl), address(this));
        reg = ImplementationRegistry(address(new BeaconProxy(address(_regBeacon), "")));
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

    function testAdminCallSuccess() public {
        MockAdminTarget target = new MockAdminTarget(address(pm));
        pm.adminCall(address(target), abi.encodeWithSignature("setValueOnlyPM(uint256)", 42));
        assertEq(target.value(), 42);
    }

    function testAdminCallOnlyOwner() public {
        MockAdminTarget target = new MockAdminTarget(address(pm));
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert();
        pm.adminCall(address(target), abi.encodeWithSignature("setValueOnlyPM(uint256)", 42));
    }

    function testAdminCallBubblesRevert() public {
        MockAdminTarget target = new MockAdminTarget(address(pm));
        vm.expectRevert("always reverts");
        pm.adminCall(address(target), abi.encodeWithSignature("alwaysReverts()"));
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
