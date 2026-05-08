// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* forge-std helpers */
import "forge-std/Test.sol";

/* target */
import {HybridVoting} from "../src/HybridVoting.sol";
import {VotingErrors} from "../src/libs/VotingErrors.sol";
import {HybridVotingProposals} from "../src/libs/HybridVotingProposals.sol";

/* OpenZeppelin */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {IExecutor} from "../src/Executor.sol";
import {MockHats} from "./mocks/MockHats.sol";

/// MockERC20 + MockExecutor copied from HybridVoting.t.sol pattern; kept
/// separate so this test file compiles standalone.
contract MockERC20EC is IERC20 {
    string public name = "PT";
    string public symbol = "PT";
    uint8 public decimals = 18;
    mapping(address => uint256) public override balanceOf;
    uint256 public override totalSupply;
    function transfer(address to, uint256 amt) public returns (bool) { balanceOf[msg.sender] -= amt; balanceOf[to] += amt; return true; }
    function transferFrom(address, address, uint256) public pure returns (bool) { return false; }
    function approve(address, uint256) public pure returns (bool) { return false; }
    function allowance(address, address) public pure returns (uint256) { return 0; }
    function mint(address to, uint256 amt) external { balanceOf[to] += amt; totalSupply += amt; }
}

contract MockExecutorEC is IExecutor {
    Call[] public lastBatch;
    uint256 public lastId;
    function execute(uint256 id, Call[] calldata batch) external {
        lastId = id;
        delete lastBatch;
        for (uint256 i; i < batch.length; ++i) lastBatch.push(batch[i]);
    }
}

/**
 * Task #441 — async-majority early-close integration tests.
 *
 * Covers the 8 scenarios from the trilateral design (vigil HB#603 7 scenarios
 * + argus HB#706 8th legacy-back-compat scenario):
 *
 *   1. threshold met + majority → early-close fires before timer
 *   2. threshold not met → reverts VotingOpen
 *   3. threshold met but tied 50/50 → reverts (strict majority required)
 *   4. callerEligibleHint = 0 → contract uses on-chain truth
 *   5. callerEligibleHint > onChainTruth → contract honors caller (over-count safe)
 *   6. callerEligibleHint < onChainTruth → contract overrides (under-count guarded — Q1 SAFETY FIX)
 *   7. callerEligibleHint == type(uint64).max → opt-out timer-only
 *   8. snapshotEligibleVoters == 0 (legacy back-compat) → timer-only fallback
 *
 * Per Argus task #441 + Proposal #60 async-majority protocol (passed 3-0 HB#493).
 */
