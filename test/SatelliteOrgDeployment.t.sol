// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {NameClaimAdapter} from "../src/crosschain/NameClaimAdapter.sol";
import {SatelliteOnboardingHelper} from "../src/crosschain/SatelliteOnboardingHelper.sol";

/* ═══════════════ Mock contracts ═══════════════ */

contract MockRelay {
    mapping(bytes32 => bool) public confirmedOrgNames;
    mapping(address => string) private _usernames;

    function setConfirmedOrgName(bytes32 nameHash, bool confirmed) external {
        confirmedOrgNames[nameHash] = confirmed;
    }

    function registerAccountDirect(string calldata) external payable {
        // no-op in mock; real relay dispatches via Hyperlane
    }

    function getUsername(address user) external view returns (string memory) {
        return _usernames[user];
    }

    function setUsername(address user, string calldata name) external {
        _usernames[user] = name;
    }
}

contract MockQuickJoin {
    mapping(address => bool) public joined;

    function quickJoinForUser(address user) external {
        joined[user] = true;
    }
}

/* ═══════════════ NameClaimAdapter Tests ═══════════════ */

contract NameClaimAdapterTest is Test {
    NameClaimAdapter adapter;
    MockRelay relay;

    address owner = address(this);
    address orgRegistry = address(0xAA);

    function setUp() public {
        relay = new MockRelay();

        NameClaimAdapter impl = new NameClaimAdapter();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        adapter = NameClaimAdapter(
            address(new BeaconProxy(address(beacon), abi.encodeCall(impl.initialize, (owner, address(relay)))))
        );

        adapter.setAuthorizedCaller(orgRegistry, true);
    }

    function testClaimConfirmedNameSucceeds() public {
        bytes32 nameHash = keccak256("MyOrg");
        relay.setConfirmedOrgName(nameHash, true);

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(nameHash);

        assertTrue(adapter.consumedOrgNames(nameHash));
    }

    function testClaimUnconfirmedNameReverts() public {
        bytes32 nameHash = keccak256("NoOrg");

        vm.prank(orgRegistry);
        vm.expectRevert(NameClaimAdapter.NameNotConfirmed.selector);
        adapter.claimOrgNameLocal(nameHash);
    }

    function testClaimAlreadyConsumedNameReverts() public {
        bytes32 nameHash = keccak256("MyOrg");
        relay.setConfirmedOrgName(nameHash, true);

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(nameHash);

        vm.prank(orgRegistry);
        vm.expectRevert(NameClaimAdapter.NameAlreadyConsumed.selector);
        adapter.claimOrgNameLocal(nameHash);
    }

    function testChangeOrgNameSucceeds() public {
        bytes32 oldHash = keccak256("OldOrg");
        bytes32 newHash = keccak256("NewOrg");

        relay.setConfirmedOrgName(oldHash, true);
        relay.setConfirmedOrgName(newHash, true);

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(oldHash);

        vm.prank(orgRegistry);
        adapter.changeOrgNameLocal(oldHash, newHash);

        assertFalse(adapter.consumedOrgNames(oldHash));
        assertTrue(adapter.consumedOrgNames(newHash));
    }

    function testChangeOrgNameUnconfirmedNewNameReverts() public {
        bytes32 oldHash = keccak256("OldOrg");
        bytes32 newHash = keccak256("NewOrg");

        relay.setConfirmedOrgName(oldHash, true);
        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(oldHash);

        vm.prank(orgRegistry);
        vm.expectRevert(NameClaimAdapter.NameNotConfirmed.selector);
        adapter.changeOrgNameLocal(oldHash, newHash);
    }

    function testUnauthorizedCallerReverts() public {
        bytes32 nameHash = keccak256("MyOrg");
        relay.setConfirmedOrgName(nameHash, true);

        vm.prank(address(0x999));
        vm.expectRevert(NameClaimAdapter.NotAuthorized.selector);
        adapter.claimOrgNameLocal(nameHash);
    }

    function testDoubleInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        adapter.initialize(owner, address(relay));
    }

    function testZeroAddressInitReverts() public {
        NameClaimAdapter impl = new NameClaimAdapter();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        NameClaimAdapter tmp = NameClaimAdapter(address(new BeaconProxy(address(beacon), "")));

        vm.expectRevert(NameClaimAdapter.ZeroAddress.selector);
        tmp.initialize(address(0), address(relay));
    }

    function testRenounceOwnershipReverts() public {
        vm.expectRevert(NameClaimAdapter.CannotRenounce.selector);
        adapter.renounceOwnership();
    }

    function testSetAuthorizedCallerZeroAddressReverts() public {
        vm.expectRevert(NameClaimAdapter.ZeroAddress.selector);
        adapter.setAuthorizedCaller(address(0), true);
    }
}

