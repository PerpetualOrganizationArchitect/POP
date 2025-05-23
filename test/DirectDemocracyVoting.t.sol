// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DirectDemocracyVoting.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockMembership is IMembership {
    mapping(address => bytes32) public role;
    mapping(address => bool) public voters;

    function roleOf(address u) external view returns (bytes32) {
        return role[u];
    }

    function canVote(address u) external view returns (bool) {
        return voters[u];
    }

    function setRole(address u, bytes32 r, bool canV) external {
        role[u] = r;
        voters[u] = canV;
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

contract DDVotingTest is Test {
    DirectDemocracyVoting dd;
    MockMembership m;
    MockExecutor exec;
    address creator = address(0x1);
    address voter = address(0x2);

    bytes32 constant ROLE = keccak256("ROLE");

    function setUp() public {
        m = new MockMembership();
        exec = new MockExecutor();
        m.setRole(creator, ROLE, true);
        m.setRole(voter, ROLE, true);

        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE;
        bytes memory data =
            abi.encodeCall(DirectDemocracyVoting.initialize, (address(m), address(exec), roles, new address[](0), 50));
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

    function _createRolePoll(uint8 opts, bytes32[] memory roles) internal returns (uint256) {
        vm.prank(creator);
        dd.createRolePoll("meta", 10, opts, roles);
        return dd.proposalsCount() - 1;
    }

    function testInitializeZeroAddress() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        bytes32[] memory r = new bytes32[](1);
        r[0] = ROLE;
        bytes memory data =
            abi.encodeCall(DirectDemocracyVoting.initialize, (address(0), address(exec), r, new address[](0), 50));
        vm.expectRevert(DirectDemocracyVoting.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), data);
    }

    function testInitializeBadQuorum() public {
        DirectDemocracyVoting impl = new DirectDemocracyVoting();
        bytes memory data = abi.encodeCall(
            DirectDemocracyVoting.initialize, (address(m), address(exec), new bytes32[](0), new address[](0), 0)
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

    function testSetRoleAllowed() public {
        vm.prank(address(exec));
        dd.setRoleAllowed(ROLE, false);
        IExecutor.Call[][] memory b = new IExecutor.Call[][](1);
        b[0] = new IExecutor.Call[](0);
        vm.prank(creator);
        vm.expectRevert(DirectDemocracyVoting.Unauthorized.selector);
        dd.createProposal("m", 10, 1, b);
        vm.prank(address(exec));
        dd.setRoleAllowed(ROLE, true);
        vm.prank(creator);
        dd.createProposal("m", 10, 1, b);
        assertEq(dd.proposalsCount(), 1);
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
        m.setRole(voter, ROLE, false);
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

    function testRolePollRestrictions() public {
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE;
        uint256 id = _createRolePoll(2, roles);
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;

        address other = address(0x3);
        m.setRole(other, keccak256("OTHER"), true);
        vm.prank(other);
        vm.expectRevert(DirectDemocracyVoting.RoleNotAllowed.selector);
        dd.vote(id, idx, w);

        vm.prank(voter);
        dd.vote(id, idx, w);
    }

    function testPollRestrictedViews() public {
        bytes32[] memory roles = new bytes32[](1);
        roles[0] = ROLE;
        uint256 id = _createRolePoll(1, roles);
        assertTrue(dd.pollRestricted(id));
        assertTrue(dd.pollRoleAllowed(id, ROLE));
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
