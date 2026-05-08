// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {EligibilityModule} from "../src/EligibilityModule.sol";
import {MockHats} from "./mocks/MockHats.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// Task #519 — direct unit coverage for EligibilityModule (vigil HB#617 surfaced absent test/EligibilityModule*.t.sol).
/// Pairs with test/ToggleModule.t.sol. Focuses on tractable paths that don't require a full
/// Hats Protocol fixture; deeper paths (claimVouchedHat reentrancy, vouching rate-limits)
/// remain as follow-up scope.
contract EligibilityModuleTest is Test {
    EligibilityModule internal eligibility;
    MockHats internal hats;

    address internal superAdmin = vm.addr(1);
    address internal toggleModule = vm.addr(2);
    address internal newSuperAdmin = vm.addr(3);
    address internal stranger = vm.addr(4);
    address internal wearerA = vm.addr(5);
    address internal wearerB = vm.addr(6);
    address internal wearerC = vm.addr(7);

    uint256 internal constant HAT_X = 1000;
    uint256 internal constant HAT_Y = 2000;

    event EligibilityModuleInitialized(address indexed superAdmin, address indexed hatsContract);
    event Paused(address indexed account);
    event Unpaused(address indexed account);
    event SuperAdminTransferred(address indexed oldSuperAdmin, address indexed newSuperAdmin);
    event UserJoinTimeSet(address indexed user, uint256 indexed joinTime);
    event EligibilityModuleAdminHatSet(uint256 indexed hatId);
    event MaxDailyVouchesSet(uint32 maxVouches);
    event BulkWearerEligibilityUpdated(
        address[] wearers, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );
    event DefaultEligibilityUpdated(uint256 indexed hatId, bool eligible, bool standing, address indexed admin);

    function setUp() public {
        hats = new MockHats();

        EligibilityModule impl = new EligibilityModule();
        bytes memory initData =
            abi.encodeCall(EligibilityModule.initialize, (superAdmin, address(hats), toggleModule));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        eligibility = EligibilityModule(address(proxy));
    }

    /*══════════════════════════════════════ initialize ══════════════════════════════════════*/

    function test_Initialize_setsSuperAdmin() public {
        // Indirect verification: superAdmin can call onlySuperAdmin functions
        vm.prank(superAdmin);
        eligibility.pause();
        assertTrue(eligibility.paused());
    }

    function test_Initialize_zeroSuperAdminReverts() public {
        EligibilityModule impl = new EligibilityModule();
        bytes memory initData =
            abi.encodeCall(EligibilityModule.initialize, (address(0), address(hats), toggleModule));
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_zeroHatsReverts() public {
        EligibilityModule impl = new EligibilityModule();
        bytes memory initData =
            abi.encodeCall(EligibilityModule.initialize, (superAdmin, address(0), toggleModule));
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_emitsInitializedEvent() public {
        EligibilityModule impl = new EligibilityModule();
        vm.expectEmit(true, true, false, false);
        emit EligibilityModuleInitialized(superAdmin, address(hats));
        bytes memory initData =
            abi.encodeCall(EligibilityModule.initialize, (superAdmin, address(hats), toggleModule));
        new ERC1967Proxy(address(impl), initData);
    }

    function test_Initialize_implementationDirectlyDisabled() public {
        EligibilityModule impl = new EligibilityModule();
        vm.expectRevert();
        impl.initialize(superAdmin, address(hats), toggleModule);
    }

    function test_Initialize_cannotReinitialize() public {
        vm.expectRevert();
        eligibility.initialize(newSuperAdmin, address(hats), toggleModule);
    }

    /*══════════════════════════════════════ pause / unpause ══════════════════════════════════════*/

    function test_Pause_superAdminCanPause() public {
        vm.expectEmit(true, false, false, false);
        emit Paused(superAdmin);
        vm.prank(superAdmin);
        eligibility.pause();
        assertTrue(eligibility.paused());
    }

    function test_Pause_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.pause();
    }

    function test_Unpause_superAdminCanUnpause() public {
        vm.startPrank(superAdmin);
        eligibility.pause();
        assertTrue(eligibility.paused());

        vm.expectEmit(true, false, false, false);
        emit Unpaused(superAdmin);
        eligibility.unpause();
        vm.stopPrank();
        assertFalse(eligibility.paused());
    }

    function test_Unpause_strangerReverts() public {
        vm.prank(superAdmin);
        eligibility.pause();

        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.unpause();
    }

    function test_Paused_initialIsFalse() public {
        assertFalse(eligibility.paused());
    }

    /*══════════════════════════════════════ transferSuperAdmin ══════════════════════════════════════*/

    function test_TransferSuperAdmin_succeeds() public {
        vm.expectEmit(true, true, false, false);
        emit SuperAdminTransferred(superAdmin, newSuperAdmin);
        vm.prank(superAdmin);
        eligibility.transferSuperAdmin(newSuperAdmin);

        // Old superAdmin loses authority
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(superAdmin);
        eligibility.pause();

        // New superAdmin can act
        vm.prank(newSuperAdmin);
        eligibility.pause();
        assertTrue(eligibility.paused());
    }

    function test_TransferSuperAdmin_zeroAddressReverts() public {
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        vm.prank(superAdmin);
        eligibility.transferSuperAdmin(address(0));
    }

    function test_TransferSuperAdmin_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.transferSuperAdmin(newSuperAdmin);
    }

    /*══════════════════════════════════════ setUserJoinTime ══════════════════════════════════════*/

    function test_SetUserJoinTime_superAdmin() public {
        uint256 joinTime = 1_700_000_000;
        vm.expectEmit(true, true, false, false);
        emit UserJoinTimeSet(wearerA, joinTime);
        vm.prank(superAdmin);
        eligibility.setUserJoinTime(wearerA, joinTime);
    }

    function test_SetUserJoinTime_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.setUserJoinTime(wearerA, 1_700_000_000);
    }

    function test_SetUserJoinTimeNow_setsBlockTimestamp() public {
        vm.warp(1_800_000_000);
        vm.expectEmit(true, true, false, false);
        emit UserJoinTimeSet(wearerA, 1_800_000_000);
        vm.prank(superAdmin);
        eligibility.setUserJoinTimeNow(wearerA);
    }

    /*══════════════════════════════════════ setMaxDailyVouches ══════════════════════════════════════*/

    function test_SetMaxDailyVouches_superAdmin() public {
        vm.expectEmit(false, false, false, true);
        emit MaxDailyVouchesSet(42);
        vm.prank(superAdmin);
        eligibility.setMaxDailyVouches(42);
        assertEq(eligibility.getMaxDailyVouches(), 42);
    }

    function test_SetMaxDailyVouches_zeroReverts() public {
        vm.expectRevert();
        vm.prank(superAdmin);
        eligibility.setMaxDailyVouches(0);
    }

    function test_SetMaxDailyVouches_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.setMaxDailyVouches(42);
    }

    /*══════════════════════════════════════ setEligibilityModuleAdminHat ══════════════════════════════════════*/

    function test_SetEligibilityModuleAdminHat_superAdmin() public {
        vm.expectEmit(true, false, false, false);
        emit EligibilityModuleAdminHatSet(HAT_X);
        vm.prank(superAdmin);
        eligibility.setEligibilityModuleAdminHat(HAT_X);
    }

    function test_SetEligibilityModuleAdminHat_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.setEligibilityModuleAdminHat(HAT_X);
    }

    /*══════════════════════════════════════ setBulkWearerEligibility ══════════════════════════════════════*/

    function test_SetBulkWearerEligibility_emptyArrayReverts() public {
        // superAdmin satisfies onlyHatAdmin; tests the array-length guard
        address[] memory wearers = new address[](0);
        vm.expectRevert(EligibilityModule.ArrayLengthMismatch.selector);
        vm.prank(superAdmin);
        eligibility.setBulkWearerEligibility(wearers, HAT_X, true, true);
    }

    function test_SetBulkWearerEligibility_zeroWearerReverts() public {
        address[] memory wearers = new address[](2);
        wearers[0] = wearerA;
        wearers[1] = address(0);
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        vm.prank(superAdmin);
        eligibility.setBulkWearerEligibility(wearers, HAT_X, true, true);
    }

    function test_SetBulkWearerEligibility_superAdminHappyPath() public {
        address[] memory wearers = new address[](3);
        wearers[0] = wearerA;
        wearers[1] = wearerB;
        wearers[2] = wearerC;

        vm.expectEmit(false, true, false, true);
        emit BulkWearerEligibilityUpdated(wearers, HAT_X, true, true, superAdmin);
        vm.prank(superAdmin);
        eligibility.setBulkWearerEligibility(wearers, HAT_X, true, true);

        // Verify via the IHatsEligibility-spec view
        (bool eligibleA, bool standingA) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertTrue(eligibleA);
        assertTrue(standingA);
    }

    function test_SetBulkWearerEligibility_strangerReverts() public {
        address[] memory wearers = new address[](1);
        wearers[0] = wearerA;
        vm.expectRevert(EligibilityModule.NotAuthorizedAdmin.selector);
        vm.prank(stranger);
        eligibility.setBulkWearerEligibility(wearers, HAT_X, true, true);
    }

    function test_SetBulkWearerEligibility_hatAdminViaMockSucceeds() public {
        // Mint HAT_X to stranger so MockHats.isAdminOfHat returns true for stranger
        hats.mintHat(HAT_X, stranger);
        address[] memory wearers = new address[](1);
        wearers[0] = wearerA;
        vm.prank(stranger);
        eligibility.setBulkWearerEligibility(wearers, HAT_X, true, true);
    }

    /*══════════════════════════════════════ setDefaultEligibility ══════════════════════════════════════*/

    function test_SetDefaultEligibility_superAdminAndAdminHatPaths() public {
        vm.expectEmit(true, false, false, true);
        emit DefaultEligibilityUpdated(HAT_X, true, true, superAdmin);
        vm.prank(superAdmin);
        eligibility.setDefaultEligibility(HAT_X, true, true);

        // Default applies when no specific wearer rule
        (bool eligibleA, bool standingA) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertTrue(eligibleA);
        assertTrue(standingA);
    }

    function test_SetDefaultEligibility_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotAuthorizedAdmin.selector);
        vm.prank(stranger);
        eligibility.setDefaultEligibility(HAT_X, true, true);
    }

    function test_SetDefaultEligibility_pausedReverts() public {
        vm.prank(superAdmin);
        eligibility.pause();
        vm.expectRevert(bytes("Contract is paused"));
        vm.prank(superAdmin);
        eligibility.setDefaultEligibility(HAT_X, true, true);
    }

    /*══════════════════════════════════════ Storage namespace ══════════════════════════════════════*/

    function test_StorageNamespace_writesGoToERC7201Slot() public {
        bytes32 base = keccak256("poa.eligibilitymodule.storage");
        // Layout fields in declaration order (Layout struct lines 76-105):
        //   slot 0: hats (IHats, 20 bytes)
        //   slot 1: superAdmin (address, 20 bytes)
        //   slot 2: toggleModule (address, 20 bytes)
        //   ... (eligibilityModuleAdminHat, _paused, mappings)
        // Each address takes its own slot (20+20 > 32 means no packing).
        bytes32 hatsSlot = vm.load(address(eligibility), base);
        assertEq(address(uint160(uint256(hatsSlot))), address(hats), "hats at namespace base");

        bytes32 superAdminSlot = vm.load(address(eligibility), bytes32(uint256(base) + 1));
        assertEq(address(uint160(uint256(superAdminSlot))), superAdmin, "superAdmin at base+1");
    }
}
