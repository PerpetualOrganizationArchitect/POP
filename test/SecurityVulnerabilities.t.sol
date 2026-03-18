// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {OwnableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {DirectDemocracyVoting} from "../src/DirectDemocracyVoting.sol";
import {VotingErrors} from "../src/libs/VotingErrors.sol";
import {ValidationLib} from "../src/libs/ValidationLib.sol";
import {IExecutor} from "../src/Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

/* ═══════════════════════════════════════════════════════════════
   MOCK CONTRACTS FOR SECURITY TESTING
   ═══════════════════════════════════════════════════════════════ */

/// @dev Malicious contract that exploits mint access on ParticipationToken
contract MaliciousMinter {
    ParticipationToken public token;

    constructor(ParticipationToken _token) {
        token = _token;
    }

    function exploit(address recipient, uint256 amount) external {
        token.mint(recipient, amount);
    }
}

/// @dev Simple mock executor that forwards calls
contract SecurityMockExecutor is IExecutor {
    Call[] public lastBatch;

    function execute(uint256, Call[] calldata batch) external {
        delete lastBatch;
        for (uint256 i; i < batch.length; ++i) {
            lastBatch.push(batch[i]);
            (bool success,) = batch[i].target.call{value: batch[i].value}(batch[i].data);
            require(success, "MockExecutor: call failed");
        }
    }
}

/* ═══════════════════════════════════════════════════════════════
   VULNERABILITY 1: ParticipationToken unauthorized setTaskManager/setEducationHub
   ═══════════════════════════════════════════════════════════════
   SEVERITY: Critical
   DESCRIPTION: The first call to setTaskManager() and setEducationHub() previously
   had NO authorization check. Anyone could call it when the value was address(0).
   For orgs deployed without an EducationHub, an attacker could set a malicious
   contract as educationHub and mint unlimited participation tokens.

   FIX: Both functions now require executor authorization for all calls.
   ═══════════════════════════════════════════════════════════════ */
