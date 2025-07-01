// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* forge‑std helpers */
import "forge-std/Test.sol";

/* target */
import {HybridVoting} from "../src/HybridVoting.sol";

/* OpenZeppelin */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IExecutor} from "../src/Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

/* ───────────── Local lightweight mocks ───────────── */
contract MockERC20 is IERC20 {
    string public name = "ParticipationToken";
    string public symbol = "PTKN";
    uint8 public decimals = 18;
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;

    function transfer(address to, uint256 amt) public returns (bool) {
        balanceOf[msg.sender] -= amt;
        balanceOf[to] += amt;
        return true;
    }

    function transferFrom(address, address, uint256) public pure returns (bool) {
        return false;
    }

    function approve(address, uint256) public pure returns (bool) {
        return false;
    }

    function allowance(address, address) public pure returns (uint256) {
        return 0;
    }

    /* mint helper for tests */
    function mint(address to, uint256 amt) external {
        balanceOf[to] += amt;
        totalSupply += amt;
    }
}

contract MockExecutor is IExecutor {
    event Executed(uint256 id, Call[] batch);

    Call[] public lastBatch;
    uint256 public lastId;

    function execute(uint256 id, Call[] calldata batch) external {
        lastId = id;
        delete lastBatch;
        for (uint256 i; i < batch.length; ++i) {
            lastBatch.push(batch[i]);
        }
        emit Executed(id, batch);
    }
}

