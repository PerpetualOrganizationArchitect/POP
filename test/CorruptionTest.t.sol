// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

/*───────── OpenZeppelin ─────────*/
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/*───────── local contracts ──────*/
import {TaskManager} from "src/TaskManager.sol";
import {TaskManagerV2} from "src/TaskManagerV2.sol";

/*───────── Mocks ───────────────*/
contract MembershipMock {
    mapping(address => bytes32) public roles;

    function setRole(address user, bytes32 role) external {
        roles[user] = role;
    }

    function roleOf(address user) external view returns (bytes32) {
        return roles[user];
    }
}

contract ParticipationTokenMock is ERC20 {
    constructor() ERC20("Participation", "PTKN") {}

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/*───────── Test Suite ───────────*/
contract TaskManagerBeaconTest is Test {
    address owner = address(0xBEEF);
    address alice = address(0xA11CE);

    MembershipMock membership;
    ParticipationTokenMock token;
    UpgradeableBeacon beacon;
    TaskManager proxy; // BeaconProxy viewed via interface

    bytes32 constant CREATOR_ROLE = keccak256("CREATOR");

    function setUp() public {
        vm.startPrank(owner);
        // deploy mocks
        membership = new MembershipMock();
        token = new ParticipationTokenMock();
        membership.setRole(alice, CREATOR_ROLE);

        // implementation v1
        TaskManager implV1 = new TaskManager();
        // beacon holds upgrade authority (owner)
        beacon = new UpgradeableBeacon(address(implV1), owner);

        // encode init data
        bytes32[] memory creatorRoles = new bytes32[](1);
        creatorRoles[0] = CREATOR_ROLE;
        bytes memory data =
            abi.encodeCall(TaskManager.initialize, (address(token), address(membership), creatorRoles, owner));
        // deploy BeaconProxy
        BeaconProxy bp = new BeaconProxy(address(beacon), data);
        proxy = TaskManager(address(bp));
        vm.stopPrank();
    }

    function _seedData() internal returns (bytes32 pid, uint256 tid) {
        // Set up role permissions
        bytes32[] memory createRoles = new bytes32[](1);
        createRoles[0] = CREATOR_ROLE;
        bytes32[] memory claimRoles = new bytes32[](1);
        claimRoles[0] = CREATOR_ROLE;
        bytes32[] memory reviewRoles = new bytes32[](1);
        reviewRoles[0] = CREATOR_ROLE;
        bytes32[] memory assignRoles = new bytes32[](1);
        assignRoles[0] = CREATOR_ROLE;

        vm.prank(owner);
        pid = proxy.createProject(
            bytes("meta"), 1000 ether, new address[](0), createRoles, claimRoles, reviewRoles, assignRoles
        );
        vm.prank(owner);
        proxy.createTask(100 ether, bytes("task-meta"), pid);
        tid = 0;
    }

    function test_BeaconUpgradeKeepsStorageIntact() public {
        (bytes32 pid, uint256 tid) = _seedData();

        // ─── read with the v1 interface ───
        (uint256 payoutB, TaskManager.Status statusB, address claimerB, bytes32 projB) = proxy.getTask(tid);
        (uint256 capB, uint256 spentB,) = proxy.getProjectInfo(pid);

        // ─── upgrade beacon to V2 ───
        vm.startPrank(owner);
        TaskManagerV2 implV2 = new TaskManagerV2();
        beacon.upgradeTo(address(implV2));
        vm.stopPrank();

        // re-cast proxy to the new ABI
        TaskManagerV2 proxyV2 = TaskManagerV2(address(proxy));

        // ─── read again with the v2 interface (now 5 returns) ───
        (uint256 payoutA, TaskManagerV2.Status statusA, address claimerA, bytes32 projA, uint64 priorityA) =
            proxyV2.getTask(tid);

        (uint256 capA, uint256 spentA,) = proxyV2.getProjectInfo(pid);

        // unchanged fields
        assertEq(payoutA, payoutB, "payout corrupt");
        assertEq(uint8(statusA), uint8(statusB), "status corrupt");
        assertEq(claimerA, claimerB, "claimer corrupt");
        assertEq(projA, projB, "projectId corrupt");
        assertEq(capA, capB, "cap corrupt");
        assertEq(spentA, spentB, "spent corrupt");

        // new field defaults to zero
        assertEq(priorityA, 0, "priority should be 0 for existing tasks");

        // prove new storage (foo) still good
        vm.prank(owner);
        proxyV2.setFoo(77);
        uint256 foo = proxyV2.getFoo();
        assertEq(foo, 77, "new var bad slot");
    }
}
