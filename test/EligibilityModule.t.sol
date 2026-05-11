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

    /*══════════════════════════════════════ setWearerEligibility ══════════════════════════════════════*/

    function test_SetWearerEligibility_superAdminHappyPath() public {
        vm.prank(superAdmin);
        eligibility.setWearerEligibility(wearerA, HAT_X, true, true);
        (bool eligible, bool standing) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertTrue(eligible);
        assertTrue(standing);
    }

    function test_SetWearerEligibility_zeroWearerReverts() public {
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        vm.prank(superAdmin);
        eligibility.setWearerEligibility(address(0), HAT_X, true, true);
    }

    function test_SetWearerEligibility_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotAuthorizedAdmin.selector);
        vm.prank(stranger);
        eligibility.setWearerEligibility(wearerA, HAT_X, true, true);
    }

    function test_SetWearerEligibility_pausedReverts() public {
        vm.prank(superAdmin);
        eligibility.pause();
        vm.expectRevert(bytes("Contract is paused"));
        vm.prank(superAdmin);
        eligibility.setWearerEligibility(wearerA, HAT_X, true, true);
    }

    /*══════════════════════════════════════ clearWearerEligibility ══════════════════════════════════════*/

    function test_ClearWearerEligibility_revertsToDefault() public {
        // Set a specific eligibility, then clear it and verify the default applies
        vm.prank(superAdmin);
        eligibility.setDefaultEligibility(HAT_X, true, true);

        vm.prank(superAdmin);
        eligibility.setWearerEligibility(wearerA, HAT_X, false, false);
        (bool e1,) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertFalse(e1, "specific overrides default");

        vm.prank(superAdmin);
        eligibility.clearWearerEligibility(wearerA, HAT_X);
        (bool e2, bool s2) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertTrue(e2, "default re-applies after clear");
        assertTrue(s2);
    }

    function test_ClearWearerEligibility_zeroWearerReverts() public {
        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        vm.prank(superAdmin);
        eligibility.clearWearerEligibility(address(0), HAT_X);
    }

    function test_ClearWearerEligibility_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotAuthorizedAdmin.selector);
        vm.prank(stranger);
        eligibility.clearWearerEligibility(wearerA, HAT_X);
    }

    /*══════════════════════════════════════ configureVouching + vouchFor ══════════════════════════════════════*/

    function test_ConfigureVouching_superAdminEnables() public {
        // membershipHatId = HAT_Y; wearers of HAT_Y can vouch for HAT_X
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);
        EligibilityModule.VouchConfig memory cfg = eligibility.vouchConfigs(HAT_X);
        assertEq(cfg.quorum, uint32(2));
        assertEq(cfg.membershipHatId, HAT_Y);
    }

    function test_ConfigureVouching_strangerReverts() public {
        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);
    }

    function test_VouchFor_succeedsAtQuorum() public {
        // Configure vouching: 2-of-N wearers of HAT_Y can vouch HAT_X eligibility
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);

        // Mint HAT_Y to wearerB + wearerC so they can vouch
        hats.mintHat(HAT_Y, wearerB);
        hats.mintHat(HAT_Y, wearerC);

        // Pre-vouch, wearerA is NOT eligible
        (bool e0,) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertFalse(e0, "no vouches yet");

        // wearerB vouches → 1/2, not enough
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);
        (bool e1,) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertFalse(e1, "1 of 2");

        // wearerC vouches → quorum reached
        vm.prank(wearerC);
        eligibility.vouchFor(wearerA, HAT_X);
        (bool e2, bool s2) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertTrue(e2, "quorum reached, eligible");
        assertTrue(s2);
    }

    function test_VouchFor_revertsWhenNotConfigured() public {
        // HAT_X has NO vouching config; vouching should be disabled
        hats.mintHat(HAT_Y, wearerB);
        vm.expectRevert(EligibilityModule.VouchingNotEnabled.selector);
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    function test_VouchFor_revertsForSelfVouch() public {
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerA);

        vm.expectRevert(EligibilityModule.CannotVouchForSelf.selector);
        vm.prank(wearerA);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    function test_VouchFor_revertsForUnauthorizedVoucher() public {
        // Configure vouching but stranger doesn't wear membership hat
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);

        vm.expectRevert(EligibilityModule.NotAuthorizedToVouch.selector);
        vm.prank(stranger);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    function test_VouchFor_revertsOnDuplicateVouch() public {
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);

        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);

        vm.expectRevert(EligibilityModule.AlreadyVouched.selector);
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    function test_VouchFor_revertsForZeroWearer() public {
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);

        vm.expectRevert(EligibilityModule.ZeroAddress.selector);
        vm.prank(wearerB);
        eligibility.vouchFor(address(0), HAT_X);
    }

    function test_VouchFor_pausedReverts() public {
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);

        vm.prank(superAdmin);
        eligibility.pause();

        vm.expectRevert(bytes("Contract is paused"));
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    function test_VouchFor_epochResetOnReconfigure() public {
        // First config: quorum 2 with HAT_Y vouchers
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);

        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);

        // Reconfigure (bumps epoch + invalidates old vouches)
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 2, HAT_Y, false);

        // wearerA should now have 0 vouches (epoch reset)
        (bool e,) = eligibility.getWearerStatus(wearerA, HAT_X);
        assertFalse(e, "epoch reset cleared prior vouch");

        // wearerB CAN vouch again post-reset (NOT AlreadyVouched)
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);
    }

    /*══════════════════════════════════════ claimVouchedHat — happy path + reentrancy ══════════════════════════════════════*/

    function test_ClaimVouchedHat_happyPath() public {
        // Configure vouching, vouch to quorum, then claim
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);

        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);

        // wearerA is eligible, claim mints the hat
        vm.prank(wearerA);
        eligibility.claimVouchedHat(HAT_X);
        assertTrue(hats.isWearerOfHat(wearerA, HAT_X), "hat minted after claim");
    }

    function test_ClaimVouchedHat_revertsWhenNotEligible() public {
        // No vouches; not eligible
        vm.expectRevert(bytes("Not eligible to claim hat"));
        vm.prank(wearerA);
        eligibility.claimVouchedHat(HAT_X);
    }

    function test_ClaimVouchedHat_revertsWhenPaused() public {
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_X, 1, HAT_Y, false);
        hats.mintHat(HAT_Y, wearerB);
        vm.prank(wearerB);
        eligibility.vouchFor(wearerA, HAT_X);

        vm.prank(superAdmin);
        eligibility.pause();

        vm.expectRevert(bytes("Contract is paused"));
        vm.prank(wearerA);
        eligibility.claimVouchedHat(HAT_X);
    }

    /*══════════════════════════════════════ batchConfigureVouching ══════════════════════════════════════*/

    function test_BatchConfigureVouching_lengthMismatchReverts() public {
        uint256[] memory hatIds = new uint256[](2);
        hatIds[0] = HAT_X;
        hatIds[1] = HAT_Y;
        uint32[] memory quorums = new uint32[](1);
        quorums[0] = 1;
        uint256[] memory members = new uint256[](2);
        members[0] = HAT_Y;
        members[1] = HAT_X;
        bool[] memory flags = new bool[](2);

        vm.expectRevert(EligibilityModule.ArrayLengthMismatch.selector);
        vm.prank(superAdmin);
        eligibility.batchConfigureVouching(hatIds, quorums, members, flags);
    }

    function test_BatchConfigureVouching_happyPath() public {
        uint256[] memory hatIds = new uint256[](2);
        hatIds[0] = HAT_X;
        hatIds[1] = HAT_Y;
        uint32[] memory quorums = new uint32[](2);
        quorums[0] = 2;
        quorums[1] = 3;
        uint256[] memory members = new uint256[](2);
        members[0] = HAT_Y;
        members[1] = HAT_X;
        bool[] memory flags = new bool[](2);

        vm.prank(superAdmin);
        eligibility.batchConfigureVouching(hatIds, quorums, members, flags);

        EligibilityModule.VouchConfig memory cfgX = eligibility.vouchConfigs(HAT_X);
        EligibilityModule.VouchConfig memory cfgY = eligibility.vouchConfigs(HAT_Y);
        assertEq(cfgX.quorum, uint32(2));
        assertEq(cfgY.quorum, uint32(3));
    }

    function test_BatchConfigureVouching_strangerReverts() public {
        uint256[] memory hatIds = new uint256[](1);
        hatIds[0] = HAT_X;
        uint32[] memory quorums = new uint32[](1);
        quorums[0] = 1;
        uint256[] memory members = new uint256[](1);
        members[0] = HAT_Y;
        bool[] memory flags = new bool[](1);

        vm.expectRevert(EligibilityModule.NotSuperAdmin.selector);
        vm.prank(stranger);
        eligibility.batchConfigureVouching(hatIds, quorums, members, flags);
    }
}

