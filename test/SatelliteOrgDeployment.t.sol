// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {Initializable} from "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {NameClaimAdapter} from "../src/crosschain/NameClaimAdapter.sol";
import {SatelliteOnboardingHelper, IPasskeyFactory} from "../src/crosschain/SatelliteOnboardingHelper.sol";

/* ═══════════════ Mock contracts ═══════════════ */

contract MockRelay {
    mapping(bytes32 => bool) public confirmedOrgNames;
    mapping(address => string) private _usernames;

    // Track calls for assertions
    address public lastRegisteredUser;
    string public lastRegisteredUsername;
    bytes32 public lastReleasedNameHash;

    function setConfirmedOrgName(bytes32 nameHash, bool confirmed) external {
        confirmedOrgNames[nameHash] = confirmed;
    }

    string public lastClaimedOrgName;

    function dispatchOrgNameClaim(string calldata orgName) external {
        lastClaimedOrgName = orgName;
    }

    function dispatchOrgNameRelease(bytes32 nameHash) external {
        lastReleasedNameHash = nameHash;
        delete confirmedOrgNames[nameHash];
    }

    function registerAccountForUser(address user, string calldata username) external payable {
        lastRegisteredUser = user;
        lastRegisteredUsername = username;
    }

    function registerAccount(address user, string calldata username, uint256, uint256, bytes calldata)
        external
        payable
    {
        lastRegisteredUser = user;
        lastRegisteredUsername = username;
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
    mapping(address => bool) public joinedNoUser;

    function quickJoinForUser(address user) external {
        joined[user] = true;
    }

    function quickJoinNoUserMasterDeploy(address newUser) external {
        joinedNoUser[newUser] = true;
    }
}

contract MockPasskeyFactory {
    address public lastCreatedAccount;

    /// @dev Returns a deterministic address based ONLY on the passkey params (not msg.sender),
    ///      so both the test and the helper get the same address for the same inputs.
    function createAccount(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        returns (address account)
    {
        account = address(uint160(uint256(keccak256(abi.encodePacked(credentialId, pubKeyX, pubKeyY, salt)))));
        lastCreatedAccount = account;
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

    function testClaimDispatchesOptimistically() public {
        bytes32 nameHash = keccak256("MyOrg");

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(nameHash, "MyOrg");

        // Verify claim was dispatched to relay
        assertEq(relay.lastClaimedOrgName(), "MyOrg");
    }

    function testChangeOrgNameSucceeds() public {
        bytes32 oldHash = keccak256("OldOrg");
        bytes32 newHash = keccak256("NewOrg");

        relay.setConfirmedOrgName(newHash, true);

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(oldHash, "OldOrg");

        vm.prank(orgRegistry);
        adapter.changeOrgNameLocal(oldHash, newHash);

        // Verify old name was released on relay
        assertEq(relay.lastReleasedNameHash(), oldHash);
        assertFalse(relay.confirmedOrgNames(oldHash));
    }

    function testChangeOrgNameUnconfirmedNewNameReverts() public {
        bytes32 oldHash = keccak256("OldOrg");
        bytes32 newHash = keccak256("NewOrg");

        vm.prank(orgRegistry);
        adapter.claimOrgNameLocal(oldHash, "OldOrg");

        vm.prank(orgRegistry);
        vm.expectRevert(NameClaimAdapter.NameNotConfirmed.selector);
        adapter.changeOrgNameLocal(oldHash, newHash);
    }

    function testUnauthorizedCallerReverts() public {
        bytes32 nameHash = keccak256("MyOrg");

        vm.prank(address(0x999));
        vm.expectRevert(NameClaimAdapter.NotAuthorized.selector);
        adapter.claimOrgNameLocal(nameHash, "MyOrg");
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
    MockPasskeyFactory passkeyFactory;

    address owner = address(this);
    address user1 = address(0x100);

    event RegisterAndJoined(address indexed user, string username);
    event RegisterAndJoinedWithPasskey(address indexed account, bytes32 indexed credentialId, string username);
    event JoinCompleted(address indexed user);
    event JoinCompletedWithPasskey(address indexed account, bytes32 indexed credentialId);

    function setUp() public {
        relay = new MockRelay();
        quickJoin = new MockQuickJoin();
        passkeyFactory = new MockPasskeyFactory();

        SatelliteOnboardingHelper impl = new SatelliteOnboardingHelper();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        helper = SatelliteOnboardingHelper(
            address(
                new BeaconProxy(
                    address(beacon),
                    abi.encodeCall(
                        impl.initialize, (owner, address(relay), address(quickJoin), address(passkeyFactory))
                    )
                )
            )
        );
    }

    /* ── Optimistic: registerAndJoin (EOA direct) ── */

    function testRegisterAndJoin() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit RegisterAndJoined(user1, "alice");
        helper.registerAndJoin("alice");

        // Verify relay was called with correct user
        assertEq(relay.lastRegisteredUser(), user1);
        assertEq(relay.lastRegisteredUsername(), "alice");
        // Verify user joined immediately (no username check)
        assertTrue(quickJoin.joinedNoUser(user1));
    }

    /* ── Optimistic: registerAndJoinSponsored (relayer path) ── */

    function testRegisterAndJoinSponsored() public {
        address relayer = address(0x200);

        vm.prank(relayer);
        vm.expectEmit(true, true, true, true);
        emit RegisterAndJoined(user1, "alice");
        helper.registerAndJoinSponsored(user1, "alice", block.timestamp + 1 hours, 0, "fakesig");

        assertEq(relay.lastRegisteredUser(), user1);
        assertEq(relay.lastRegisteredUsername(), "alice");
        assertTrue(quickJoin.joinedNoUser(user1));
    }

    /* ── Optimistic: registerAndJoinWithPasskey ── */

    function testRegisterAndJoinWithPasskey() public {
        SatelliteOnboardingHelper.PasskeyEnrollment memory passkey = _defaultPasskey();

        address account = helper.registerAndJoinWithPasskey(passkey, "alice");

        // Verify passkey account was created
        assertEq(passkeyFactory.lastCreatedAccount(), account);
        // Verify relay was called with passkey account address
        assertEq(relay.lastRegisteredUser(), account);
        assertEq(relay.lastRegisteredUsername(), "alice");
        // Verify account joined immediately
        assertTrue(quickJoin.joinedNoUser(account));
    }

    function testRegisterAndJoinWithPasskeyRevertsNoFactory() public {
        SatelliteOnboardingHelper noPasskeyHelper = _deployWithoutPasskey();

        vm.expectRevert(SatelliteOnboardingHelper.PasskeyFactoryNotSet.selector);
        noPasskeyHelper.registerAndJoinWithPasskey(_defaultPasskey(), "alice");
    }

    /* ── Non-optimistic: quickJoinWithUser ── */

    function testQuickJoinWithUser() public {
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

    /* ── Non-optimistic: quickJoinWithPasskey ── */

    function testQuickJoinWithPasskey() public {
        SatelliteOnboardingHelper.PasskeyEnrollment memory passkey = _defaultPasskey();

        // Compute the deterministic account address (same formula as MockPasskeyFactory)
        address account = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt)
                    )
                )
            )
        );

        // Simulate username already confirmed for this passkey account
        relay.setUsername(account, "alice");

        address returned = helper.quickJoinWithPasskey(passkey);

        assertEq(returned, account);
        assertTrue(quickJoin.joined(account));
    }

    function testQuickJoinWithPasskeyRevertsNoUsername() public {
        vm.expectRevert(SatelliteOnboardingHelper.NoUsername.selector);
        helper.quickJoinWithPasskey(_defaultPasskey());
    }

    function testQuickJoinWithPasskeyRevertsNoFactory() public {
        SatelliteOnboardingHelper noPasskeyHelper = _deployWithoutPasskey();

        vm.expectRevert(SatelliteOnboardingHelper.PasskeyFactoryNotSet.selector);
        noPasskeyHelper.quickJoinWithPasskey(_defaultPasskey());
    }

    /* ── Admin / Init ── */

    function testDoubleInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        helper.initialize(owner, address(relay), address(quickJoin), address(passkeyFactory));
    }

    function testZeroAddressInitReverts() public {
        SatelliteOnboardingHelper impl = new SatelliteOnboardingHelper();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        SatelliteOnboardingHelper tmp = SatelliteOnboardingHelper(address(new BeaconProxy(address(beacon), "")));

        vm.expectRevert(SatelliteOnboardingHelper.ZeroAddress.selector);
        tmp.initialize(address(0), address(relay), address(quickJoin), address(passkeyFactory));
    }

    function testRenounceOwnershipReverts() public {
        vm.expectRevert(SatelliteOnboardingHelper.CannotRenounce.selector);
        helper.renounceOwnership();
    }

    function testGetters() public view {
        assertEq(address(helper.relay()), address(relay));
        assertEq(address(helper.quickJoin()), address(quickJoin));
        assertEq(address(helper.passkeyFactory()), address(passkeyFactory));
    }

    /* ── Test Helpers ── */

    function _defaultPasskey() internal pure returns (SatelliteOnboardingHelper.PasskeyEnrollment memory) {
        return SatelliteOnboardingHelper.PasskeyEnrollment({
            credentialId: bytes32(uint256(1)),
            publicKeyX: bytes32(uint256(2)),
            publicKeyY: bytes32(uint256(3)),
            salt: 42
        });
    }

    function _deployWithoutPasskey() internal returns (SatelliteOnboardingHelper) {
        SatelliteOnboardingHelper impl = new SatelliteOnboardingHelper();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), address(this));
        return SatelliteOnboardingHelper(
            address(
                new BeaconProxy(
                    address(beacon),
                    abi.encodeCall(impl.initialize, (owner, address(relay), address(quickJoin), address(0)))
                )
            )
        );
    }
}