/* ────────────────────────────────   TEST  ──────────────────────────────── */
contract HybridVotingTest is Test {
    /* actors */
    address owner = vm.addr(1);
    address alice = vm.addr(2); // has executive hat (voting + DD power), some tokens
    address bob = vm.addr(3); // has default hat (voting only, no DD power), many tokens
    address carol = vm.addr(4); // has executive hat (voting + DD power), tokens
    address nonExecutor = vm.addr(5); // someone without executor access

    /* contracts */
    MockERC20 token;
    MockHats hats;
    MockExecutor exec;
    HybridVoting hv;

    /* hat constants */
    uint256 constant DEFAULT_HAT_ID = 1;
    uint256 constant EXECUTIVE_HAT_ID = 2;
    uint256 constant CREATOR_HAT_ID = 3;

    /* ────────── set‑up ────────── */
    function setUp() public {
        token = new MockERC20();
        hats = new MockHats();
        exec = new MockExecutor();

        /* give hats */
        hats.mintHat(DEFAULT_HAT_ID, alice);
        hats.mintHat(EXECUTIVE_HAT_ID, alice);
        hats.mintHat(CREATOR_HAT_ID, alice);
        hats.mintHat(DEFAULT_HAT_ID, bob); // Bob gets voting permission but no DD power
        hats.mintHat(DEFAULT_HAT_ID, carol);
        hats.mintHat(EXECUTIVE_HAT_ID, carol);
        hats.mintHat(CREATOR_HAT_ID, carol);

        /* mint tokens (18 dec) - adjust balances to make sure YES wins */
        token.mint(bob, 400e18); // reduce bob's tokens
        token.mint(alice, 400e18); // increase alice's balance
        token.mint(carol, 600e18); // increase carol's balance

        /* prepare allowed hats/targets for init */
        uint256[] memory votingHats = new uint256[](2);
        votingHats[0] = DEFAULT_HAT_ID;
        votingHats[1] = EXECUTIVE_HAT_ID;
        
        uint256[] memory democracyHats = new uint256[](1);
        democracyHats[0] = EXECUTIVE_HAT_ID; // Only EXECUTIVE hat gets DD power
        
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT_ID;
        
        address[] memory targets = new address[](1);
        targets[0] = address(0xCA11); // random allowed call target

        bytes memory initData = abi.encodeCall(
            HybridVoting.initialize,
            (
                address(hats), // hats
                address(token), // participation token
                address(exec), // executor
                votingHats, // allowed voting hats
                democracyHats, // allowed democracy hats (DD power)
                creatorHats, // allowed creator hats
                targets, // allowed target(s)
                uint8(50), // quorum %
                uint8(50), // 50‑50 split DD : PT
                false, // quadratic off
                1 ether // Lower MIN_BAL to ensure all users can participate
            )
        );

        HybridVoting impl = new HybridVoting();

        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);

        hv = HybridVoting(payable(address(proxy)));
        vm.label(address(hv), "HybridVoting");
    }

    /* ───────────────────────── CREATE PROPOSAL ───────────────────────── */

    function _defaultNames() internal pure returns (string[] memory n) {
        n = new string[](2);
        n[0] = "YES";
        n[1] = "NO";
    }

    function testCreateProposalEmptyBatches() public {
        vm.startPrank(alice);

        /* build empty 2‑option batches */
        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](1);
        batches[1] = new IExecutor.Call[](1);

        batches[0][0] = IExecutor.Call({target: address(0xCA11), value: 0, data: ""});
        batches[1][0] = IExecutor.Call({target: address(0xCA11), value: 0, data: ""});

        // Convert string to bytes for metadata
        bytes memory metadata = bytes("ipfs://test");
        hv.createProposal(metadata, 30, 2, batches);

        vm.stopPrank();

        assertEq(hv.proposalsCount(), 1, "should store proposal");
    }

    function testCreateProposalUnauthorized() public {
        // Bob has no creator hat, should fail
        vm.startPrank(bob);

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](0);
        batches[1] = new IExecutor.Call[](0);

        bytes memory metadata = bytes("ipfs://test");
        vm.expectRevert(HybridVoting.Unauthorized.selector);
        hv.createProposal(metadata, 30, 2, batches);

        vm.stopPrank();
    }

    /* ───────────────────────── VOTING paths ───────────────────────── */

    function _create() internal returns (uint256) {
        /* anyone with creator hat */
        vm.startPrank(alice);

        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](1);
        batches[1] = new IExecutor.Call[](1);

        batches[0][0] = IExecutor.Call({
            target: address(0xCA11), // Use the same target that was allowed during initialization
            value: 0,
            data: ""
        });

        batches[1][0] = IExecutor.Call({
            target: address(0xCA11), // Use the same target that was allowed during initialization
            value: 0,
            data: ""
        });

        // Convert string to bytes for metadata
        bytes memory metadata = bytes("ipfs://p");
        hv.createProposal(metadata, 15, 2, batches);
        vm.stopPrank();
        return 0;
    }

    function _voteYES(address voter) internal {
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        hv.vote(0, idx, w);
    }

    function testDDOnlyWeight() public {
        _create();
        /* bob has voting hat but no DD hat => can vote but only contributes PT power */
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(bob);
        hv.vote(0, idx, w); // should succeed because bob has voting hat, but no DD power
        /* bob contributes only PT power (400e18 tokens), no DD power */
    }

    function testVoteUnauthorized() public {
        _create();
        
        // Create a voter with no hats and insufficient tokens
        address poorVoter = vm.addr(10);
        token.mint(poorVoter, 0.5 ether); // Below minimum balance
        
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        
        vm.prank(poorVoter);
        vm.expectRevert(HybridVoting.Unauthorized.selector);
        hv.vote(0, idx, w);
    }

    function testBlendAndExecution() public {
        uint256 id = _create();

        /* enable quadratic voting first, before any votes are cast */
        vm.prank(address(exec));
        hv.toggleQuadratic();

        /* YES votes: Alice and Carol (both have DD power) */
        _voteYES(alice);
        _voteYES(carol);

        /* NO vote: Bob (has voting permission but no DD power, only PT power) */
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(bob);
        hv.vote(id, idx, w); // should succeed with PT power only

        /* advance time, finalise */
        vm.warp(block.timestamp + 16 minutes);
        vm.prank(alice);
        (uint256 win, bool ok) = hv.announceWinner(id);

        assertTrue(ok, "quorum not met");
        assertEq(win, 0, "YES should win");

        /* executor should be called with the winning option's batch */
        assertEq(exec.lastId(), id, "executor should be called with correct id");
    }

    /* ───────────────────────── PAUSE / CLEANUP ───────────────────────── */
    function testPauseUnpause() public {
        vm.prank(address(exec));
        hv.pause();
        vm.expectRevert();
        _create();
        vm.prank(address(exec));
        hv.unpause();
        _create();
    }

    /* ───────────────────────── HAT MANAGEMENT TESTS ───────────────────────── */
    function testSetHatAllowed() public {
        // Test that executor can modify voting hat permissions
        vm.prank(address(exec));
        hv.setHatAllowed(DEFAULT_HAT_ID, false);
        
        // Alice should still be able to vote with EXECUTIVE_HAT_ID (DD power)
        _create();
        _voteYES(alice);
        
        // Create a new voter with only the disabled DEFAULT_HAT_ID and insufficient tokens
        address hatOnlyVoter = vm.addr(15);
        hats.mintHat(DEFAULT_HAT_ID, hatOnlyVoter);
        token.mint(hatOnlyVoter, 0.5 ether); // Below minimum balance
        
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        
        // This voter should not be able to vote (no valid DD hat, insufficient PT tokens)
        vm.prank(hatOnlyVoter);
        vm.expectRevert(HybridVoting.Unauthorized.selector);
        hv.vote(0, idx, w);
        
        // Re-enable the hat and the same voter should now be able to vote
        vm.prank(address(exec));
        hv.setHatAllowed(DEFAULT_HAT_ID, true);
        
        vm.prank(hatOnlyVoter);
        hv.vote(0, idx, w); // Should work now with DD power from hat
    }

    function testSetCreatorHatAllowed() public {
        // Test that executor can modify creator hat permissions
        uint256 newCreatorHat = 99;
        address newCreator = vm.addr(20);
        
        // Give new creator the new hat
        hats.mintHat(newCreatorHat, newCreator);
        
        // Enable new hat as creator hat
        vm.prank(address(exec));
        hv.setCreatorHatAllowed(newCreatorHat, true);
        
        // New creator should be able to create proposal
        IExecutor.Call[][] memory batches = new IExecutor.Call[][](2);
        batches[0] = new IExecutor.Call[](0);
        batches[1] = new IExecutor.Call[](0);
        
        vm.prank(newCreator);
        hv.createProposal(bytes("ipfs://test"), 15, 2, batches);
        assertEq(hv.proposalsCount(), 1);
        
        // Disable new hat
        vm.prank(address(exec));
        hv.setCreatorHatAllowed(newCreatorHat, false);
        
        // Should now fail
        vm.prank(newCreator);
        vm.expectRevert(HybridVoting.Unauthorized.selector);
        hv.createProposal(bytes("ipfs://test2"), 15, 2, batches);
    }

    /* ───────────────────────── UNAUTHORIZED ACCESS TESTS ───────────────────────── */
    function testOnlyExecutorRevertWhenNonExecutorCallsAdminFunctions() public {
        // Test that non-executors cannot call admin functions
        vm.startPrank(nonExecutor);

        // Pause
        vm.expectRevert();
        hv.pause();

        // Set executor
        vm.expectRevert();
        hv.setExecutor(nonExecutor);

        // Set hat allowed
        vm.expectRevert();
        hv.setHatAllowed(DEFAULT_HAT_ID, false);

        // Set creator hat allowed
        vm.expectRevert();
        hv.setCreatorHatAllowed(CREATOR_HAT_ID, false);

        // Set target allowed
        vm.expectRevert();
        hv.setTargetAllowed(address(0xDEAD), true);

        // Set quorum
        vm.expectRevert();
        hv.setQuorum(60);

        // Set split
        vm.expectRevert();
        hv.setSplit(60);

        // Toggle quadratic
        vm.expectRevert();
        hv.toggleQuadratic();

        // Set min balance
        vm.expectRevert();
        hv.setMinBalance(2 ether);

        vm.stopPrank();
    }

    function testExecutorCanCallAdminFunctions() public {
        // Test that executor can call admin functions
        vm.startPrank(address(exec));

        // Set quorum
        hv.setQuorum(60);
        assertEq(hv.quorumPct(), 60);

        // Set split
        hv.setSplit(60);
        assertEq(hv.ddSharePct(), 60);

        // Toggle quadratic
        bool initialQuadratic = hv.quadraticVoting();
        hv.toggleQuadratic();
        assertEq(hv.quadraticVoting(), !initialQuadratic);

        // Set min balance
        hv.setMinBalance(2 ether);
        assertEq(hv.MIN_BAL(), 2 ether);

        vm.stopPrank();
    }

    function testExecutorTransfer() public {
        // Test transfer of executor role
        address newExecutor = vm.addr(6);

        // Set new executor
        vm.prank(address(exec));
        hv.setExecutor(newExecutor);

        // Old executor should no longer have permissions
        vm.prank(address(exec));
        vm.expectRevert();
        hv.setQuorum(70);

        // New executor should have permissions
        vm.prank(newExecutor);
        hv.setQuorum(70);
        assertEq(hv.quorumPct(), 70);
    }

    function testCleanup() public {
        _create();
        _voteYES(alice);
        address[] memory voters = new address[](1);
        voters[0] = alice;
        /* warp */
        vm.warp(block.timestamp + 20 minutes);
        hv.cleanupProposal(0, voters);
    }

    function testSpecialCase() public {
        // This test verifies the difference between voting hats and democracy hats
        // and creates a perfect tie scenario with 50-50 hybrid split

        // 1. Setup specific test actors
        address votingOnlyUser = vm.addr(40); // Has voting hat but no democracy hat
        address democracyUser = vm.addr(41); // Has democracy hat but insufficient tokens

        // 2. Give hats
        hats.mintHat(DEFAULT_HAT_ID, votingOnlyUser); // Voting permission only
        hats.mintHat(EXECUTIVE_HAT_ID, democracyUser); // Both voting and DD power

        // 3. Give tokens to create perfect tie scenario
        // votingOnlyUser: only PT power (gets 100% of PT slice = 50% total)
        token.mint(votingOnlyUser, 100 ether);
        // democracyUser: only DD power (gets 100% of DD slice = 50% total)
        token.mint(democracyUser, 0.5 ether); // Below MIN_BAL, so no PT power

        // 4. Create a test proposal
        uint256 id = _create();

        // 5. Both users vote
        uint8[] memory idxYes = new uint8[](1);
        idxYes[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;

        // votingOnlyUser votes YES (only PT power: 50% of total)
        vm.prank(votingOnlyUser);
        hv.vote(id, idxYes, w);

        // democracyUser votes NO (only DD power: 50% of total)
        uint8[] memory idxNo = new uint8[](1);
        idxNo[0] = 1;

        vm.prank(democracyUser);
        hv.vote(id, idxNo, w);

        // 6. Advance time and check results
        vm.warp(block.timestamp + 16 minutes);
        (uint256 win, bool valid) = hv.announceWinner(id);

        // 7. Should be invalid due to perfect tie (50-50 split)
        assertFalse(valid, "Should be invalid due to perfect tie");
    }
}
