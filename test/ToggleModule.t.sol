// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ToggleModule} from "../src/ToggleModule.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// Task #519 — direct unit coverage for ToggleModule (vigil HB#617 surfaced absent test/ToggleModule*.t.sol).
/// Pairs with task #519 EligibilityModule coverage in a sibling file.
contract ToggleModuleTest is Test {
    ToggleModule internal toggle;

    address internal admin = vm.addr(1);
    address internal eligibility = vm.addr(2);
    address internal stranger = vm.addr(3);
    address internal newAdmin = vm.addr(4);

    uint256 internal constant HAT_A = 100;
    uint256 internal constant HAT_B = 200;
    uint256 internal constant HAT_C = 300;

    event HatToggled(uint256 indexed hatId, bool newStatus);
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);
    event ToggleModuleInitialized(address indexed admin);

    function setUp() public {
        ToggleModule impl = new ToggleModule();
        bytes memory initData = abi.encodeCall(ToggleModule.initialize, (admin));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        toggle = ToggleModule(address(proxy));
    }

    /*══════════════════════════════════════ initialize ══════════════════════════════════════*/

    function test_Initialize_setsAdmin() public {
        assertEq(toggle.admin(), admin);
    }

    function test_Initialize_zeroAdminReverts() public {
        ToggleModule impl = new ToggleModule();
        bytes memory initData = abi.encodeCall(ToggleModule.initialize, (address(0)));
        vm.expectRevert(ToggleModule.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_emitsToggleModuleInitialized() public {
        ToggleModule impl = new ToggleModule();
        vm.expectEmit(true, false, false, false);
        emit ToggleModuleInitialized(admin);
        bytes memory initData = abi.encodeCall(ToggleModule.initialize, (admin));
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_implementationDirectlyDisabled() public {
        ToggleModule impl = new ToggleModule();
        vm.expectRevert(); // _disableInitializers in constructor
        impl.initialize(admin);
    }

    function test_Initialize_cannotReinitialize() public {
        vm.expectRevert();
        toggle.initialize(newAdmin);
    }

    /*══════════════════════════════════════ setHatStatus ══════════════════════════════════════*/

    function test_SetHatStatus_adminCanActivate() public {
        vm.expectEmit(true, false, false, true);
        emit HatToggled(HAT_A, true);
        vm.prank(admin);
        toggle.setHatStatus(HAT_A, true);
        assertTrue(toggle.hatActive(HAT_A));
        assertEq(toggle.getHatStatus(HAT_A), 1);
    }

    function test_SetHatStatus_adminCanDeactivate() public {
        vm.startPrank(admin);
        toggle.setHatStatus(HAT_A, true);
        toggle.setHatStatus(HAT_A, false);
        vm.stopPrank();
        assertFalse(toggle.hatActive(HAT_A));
        assertEq(toggle.getHatStatus(HAT_A), 0);
    }

    function test_SetHatStatus_eligibilityModuleCanToggle() public {
        vm.prank(admin);
        toggle.setEligibilityModule(eligibility);

        vm.prank(eligibility);
        toggle.setHatStatus(HAT_A, true);
        assertTrue(toggle.hatActive(HAT_A));
    }

    function test_SetHatStatus_strangerReverts() public {
        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(stranger);
        toggle.setHatStatus(HAT_A, true);
    }

    /*══════════════════════════════════════ batchSetHatStatus ══════════════════════════════════════*/

    function test_BatchSetHatStatus_setsAllAndEmitsPerHat() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = HAT_A;
        ids[1] = HAT_B;
        ids[2] = HAT_C;
        bool[] memory actives = new bool[](3);
        actives[0] = true;
        actives[1] = false;
        actives[2] = true;

        vm.expectEmit(true, false, false, true);
        emit HatToggled(HAT_A, true);
        vm.expectEmit(true, false, false, true);
        emit HatToggled(HAT_B, false);
        vm.expectEmit(true, false, false, true);
        emit HatToggled(HAT_C, true);

        vm.prank(admin);
        toggle.batchSetHatStatus(ids, actives);

        assertTrue(toggle.hatActive(HAT_A));
        assertFalse(toggle.hatActive(HAT_B));
        assertTrue(toggle.hatActive(HAT_C));
    }

    function test_BatchSetHatStatus_lengthMismatchReverts() public {
        uint256[] memory ids = new uint256[](2);
        ids[0] = HAT_A;
        ids[1] = HAT_B;
        bool[] memory actives = new bool[](1);
        actives[0] = true;

        vm.expectRevert(bytes("Array length mismatch"));
        vm.prank(admin);
        toggle.batchSetHatStatus(ids, actives);
    }

    function test_BatchSetHatStatus_strangerReverts() public {
        uint256[] memory ids = new uint256[](1);
        ids[0] = HAT_A;
        bool[] memory actives = new bool[](1);
        actives[0] = true;
        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(stranger);
        toggle.batchSetHatStatus(ids, actives);
    }

    function test_BatchSetHatStatus_emptyArraysIsNoop() public {
        uint256[] memory ids = new uint256[](0);
        bool[] memory actives = new bool[](0);
        vm.prank(admin);
        toggle.batchSetHatStatus(ids, actives);
        // No state change, no revert
        assertFalse(toggle.hatActive(HAT_A));
    }

    /*══════════════════════════════════════ getHatStatus ══════════════════════════════════════*/

    function test_GetHatStatus_unsetReturnsZero() public {
        assertEq(toggle.getHatStatus(HAT_A), 0);
    }

    function test_GetHatStatus_returnsOneOrZero() public {
        vm.prank(admin);
        toggle.setHatStatus(HAT_A, true);
        assertEq(toggle.getHatStatus(HAT_A), 1);

        vm.prank(admin);
        toggle.setHatStatus(HAT_A, false);
        assertEq(toggle.getHatStatus(HAT_A), 0);
    }

    /*══════════════════════════════════════ transferAdmin ══════════════════════════════════════*/

    function test_TransferAdmin_adminCanTransfer() public {
        vm.expectEmit(true, true, false, false);
        emit AdminTransferred(admin, newAdmin);
        vm.prank(admin);
        toggle.transferAdmin(newAdmin);
        assertEq(toggle.admin(), newAdmin);

        // Old admin loses authority
        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(admin);
        toggle.setHatStatus(HAT_A, true);

        // New admin can act
        vm.prank(newAdmin);
        toggle.setHatStatus(HAT_A, true);
        assertTrue(toggle.hatActive(HAT_A));
    }

    function test_TransferAdmin_zeroAddressReverts() public {
        vm.expectRevert(ToggleModule.ZeroAddress.selector);
        vm.prank(admin);
        toggle.transferAdmin(address(0));
    }

    function test_TransferAdmin_strangerReverts() public {
        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(stranger);
        toggle.transferAdmin(newAdmin);
    }

    function test_TransferAdmin_eligibilityModuleCanTransfer() public {
        // The onlyAdmin modifier accepts the eligibility module too
        vm.prank(admin);
        toggle.setEligibilityModule(eligibility);

        vm.prank(eligibility);
        toggle.transferAdmin(newAdmin);
        assertEq(toggle.admin(), newAdmin);
    }

    /*══════════════════════════════════════ setEligibilityModule ══════════════════════════════════════*/

    function test_SetEligibilityModule_adminCanSet() public {
        vm.prank(admin);
        toggle.setEligibilityModule(eligibility);
        // Verify by attempting an admin-gated action from eligibility
        vm.prank(eligibility);
        toggle.setHatStatus(HAT_A, true);
        assertTrue(toggle.hatActive(HAT_A));
    }

    function test_SetEligibilityModule_strangerReverts() public {
        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(stranger);
        toggle.setEligibilityModule(eligibility);
    }

    function test_SetEligibilityModule_eligibilityModuleCannotSetItself() public {
        // Per the explicit comment in setEligibilityModule, this function does NOT use the
        // onlyAdmin modifier — it's admin-only. The eligibility module must NOT be able to
        // re-route which contract has setHatStatus authority.
        vm.prank(admin);
        toggle.setEligibilityModule(eligibility);

        vm.expectRevert(ToggleModule.NotToggleAdmin.selector);
        vm.prank(eligibility);
        toggle.setEligibilityModule(stranger);
    }

    /*══════════════════════════════════════ Storage namespace ══════════════════════════════════════*/

    function test_StorageNamespace_writesGoToERC7201Slot() public {
        // ERC-7201 slot for "poa.togglemodule.storage"
        bytes32 expectedSlot = keccak256("poa.togglemodule.storage");

        vm.prank(admin);
        toggle.setHatStatus(HAT_A, true);

        // The Layout struct begins at expectedSlot. admin is field 0, eligibilityModule is field 1,
        // hatActive mapping is field 2. Reading admin should match.
        bytes32 adminSlotData = vm.load(address(toggle), expectedSlot);
        assertEq(address(uint160(uint256(adminSlotData))), admin);
    }
}
