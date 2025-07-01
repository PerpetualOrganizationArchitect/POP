// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/ParticipationVoting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

contract MockToken is IERC20 {
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function allowance(address, address) external pure returns (uint256) {
        return 0;
    }

    function approve(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }
}

contract MockExecutor is IExecutor {
    Call[] public last;

    function execute(uint256, Call[] calldata batch) external {
        delete last;
        for (uint256 i; i < batch.length; ++i) {
            last.push(batch[i]);
        }
    }
}

contract PVotingTest is Test {
    ParticipationVoting pv;
    MockHats hats;
    MockToken t;
    MockExecutor exec;
    address creator = address(0x1);
    address voter = address(0x2);

    uint256 constant HAT_ID = 1;
    uint256 constant CREATOR_HAT_ID = 2;

    function setUp() public {
        hats = new MockHats();
        t = new MockToken();
        exec = new MockExecutor();
        
        // Mint voting hat to both creator and voter
        hats.mintHat(HAT_ID, creator);
        hats.mintHat(HAT_ID, voter);
        
        // Mint creator hat only to creator
        hats.mintHat(CREATOR_HAT_ID, creator);
        
        // Give voter some tokens
        t.mint(voter, 10 ether);

        ParticipationVoting impl = new ParticipationVoting();
        uint256[] memory initialHats = new uint256[](1);
        initialHats[0] = HAT_ID;
        uint256[] memory initialCreatorHats = new uint256[](1);
        initialCreatorHats[0] = CREATOR_HAT_ID;
        bytes memory data = abi.encodeCall(
            ParticipationVoting.initialize,
            (address(exec), address(hats), address(t), initialHats, initialCreatorHats, new address[](0), 50, false, 1 ether)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        pv = ParticipationVoting(address(proxy));
    }

    function _createSimple(uint8 opts) internal returns (uint256) {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](opts);
        for (uint256 i; i < opts; ++i) {
            b[i] = new IExecutor.Call[](0);
        }
        vm.prank(creator);
        pv.createProposal("meta", 10, opts, b);
        return pv.proposalsCount() - 1;
    }

    function testInitializeZeroAddress() public {
        ParticipationVoting impl = new ParticipationVoting();
        uint256[] memory h = new uint256[](1);
        h[0] = HAT_ID;
        uint256[] memory ch = new uint256[](1);
        ch[0] = CREATOR_HAT_ID;
        bytes memory data = abi.encodeCall(
            ParticipationVoting.initialize,
            (address(0), address(hats), address(t), h, ch, new address[](0), 50, false, 1 ether)
        );
        vm.expectRevert(ParticipationVoting.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function testInitializeBadQuorum() public {
        ParticipationVoting impl = new ParticipationVoting();
        bytes memory data = abi.encodeCall(
            ParticipationVoting.initialize,
            (address(exec), address(hats), address(t), new uint256[](0), new uint256[](0), new address[](0), 0, false, 1 ether)
        );
        vm.expectRevert("quorum");
        new ERC1967Proxy(address(impl), data);
    }

    function testPauseAndUnpause() public {
        vm.prank(address(exec));
        pv.pause();
        assertTrue(pv.paused());
        vm.prank(address(exec));
        pv.unpause();
        assertFalse(pv.paused());
    }

    function testPauseUnauthorized() public {
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.pause();
    }

    function testSetExecutor() public {
        address newExec = address(0x9);
        vm.prank(address(exec));
        pv.setExecutor(newExec);
        assertEq(address(pv.executor()), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.setExecutor(address(0x9));
    }

    function testSetExecutorZero() public {
        vm.prank(address(exec));
        vm.expectRevert(ParticipationVoting.ZeroAddress.selector);
        pv.setExecutor(address(0));
    }

    function testSetHatAllowed() public {
        vm.prank(address(exec));
        pv.setHatAllowed(HAT_ID, false);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        // Creator should still be able to create (different permission)
        vm.prank(creator);
        pv.createProposal("m", 10, 1, b);
        assertEq(pv.proposalsCount(), 1);
        
        // But voting should fail
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.vote(0, idx, w);
        
        // Re-enable voting
        vm.prank(address(exec));
        pv.setHatAllowed(HAT_ID, true);
        vm.prank(voter);
        pv.vote(0, idx, w); // Should work now
    }

    function testSetCreatorHatAllowed() public {
        uint256 newHatId = 123;
        address newCreator = address(0xbeef);
        
        // Create and assign new hat
        hats.createHat(newHatId, "New Creator Hat", 1, address(0), address(0), true, "");
        hats.mintHat(newHatId, newCreator);
        
        // Enable new hat as creator hat
        vm.prank(address(exec));
        pv.setCreatorHatAllowed(newHatId, true);

        // New creator should be able to create proposal
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(newCreator);
        pv.createProposal("m", 10, 1, b);
        assertEq(pv.proposalsCount(), 1);

        // Disable new hat
        vm.prank(address(exec));
        pv.setCreatorHatAllowed(newHatId, false);
        
        // Should now fail
        vm.prank(newCreator);
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.createProposal("m", 10, 1, b);
    }

    function testVoterCannotCreateProposal() public {
        // Voter has voting hat but not creator hat
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.createProposal("m", 10, 1, b);
    }

    function testSetTargetAllowed() public {
        address tgt = address(0xdead);
        vm.prank(address(exec));
        pv.setTargetAllowed(tgt, true);
        assertTrue(pv.allowedTarget(tgt));
    }

    function testSetQuorum() public {
        vm.prank(address(exec));
        pv.setQuorumPercentage(80);
        assertEq(pv.quorumPercentage(), 80);
    }

    function testSetQuorumBad() public {
        vm.prank(address(exec));
        vm.expectRevert("quorum");
        pv.setQuorumPercentage(0);
    }

    function testSetQuorumUnauthorized() public {
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.setQuorumPercentage(80);
    }

    function testToggleQuadratic() public {
        assertFalse(pv.quadraticVoting());
        vm.prank(address(exec));
        pv.toggleQuadratic();
        assertTrue(pv.quadraticVoting());
    }

    function testSetMinBalance() public {
        vm.prank(address(exec));
        pv.setMinBalance(5 ether);
        assertEq(pv.MIN_BAL(), 5 ether);
    }

    function testCreateProposalBasic() public {
        vm.prank(address(exec));
        pv.setTargetAllowed(address(0xdead), true);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(0xdead), value: 0, data: ""});
        vm.prank(creator);
        pv.createProposal("hello", 10, 1, b);
        assertEq(pv.proposalsCount(), 1);
    }

    function testCreateProposalMetadataEmpty() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(creator);
        vm.expectRevert(ParticipationVoting.InvalidMetadata.selector);
        pv.createProposal("", 10, 1, b);
    }

    function testCreateProposalDurationOutOfRange() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(creator);
        vm.expectRevert(ParticipationVoting.DurationOutOfRange.selector);
        pv.createProposal("m", 5, 1, b);
    }

    function testCreateProposalTooManyOptions() public {
        uint8 n = pv.MAX_OPTIONS() + 1;
        IExecutor.Call[][] memory b = new IExecutor.Call[][](n);
        for (uint256 i; i < n; ++i) {
            b[i] = new IExecutor.Call[](0);
        }
        vm.prank(creator);
        vm.expectRevert(ParticipationVoting.TooManyOptions.selector);
        pv.createProposal("m", 10, n, b);
    }

    function testCreateProposalBadBatch() public {
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(0xdead), value: 0, data: ""});
        vm.prank(creator);
        vm.expectRevert(ParticipationVoting.TargetNotAllowed.selector);
        pv.createProposal("m", 10, 1, b);
    }

    function testVoteBasic() public {
        uint256 id = _createSimple(2);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        pv.vote(id, idx, w);
    }

    function testVoteExpired() public {
        uint256 id = _createSimple(1);
        vm.warp(block.timestamp + 11 minutes);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.VotingExpired.selector);
        pv.vote(id, idx, w);
    }

    function testVoteUnauthorized() public {
        hats.setHatWearerStatus(HAT_ID, voter, false, false);
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.Unauthorized.selector);
        pv.vote(id, idx, w);
    }

    function testVoteMinBalance() public {
        address poorVoter = address(0x5);
        hats.mintHat(HAT_ID, poorVoter);
        t.mint(poorVoter, 0.5 ether); // Below minimum balance
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(poorVoter);
        vm.expectRevert(ParticipationVoting.MinBalance.selector);
        pv.vote(id, idx, w);
    }

    function testVoteAlready() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        pv.vote(id, idx, w);
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.AlreadyVoted.selector);
        pv.vote(id, idx, w);
    }

    function testVoteInvalidIndex() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 2;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.InvalidIndex.selector);
        pv.vote(id, idx, w);
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
        vm.expectRevert(ParticipationVoting.DuplicateIndex.selector);
        pv.vote(id, idx, w);
    }

    function testVoteBadWeight() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 150;
        vm.prank(voter);
        vm.expectRevert(ParticipationVoting.InvalidWeight.selector);
        pv.vote(id, idx, w);
    }

    function testVoteSumNot100() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 40;
        vm.prank(voter);
        vm.expectRevert(abi.encodeWithSelector(ParticipationVoting.WeightSumNot100.selector, 40));
        pv.vote(id, idx, w);
    }

    function testAnnounceWinner() public {
        vm.prank(address(exec));
        pv.setTargetAllowed(address(this), true);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](2);
        b[0] = new IExecutor.Call[](1);
        b[0][0] = IExecutor.Call({target: address(this), value: 0, data: ""});
        b[1] = new IExecutor.Call[](0);
        vm.prank(creator);
        pv.createProposal("m", 10, 2, b);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        pv.vote(0, idx, w);
        vm.warp(block.timestamp + 11 minutes);
        vm.prank(address(exec));
        pv.announceWinner(0);
        (address tgt,,) = exec.last(0);
        assertEq(tgt, address(this));
    }

    function testAnnounceWinnerOpen() public {
        _createSimple(1);
        vm.expectRevert(ParticipationVoting.VotingOpen.selector);
        pv.announceWinner(0);
    }

    function testCleanup() public {
        uint256 id = _createSimple(1);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        pv.vote(id, idx, w);
        vm.warp(block.timestamp + 11 minutes);
        address[] memory vs = new address[](1);
        vs[0] = voter;
        pv.cleanupProposal(id, vs);
    }
}
