// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DirectDemocracyVoting.sol";
import "../src/libs/VotingMath.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

contract MockExecutor is IExecutor {
    Call[] public last;

    function execute(uint256, Call[] calldata batch) external {
        delete last;
        for (uint256 i; i < batch.length; ++i) {
            last.push(batch[i]);
            // Actually execute the call on the target
            (bool success,) = batch[i].target.call{value: batch[i].value}(batch[i].data);
            require(success, "MockExecutor: call failed");
        }
    }
}

contract DDVotingTest is Test {
    DirectDemocracyVoting dd;
    MockHats hats;
    MockExecutor exec;
    address creator = address(0x1);
    address voter = address(0x2);

    uint256 constant HAT_ID = 1;
    uint256 constant CREATOR_HAT_ID = 2;

    function setUp() public {
        hats = new MockHats();
        exec = new MockExecutor();

        // Mint voting hat to both creator and voter
        hats.mintHat(HAT_ID, creator);
        hats.mintHat(HAT_ID, voter);

        // Mint creator hat only to creator
        hats.mintHat(CREATOR_HAT_ID, creator);

        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        uint256[] memory initialHats = new uint256[](1);
        initialHats[0] = HAT_ID;
        uint256[] memory initialCreatorHats = new uint256[](1);
        initialCreatorHats[0] = CREATOR_HAT_ID;
        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize,
            (address(hats), address(exec), initialHats, initialCreatorHats, new address[](0), 50)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        dd = DirectDemocracyVoting(address(proxy));
    }

    function _createSimple(uint8 opts) internal returns (uint256) {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](opts);
        for (uint256 i; i < opts; ++i) {
            b[i] = new IExecutor.Call[](0);
        }
        vm.prank(creator);
        dd.createProposal("meta", 10, opts, b);
        return abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)) - 1;
    }

    function _createHatPoll(uint8 opts, uint256[] memory hatIds) internal returns (uint256) {
        vm.prank(creator);
        dd.createHatPoll("meta", 10, opts, hatIds);
        return abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)) - 1;
    }

    function testInitializeZeroAddress() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        uint256[] memory h = new uint256[](1);
        h[0] = HAT_ID;
        uint256[] memory ch = new uint256[](1);
        ch[0] = CREATOR_HAT_ID;
        bytes memory data =
            abi.encodeCall(DirectDemocracyVoting.initialize, (address(0), address(exec), h, ch, new address[](0), 50));
        vm.expectRevert(DirectDemocracyVoting.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function testInitializeBadQuorum() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize,
            (address(hats), address(exec), new uint256[](0), new uint256[](0), new address[](0), 0)
        );
        vm.expectRevert(VotingMath.InvalidQuorum.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function testPauseAndUnpause() public {
        vm.prank(address(exec));
        dd.pause();
        assertTrue(dd.paused());
        vm.prank(address(exec));
        dd.unpause();
        assertFalse(dd.paused());
    }

    function testPauseUnauthorized() public {
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.pause();
    }

    function testSetExecutor() public {
        address newExec = address(0x9);
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.EXECUTOR, abi.encode(newExec));
        assertEq(address(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.EXECUTOR, ""), (address))), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.setConfig(DirectDemocracyVoting.ConfigKey.EXECUTOR, abi.encode(address(0x9)));
    }

    function testSetExecutorZero() public {
        vm.prank(address(exec));
        vm.expectRevert(DirectDemocracyVoting.ZeroAddress.selector);
        dd.setConfig(DirectDemocracyVoting.ConfigKey.EXECUTOR, abi.encode(address(0)));
    }

    function testSetHatAllowed() public {
        vm.prank(address(exec));
        dd.setConfig(
            DirectDemocracyVoting.ConfigKey.HAT_ALLOWED, abi.encode(DirectDemocracyVoting.HatType.VOTING, HAT_ID, false)
        );
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        // Creator should still be able to create (different permission)
        vm.prank(creator);
        dd.createProposal("m", 10, 1, b);
        assertEq(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)), 1);

        // But voting should fail
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.vote(0, idx, w);

        // Re-enable voting
        vm.prank(address(exec));
        dd.setConfig(
            DirectDemocracyVoting.ConfigKey.HAT_ALLOWED, abi.encode(DirectDemocracyVoting.HatType.VOTING, HAT_ID, true)
        );
        vm.prank(voter);
        dd.vote(0, idx, w); // Should work now
    }

    function testSetCreatorHatAllowed() public {
        uint256 newHatId = 123;
        address newCreator = address(0xbeef);

        // Create and assign new hat
        hats.createHat(newHatId, "New Creator Hat", 1, address(0), address(0), true, "");
        hats.mintHat(newHatId, newCreator);

        // Enable new hat as creator hat
        vm.prank(address(exec));
        dd.setConfig(
            DirectDemocracyVoting.ConfigKey.HAT_ALLOWED,
            abi.encode(DirectDemocracyVoting.HatType.CREATOR, newHatId, true)
        );

        // New creator should be able to create proposal
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(newCreator);
        dd.createProposal("m", 10, 1, b);
        assertEq(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)), 1);

        // Disable new hat
        vm.prank(address(exec));
        dd.setConfig(
            DirectDemocracyVoting.ConfigKey.HAT_ALLOWED,
            abi.encode(DirectDemocracyVoting.HatType.CREATOR, newHatId, false)
        );

        // Should now fail
        vm.prank(newCreator);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.createProposal("m", 10, 1, b);
    }

    function testVoterCannotCreateProposal() public {
        // Voter has voting hat but not creator hat
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.createProposal("m", 10, 1, b);
    }

    function testSetTargetAllowed() public {
        address tgt = address(0xdead);
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.TARGET_ALLOWED, abi.encode(tgt, true));
        assertTrue(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.ALLOWED_TARGET, abi.encode(tgt)), (bool)));
    }

    function testSetQuorum() public {
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.QUORUM, abi.encode(80));
        assertEq(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.QUORUM_PERCENTAGE, ""), (uint8)), 80);
    }

    function testSetQuorumBad() public {
        vm.prank(address(exec));
        vm.expectRevert(VotingMath.InvalidQuorum.selector);
        dd.setConfig(DirectDemocracyVoting.ConfigKey.QUORUM, abi.encode(0));
    }

    function testSetQuorumUnauthorized() public {
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.setConfig(DirectDemocracyVoting.ConfigKey.QUORUM, abi.encode(80));
    }

    function testCreateProposalBasic() public {
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.TARGET_ALLOWED, abi.encode(address(0xdead), true));
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(0xdead), value: 0, data: ""});
        vm.prank(creator);
        dd.createProposal("hello", 10, 1, b);
        assertEq(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)), 1);
    }

    function testCreateProposalMetadataEmpty() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(creator);
        vm.expectRevert(DirectDemocracyVoting.InvalidMetadata.selector);
        dd.createProposal("", 10, 1, b);
    }

    function testCreateProposalDurationOutOfRange() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(creator);
        vm.expectRevert(DirectDemocracyVoting.DurationOutOfRange.selector);
        dd.createProposal("m", 5, 1, b);
    }

    function testCreateProposalTooManyOptions() public {
        uint8 n = dd.MAX_OPTIONS() + 1;
        IExecutor.Call[][] memory b = new IExecutor.Call[][](n);
        for (uint256 i; i < n; ++i) {
            b[i] = new IExecutor.Call[](0);
        }
        vm.prank(creator);
        vm.expectRevert(DirectDemocracyVoting.TooManyOptions.selector);
        dd.createProposal("m", 10, n, b);
    }

    function testCreateProposalBadBatch() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(0xdead), value: 0, data: ""});
        vm.prank(creator);
        vm.expectRevert(DirectDemocracyVoting.TargetNotAllowed.selector);
        dd.createProposal("m", 10, 1, b);
    }

    function testVoteBasic() public {
        uint256 id = _createSimple(2);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        dd.vote(id, idx, w);
    }

    function testVoteExpired() public {
        uint256 id = _createSimple(1);
        vm.warp(block.timestamp + 11 minutes);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.VotingExpired.selector);
        dd.vote(id, idx, w);
    }

    function testVoteUnauthorized() public {
        hats.setHatWearerStatus(HAT_ID, voter, false, false);
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.vote(id, idx, w);
    }

    function testVoteAlready() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        dd.vote(id, idx, w);
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.AlreadyVoted.selector);
        dd.vote(id, idx, w);
    }

    function testVoteInvalidIndex() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 2;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(VotingMath.InvalidIndex.selector);
        dd.vote(id, idx, w);
    }

    function testVoteDuplicate() public {
        uint256 id = _createSimple(2);
        uint8[] memory idx = new uint8[](2);
        idx[0] = 0;
        idx[1] = 0;
        uint8[] memory w = new uint8[](2);
        w[0] = 50;
        w[1] = 50;
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.DuplicateIndex.selector);
        dd.vote(id, idx, w);
    }

    function testVoteBadWeight() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 150;
        vm.prank(voter);
        vm.expectRevert(DirectDemocracyVoting.InvalidWeight.selector);
        dd.vote(id, idx, w);
    }

    function testVoteSumNot100() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 40;
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(DirectDemocracyVoting.WeightSumNot100.selector, 40));
        dd.vote(id, idx, w);
    }

    function testHatPollRestrictions() public {
        // Create a different hat for the poll
        uint256 POLL_HAT_ID = 2;
        hats.createHat(1, "Poll Hat", type(uint32).max, address(0), address(0), true, "");

        uint256[] memory hatIds = new uint256[](1);
        hatIds[0] = POLL_HAT_ID; // Use the new hat ID for the poll
        uint256 id = _createHatPoll(2, hatIds);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;

        // First test: voter with no hat should get Unauthorized
        address noHatVoter = address(0x3);
        vm.prank(noHatVoter);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.vote(id, idx, w);

        // Second test: voter with valid hat but not the specific poll hat should get RoleNotAllowed
        address wrongHatVoter = address(0x4);
        // Give them a valid voting hat (HAT_ID) but not the specific hat for this poll
        hats.mintHat(HAT_ID, wrongHatVoter);
        vm.prank(wrongHatVoter);
        vm.expectRevert(DirectDemocracyVoting.RoleNotAllowed.selector);
        dd.vote(id, idx, w);

        // Third test: voter with correct hat should succeed
        // Give the voter the poll-specific hat
        hats.mintHat(POLL_HAT_ID, voter);
        vm.prank(voter);
        dd.vote(id, idx, w);
    }

    function testPollRestrictedViews() public {
        uint256[] memory hatIds = new uint256[](1);
        hatIds[0] = HAT_ID;

        // Expect the NewHatProposal event to be emitted
        vm.expectEmit(true, true, true, true);
        emit DirectDemocracyVoting.NewHatProposal(
            0, "meta", 1, uint64(block.timestamp + 10 minutes), uint64(block.timestamp), hatIds
        );

        uint256 id = _createHatPoll(1, hatIds);
        assertTrue(abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.POLL_RESTRICTED, abi.encode(id)), (bool)));
        assertTrue(
            abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.POLL_HAT_ALLOWED, abi.encode(id, HAT_ID)), (bool))
        );
    }

    function testAnnounceWinner() public {
        // Create proposal with empty batches (no execution needed for this test)
        IExecutor.Call[][] memory b = new IExecutor.Call[][](2);
        b[0] = new IExecutor.Call[](0); // empty batch
        b[1] = new IExecutor.Call[](0); // empty batch
        vm.prank(creator);
        dd.createProposal("m", 10, 2, b);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        dd.vote(0, idx, w);
        vm.warp(block.timestamp + 11 minutes);
        (uint256 winner, bool valid) = dd.announceWinner(0);
        assertTrue(valid, "Winner should be valid");
        assertEq(winner, 0, "Option 0 should win");
    }

    function testAnnounceWinnerOpen() public {
        _createSimple(1);
        vm.expectRevert(DirectDemocracyVoting.VotingOpen.selector);
        dd.announceWinner(0);
    }

    // function testCleanup() public {
    //     uint256 id = _createSimple(1);
    //     uint8[] memory idx = new uint8[](1);
    //     idx[0] = 0;
    //     uint8[] memory w = new uint8[](1);
    //     w[0] = 100;
    //     vm.prank(voter);
    //     dd.vote(id, idx, w);
    //     vm.warp(block.timestamp + 11 minutes);
    //     address[] memory vs = new address[](1);
    //     vs[0] = voter;
    //     dd.cleanupProposal(id, vs);
    // }

    /*////////////////////////////////////////////////////////////
                            ELECTION TESTS
    ////////////////////////////////////////////////////////////*/

    function testElectionWithHatMinting() public {
        // Define election candidates
        address alice = address(0x100);
        address bob = address(0x200);
        address charlie = address(0x300);
        uint256 executiveHatId = 99;

        // Allow hats contract as execution target
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.TARGET_ALLOWED, abi.encode(address(hats), true));

        // Create election with 3 candidates (3 options)
        // Option 0: Alice wins -> mint executive hat to Alice
        // Option 1: Bob wins -> mint executive hat to Bob
        // Option 2: Charlie wins -> mint executive hat to Charlie
        IExecutor.Call[][] memory batches = new IExecutor.Call[][](3);

        // Alice option (index 0)
        batches[0] = new IExecutor.Call[](1);
        batches[0][0] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", executiveHatId, alice)
        });

        // Bob option (index 1)
        batches[1] = new IExecutor.Call[](1);
        batches[1][0] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", executiveHatId, bob)
        });

        // Charlie option (index 2)
        batches[2] = new IExecutor.Call[](1);
        batches[2][0] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", executiveHatId, charlie)
        });

        // Create the election proposal
        vm.prank(creator);
        dd.createProposal("Election: Choose new executive leader", 60, 3, batches);
        uint256 proposalId =
            abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)) - 1;

        // Verify no candidates have the hat initially
        assertFalse(hats.isWearerOfHat(alice, executiveHatId));
        assertFalse(hats.isWearerOfHat(bob, executiveHatId));
        assertFalse(hats.isWearerOfHat(charlie, executiveHatId));

        // Vote for Bob (option 1)
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1; // Bob
        uint8[] memory weights = new uint8[](1);
        weights[0] = 100;

        vm.prank(voter);
        dd.vote(proposalId, idx, weights);

        // Fast forward past voting period
        vm.warp(block.timestamp + 61 minutes);

        // Announce winner and execute - Bob should get the hat
        (uint256 winner, bool valid) = dd.announceWinner(proposalId);

        assertTrue(valid, "Vote should be valid");
        assertEq(winner, 1, "Bob (option 1) should win");

        // Verify Bob received the executive hat
        assertTrue(hats.isWearerOfHat(bob, executiveHatId), "Bob should have the executive hat");
        assertFalse(hats.isWearerOfHat(alice, executiveHatId), "Alice should not have the hat");
        assertFalse(hats.isWearerOfHat(charlie, executiveHatId), "Charlie should not have the hat");

        // Alternative verification using balanceOf
        assertEq(hats.balanceOf(bob, executiveHatId), 1, "Bob should have balance of 1 for executive hat");
        assertEq(hats.balanceOf(alice, executiveHatId), 0, "Alice should have balance of 0 for executive hat");
        assertEq(hats.balanceOf(charlie, executiveHatId), 0, "Charlie should have balance of 0 for executive hat");
    }

    function testElectionWithMultipleActions() public {
        // Define candidates and additional hat IDs
        address alice = address(0x100);
        address bob = address(0x200);
        uint256 executiveHatId = 99;
        uint256 managerHatId = 88;

        // Allow hats contract as execution target
        vm.prank(address(exec));
        dd.setConfig(DirectDemocracyVoting.ConfigKey.TARGET_ALLOWED, abi.encode(address(hats), true));

        // Create election where winner gets both executive and manager hats
        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);

        // Alice option: gets both hats
        batches[0] = new IExecutor.Call[](2);
        batches[0][0] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", executiveHatId, alice)
        });
        batches[0][1] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", managerHatId, alice)
        });

        // Bob option: gets only executive hat
        batches[1] = new IExecutor.Call[](1);
        batches[1][0] = IExecutor.Call({
            target: address(hats),
            value: 0,
            data: abi.encodeWithSignature("mintHat(uint256,address)", executiveHatId, bob)
        });

        // Create the election proposal
        vm.prank(creator);
        dd.createProposal("Election: Choose executive with different privileges", 60, 2, batches);
        uint256 proposalId =
            abi.decode(dd.getStorage(DirectDemocracyVoting.StorageKey.PROPOSALS_COUNT, ""), (uint256)) - 1;

        // Vote for Alice (option 0) who gets both hats
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0; // Alice
        uint8[] memory weights = new uint8[](1);
        weights[0] = 100;

        vm.prank(voter);
        dd.vote(proposalId, idx, weights);

        // Fast forward and execute
        vm.warp(block.timestamp + 61 minutes);
        (uint256 winner, bool valid) = dd.announceWinner(proposalId);

        assertTrue(valid, "Vote should be valid");
        assertEq(winner, 0, "Alice (option 0) should win");

        // Verify Alice received both hats
        assertTrue(hats.isWearerOfHat(alice, executiveHatId), "Alice should have executive hat");
        assertTrue(hats.isWearerOfHat(alice, managerHatId), "Alice should have manager hat");
        assertFalse(hats.isWearerOfHat(bob, executiveHatId), "Bob should not have executive hat");
        assertFalse(hats.isWearerOfHat(bob, managerHatId), "Bob should not have manager hat");

        // Verify hat balances
        assertEq(hats.balanceOf(alice, executiveHatId), 1, "Alice should have executive hat");
        assertEq(hats.balanceOf(alice, managerHatId), 1, "Alice should have manager hat");
        assertEq(hats.balanceOf(bob, executiveHatId), 0, "Bob should not have executive hat");
        assertEq(hats.balanceOf(bob, managerHatId), 0, "Bob should not have manager hat");
    }
}