contract ParticipationTokenAuthTest is Test {
    ParticipationToken token;
    MockHats hats;
    MockOwnableExecutor exec;
    address attacker = address(0xBAD);

    uint256 constant MEMBER_HAT = 1;
    uint256 constant APPROVER_HAT = 2;

    function setUp() public {
        hats = new MockHats();

        // Deploy a mock executor that is Ownable (simulates deployment flow)
        exec = new MockOwnableExecutor();

        ParticipationToken impl = new ParticipationToken();
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = MEMBER_HAT;
        uint256[] memory approverHats = new uint256[](1);
        approverHats[0] = APPROVER_HAT;

        bytes memory data = abi.encodeCall(
            ParticipationToken.initialize, (address(exec), "OrgToken", "ORG", address(hats), memberHats, approverHats)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        token = ParticipationToken(address(proxy));
    }

    /// @notice Attacker cannot set educationHub (not executor or executor's owner)
    function test_setEducationHub_requiresAuth() public {
        MaliciousMinter malicious = new MaliciousMinter(token);

        vm.prank(attacker);
        vm.expectRevert(ParticipationToken.Unauthorized.selector);
        token.setEducationHub(address(malicious));
    }

    /// @notice Attacker cannot set taskManager (not executor or executor's owner)
    function test_setTaskManager_requiresAuth() public {
        MaliciousMinter malicious = new MaliciousMinter(token);

        vm.prank(attacker);
        vm.expectRevert(ParticipationToken.Unauthorized.selector);
        token.setTaskManager(address(malicious));
    }

    /// @notice Executor's owner (OrgDeployer during deployment) CAN set taskManager
    function test_executorOwner_canSetTaskManager() public {
        // address(this) is the owner of exec (deployed it), simulates OrgDeployer
        token.setTaskManager(address(0x456));
        assertEq(token.taskManager(), address(0x456));
    }

    /// @notice After executor ownership is renounced, only executor can set
    function test_afterOwnershipRenounced_onlyExecutor() public {
        // Renounce ownership (simulates end of deployment)
        exec.renounceOwnership();

        // Now the previous owner (address(this)) is blocked
        vm.expectRevert(ParticipationToken.Unauthorized.selector);
        token.setTaskManager(address(0x456));

        // But the executor itself can still set it
        vm.prank(address(exec));
        token.setTaskManager(address(0x789));
        assertEq(token.taskManager(), address(0x789));
    }

    /// @notice Executor CAN set educationHub
    function test_executor_canSetEducationHub() public {
        vm.prank(address(exec));
        token.setEducationHub(address(0x123));
        assertEq(token.educationHub(), address(0x123));
    }

    /// @notice Executor CAN set taskManager
    function test_executor_canSetTaskManager() public {
        vm.prank(address(exec));
        token.setTaskManager(address(0x456));
        assertEq(token.taskManager(), address(0x456));
    }

    /// @notice Full exploit chain blocked: attacker cannot set educationHub to mint tokens
    function test_fullChain_unlimitedMint_blocked() public {
        // Renounce ownership (deployment complete)
        exec.renounceOwnership();

        // Attacker tries to set educationHub to themselves - blocked
        vm.prank(attacker);
        vm.expectRevert(ParticipationToken.Unauthorized.selector);
        token.setEducationHub(attacker);

        // educationHub remains unset
        assertEq(token.educationHub(), address(0));
    }

    /// @notice Executor can set educationHub to address(0) for optional deployment
    function test_executor_canClearEducationHub() public {
        vm.prank(address(exec));
        token.setEducationHub(address(0x123));

        vm.prank(address(exec));
        token.setEducationHub(address(0));
        assertEq(token.educationHub(), address(0));
    }
}

/// @dev Mock executor with Ownable for testing the owner-check in setTaskManager/setEducationHub
contract MockOwnableExecutor is OwnableUpgradeable {
    constructor() {
        // Initialize with msg.sender as owner (simulates OrgDeployer being owner during deployment)
        __Ownable_init(msg.sender);
    }
}

/* ═══════════════════════════════════════════════════════════════
   VULNERABILITY 3: DirectDemocracyVoting unchecked vote overflow
   ═══════════════════════════════════════════════════════════════
   SEVERITY: Low (practically impossible but defense-in-depth fix)
   DESCRIPTION: In DD voting's vote() function, totalWeight and option votes
   used unchecked arithmetic. While overflow requires astronomically many
   voters, unchecked arithmetic in governance code violates defense-in-depth.

   FIX: Removed unchecked blocks around vote accumulation arithmetic.
   ═══════════════════════════════════════════════════════════════ */
contract DDVotingOverflowTest is Test {
    DirectDemocracyVoting dd;
    MockHats hats;
    SecurityMockExecutor exec;
    address creator = address(0xC);
    address voter = address(0xD);

    uint256 constant HAT_ID = 1;
    uint256 constant CREATOR_HAT = 2;

    function setUp() public {
        hats = new MockHats();
        exec = new SecurityMockExecutor();

        hats.mintHat(HAT_ID, creator);
        hats.mintHat(CREATOR_HAT, creator);
        hats.mintHat(HAT_ID, voter);

        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        uint256[] memory votingHats = new uint256[](1);
        votingHats[0] = HAT_ID;
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT;

        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize,
            (address(hats), address(exec), votingHats, creatorHats, new address[](0), 50)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        dd = DirectDemocracyVoting(address(proxy));
    }

    /// @notice Verify vote accumulation works correctly with checked arithmetic
    function test_voteAccumulation_checked() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](2);
        b[0] = new IExecutor.Call[](0);
        b[1] = new IExecutor.Call[](0);

        vm.prank(creator);
        dd.createProposal(bytes("Overflow Test"), bytes32(0), 10, 2, b, new uint256[](0));

        // Vote from creator
        uint8[] memory idxs = new uint8[](1);
        idxs[0] = 0;
        uint8[] memory weights = new uint8[](1);
        weights[0] = 100;

        vm.prank(creator);
        dd.vote(0, idxs, weights);

        // Vote from voter
        uint8[] memory idxs2 = new uint8[](1);
        idxs2[0] = 1;
        uint8[] memory weights2 = new uint8[](1);
        weights2[0] = 100;

        vm.prank(voter);
        dd.vote(0, idxs2, weights2);

        // Both votes counted correctly
        vm.warp(block.timestamp + 11 minutes);
        (uint256 winner, bool valid) = dd.announceWinner(0);
        // Neither meets threshold since they're tied 50/50
        assertFalse(valid, "Tied vote should not be valid");
    }
}
