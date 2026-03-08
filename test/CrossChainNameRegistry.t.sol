// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {NameRegistryHub} from "../src/crosschain/NameRegistryHub.sol";
import {RegistryRelay} from "../src/crosschain/RegistryRelay.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";
import {StoringMailbox} from "./mocks/StoringMailbox.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract CrossChainNameRegistryTest is Test {
    /*──────────── Constants ───────────*/
    uint32 constant HOME_DOMAIN = 42161; // Arbitrum
    uint32 constant SAT_DOMAIN_A = 100; // Gnosis
    uint32 constant SAT_DOMAIN_B = 8453; // Base

    /*──────────── Contracts ───────────*/
    // Home chain: uses StoringMailbox (no auto-delivery) so hub's return dispatches
    // don't fail when crossing chain boundaries in tests.
    StoringMailbox homeMailbox;
    UniversalAccountRegistry uar;
    NameRegistryHub hub;

    // Satellite mailboxes (StoringMailbox — no auto-delivery, avoids cross-chain sender mismatch)
    StoringMailbox satMailboxA;
    StoringMailbox satMailboxB;
    RegistryRelay relayA;
    RegistryRelay relayB;

    // Home chain: OrgRegistry for org name tests
    OrgRegistry orgRegistry;

    /*──────────── Users ───────────*/
    uint256 aliceKey = 0xa11ce;
    address alice = vm.addr(aliceKey);
    uint256 bobKey = 0xb0b;
    address bob = vm.addr(bobKey);

    /*──────────── Setup ───────────*/
    function setUp() public {
        // Deploy home-chain UAR behind beacon proxy
        UniversalAccountRegistry uarImpl = new UniversalAccountRegistry();
        UpgradeableBeacon uarBeacon = new UpgradeableBeacon(address(uarImpl), address(this));
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        uar = UniversalAccountRegistry(address(new BeaconProxy(address(uarBeacon), initData)));

        // Deploy home-chain mailbox (storing, no auto-delivery)
        homeMailbox = new StoringMailbox(HOME_DOMAIN);

        // Deploy hub behind beacon proxy (upgradeable pattern)
        NameRegistryHub hubImpl = new NameRegistryHub();
        UpgradeableBeacon hubBeacon = new UpgradeableBeacon(address(hubImpl), address(this));
        bytes memory hubInit =
            abi.encodeCall(NameRegistryHub.initialize, (address(this), address(uar), address(homeMailbox)));
        hub = NameRegistryHub(payable(address(new BeaconProxy(address(hubBeacon), hubInit))));

        // Wire UAR to hub
        uar.setNameRegistryHub(address(hub));

        // Deploy satellite mailboxes (storing, no auto-delivery)
        satMailboxA = new StoringMailbox(SAT_DOMAIN_A);
        satMailboxB = new StoringMailbox(SAT_DOMAIN_B);

        // Deploy relays behind shared beacon proxy (upgradeable pattern)
        RegistryRelay relayImpl = new RegistryRelay();
        UpgradeableBeacon relayBeacon = new UpgradeableBeacon(address(relayImpl), address(this));

        bytes memory relayInitA =
            abi.encodeCall(RegistryRelay.initialize, (address(this), address(satMailboxA), HOME_DOMAIN, address(hub)));
        relayA = RegistryRelay(address(new BeaconProxy(address(relayBeacon), relayInitA)));

        bytes memory relayInitB =
            abi.encodeCall(RegistryRelay.initialize, (address(this), address(satMailboxB), HOME_DOMAIN, address(hub)));
        relayB = RegistryRelay(address(new BeaconProxy(address(relayBeacon), relayInitB)));

        // Register satellites on hub
        hub.registerSatellite(SAT_DOMAIN_A, address(relayA));
        hub.registerSatellite(SAT_DOMAIN_B, address(relayB));

        // Deploy OrgRegistry behind ERC1967 proxy (for org name tests)
        OrgRegistry orgImpl = new OrgRegistry();
        bytes memory orgInit = abi.encodeCall(OrgRegistry.initialize, (address(this), address(1))); // mock hats
        orgRegistry = OrgRegistry(address(new ERC1967Proxy(address(orgImpl), orgInit)));

        // Wire OrgRegistry to NameRegistryHub
        orgRegistry.setNameRegistryHub(address(hub));
        hub.setAuthorizedOrgRegistry(address(orgRegistry), true);
    }

    /*══════════════════ Helper ══════════════════*/

    function _hubHandle(uint32 origin, address satellite, bytes memory body) internal {
        vm.prank(address(homeMailbox));
        hub.handle(origin, bytes32(uint256(uint160(satellite))), body);
    }

    /// @dev Deliver the last dispatched message from hub's StoringMailbox to a relay.
    function _deliverConfirmToRelay(RegistryRelay relay, StoringMailbox relayMailbox) internal {
        uint256 count = homeMailbox.dispatchedCount();
        require(count > 0, "no messages to deliver");
        StoringMailbox.DispatchedMessage memory msg_ = homeMailbox.getDispatched(count - 1);
        vm.prank(address(relayMailbox));
        relay.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), msg_.messageBody);
    }

    /*══════════════════ Home-Chain Registration ══════════════════*/

    function testHomeChainRegister() public {
        vm.prank(alice);
        uar.registerAccount("alice");

        assertEq(uar.getUsername(alice), "alice");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
    }

    function testHomeChainRegisterDuplicate() public {
        vm.prank(alice);
        uar.registerAccount("alice");

        vm.prank(bob);
        vm.expectRevert();
        uar.registerAccount("alice");
    }

    function testHomeChainRegisterCaseInsensitive() public {
        vm.prank(alice);
        uar.registerAccount("Alice");

        vm.prank(bob);
        vm.expectRevert();
        uar.registerAccount("alice");
    }

    function testHomeChainChangeUsername() public {
        vm.prank(alice);
        uar.registerAccount("alice");

        vm.prank(alice);
        uar.changeUsername("alice2");

        assertEq(uar.getUsername(alice), "alice2");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
        assertTrue(hub.reserved(keccak256(bytes("alice2"))));
    }

    function testHomeChainChangeUsernameTaken() public {
        vm.prank(alice);
        uar.registerAccount("alice");

        vm.prank(bob);
        uar.registerAccount("bob");

        vm.prank(alice);
        vm.expectRevert();
        uar.changeUsername("bob");
    }

    function testHomeChainDeleteAccount() public {
        vm.prank(alice);
        uar.registerAccount("alice");

        vm.prank(alice);
        uar.deleteAccount();

        assertEq(uar.getUsername(alice), "");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
    }

    /*══════════════════ Cross-Chain Registration (Hub Side) ══════════════════*/

    function testCrossChainClaimSuccess() public {
        bytes memory claim = abi.encode(uint8(0x01), alice, "alice");
        _hubHandle(SAT_DOMAIN_A, address(relayA), claim);

        assertEq(uar.getUsername(alice), "alice");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));

        // Hub dispatched MSG_CONFIRM back
        assertEq(homeMailbox.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(resp.destinationDomain, SAT_DOMAIN_A);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x02); // MSG_CONFIRM_USERNAME
    }

    function testCrossChainRaceCondition() public {
        bytes memory claimAlice = abi.encode(uint8(0x01), alice, "coolname");
        bytes memory claimBob = abi.encode(uint8(0x01), bob, "coolname");

        // Alice arrives first → success
        _hubHandle(SAT_DOMAIN_A, address(relayA), claimAlice);
        assertEq(uar.getUsername(alice), "coolname");

        // Bob arrives second → reject
        _hubHandle(SAT_DOMAIN_B, address(relayB), claimBob);
        assertEq(uar.getUsername(bob), "");

        assertEq(homeMailbox.dispatchedCount(), 2);

        // Confirm to A
        StoringMailbox.DispatchedMessage memory resp0 = homeMailbox.getDispatched(0);
        assertEq(resp0.destinationDomain, SAT_DOMAIN_A);
        assertEq(abi.decode(resp0.messageBody, (uint8)), 0x02);

        // Reject to B
        StoringMailbox.DispatchedMessage memory resp1 = homeMailbox.getDispatched(1);
        assertEq(resp1.destinationDomain, SAT_DOMAIN_B);
        assertEq(abi.decode(resp1.messageBody, (uint8)), 0x03);
    }

    function testCrossChainThenHomeChainFails() public {
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));

        vm.prank(bob);
        vm.expectRevert();
        uar.registerAccount("alice");
    }

    function testCrossChainBurn() public {
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));

        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x04), alice));

        assertEq(uar.getUsername(alice), "");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
    }

    function testCrossChainChangeUsername() public {
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));

        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x05), alice, "alice2"));

        assertEq(uar.getUsername(alice), "alice2");
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
        assertTrue(hub.reserved(keccak256(bytes("alice2"))));

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(1);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x02);
    }

    function testCrossChainChangeUsernameTaken() public {
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x01), bob, "bob"));

        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x05), alice, "bob"));

        assertEq(uar.getUsername(alice), "alice");

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(2);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x03);
    }

    /*══════════════════ Full Round-Trip ══════════════════*/

    function testFullRoundTripConfirm() public {
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        _deliverConfirmToRelay(relayA, satMailboxA);

        assertEq(relayA.getUsername(alice), "alice");
        assertEq(relayA.getAddressOfUsername("alice"), alice);
    }

    function testFullRoundTripReject() public {
        // Alice takes "coolname"
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "coolname"));

        // Bob tries same → rejected
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x01), bob, "coolname"));

        // Deliver reject to relay B
        StoringMailbox.DispatchedMessage memory rejectMsg = homeMailbox.getDispatched(1);
        vm.prank(address(satMailboxB));
        relayB.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), rejectMsg.messageBody);

        assertEq(relayB.getUsername(bob), "");
    }

    /*══════════════════ Hub Security ══════════════════*/

    function testHubRejectsUnauthorizedMailbox() public {
        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.UnauthorizedMailbox.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(relayA)))), abi.encode(uint8(0x01), alice, "a"));
    }

    function testHubRejectsUnregisteredSatellite() public {
        vm.prank(address(homeMailbox));
        vm.expectRevert(NameRegistryHub.UnauthorizedSatellite.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(0xdead)))), abi.encode(uint8(0x01), alice, "a"));
    }

    function testHubRejectsUnknownMessageType() public {
        vm.prank(address(homeMailbox));
        vm.expectRevert(NameRegistryHub.UnknownMessageType.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(relayA)))), abi.encode(uint8(0xFF), alice, "a"));
    }

    function testHubPause() public {
        hub.setPaused(true);
        vm.prank(address(homeMailbox));
        vm.expectRevert(NameRegistryHub.IsPaused.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(relayA)))), abi.encode(uint8(0x01), alice, "a"));
    }

    function testHubCannotRenounceOwnership() public {
        vm.expectRevert(NameRegistryHub.CannotRenounce.selector);
        hub.renounceOwnership();
    }

    function testHubAdminBurn() public {
        hub.adminBurn(keccak256(bytes("offensive")));
        assertTrue(hub.reserved(keccak256(bytes("offensive"))));

        vm.prank(alice);
        vm.expectRevert();
        uar.registerAccount("offensive");
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function testRegisterDuplicateSatelliteFails() public {
        vm.expectRevert(abi.encodeWithSelector(NameRegistryHub.DuplicateDomain.selector, SAT_DOMAIN_A));
        hub.registerSatellite(SAT_DOMAIN_A, address(0x1234));
    }

    function testRemoveSatellite() public {
        hub.removeSatellite(0);
        vm.prank(address(homeMailbox));
        vm.expectRevert(NameRegistryHub.UnauthorizedSatellite.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(relayA)))), abi.encode(uint8(0x01), alice, "a"));
    }

    function testSatelliteCount() public view {
        assertEq(hub.satelliteCount(), 2);
    }

    /*══════════════════ Relay Tests ══════════════════*/

    function testRelayRejectsUnauthorizedMailbox() public {
        vm.prank(alice);
        vm.expectRevert(RegistryRelay.UnauthorizedMailbox.selector);
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "a"));
    }

    function testRelayRejectsWrongOrigin() public {
        vm.prank(address(satMailboxA));
        vm.expectRevert(RegistryRelay.UnauthorizedOrigin.selector);
        relayA.handle(999, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "a"));
    }

    function testRelayRejectsWrongSender() public {
        vm.prank(address(satMailboxA));
        vm.expectRevert(RegistryRelay.UnauthorizedSender.selector);
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(0xdead)))), abi.encode(uint8(0x02), alice, "a"));
    }

    function testRelayConfirmUpdatesCache() public {
        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "alice"));

        assertEq(relayA.getUsername(alice), "alice");
        assertEq(relayA.getAddressOfUsername("alice"), alice);
    }

    function testRelayRejectEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit RegistryRelay.UsernameRejected(alice, "alice");

        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x03), alice, "alice"));

        assertEq(relayA.getUsername(alice), "");
    }

    function testRelayPause() public {
        relayA.setPaused(true);
        vm.expectRevert(RegistryRelay.IsPaused.selector);
        relayA.registerAccountDirect("alice");
    }

    function testRelayCannotRenounceOwnership() public {
        vm.expectRevert(RegistryRelay.CannotRenounce.selector);
        relayA.renounceOwnership();
    }

    function testRelayUsernameValidation() public {
        vm.expectRevert(RegistryRelay.UsernameEmpty.selector);
        relayA.registerAccountDirect("");

        vm.expectRevert(RegistryRelay.InvalidChars.selector);
        relayA.registerAccountDirect("bad name!");
    }

    function testRelayDeleteClearsCache() public {
        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "alice"));
        assertEq(relayA.getUsername(alice), "alice");

        vm.prank(alice);
        relayA.deleteAccount();
        assertEq(relayA.getUsername(alice), "");
    }

    /*══════════════════ UAR Standalone / Access ══════════════════*/

    function testUARStandaloneMode() public {
        UniversalAccountRegistry uarImpl = new UniversalAccountRegistry();
        UpgradeableBeacon uarBeacon = new UpgradeableBeacon(address(uarImpl), address(this));
        bytes memory initData = abi.encodeWithSignature("initialize(address)", address(this));
        UniversalAccountRegistry standalone =
            UniversalAccountRegistry(address(new BeaconProxy(address(uarBeacon), initData)));

        assertEq(standalone.nameRegistryHub(), address(0));
        vm.prank(alice);
        standalone.registerAccount("alice");
        assertEq(standalone.getUsername(alice), "alice");
    }

    function testUARCrossChainOnlyHub() public {
        vm.prank(alice);
        vm.expectRevert(UniversalAccountRegistry.NotHub.selector);
        uar.registerAccountCrossChain(alice, "alice");
    }

    /*══════════════════ ETH ══════════════════*/

    function testHubReceiveETH() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(hub).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(hub).balance, 1 ether);
    }

    function testHubWithdrawETH() public {
        vm.deal(address(hub), 1 ether);
        hub.withdrawETH(payable(address(0x1234)));
        assertEq(address(hub).balance, 0);
        assertEq(address(0x1234).balance, 1 ether);
    }

    /*══════════════════ Hub Return Fee ══════════════════*/

    function testHubReturnFeeDispatch() public {
        hub.setReturnFee(0.001 ether);
        vm.deal(address(hub), 1 ether);

        // Cross-chain claim — hub should use returnFee for the confirm dispatch
        bytes memory claim = abi.encode(uint8(0x01), alice, "alice");
        _hubHandle(SAT_DOMAIN_A, address(relayA), claim);

        assertEq(uar.getUsername(alice), "alice");
        assertEq(homeMailbox.dispatchedCount(), 1);
    }

    function testHubReturnFeeInsufficientBalance() public {
        hub.setReturnFee(1 ether);
        // Hub has no ETH — should revert when trying to dispatch confirm

        bytes memory claim = abi.encode(uint8(0x01), alice, "alice");
        vm.prank(address(homeMailbox));
        vm.expectRevert(NameRegistryHub.InsufficientBalance.selector);
        hub.handle(SAT_DOMAIN_A, bytes32(uint256(uint160(address(relayA)))), claim);
    }

    /*══════════════════ Relay Signature Registration ══════════════════*/

    function testRelayRegisterAccountBySig() public {
        string memory username = "alice";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        // Build EIP-712 digest (relay's domain separator)
        bytes32 registerTypehash =
            keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(registerTypehash, alice, keccak256(bytes(username)), nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", relayA.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        relayA.registerAccount(alice, username, deadline, nonce, sig);

        // Verify claim was dispatched
        assertEq(satMailboxA.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory msg_ = satMailboxA.getDispatched(0);
        assertEq(msg_.destinationDomain, HOME_DOMAIN);
        (, address decodedUser, string memory decodedName) = abi.decode(msg_.messageBody, (uint8, address, string));
        assertEq(decodedUser, alice);
        assertEq(decodedName, username);

        // Nonce should have incremented
        assertEq(relayA.nonces(alice), 1);
    }

    function testRelayRegisterAccountBySigBadSigner() public {
        string memory username = "alice";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;

        bytes32 registerTypehash =
            keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(registerTypehash, alice, keccak256(bytes(username)), nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", relayA.DOMAIN_SEPARATOR(), structHash));

        // Sign with bob's key instead of alice's
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(RegistryRelay.InvalidSigner.selector);
        relayA.registerAccount(alice, username, deadline, nonce, sig);
    }

    /*══════════════════ Relay Change Username ══════════════════*/

    function testRelayChangeUsernameDispatch() public {
        vm.prank(alice);
        relayA.changeUsername("alice2");

        assertEq(satMailboxA.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory msg_ = satMailboxA.getDispatched(0);
        (uint8 msgType, address user, string memory name) = abi.decode(msg_.messageBody, (uint8, address, string));
        assertEq(msgType, 0x05); // MSG_CHANGE_USERNAME
        assertEq(user, alice);
        assertEq(name, "alice2");
    }

    /*══════════════════ Relay Delete Dispatches Burn ══════════════════*/

    function testRelayDeleteDispatchesBurn() public {
        // Populate cache first
        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "alice"));

        vm.prank(alice);
        relayA.deleteAccount();

        // Cache cleared
        assertEq(relayA.getUsername(alice), "");
        assertEq(relayA.getAddressOfUsername("alice"), address(0));

        // MSG_BURN dispatched
        assertEq(satMailboxA.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory msg_ = satMailboxA.getDispatched(0);
        (uint8 msgType, address user) = abi.decode(msg_.messageBody, (uint8, address));
        assertEq(msgType, 0x04); // MSG_BURN_USERNAME
        assertEq(user, alice);
    }

    /*══════════════════ Stale Cache Fix ══════════════════*/

    function testRelayCacheClearedOnUsernameChange() public {
        // Confirm "alice" for alice
        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "alice"));
        assertEq(relayA.getUsername(alice), "alice");
        assertEq(relayA.getAddressOfUsername("alice"), alice);

        // Confirm "alice2" for alice (username change)
        vm.prank(address(satMailboxA));
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0x02), alice, "alice2"));

        // New name resolves
        assertEq(relayA.getUsername(alice), "alice2");
        assertEq(relayA.getAddressOfUsername("alice2"), alice);

        // Old name no longer resolves (was stale before the fix)
        assertEq(relayA.getAddressOfUsername("alice"), address(0));
    }

    /*══════════════════ Hub Error Names ══════════════════*/

    function testHubLocalFunctionsRejectNonRegistry() public {
        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.NotAccountRegistry.selector);
        hub.claimUsernameLocal(keccak256(bytes("test")));

        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.NotAccountRegistry.selector);
        hub.changeUsernameLocal(keccak256(bytes("old")), keccak256(bytes("new")));

        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.NotAccountRegistry.selector);
        hub.burnUsernameLocal(keccak256(bytes("test")));
    }

    /*══════════════════ Integration: Multi-Step Round-Trips ══════════════════*/

    function testFullRoundTripChangeUsername() public {
        // Register "alice" via satellite A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        _deliverConfirmToRelay(relayA, satMailboxA);
        assertEq(relayA.getUsername(alice), "alice");
        assertEq(relayA.getAddressOfUsername("alice"), alice);

        // Change to "alice2" via satellite A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x05), alice, "alice2"));
        _deliverConfirmToRelay(relayA, satMailboxA);

        // New name cached, old name cleared
        assertEq(relayA.getUsername(alice), "alice2");
        assertEq(relayA.getAddressOfUsername("alice2"), alice);
        assertEq(relayA.getAddressOfUsername("alice"), address(0));

        // Both names reserved on hub (old name burned)
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
        assertTrue(hub.reserved(keccak256(bytes("alice2"))));
    }

    function testFullRoundTripDeleteAndReRegister() public {
        // Register "alice" via satellite A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        _deliverConfirmToRelay(relayA, satMailboxA);
        assertEq(relayA.getUsername(alice), "alice");

        // Delete (burn) via satellite A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x04), alice));

        // Try re-registering the burned name with a fresh address (charlie)
        // to isolate that rejection is due to name being burned, not account existing
        address charlie = vm.addr(0xc0de);
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), charlie, "alice"));

        // Charlie should get a reject (name is burned/reserved)
        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(homeMailbox.dispatchedCount() - 1);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x03); // MSG_REJECT
    }

    function testMultiSatelliteRegistration() public {
        // Alice registers on relay A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        _deliverConfirmToRelay(relayA, satMailboxA);

        // Bob registers on relay B (different name)
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x01), bob, "bob"));
        // Deliver confirm to relay B (second dispatched message)
        StoringMailbox.DispatchedMessage memory msg_ = homeMailbox.getDispatched(1);
        vm.prank(address(satMailboxB));
        relayB.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), msg_.messageBody);

        // Each relay has only its own user cached
        assertEq(relayA.getUsername(alice), "alice");
        assertEq(relayA.getUsername(bob), "");
        assertEq(relayB.getUsername(bob), "bob");
        assertEq(relayB.getUsername(alice), "");

        // Both globally reserved
        assertTrue(hub.reserved(keccak256(bytes("alice"))));
        assertTrue(hub.reserved(keccak256(bytes("bob"))));
    }

    /*══════════════════ Integration: Cross-Chain vs Home-Chain ══════════════════*/

    function testHomeChainBlocksCrossChainDuplicate() public {
        // Register "alice" on home chain
        vm.prank(alice);
        uar.registerAccount("alice");

        // Cross-chain claim for "alice" from satellite — should be rejected
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), bob, "alice"));

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x03); // MSG_REJECT
    }

    function testCrossChainBlocksHomeChainDuplicate() public {
        // Cross-chain claim "alice" arrives first
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        assertEq(uar.getUsername(alice), "alice");

        // Home-chain user tries to register same name — reverts
        vm.prank(bob);
        vm.expectRevert();
        uar.registerAccount("alice");
    }

    function testAdminBurnBlocksCrossChain() public {
        // Admin burns a name
        hub.adminBurn(keccak256(bytes("reserved-name")));

        // Cross-chain claim for that name — should be rejected
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "reserved-name"));

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x03); // MSG_REJECT
    }

    /*══════════════════ Integration: Edge Cases ══════════════════*/

    function testRelayRegisterExpiredDeadline() public {
        string memory username = "alice";
        uint256 deadline = block.timestamp - 1; // expired
        uint256 nonce = 0;

        bytes32 registerTypehash =
            keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(registerTypehash, alice, keccak256(bytes(username)), nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", relayA.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(RegistryRelay.SignatureExpired.selector);
        relayA.registerAccount(alice, username, deadline, nonce, sig);
    }

    function testRelayRegisterBadNonce() public {
        string memory username = "alice";
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 999; // wrong nonce (should be 0)

        bytes32 registerTypehash =
            keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
        bytes32 structHash = keccak256(abi.encode(registerTypehash, alice, keccak256(bytes(username)), nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", relayA.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert(RegistryRelay.InvalidNonce.selector);
        relayA.registerAccount(alice, username, deadline, nonce, sig);
    }

    function testRelayRejectsUnknownMessageType() public {
        vm.prank(address(satMailboxA));
        vm.expectRevert(RegistryRelay.UnknownMessageType.selector);
        relayA.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), abi.encode(uint8(0xFF), alice, "a"));
    }

    function testRelayUsernameTooLong() public {
        // 65 characters — exceeds MAX_LEN of 64
        string memory longName = "abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwxyzabcdefghijklm";
        vm.expectRevert(RegistryRelay.UsernameTooLong.selector);
        relayA.registerAccountDirect(longName);
    }

    function testRelayDirectRegisterDispatch() public {
        vm.prank(alice);
        relayA.registerAccountDirect("alice");

        assertEq(satMailboxA.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory msg_ = satMailboxA.getDispatched(0);
        assertEq(msg_.destinationDomain, HOME_DOMAIN);
        (uint8 msgType, address user, string memory name) = abi.decode(msg_.messageBody, (uint8, address, string));
        assertEq(msgType, 0x01); // MSG_CLAIM_USERNAME
        assertEq(user, alice);
        assertEq(name, "alice");
    }

    function testHubRegisterSatelliteZeroAddress() public {
        vm.expectRevert(NameRegistryHub.ZeroAddress.selector);
        hub.registerSatellite(999, address(0));
    }

    function testAdminBurnBlocksCrossChainUsernameChange() public {
        // Register alice with name "alice" via cross-chain
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x01), alice, "alice"));
        assertEq(uar.getUsername(alice), "alice");

        // Admin burns "offensive"
        hub.adminBurn(keccak256(bytes("offensive")));

        // Alice tries to change to the burned name via cross-chain
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x05), alice, "offensive"));

        // Should get MSG_REJECT (not MSG_CONFIRM)
        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(homeMailbox.dispatchedCount() - 1);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x03); // MSG_REJECT

        // Alice should still have her original name
        assertEq(uar.getUsername(alice), "alice");
    }

    /*══════════════════ Home-Chain Org Names ══════════════════*/

    function testHomeChainOrgNameReservation() public {
        bytes32 orgId = keccak256("ORG1");
        orgRegistry.registerOrg(orgId, address(this), bytes("MyOrg"), bytes32(0));

        // Name should be reserved on hub
        bytes memory nameBytes = bytes("MyOrg");
        // Normalize to lowercase for hash
        for (uint256 i; i < nameBytes.length; ++i) {
            uint8 c = uint8(nameBytes[i]);
            if (c >= 65 && c <= 90) nameBytes[i] = bytes1(c + 32);
        }
        assertTrue(hub.reservedOrgNames(keccak256(nameBytes)));
    }

    function testHomeChainOrgNameDuplicate() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        orgRegistry.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));

        vm.expectRevert();
        orgRegistry.registerOrg(orgB, address(this), bytes("Alpha"), bytes32(0));
    }

    function testHomeChainOrgNameCaseInsensitive() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        orgRegistry.registerOrg(orgA, address(this), bytes("MyOrg"), bytes32(0));

        vm.expectRevert();
        orgRegistry.registerOrg(orgB, address(this), bytes("myorg"), bytes32(0));
    }

    function testHomeChainOrgNameChange() public {
        bytes32 orgId = keccak256("ORG1");
        orgRegistry.registerOrg(orgId, address(this), bytes("Alpha"), bytes32(0));

        // Rename Alpha → Gamma
        orgRegistry.updateOrgMeta(orgId, bytes("Gamma"), bytes32(0));

        // Old name should be released (org names release on rename, unlike usernames)
        bytes memory oldNameBytes = bytes("alpha");
        assertFalse(hub.reservedOrgNames(keccak256(oldNameBytes)));

        // New name should be reserved
        bytes memory newNameBytes = bytes("gamma");
        assertTrue(hub.reservedOrgNames(keccak256(newNameBytes)));
    }

    function testHomeChainOrgNameChangeToTaken() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        orgRegistry.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));
        orgRegistry.registerOrg(orgB, address(this), bytes("Beta"), bytes32(0));

        vm.expectRevert();
        orgRegistry.updateOrgMeta(orgA, bytes("Beta"), bytes32(0));
    }

    /*══════════════════ Cross-Chain Org Names (Hub Side) ══════════════════*/

    function testCrossChainOrgNameClaimSuccess() public {
        bytes memory claim = abi.encode(uint8(0x06), "CrossOrg");
        _hubHandle(SAT_DOMAIN_A, address(relayA), claim);

        // Name reserved on hub
        bytes memory nameBytes = bytes("crossorg");
        assertTrue(hub.reservedOrgNames(keccak256(nameBytes)));

        // Confirm dispatched
        assertEq(homeMailbox.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(resp.destinationDomain, SAT_DOMAIN_A);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x07); // MSG_CONFIRM_ORG_NAME
    }

    function testCrossChainOrgNameClaimRejected() public {
        // First claim succeeds
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "CrossOrg"));

        // Second claim for same name rejected
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x06), "CrossOrg"));

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(1);
        assertEq(resp.destinationDomain, SAT_DOMAIN_B);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x08); // MSG_REJECT_ORG_NAME
    }

    function testCrossChainOrgNameRaceCondition() public {
        // Two satellites claim same name — first-come-first-served
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "RaceName"));
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x06), "RaceName"));

        // Confirm to A
        StoringMailbox.DispatchedMessage memory resp0 = homeMailbox.getDispatched(0);
        assertEq(resp0.destinationDomain, SAT_DOMAIN_A);
        assertEq(abi.decode(resp0.messageBody, (uint8)), 0x07);

        // Reject to B
        StoringMailbox.DispatchedMessage memory resp1 = homeMailbox.getDispatched(1);
        assertEq(resp1.destinationDomain, SAT_DOMAIN_B);
        assertEq(abi.decode(resp1.messageBody, (uint8)), 0x08);
    }

    /*══════════════════ Cross-Chain vs Home-Chain Org Names ══════════════════*/

    function testHomeChainBlocksCrossChainOrgName() public {
        // Register org on home chain — reserves name
        orgRegistry.registerOrg(keccak256("ORG1"), address(this), bytes("Alpha"), bytes32(0));

        // Cross-chain claim for same name — should be rejected
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "Alpha"));

        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x08); // MSG_REJECT_ORG_NAME
    }

    function testCrossChainBlocksHomeChainOrgName() public {
        // Cross-chain reserves name first
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "Alpha"));

        // Home-chain org creation with same name — should revert
        vm.expectRevert();
        orgRegistry.registerOrg(keccak256("ORG1"), address(this), bytes("Alpha"), bytes32(0));
    }

    /*══════════════════ Org Name Admin + Namespace ══════════════════*/

    function testAdminBurnOrgName() public {
        // Admin burns an org name
        hub.adminBurnOrgName(keccak256(bytes("burned")));
        assertTrue(hub.reservedOrgNames(keccak256(bytes("burned"))));

        // Cross-chain claim for burned name — rejected
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "burned"));
        StoringMailbox.DispatchedMessage memory resp = homeMailbox.getDispatched(0);
        assertEq(abi.decode(resp.messageBody, (uint8)), 0x08); // MSG_REJECT_ORG_NAME

        // Home-chain claim for burned name — reverts
        vm.expectRevert();
        orgRegistry.registerOrg(keccak256("ORG1"), address(this), bytes("burned"), bytes32(0));
    }

    function testOrgNameAndUsernameIndependent() public {
        // Same string can be both a username and an org name (separate namespaces)
        vm.prank(alice);
        uar.registerAccount("alpha");

        orgRegistry.registerOrg(keccak256("ORG1"), address(this), bytes("alpha"), bytes32(0));

        // Both succeed — independent namespaces
        assertEq(uar.getUsername(alice), "alpha");
        bytes memory nameBytes = bytes("alpha");
        assertTrue(hub.reservedOrgNames(keccak256(nameBytes)));
        assertTrue(hub.reserved(keccak256(nameBytes)));
    }

    /*══════════════════ Org Name Full Round-Trip ══════════════════*/

    function testFullRoundTripOrgNameConfirm() public {
        // Claim org name via satellite A
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "MyOrg"));

        // Deliver confirm to relay
        _deliverConfirmToRelay(relayA, satMailboxA);

        // Relay cache updated
        assertTrue(relayA.isOrgNameConfirmed("MyOrg"));
    }

    function testFullRoundTripOrgNameReject() public {
        // First claim succeeds
        _hubHandle(SAT_DOMAIN_A, address(relayA), abi.encode(uint8(0x06), "MyOrg"));

        // Second claim from B — rejected
        _hubHandle(SAT_DOMAIN_B, address(relayB), abi.encode(uint8(0x06), "MyOrg"));

        // Deliver reject to relay B
        StoringMailbox.DispatchedMessage memory rejectMsg = homeMailbox.getDispatched(1);
        vm.prank(address(satMailboxB));
        relayB.handle(HOME_DOMAIN, bytes32(uint256(uint160(address(hub)))), rejectMsg.messageBody);

        // Relay B cache NOT updated
        assertFalse(relayB.isOrgNameConfirmed("MyOrg"));
    }

    /*══════════════════ Org Name Relay Edge Cases ══════════════════*/

    function testRelayOrgNameClaimEmpty() public {
        vm.expectRevert(RegistryRelay.OrgNameEmpty.selector);
        relayA.claimOrgName("");
    }

    function testRelayOrgNameClaimDispatch() public {
        relayA.claimOrgName("TestOrg");

        assertEq(satMailboxA.dispatchedCount(), 1);
        StoringMailbox.DispatchedMessage memory msg_ = satMailboxA.getDispatched(0);
        (uint8 msgType, string memory name) = abi.decode(msg_.messageBody, (uint8, string));
        assertEq(msgType, 0x06); // MSG_CLAIM_ORG_NAME
        assertEq(name, "TestOrg");
    }

    function testRelayOrgNameClaimRequiresOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        relayA.claimOrgName("Squatted");
    }

    function testHubOrgRegistryAuthorization() public {
        // Unauthorized address cannot call claimOrgNameLocal
        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.NotOrgRegistry.selector);
        hub.claimOrgNameLocal(keccak256(bytes("test")));

        // Unauthorized address cannot call changeOrgNameLocal
        vm.prank(alice);
        vm.expectRevert(NameRegistryHub.NotOrgRegistry.selector);
        hub.changeOrgNameLocal(keccak256(bytes("old")), keccak256(bytes("new")));
    }

    /*══════════════════ Upgradeability: Double-Init & Zero-Owner ══════════════════*/

    function testHubDoubleInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        hub.initialize(address(this), address(uar), address(homeMailbox));
    }

    function testRelayDoubleInitializeReverts() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        relayA.initialize(address(this), address(satMailboxA), HOME_DOMAIN, address(hub));
    }

    function testHubInitializeRevertsZeroOwner() public {
        NameRegistryHub hubImpl2 = new NameRegistryHub();
        UpgradeableBeacon hubBeacon2 = new UpgradeableBeacon(address(hubImpl2), address(this));
        bytes memory badInit =
            abi.encodeCall(NameRegistryHub.initialize, (address(0), address(uar), address(homeMailbox)));
        vm.expectRevert(NameRegistryHub.ZeroAddress.selector);
        new BeaconProxy(address(hubBeacon2), badInit);
    }

    function testHubInitializeRevertsZeroAccountRegistry() public {
        NameRegistryHub hubImpl2 = new NameRegistryHub();
        UpgradeableBeacon hubBeacon2 = new UpgradeableBeacon(address(hubImpl2), address(this));
        bytes memory badInit =
            abi.encodeCall(NameRegistryHub.initialize, (address(this), address(0), address(homeMailbox)));
        vm.expectRevert(NameRegistryHub.ZeroAddress.selector);
        new BeaconProxy(address(hubBeacon2), badInit);
    }

    function testHubInitializeRevertsZeroMailbox() public {
        NameRegistryHub hubImpl2 = new NameRegistryHub();
        UpgradeableBeacon hubBeacon2 = new UpgradeableBeacon(address(hubImpl2), address(this));
        bytes memory badInit = abi.encodeCall(NameRegistryHub.initialize, (address(this), address(uar), address(0)));
        vm.expectRevert(NameRegistryHub.ZeroAddress.selector);
        new BeaconProxy(address(hubBeacon2), badInit);
    }

    function testRelayInitializeRevertsZeroOwner() public {
        RegistryRelay relayImpl2 = new RegistryRelay();
        UpgradeableBeacon relayBeacon2 = new UpgradeableBeacon(address(relayImpl2), address(this));
        bytes memory badInit =
            abi.encodeCall(RegistryRelay.initialize, (address(0), address(satMailboxA), HOME_DOMAIN, address(hub)));
        vm.expectRevert(RegistryRelay.ZeroAddress.selector);
        new BeaconProxy(address(relayBeacon2), badInit);
    }

    function testRelayInitializeRevertsZeroMailbox() public {
        RegistryRelay relayImpl2 = new RegistryRelay();
        UpgradeableBeacon relayBeacon2 = new UpgradeableBeacon(address(relayImpl2), address(this));
        bytes memory badInit =
            abi.encodeCall(RegistryRelay.initialize, (address(this), address(0), HOME_DOMAIN, address(hub)));
        vm.expectRevert(RegistryRelay.ZeroAddress.selector);
        new BeaconProxy(address(relayBeacon2), badInit);
    }

    function testRelayInitializeRevertsZeroHubAddress() public {
        RegistryRelay relayImpl2 = new RegistryRelay();
        UpgradeableBeacon relayBeacon2 = new UpgradeableBeacon(address(relayImpl2), address(this));
        bytes memory badInit =
            abi.encodeCall(RegistryRelay.initialize, (address(this), address(satMailboxA), HOME_DOMAIN, address(0)));
        vm.expectRevert(RegistryRelay.ZeroAddress.selector);
        new BeaconProxy(address(relayBeacon2), badInit);
    }
}