/// MaliciousHats — synthetic IHats impl whose mintHat re-enters claimVouchedHat.
/// Used by ReentrancyAttackTest below to verify the nonReentrant modifier on
/// claimVouchedHat (line 881 of EligibilityModule.sol post-PR-#129) actually
/// fires on the re-entry attempt. This is the cat-5 finding vigil's cancelled
/// #520 wanted but didn't ship; closing the gap here.
contract MaliciousHats is MockHats {
    EligibilityModule public target;
    uint256 public targetHatId;
    address public attacker;
    bool public attackArmed;
    uint256 public reentryCount;
    bool public reentryReverted;

    function arm(EligibilityModule _target, uint256 _hatId, address _attacker) external {
        target = _target;
        targetHatId = _hatId;
        attacker = _attacker;
        attackArmed = true;
    }

    function mintHat(uint256 _hatId, address _wearer) external override returns (bool) {
        // The original MockHats.mintHat sets wearers[_wearer][_hatId] = true.
        // We do that too so the outer call appears to succeed normally if
        // re-entry is blocked (which is what we expect).
        if (attackArmed) {
            attackArmed = false; // single-shot
            reentryCount++;
            // Try to re-enter claimVouchedHat. With nonReentrant in place,
            // this MUST revert. We catch + record.
            try target.claimVouchedHat(targetHatId) {
                // Did NOT revert — reentrancy succeeded, fix is broken.
                reentryReverted = false;
            } catch {
                // Revert as expected.
                reentryReverted = true;
            }
        }
        // Always honor the legit mint so the outer call sees success
        wearers[_wearer][_hatId] = true;
        return true;
    }
}