contract HybridVotingEarlyCloseTest is Test {
    address owner = vm.addr(1);
    address alice = vm.addr(2);
    address bob = vm.addr(3);
    address carol = vm.addr(4);

    MockERC20EC token;
    MockHats hats;
    MockExecutorEC exec;
    HybridVoting hv;

    uint256 constant DEFAULT_HAT_ID = 1;
    uint256 constant EXECUTIVE_HAT_ID = 2;
    uint256 constant CREATOR_HAT_ID = 3;

    function setUp() public {
        token = new MockERC20EC();
        hats = new MockHats();
        exec = new MockExecutorEC();

        // 3 voters all wearing creator + executive + default hats.
        hats.mintHat(DEFAULT_HAT_ID, alice);
        hats.mintHat(EXECUTIVE_HAT_ID, alice);
        hats.mintHat(CREATOR_HAT_ID, alice);
        hats.mintHat(DEFAULT_HAT_ID, bob);
        hats.mintHat(EXECUTIVE_HAT_ID, bob);
        hats.mintHat(CREATOR_HAT_ID, bob);
        hats.mintHat(DEFAULT_HAT_ID, carol);
        hats.mintHat(EXECUTIVE_HAT_ID, carol);
        hats.mintHat(CREATOR_HAT_ID, carol);

        token.mint(alice, 100e18);
        token.mint(bob, 100e18);
        token.mint(carol, 100e18);

        uint256[] memory votingHats = new uint256[](2);
        votingHats[0] = DEFAULT_HAT_ID;
        votingHats[1] = EXECUTIVE_HAT_ID;
        uint256[] memory democracyHats = new uint256[](1);
        democracyHats[0] = EXECUTIVE_HAT_ID;
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = CREATOR_HAT_ID;
        address[] memory targets = new address[](1);
        targets[0] = address(0xCA11);

        HybridVoting.ClassConfig[] memory classes = new HybridVoting.ClassConfig[](2);
        classes[0] = HybridVoting.ClassConfig({
            strategy: HybridVoting.ClassStrategy.DIRECT,
            slicePct: 50,
            quadratic: false,
            minBalance: 0,
            asset: address(0),
            hatIds: democracyHats
        });
        classes[1] = HybridVoting.ClassConfig({
            strategy: HybridVoting.ClassStrategy.ERC20_BAL,
            slicePct: 50,
            quadratic: false,
            minBalance: 1 ether,
            asset: address(token),
            hatIds: votingHats
        });

        bytes memory initData = abi.encodeCall(
            HybridVoting.initialize,
            (address(hats), address(exec), creatorHats, targets, uint8(50), classes)
        );

        HybridVoting impl = new HybridVoting();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner);
        BeaconProxy proxy = new BeaconProxy(address(beacon), initData);
        hv = HybridVoting(payable(address(proxy)));
    }

    function _names() internal pure returns (string[] memory n) {
        n = new string[](2);
        n[0] = "YES";
        n[1] = "NO";
    }

    function _emptyBatches() internal pure returns (IExecutor.Call[][] memory b) {
        b = new IExecutor.Call[][](2);
        b[0] = new IExecutor.Call[](0);
        b[1] = new IExecutor.Call[](0);
    }

    function _voteYes(address voter) internal {
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        hv.vote(0, idx, w);
    }

    function _voteNo(address voter) internal {
        uint8[] memory idx = new uint8[](1);
        idx[0] = 1;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(voter);
        hv.vote(0, idx, w);
    }

    function _createDefault() internal {
        bytes memory title = "Async-Majority Test";
        vm.prank(alice);
        hv.createProposal(title, bytes32(0), 60, 2, _emptyBatches(), new uint256[](0));
    }

    function _createWithHint(uint64 callerHint) internal {
        bytes memory title = "Async-Majority With Hint";
        vm.prank(alice);
        hv.createProposalWithEligibleSnapshot(title, bytes32(0), 60, 2, _emptyBatches(), new uint256[](0), callerHint);
    }

    function _createLegacyTimerOnly() internal {
        bytes memory title = "Legacy Timer Only";
        vm.prank(alice);
        hv.createProposalLegacyTimerOnly(title, bytes32(0), 60, 2, _emptyBatches(), new uint256[](0));
    }

    /* ─── Scenario 1: threshold met + majority → early-close fires ─── */

    function test_EarlyClose_thresholdMet_majorityWinning_announceSucceedsBeforeTimer() public {
        _createDefault();
        // 3 eligible voters; ceil(3/2)=2 threshold. 2 of 3 vote YES = majority.
        _voteYes(alice);
        _voteYes(bob);
        // Timer is 60 minutes; we're at t=0
        // Without early-close this would revert VotingOpen.
        (uint256 win, bool ok) = hv.announceWinner(0);
        assertEq(win, 0); // YES option index
        assertTrue(ok);   // valid winner
    }

    /* ─── Scenario 2: threshold not met → reverts VotingOpen ─── */

    function test_EarlyClose_thresholdNotMet_revertsVotingOpen() public {
        _createDefault();
        // Only 1 of 3 voted; ceil(3/2)=2 not met
        _voteYes(alice);
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);
    }

    /* ─── Scenario 3: threshold met but tied → reverts (strict majority) ─── */

    function test_EarlyClose_thresholdMetButTied_revertsVotingOpen() public {
        _createDefault();
        // 2 of 3 vote split 1-1 between YES and NO
        _voteYes(alice);
        _voteNo(bob);
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);
    }

    /* ─── Scenario 4: callerHint=0 (default path) uses on-chain truth ─── */

    function test_EarlyClose_callerHintZero_usesOnChainTruth() public {
        _createDefault(); // back-compat path passes callerHint=0
        // On-chain truth from creatorHatIds=[CREATOR_HAT_ID] sums hatSupply
        // alice+bob+carol all wear CREATOR_HAT_ID = 3. Threshold ceil(3/2)=2.
        _voteYes(alice);
        _voteYes(bob);
        // Should be early-close eligible (threshold + majority both met)
        assertTrue(hv.isEarlyCloseEligible(0));
        (uint256 win, bool ok) = hv.announceWinner(0);
        assertEq(win, 0);
        assertTrue(ok);
    }

    /* ─── Scenario 5: callerHint > onChainTruth → caller honored ─── */

    function test_EarlyClose_callerHintExceedsOnChainTruth_callerHonored() public {
        // On-chain truth = 3 (3 creator-hat wearers). Caller passes 10.
        _createWithHint(10);
        // Threshold = ceil(10/2) = 5. Only 3 voters exist; threshold uncrossable.
        _voteYes(alice);
        _voteYes(bob);
        _voteYes(carol);
        // All 3 voted but threshold is 5 → not early-close eligible
        assertFalse(hv.isEarlyCloseEligible(0));
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);
    }

    /* ─── Scenario 6: callerHint < onChainTruth → contract overrides (Q1 SAFETY FIX) ─── */

    function test_EarlyClose_callerHintBelowOnChainTruth_contractOverrides() public {
        // On-chain truth = 3 (3 creator-hat wearers). Caller passes 1 (ATTEMPTED UNDER-COUNT).
        _createWithHint(1);
        // If caller hint were honored, threshold would be ceil(1/2)=1; single voter would early-close.
        // BUT contract enforces max(1, 3) = 3 → threshold ceil(3/2) = 2.
        _voteYes(alice);
        // 1 of 3 voted; threshold 2 not met
        assertFalse(hv.isEarlyCloseEligible(0));
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);
    }

    /* ─── Scenario 7: callerHint == max → opt-out timer-only ─── */

    function test_EarlyClose_legacyTimerOnly_optOut_neverEligible() public {
        _createLegacyTimerOnly();
        // All 3 vote unanimously YES — would normally early-close
        _voteYes(alice);
        _voteYes(bob);
        _voteYes(carol);
        // But snapshotEligibleVoters = type(uint64).max → not eligible
        assertFalse(hv.isEarlyCloseEligible(0));
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);
    }

    /* ─── Scenario 8: snapshotEligibleVoters == 0 (legacy back-compat) → timer-only ─── */

    /// Exercises the legacy-back-compat gate by creating a proposal, then
    /// zeroing snapshotEligibleVoters via vm.store to simulate a pre-upgrade
    /// proposal (zero-init for new fields). This is the rigorous test for
    /// the gate at HybridVotingCore._isEarlyCloseEligible:
    ///   if (p.snapshotEligibleVoters == 0) return false;
    /// Without this gate, post-upgrade announce paths would treat legacy
    /// proposals as having a threshold of ceil(0/2)=0 — every vote would
    /// trip early-close for a corpus of pre-upgrade proposals.
    function test_EarlyClose_legacyBackCompat_zeroSnapshot_timerOnly() public {
        _createDefault();
        _voteYes(alice);
        _voteYes(bob);
        _voteYes(carol);

        // Sanity: as-created with on-chain snapshot, the proposal IS eligible.
        assertTrue(hv.isEarlyCloseEligible(0));

        // Locate the storage slot holding (executed | voterCount | snapshotEligibleVoters).
        // ERC-7201 layout slot for `poa.hybridvoting.v2.storage`. The Layout
        // struct's `_proposals` array starts at a deterministic offset; for
        // proposal index 0, the slot containing the post-classesSnapshot
        // packed fields is computed below. We rely on the fact that all
        // earlier struct fields use full slots or dynamic-array-headers,
        // so the (bool executed, uint32 voterCount, uint64 snapshotEligibleVoters)
        // group lands together.
        //
        // To avoid fragility we lookup via probe: read each candidate slot,
        // find the one whose lowest-72-bits encodes our known voterCount=3
        // followed by our known snapshotEligibleVoters=3. Then zero the
        // snapshotEligibleVoters portion (high 64 bits of that 72-bit window).
        bytes32 storageSlot = keccak256("poa.hybridvoting.v2.storage");
        // _proposals is the 7th element in Layout (slot offset 6):
        // hats(0) executor(1) allowedTarget-mapping(2) creatorHatIds-len(3)
        // thresholdPct(4) classes-len(5) _proposals-len(6)
        bytes32 proposalsArrayLengthSlot = bytes32(uint256(storageSlot) + 6);
        // Element 0 of the dynamic Proposal[] starts at keccak256(slot 6).
        bytes32 proposal0Base = keccak256(abi.encode(proposalsArrayLengthSlot));
        // Walk the next ~12 slots looking for the packed (executed,voterCount,snapshotEligibleVoters)
        // storage word. Match on voterCount=3 + snapshotEligibleVoters=3 packed.
        bytes32 zeroSnapshot = bytes32(0); // we'll write this if the slot matches
        bool found;
        for (uint256 offset; offset < 16; ++offset) {
            bytes32 slot = bytes32(uint256(proposal0Base) + offset);
            uint256 raw = uint256(vm.load(address(hv), slot));
            // Layout in the packed slot (bool executed, uint32 voterCount, uint64 snapshotEligibleVoters):
            //   executed at bits 0:8 (1 byte), voterCount at 8:40 (4 bytes), snapshot at 40:104 (8 bytes).
            uint8 executedBit = uint8(raw & 0xFF);
            uint32 vCount = uint32((raw >> 8) & 0xFFFFFFFF);
            uint64 snap = uint64((raw >> 40) & 0xFFFFFFFFFFFFFFFF);
            if (executedBit == 0 && vCount == 3 && snap == 3) {
                // Zero the snapshot portion (clear bits 40:104).
                uint256 mask = ~(uint256(0xFFFFFFFFFFFFFFFF) << 40);
                uint256 newRaw = raw & mask;
                vm.store(address(hv), slot, bytes32(newRaw));
                found = true;
                break;
            }
        }
        assertTrue(found, "could not locate packed (executed,voterCount,snapshot) slot");

        // Now the gate must fire: snapshotEligibleVoters == 0 → not eligible.
        assertFalse(hv.isEarlyCloseEligible(0));
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);

        // After timer expires the legacy timer path still works.
        vm.warp(block.timestamp + 60 * 60 + 1);
        (uint256 win, bool ok) = hv.announceWinner(0);
        assertEq(win, 0);
        assertTrue(ok);
        zeroSnapshot; // silence unused warning if any
    }

    /* ─── Additional robustness scenarios ─── */

    /// Restricted-poll proposals snapshot from pollHatIds, not creatorHatIds.
    /// Verifies the branching in _initProposal that picks the right hat
    /// array for the on-chain snapshot computation.
    function test_EarlyClose_restrictedPoll_snapshotFromPollHatIds() public {
        // Add a 4th wearer to the DEFAULT_HAT_ID so creator and poll counts diverge:
        // - creatorHatIds = [CREATOR_HAT_ID]; supply = 3 (alice/bob/carol)
        // - pollHatIds (passed at create) = [DEFAULT_HAT_ID]; supply = 4 after we add dave
        address dave = vm.addr(99);
        hats.mintHat(DEFAULT_HAT_ID, dave);
        // dave doesn't get the EXECUTIVE_HAT_ID so they have no DD power, but
        // we don't actually have them vote — we only need their hat to bump
        // pollHatId supply.

        uint256[] memory pollHats = new uint256[](1);
        pollHats[0] = DEFAULT_HAT_ID;
        vm.prank(alice);
        hv.createProposal("Restricted Poll", bytes32(0), 60, 2, _emptyBatches(), pollHats);

        // Snapshot should be 4 (DEFAULT_HAT_ID supply), not 3 (CREATOR_HAT_ID).
        // Threshold = ceil(4/2) = 2.
        _voteYes(alice);
        // 1 voter; threshold 2 not met
        assertFalse(hv.isEarlyCloseEligible(0));
        _voteYes(bob);
        // 2 voters; threshold met + 100% YES
        assertTrue(hv.isEarlyCloseEligible(0));
    }

    /// Boundary: even-N threshold rounds correctly. With N=4 eligible, we
    /// need 2 voters (ceil(4/2) = 2), not 3.
    function test_EarlyClose_thresholdBoundary_evenEligibleSet() public {
        // 4 eligible via callerHint (skipping on-chain since fleet is 3)
        _createWithHint(4);
        _voteYes(alice);
        _voteYes(bob);
        // 2 of 4; ceil(4/2)=2 met. Both YES → 100% > 50% strict majority.
        assertTrue(hv.isEarlyCloseEligible(0));
    }

    /// Boundary: odd-N threshold rounds UP correctly. With N=5 eligible, we
    /// need 3 voters (ceil(5/2)=3), not 2.
    function test_EarlyClose_thresholdBoundary_oddEligibleSet() public {
        _createWithHint(5);
        _voteYes(alice);
        _voteYes(bob);
        // 2 of 5; ceil(5/2)=3 not met
        assertFalse(hv.isEarlyCloseEligible(0));
        _voteYes(carol);
        // 3 of 5; threshold met + unanimous → eligible
        assertTrue(hv.isEarlyCloseEligible(0));
    }

    /// Strict majority means winning > 50%, not winning >= 50%. With 3-way
    /// split where one option has 51% and another 49%, the 51% option wins.
    function test_EarlyClose_strictMajority_narrowWinPasses() public {
        _createDefault();
        // Vote weights: alice 60% YES / 40% NO; bob 60% YES / 40% NO
        // Carol abstains. 2 of 3 voters meets threshold; YES leads strictly.
        uint8[] memory idx = new uint8[](2);
        idx[0] = 0;
        idx[1] = 1;
        uint8[] memory w = new uint8[](2);
        w[0] = 60;
        w[1] = 40;
        vm.prank(alice);
        hv.vote(0, idx, w);
        vm.prank(bob);
        hv.vote(0, idx, w);
        assertTrue(hv.isEarlyCloseEligible(0));
        (uint256 win, bool ok) = hv.announceWinner(0);
        assertEq(win, 0); // YES wins
        assertTrue(ok);
    }

    /// _eligibleVotersUpperBound double-counts when a single address wears
    /// multiple eligible hats. Verifies the over-count is in the SAFE
    /// direction (raises threshold, makes early-close harder).
    function test_EarlyClose_overlappingHats_overcountIsSafeDirection() public {
        // Use callerHint=0 so contract uses on-chain truth across creatorHatIds=[CREATOR_HAT_ID].
        // alice/bob/carol each wear CREATOR_HAT_ID → supply=3 → threshold=2.
        _createDefault();
        _voteYes(alice);
        _voteYes(bob);
        // 2 voters meets threshold; unanimous YES; eligible.
        assertTrue(hv.isEarlyCloseEligible(0));

        // Now create a proposal restricted to BOTH default and executive hats.
        // alice/bob/carol all wear both → snapshot is 3 + 3 = 6 (overlapping
        // double-count). Threshold = ceil(6/2) = 3.
        uint256[] memory pollHats = new uint256[](2);
        pollHats[0] = DEFAULT_HAT_ID;
        pollHats[1] = EXECUTIVE_HAT_ID;
        vm.prank(alice);
        hv.createProposal("Multi-hat Poll", bytes32(0), 60, 2, _emptyBatches(), pollHats);
        // Vote on the SECOND proposal (id=1)
        uint8[] memory idx = new uint8[](1);
        idx[0] = 0;
        uint8[] memory w = new uint8[](1);
        w[0] = 100;
        vm.prank(alice);
        hv.vote(1, idx, w);
        vm.prank(bob);
        hv.vote(1, idx, w);
        // 2 voters, but threshold is 3 (because of double-count) → NOT eligible
        assertFalse(hv.isEarlyCloseEligible(1));
    }

    /* ─── Scenario sanity: timer-only path still works for new proposals after timer expires ─── */

    function test_EarlyClose_timerExpiry_legacyPathStillWorks() public {
        _createLegacyTimerOnly(); // explicit timer-only
        _voteYes(alice);
        _voteYes(bob);
        _voteYes(carol);
        // Before timer: should revert
        assertFalse(hv.isEarlyCloseEligible(0));
        vm.expectRevert(VotingErrors.VotingOpen.selector);
        hv.announceWinner(0);

        // After timer expires: should succeed (timer path, regardless of snapshot)
        vm.warp(block.timestamp + 60 * 60 + 1);
        (uint256 win, bool ok) = hv.announceWinner(0);
        assertEq(win, 0);
        assertTrue(ok);
    }
}
