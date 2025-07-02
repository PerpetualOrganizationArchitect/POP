// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DirectDemocracyVoting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

contract MockExecutor is IExecutor {
    Call[] public last;

    function execute(uint256, Call[] calldata batch) external {
        delete last;
        for (uint256 i; i < batch.length; ++i) {
            last.push(batch[i]);
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
        return dd.proposalsCount() - 1;
    }

    function _createHatPoll(uint8 opts, uint256[] memory hatIds) internal returns (uint256) {
        vm.prank(creator);
        dd.createHatPoll("meta", 10, opts, hatIds);
        return dd.proposalsCount() - 1;
    }

    function testInitializeZeroAddress() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        uint256[] memory h = new uint256[](1);
        h[0] = HAT_ID;
        uint256[] memory ch = new uint256[](1);
        ch[0] = CREATOR_HAT_ID;
        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize,
            (address(0), address(exec), h, ch, new address[](0), 50)
        );
        vm.expectRevert(DirectDemocracyVoting.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function testInitializeBadQuorum() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize,
            (address(hats), address(exec), new uint256[](0), new uint256[](0), new address[](0), 0)
        );
        vm.expectRevert("quorum");
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
        dd.setExecutor(newExec);
        assertEq(address(dd.executor()), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.setExecutor(address(0x9));
    }

    function testSetExecutorZero() public {
        vm.prank(address(exec));
        vm.expectRevert(DirectDemocracyVoting.ZeroAddress.selector);
        dd.setExecutor(address(0));
    }

    function testSetHatAllowed() public {
        vm.prank(address(exec));
        dd.setHatAllowed(HAT_ID, false);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        // Creator should still be able to create (different permission)
        vm.prank(creator);
        dd.createProposal("m", 10, 1, b);
        assertEq(dd.proposalsCount(), 1);
        
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
        dd.setHatAllowed(HAT_ID, true);
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
        dd.setCreatorHatAllowed(newHatId, true);

        // New creator should be able to create proposal
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(newCreator);
        dd.createProposal("m", 10, 1, b);
        assertEq(dd.proposalsCount(), 1);

        // Disable new hat
        vm.prank(address(exec));
        dd.setCreatorHatAllowed(newHatId, false);
        
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
        dd.setTargetAllowed(tgt, true);
        assertTrue(dd.allowedTarget(tgt));
    }

    function testSetQuorum() public {
        vm.prank(address(exec));
        dd.setQuorumPercentage(80);
        assertEq(dd.quorumPercentage(), 80);
    }

    function testSetQuorumBad() public {
        vm.prank(address(exec));
        vm.expectRevert("quorum");
        dd.setQuorumPercentage(0);
    }

    function testSetQuorumUnauthorized() public {
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.setQuorumPercentage(80);
    }

    function testCreateProposalBasic() public {
        vm.prank(address(exec));
        dd.setTargetAllowed(address(0xdead), true);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(0xdead), value: 0, data: ""});
        vm.prank(creator);
        dd.createProposal("hello", 10, 1, b);
        assertEq(dd.proposalsCount(), 1);
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
        vm.expectRevert(DirectDemocracyVoting.InvalidIndex.selector);
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
        hatIds[0] = POLL_HAT_ID;  // Use the new hat ID for the poll
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
        emit DirectDemocracyVoting.NewHatProposal(0, "meta", 1, uint64(block.timestamp + 10 minutes), uint64(block.timestamp), hatIds);
        
        uint256 id = _createHatPoll(1, hatIds);
        assertTrue(dd.pollRestricted(id));
        assertTrue(dd.pollHatAllowed(id, HAT_ID));
    }

    function testAnnounceWinner() public {
        vm.prank(address(exec));
        dd.setTargetAllowed(address(this), true);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](2);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(this), value: 0, data: ""});
        b[1] = new IExecutor.Call[](0);
        vm.prank(creator);
        dd.createProposal("m", 10, 2, b);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        dd.vote(0, idx, w);
        vm.warp(block.timestamp + 11 minutes);
        vm.prank(address(exec));
        dd.announceWinner(0);
        (address tgt,,) = exec.last(0);
        assertEq(tgt, address(this));
    }

    function testAnnounceWinnerOpen() public {
        _createSimple(1);
        vm.expectRevert(DirectDemocracyVoting.VotingOpen.selector);
        dd.announceWinner(0);
    }

    function testCleanup() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        dd.vote(id, idx, w);
        vm.warp(block.timestamp + 11 minutes);
        address[] memory vs = new address[](1);
        vs[0] = voter;
        dd.cleanupProposal(id, vs);
    }
}