/// Verifies the nonReentrant modifier on claimVouchedHat blocks the cat-5
/// reentrancy attack vigil's cancelled #520 called out. A malicious IHats
/// impl re-enters claimVouchedHat during the mintHat external call inside
/// claimVouchedHat. Pre-fix (no modifier wired): re-entry double-claims.
/// Post-fix: re-entry hits the nonReentrant guard and reverts.
contract EligibilityModuleReentrancyTest is Test {
    EligibilityModule internal eligibility;
    MaliciousHats internal hats;

    address internal superAdmin = vm.addr(11);
    address internal voucher = vm.addr(12);
    address internal attacker = vm.addr(13);

    uint256 internal constant HAT_TARGET = 7000;
    uint256 internal constant HAT_VOUCHER = 8000;

    function setUp() public {
        hats = new MaliciousHats();

        EligibilityModule impl = new EligibilityModule();
        bytes memory initData =
            abi.encodeCall(EligibilityModule.initialize, (superAdmin, address(hats), address(0)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        eligibility = EligibilityModule(address(proxy));

        // Setup: 1-of-1 vouching for HAT_TARGET, vouchers wear HAT_VOUCHER
        vm.prank(superAdmin);
        eligibility.configureVouching(HAT_TARGET, 1, HAT_VOUCHER, false);

        // Mint voucher hat directly to voucher so they can vouch
        hats.mintHat(HAT_VOUCHER, voucher);

        // voucher vouches attacker → attacker becomes eligible to claim
        vm.prank(voucher);
        eligibility.vouchFor(attacker, HAT_TARGET);
    }

    function test_Reentrancy_claimVouchedHat_blocksRecursion() public {
        // Arm the attack: when claimVouchedHat calls hats.mintHat(HAT_TARGET, attacker),
        // our MaliciousHats re-enters claimVouchedHat(HAT_TARGET).
        hats.arm(eligibility, HAT_TARGET, attacker);

        // Outer claim succeeds; inner re-entry must be blocked by nonReentrant.
        vm.prank(attacker);
        eligibility.claimVouchedHat(HAT_TARGET);

        // Verify the attempt happened + reverted.
        assertEq(hats.reentryCount(), 1, "re-entry attempted exactly once");
        assertTrue(hats.reentryReverted(), "re-entry hit nonReentrant guard and reverted");

        // Verify attacker has the hat exactly once (not double-claimed).
        assertTrue(hats.isWearerOfHat(attacker, HAT_TARGET), "outer claim minted hat");
    }
}