/* ═══════════════ SatelliteOnboardingHelper Tests ═══════════════ */

contract SatelliteOnboardingHelperTest is Test {
    SatelliteOnboardingHelper helper;
    MockRelay relay;
    MockQuickJoin quickJoin;

    address owner = address(this);
    address user1 = address(0x100);

    event JoinRequested(address indexed user, string username);
    event JoinCompleted(address indexed user);

    function setUp() public {
        relay = new MockRelay();
        quickJoin = new MockQuickJoin();

        SatelliteOnboardingHelper impl = new SatelliteOnboardingHelper();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        helper = SatelliteOnboardingHelper(
            address(
                new BeaconProxy(
                    address(beacon), abi.encodeCall(impl.initialize, (owner, address(relay), address(quickJoin)))
                )
            )
        );
    }

    function testRegisterAndRequestJoin() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit JoinRequested(user1, "alice");
        helper.registerAndRequestJoin("alice");

        assertTrue(helper.pendingJoins(user1));
    }

    function testCompletePendingJoinMintsHats() public {
        // Step 1: Request join
        vm.prank(user1);
        helper.registerAndRequestJoin("alice");

        // Step 2: Simulate username confirmation arriving via Hyperlane
        relay.setUsername(user1, "alice");

        // Step 3: Complete the join (anyone can call)
        vm.expectEmit(true, true, true, true);
        emit JoinCompleted(user1);
        helper.completePendingJoin(user1);

        assertTrue(quickJoin.joined(user1));
        assertFalse(helper.pendingJoins(user1));
    }

    function testCompletePendingJoinRevertsNoConfirmation() public {
        vm.prank(user1);
        helper.registerAndRequestJoin("alice");

        // Username not confirmed yet
        vm.expectRevert(SatelliteOnboardingHelper.UsernameNotConfirmed.selector);
        helper.completePendingJoin(user1);
    }

    function testCompletePendingJoinRevertsNoPending() public {
        vm.expectRevert(SatelliteOnboardingHelper.NoPendingJoin.selector);
        helper.completePendingJoin(user1);
    }

    function testQuickJoinWithUserDirect() public {
        relay.setUsername(user1, "alice");

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit JoinCompleted(user1);
        helper.quickJoinWithUser();

        assertTrue(quickJoin.joined(user1));
    }

    function testQuickJoinWithUserRevertsNoUsername() public {
        vm.prank(user1);
        vm.expectRevert(SatelliteOnboardingHelper.NoUsername.selector);
        helper.quickJoinWithUser();
    }

    function testDoubleInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        helper.initialize(owner, address(relay), address(quickJoin));
    }

    function testZeroAddressInitReverts() public {
        SatelliteOnboardingHelper impl = new SatelliteOnboardingHelper();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        SatelliteOnboardingHelper tmp = SatelliteOnboardingHelper(address(new BeaconProxy(address(beacon), "")));

        vm.expectRevert(SatelliteOnboardingHelper.ZeroAddress.selector);
        tmp.initialize(address(0), address(relay), address(quickJoin));
    }

    function testRenounceOwnershipReverts() public {
        vm.expectRevert(SatelliteOnboardingHelper.CannotRenounce.selector);
        helper.renounceOwnership();
    }
}
