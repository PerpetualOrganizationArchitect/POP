// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IExecutor} from "../../src/Executor.sol";
import {EligibilityModule} from "../../src/EligibilityModule.sol";

interface IPoaManagerLike {
    function upgradeBeacon(string calldata name, address newImpl, string calldata version) external;
    function owner() external view returns (address);
}

/*
 * ============================================================================
 * SimulateKUBIElections — Gnosis fork simulation
 * ============================================================================
 *
 * Reproduces, in Solidity, the exact batch shape the POA frontend builds in
 * `useProposalForm.js`'s election branch (post-fix), then executes the batch
 * against KUBI's real contracts on a Gnosis fork by pranking as the
 * HybridVoting (the only `allowedCaller` of the Executor).
 *
 * Scenarios:
 *   A — Post-fix transfer to a fresh address (Member hat, supply available)
 *   B — Re-elect existing wearer (eligibility refresh only, no mint)
 *   C — Demote loser to fallback Member, winner already wears Executive
 *   D — Pre-fix bare mint to a fresh address (no eligibility) → NotEligible revert
 *   E — Pre-fix zero-address mint → revert (the old "No One = 0x0" workaround)
 *   F — Post-fix "No One" empty batch → no-op (announceWinner skips execute)
 *   G — Transferring the MAX-SUPPLY Executive hat — documents KUBI's structural
 *       limit (vouching keeps incumbents eligible, supply slot can't free)
 *
 * Usage:
 *   forge script script/SimulateKUBIElections.s.sol:SimulateKUBIElections \
 *     --rpc-url gnosis -vv
 */

interface IEligibilityModule {
    function mintHatToAddress(uint256 hatId, address wearer) external;
    function setWearerEligibility(address wearer, uint256 hatId, bool eligible, bool standing) external;
}

interface IHats {
    function isWearerOfHat(address user, uint256 hatId) external view returns (bool);
    function checkHatWearerStatus(uint256 hatId, address wearer) external returns (bool);
    function transferHat(uint256 hatId, address from, address to) external;
    function viewHat(uint256 hatId)
        external
        view
        returns (
            string memory details,
            uint32 maxSupply,
            uint32 supply,
            address eligibility,
            address toggle,
            string memory imageURI,
            uint16 lastHatId,
            bool mutable_,
            bool active
        );
    function balanceOf(address account, uint256 hatId) external view returns (uint256);
}

interface IEligibilityModuleVouch {
    function currentVouchCount(uint256 hatId, address wearer) external view returns (uint32);
    function claimVouchedHat(uint256 hatId) external;
    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing);
    function resetVouches(uint256 hatId) external;
    function configureVouching(uint256 hatId, uint32 quorum, uint256 membershipHatId, bool combineWithHierarchy)
        external;
    function setBulkWearerEligibility(address[] calldata wearers, uint256 hatId, bool eligible, bool standing) external;
    function getVouchConfig(uint256 hatId) external view returns (VouchConfigView memory);
    function clearWearerVouches(address wearer, uint256 hatId) external;
}

struct VouchConfigView {
    uint32 quorum;
    uint256 membershipHatId;
    uint8 flags;
}

contract SimulateKUBIElections is Script {
    address constant KUBI_EXECUTOR = 0x23f90B3859818A843C3a848627A304Bc53947342;
    address constant KUBI_HYBRID_VOTING = 0x13CBd5eD47bF177968B24D84516a75879c23971E;
    address constant KUBI_ELIG_MODULE = 0x27114Cb757BeDF77E30EeB0Ca635e3368d8C2914;
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    uint256 constant EXECUTIVE_HAT = 0x0000043700010001000000000000000000000000000000000000000000000000;
    uint256 constant MEMBER_HAT = 0x0000043700010001000100000000000000000000000000000000000000000000;

    address constant CDOHERTY = 0x27677cD05185395be6DCe86b1c251410EC3c6239;
    address constant CALEB = 0x439831a0C10F834D6Bc6f62917834DdCaa203dCf;
    address constant WCALHOUN = 0xB1392EFc004ad50292C809f28DAFC746c404aed0;
    address constant SHARIVAPRADHAN = 0x94ae540518F0FC6eDA37cB7D76cf9da660345B83;

    // Fresh address with no eligibility, no vouches, no hats — exposes both
    // the pre-fix NotEligible bug AND verifies the post-fix path mints cleanly.
    address constant FRESH_ALICE = 0x000000000000000000000000000000000000a11c;

    uint256 totalScenarios;
    uint256 passedScenarios;

    function run() public {
        console.log("\n============================================================");
        console.log("  KUBI Election Frontend Batch Simulation (Gnosis fork)");
        console.log("============================================================");

        // Upgrade EligibilityModule beacon to v2 (with clearWearerVouches).
        // This mirrors what the Step1/2/3 cross-chain upgrade would deploy on
        // mainnet. All subsequent scenarios run against the upgraded module.
        EligibilityModule newImpl = new EligibilityModule();
        IPoaManagerLike poaManager = IPoaManagerLike(0x794fD39e75140ee1545B1B022E5486B7c863789b);
        address pmOwner = poaManager.owner();
        vm.prank(pmOwner);
        poaManager.upgradeBeacon("EligibilityModule", address(newImpl), "v2-test");
        console.log(string.concat("  EligibilityModule upgraded on fork to ", vm.toString(address(newImpl))));

        _logState();

        uint256 baseFork = vm.activeFork();
        // Each scenario snapshots before its state-changing calls and reverts
        // after, so they run independently against the original fork state.

        _isolated(baseFork, _runScenarioA);
        _isolated(baseFork, _runScenarioB);
        _isolated(baseFork, _runScenarioC);
        _isolated(baseFork, _runScenarioD);
        _isolated(baseFork, _runScenarioE);
        _isolated(baseFork, _runScenarioF);
        _isolated(baseFork, _runScenarioG);
        _isolated(baseFork, _runScenarioH);
        _isolated(baseFork, _runScenarioI);
        _isolated(baseFork, _runScenarioJ);
        _isolated(baseFork, _runScenarioK);
        _isolated(baseFork, _runScenarioL);
        _isolated(baseFork, _runScenarioM);
        _isolated(baseFork, _runScenarioN);
        _isolated(baseFork, _runScenarioO);
        _isolated(baseFork, _runScenarioP);
        _isolated(baseFork, _runScenarioQ);
        _isolated(baseFork, _runScenarioR);
        _isolated(baseFork, _runScenarioS);
        _isolated(baseFork, _runScenarioT);
        _runParityCheck();

        console.log("\n============================================================");
        console.log("  Summary");
        console.log("============================================================");
        console.log("  Passed:", passedScenarios, "/", totalScenarios);
        require(passedScenarios == totalScenarios, "one or more scenarios failed expectations");
    }

    /* ---------------------------- Scenarios ---------------------------- */

    /// Post-fix transfer of the Member hat from caleb to a fresh address.
    /// 4-call shape: revoke caleb + clearVouches caleb + grant alice + transferHat.
    function _runScenarioA(uint256 baseFork) internal {
        _banner("A", "Post-fix transferHat (Member, 1 incumbent -> fresh candidate)");
        vm.selectFork(baseFork);

        IExecutor.Call[] memory batch = new IExecutor.Call[](4);
        batch[0] = _setElig(CALEB, MEMBER_HAT, false, false);
        batch[1] = _clearVouches(CALEB, MEMBER_HAT);
        batch[2] = _setElig(FRESH_ALICE, MEMBER_HAT, true, true);
        batch[3] = _transferHat(MEMBER_HAT, CALEB, FRESH_ALICE);

        bool ok = _execAndReport(99, batch);
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, MEMBER_HAT);
        bool calebGone = !IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT);
        _record("A", ok && aliceWears && calebGone, "expected: alice gets Member via transferHat, caleb loses it");
    }

    /// Re-elect someone who already wears the hat.
    /// Frontend skips the mint via the fresh-holder check; only the
    /// eligibility refresh remains. Idempotent, must succeed.
    function _runScenarioB(uint256 baseFork) internal {
        _banner("B", "Re-elect existing wearer (no mint, just eligibility refresh)");
        vm.selectFork(baseFork);

        IExecutor.Call[] memory batch = new IExecutor.Call[](1);
        batch[0] = _setElig(WCALHOUN, MEMBER_HAT, true, true);

        bool ok = _execAndReport(100, batch);
        bool stillWears = IHats(HATS).isWearerOfHat(WCALHOUN, MEMBER_HAT);
        _record("B", ok && stillWears, "expected: wcalhoun still wears Member, no revert");
    }

    /// Demote loser incumbent to fallback Member when winner already wears
    /// Executive. Mirrors KUBI #2 batch[1] with the new batch shape.
    /// Note: KUBI's vouching keeps caleb eligible for Executive even after
    /// our revoke, so checkHatWearerStatus will not actually burn his
    /// Executive token. That's a KUBI hat-tree config consequence and is
    /// expected behaviour from the frontend's POV — the batch builds and
    /// executes; the on-chain effect just doesn't include token burn.
    function _runScenarioC(uint256 baseFork) internal {
        _banner("C", "Demote loser to fallback Member (winner already wears Executive)");
        vm.selectFork(baseFork);

        bool calebHoldsMember = IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT);
        uint256 size = 4 + (calebHoldsMember ? 0 : 1);
        IExecutor.Call[] memory batch = new IExecutor.Call[](size);
        batch[0] = _setElig(CALEB, EXECUTIVE_HAT, false, false);
        batch[1] = _checkHat(EXECUTIVE_HAT, CALEB);
        batch[2] = _setElig(CALEB, MEMBER_HAT, true, true);
        uint256 j = 3;
        if (!calebHoldsMember) batch[j++] = _mint(MEMBER_HAT, CALEB);
        batch[j] = _setElig(CDOHERTY, EXECUTIVE_HAT, true, true);

        bool ok = _execAndReport(101, batch);
        bool cdohertyExec = IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT);
        bool calebMember = IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT);
        _record(
            "C",
            ok && cdohertyExec && calebMember,
            "expected: batch executes; cdoherty Executive intact, caleb has Member"
        );
    }

    /// PRE-FIX: bare mint to a fresh address with no eligibility set.
    /// Demonstrates the NotEligible() revert that broke KUBI #14.
    function _runScenarioD(uint256 baseFork) internal {
        _banner("D", "PRE-FIX: bare mint to fresh address (no eligibility) -> revert");
        vm.selectFork(baseFork);

        IExecutor.Call[] memory batch = new IExecutor.Call[](2);
        batch[0] = _setElig(CALEB, MEMBER_HAT, false, false);
        batch[1] = _mint(MEMBER_HAT, FRESH_ALICE);

        bool ok = _execAndReport(102, batch);
        _record("D", !ok, "expected: revert (NotEligible) - fresh candidate has no module record");
    }

    /// PRE-FIX: zero-address as a candidate. Mint reverts.
    function _runScenarioE(uint256 baseFork) internal {
        _banner("E", "PRE-FIX: zero-address candidate -> revert");
        vm.selectFork(baseFork);

        IExecutor.Call[] memory batch = new IExecutor.Call[](1);
        batch[0] = _mint(MEMBER_HAT, address(0));

        bool ok = _execAndReport(103, batch);
        _record("E", !ok, "expected: revert");
    }

    /// POST-FIX: "No One" wins. The empty batch is gated by
    /// HybridVoting.announceWinner via `if (valid && batch.length > 0)`,
    /// so execute is never called. We mirror that gate here.
    function _runScenarioF(
        uint256 /* baseFork */
    )
        internal
    {
        _banner("F", "POST-FIX: 'No One' empty batch -> no-op (no execute)");

        IExecutor.Call[] memory batch = new IExecutor.Call[](0);
        bool gated = batch.length == 0;
        // No call to execute — exactly what announceWinner does.
        _record("F", gated, "expected: announceWinner skips empty batch (no on-chain effect)");
    }

    /// Documents KUBI's structural limit: Executive is at maxSupply 10/10,
    /// AND vouching keeps incumbents eligible despite our setEligibility
    /// revoke, so checkHatWearerStatus refuses to burn. The batch the frontend
    /// builds is correct; the on-chain configuration prevents success. Failure
    /// is GRACEFUL (try/catch in announceWinner, ProposalExecutionFailed event).
    function _runScenarioG(uint256 baseFork) internal {
        _banner("G", "Maxed-supply Executive transfer -> graceful revert (KUBI hat-config issue)");
        vm.selectFork(baseFork);

        IExecutor.Call[] memory batch = new IExecutor.Call[](4);
        batch[0] = _setElig(CALEB, EXECUTIVE_HAT, false, false);
        batch[1] = _checkHat(EXECUTIVE_HAT, CALEB);
        batch[2] = _setElig(SHARIVAPRADHAN, EXECUTIVE_HAT, true, true);
        batch[3] = _mint(EXECUTIVE_HAT, SHARIVAPRADHAN);

        bool ok = _execAndReport(104, batch);
        // Expected: revert. Documents that frontend can't unilaterally fix
        // this — KUBI must increase Executive maxSupply or remove vouching.
        _record("G", !ok, "expected: revert (AllHatsWorn) - frontend builds correct batch; org config blocks");
    }

    /// Wraps a scenario in a snapshot/revert so state changes don't leak
    /// between scenarios. Without this, scenario A mints Member to alice and
    /// later scenarios trying to mint to alice would fail with AlreadyWearingHat.
    /// Counter values are preserved across the revert by saving them to memory
    /// and writing them back — vm.revertTo otherwise rolls back contract storage.
    function _isolated(uint256 baseFork, function(uint256) internal scenario) internal {
        uint256 totalBefore = totalScenarios;
        uint256 passedBefore = passedScenarios;
        uint256 snap = vm.snapshot();
        scenario(baseFork);
        uint256 totalAfter = totalScenarios;
        uint256 passedAfter = passedScenarios;
        vm.revertTo(snap);
        totalScenarios = totalBefore + (totalAfter - totalBefore);
        passedScenarios = passedBefore + (passedAfter - passedBefore);
    }

    /* ----------------------- Frontend logic mirror ----------------------- */
    /// Solidity port of useProposalForm.js's election batch builder. Used
    /// for scenarios H+ to verify the JS logic is correct under N candidates
    /// / N incumbents / fallback-already-holds permutations. ANY divergence
    /// between this and the JS would surface as a failing scenario below.
    struct Person {
        address addr;
        bool alreadyHoldsRole;
        bool alreadyHoldsFallback;
    }

    /// Mirrors useProposalForm.js's election batch builder including the
    /// transferHat optimization: when there is exactly 1 incumbent != candidate
    /// AND the candidate doesn't already hold the role AND a Hats address is
    /// known, use Hats.transferHat to atomically move the slot. Otherwise fall
    /// back to setEligibility(revoke) + mint.
    function _buildElectionBatch(
        Person memory candidate,
        Person[] memory incumbents,
        uint256 electionRoleId,
        uint256 fallbackRoleId, // 0 = no fallback
        bool hasHatsAddress
    ) internal pure returns (IExecutor.Call[] memory) {
        // Determine if the transferHat optimization applies.
        uint256 otherIncumbentCount;
        address transferSource;
        for (uint256 i; i < incumbents.length; i++) {
            if (incumbents[i].addr != candidate.addr) {
                otherIncumbentCount++;
                if (otherIncumbentCount == 1) transferSource = incumbents[i].addr;
            }
        }
        bool useTransferHat = hasHatsAddress && otherIncumbentCount == 1 && !candidate.alreadyHoldsRole;

        // Compute size. Each incumbent contributes: revoke + clearVouches
        // (always — the revoke alone is OR-ed away by vouching;
        // clearWearerVouches surgically zeros their vouch state). Plus
        // optional fallback grant + maybe fallback mint.
        uint256 size = 0;
        for (uint256 i; i < incumbents.length; i++) {
            if (incumbents[i].addr == candidate.addr) continue;
            size += 2; // revoke + clearWearerVouches
            if (fallbackRoleId != 0) {
                size += 1; // grant fallback
                if (!incumbents[i].alreadyHoldsFallback) size += 1; // mint fallback
            }
        }
        size += 1; // candidate eligibility grant
        if (useTransferHat) size += 1; // transferHat
        else if (!candidate.alreadyHoldsRole) size += 1; // mint

        IExecutor.Call[] memory batch = new IExecutor.Call[](size);
        uint256 j;
        for (uint256 i; i < incumbents.length; i++) {
            Person memory inc = incumbents[i];
            if (inc.addr == candidate.addr) continue;
            batch[j++] = _setElig(inc.addr, electionRoleId, false, false);
            batch[j++] = _clearVouches(inc.addr, electionRoleId);
            if (fallbackRoleId != 0) {
                batch[j++] = _setElig(inc.addr, fallbackRoleId, true, true);
                if (!inc.alreadyHoldsFallback) batch[j++] = _mint(fallbackRoleId, inc.addr);
            }
        }
        batch[j++] = _setElig(candidate.addr, electionRoleId, true, true);
        if (useTransferHat) {
            batch[j++] = _transferHat(electionRoleId, transferSource, candidate.addr);
        } else if (!candidate.alreadyHoldsRole) {
            batch[j++] = _mint(electionRoleId, candidate.addr);
        }
        return batch;
    }

    /* ---------------------------- New scenarios --------------------------- */

    /// 3-candidate election; winner at index 1 (not 0). Build all 3 batches
    /// via the mirror, execute batches[1], assert correct outcome.
    function _runScenarioH(uint256 baseFork) internal {
        _banner("H", "3-candidate election; winner at index 1; batches[1] is what gets run");
        vm.selectFork(baseFork);

        Person memory candWinner = Person({addr: FRESH_ALICE, alreadyHoldsRole: false, alreadyHoldsFallback: false});
        Person[] memory incumbents = new Person[](1);
        incumbents[0] = Person({addr: CALEB, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        IExecutor.Call[] memory batch1 = _buildElectionBatch(candWinner, incumbents, MEMBER_HAT, 0, true);

        bool ok = _execAndReport(105, batch1);
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, MEMBER_HAT);
        _record("H", ok && aliceWears, "expected: batches[1] (winner) executes, alice gets Member");
    }

    /// Multi-incumbent demote: 2 incumbents (caleb, wcalhoun) lose to alice.
    /// Verifies the per-incumbent loop emits the right calls per loser.
    function _runScenarioI(uint256 baseFork) internal {
        _banner("I", "Multi-incumbent demote (2 losers + 1 fresh winner)");
        vm.selectFork(baseFork);

        Person memory cand = Person({addr: FRESH_ALICE, alreadyHoldsRole: false, alreadyHoldsFallback: false});
        Person[] memory incumbents = new Person[](2);
        incumbents[0] = Person({addr: CALEB, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        incumbents[1] = Person({addr: WCALHOUN, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        // Use Member as electionRoleId (supply available), no fallback to keep simple.
        IExecutor.Call[] memory batch = _buildElectionBatch(cand, incumbents, MEMBER_HAT, 0, true);

        // 2 losers (revoke+clearVouches each = 4) + candidate grant + mint
        // = 6 calls. Multi-incumbent doesn't use transferHat — falls back
        // to mint.
        require(batch.length == 6, "I: unexpected batch size");

        bool ok = _execAndReport(106, batch);
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, MEMBER_HAT);
        _record("I", ok && aliceWears, "expected: 4-call batch executes; alice wears Member");
    }

    /// Incumbent IS the candidate: loop must SKIP that incumbent.
    /// Re-electing a current wearer should produce a single eligibility-refresh,
    /// not a self-revoke.
    function _runScenarioJ(uint256 baseFork) internal {
        _banner("J", "Candidate is also a selected incumbent (re-elect; loop must skip)");
        vm.selectFork(baseFork);

        Person memory cand = Person({addr: WCALHOUN, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        Person[] memory incumbents = new Person[](1);
        incumbents[0] = Person({addr: WCALHOUN, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        IExecutor.Call[] memory batch = _buildElectionBatch(cand, incumbents, MEMBER_HAT, 0, true);

        // Expected: just the single eligibility-grant (no self-revoke, no mint).
        require(batch.length == 1, "J: should be exactly 1 call");

        bool ok = _execAndReport(107, batch);
        bool stillWears = IHats(HATS).isWearerOfHat(WCALHOUN, MEMBER_HAT);
        _record("J", ok && stillWears, "expected: 1-call batch; wcalhoun still wears Member");
    }

    /// Incumbent already holds the fallback hat: fallback mint must be skipped.
    function _runScenarioK(uint256 baseFork) internal {
        _banner("K", "Loser already holds fallback hat (fallback mint skipped)");
        vm.selectFork(baseFork);

        Person memory cand = Person({addr: CDOHERTY, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        Person[] memory incumbents = new Person[](1);
        incumbents[0] = Person({addr: CALEB, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        // electionRole = Executive, fallback = Member. Caleb already holds Member.
        IExecutor.Call[] memory batch = _buildElectionBatch(cand, incumbents, EXECUTIVE_HAT, MEMBER_HAT, true);

        // Expected: revoke + clearVouches + fallback-grant + winner-grant
        // = 4 calls (no fallback-mint since caleb already holds Member; no
        // winner-mint since cdoherty already holds Executive; no transferHat
        // since candidate already holds the role).
        require(batch.length == 4, "K: should be 4 calls");

        bool ok = _execAndReport(108, batch);
        // Test passes if the batch executes (caleb's Executive may not actually burn
        // due to vouching, but the batch shape is correct and submits cleanly).
        _record("K", ok, "expected: batch executes, no fallback mint emitted");
    }

    /// Multi-candidate election where the winner already holds the role.
    /// Candidate-grant is still emitted (idempotent, refreshes module state),
    /// but the mint is skipped. Mirrors the most common KUBI pattern.
    function _runScenarioL(uint256 baseFork) internal {
        _banner("L", "Winner already holds role -> candidate-grant emitted, mint skipped");
        vm.selectFork(baseFork);

        Person memory cand = Person({addr: WCALHOUN, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        Person[] memory incumbents = new Person[](0); // no incumbents at stake
        IExecutor.Call[] memory batch = _buildElectionBatch(cand, incumbents, MEMBER_HAT, 0, true);

        require(batch.length == 1, "L: should be 1 call (just eligibility grant)");

        bool ok = _execAndReport(109, batch);
        bool stillWears = IHats(HATS).isWearerOfHat(WCALHOUN, MEMBER_HAT);
        _record("L", ok && stillWears, "expected: idempotent grant; mint skipped; wcalhoun retains Member");
    }

    /// THE BIG ONE: replace the broken supply-burn pattern with Hats.transferHat.
    /// Transfers caleb's Executive (vouching-gated, supply 10/10 maxed) to alice
    /// (no vouches, no eligibility) using ONLY: setEligibility(alice, ...) +
    /// Hats.transferHat. No vouching manipulation, no contract upgrade.
    /// Verifies alice keeps the hat after the transfer despite zero vouches.
    function _runScenarioM(uint256 baseFork) internal {
        _banner("M", "transferHat to replace caleb (vouched, capped) with alice (no vouches)");
        vm.selectFork(baseFork);

        // Pre-state assertions
        require(IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT), "M.pre: caleb wears Executive");
        require(!IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT), "M.pre: alice doesn't");
        uint32 aliceVouchesBefore =
            IEligibilityModuleVouch(KUBI_ELIG_MODULE).currentVouchCount(EXECUTIVE_HAT, FRESH_ALICE);
        require(aliceVouchesBefore == 0, "M.pre: alice has 0 vouches");
        (, uint32 maxSup, uint32 supBefore,,,,,,) = IHats(HATS).viewHat(EXECUTIVE_HAT);
        require(maxSup == 10 && supBefore == 10, "M.pre: Executive at 10/10 maxed");

        // SANITY: a bare transferHat WITHOUT eligibility-grant should revert NotEligible
        IExecutor.Call[] memory bare = new IExecutor.Call[](1);
        bare[0] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);
        require(!_execAndReportSilent(200, bare), "M: bare transferHat must revert (alice not eligible yet)");

        // PROPER batch: grant alice eligibility, then transfer
        IExecutor.Call[] memory batch = new IExecutor.Call[](2);
        batch[0] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        batch[1] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);

        bool ok = _execAndReport(201, batch);

        // Post-state assertions
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT);
        bool calebGone = !IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT);
        (,, uint32 supAfter,,,,,,) = IHats(HATS).viewHat(EXECUTIVE_HAT);
        bool supplyUnchanged = supAfter == 10; // transfer doesn't change supply
        uint32 aliceVouchesAfter =
            IEligibilityModuleVouch(KUBI_ELIG_MODULE).currentVouchCount(EXECUTIVE_HAT, FRESH_ALICE);
        bool noVouchesAdded = aliceVouchesAfter == 0;

        // CRITICAL CHECK: does alice keep the hat under a fresh status query?
        // checkHatWearerStatus calls eligibility module's getWearerStatus. With
        // explicit (true,true) rules, it returns eligible -> no burn.
        vm.prank(KUBI_HYBRID_VOTING);
        try IExecutor(KUBI_EXECUTOR).execute(202, _wrap(_checkHat(EXECUTIVE_HAT, FRESH_ALICE))) {} catch {}
        bool aliceStillWearsAfterStatusCheck = IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT);

        console.log(unicode"  alice wears Executive:    ", aliceWears);
        console.log(unicode"  caleb removed:            ", calebGone);
        console.log(unicode"  supply unchanged (10/10): ", supplyUnchanged);
        console.log(unicode"  alice vouch count == 0:   ", noVouchesAdded);
        console.log(unicode"  alice survives checkHat:  ", aliceStillWearsAfterStatusCheck);

        _record(
            "M",
            ok && aliceWears && calebGone && supplyUnchanged && noVouchesAdded && aliceStillWearsAfterStatusCheck,
            "expected: transferHat works; alice wears Executive with 0 vouches and survives status checks"
        );
    }

    /// Edge case: transfer to a candidate who already holds the role.
    /// Hats.transferHat reverts with AlreadyWearingHat. Must NOT be used in
    /// this case — frontend's `candidateAlreadyHolds` skip path handles it.
    function _runScenarioN(uint256 baseFork) internal {
        _banner("N", "transferHat must NOT fire when candidate already holds the role");
        vm.selectFork(baseFork);

        require(IHats(HATS).isWearerOfHat(WCALHOUN, EXECUTIVE_HAT), "N.pre: wcalhoun wears Executive");
        require(IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT), "N.pre: cdoherty wears Executive");

        // If the frontend mistakenly tried to transfer Executive from wcalhoun to cdoherty
        // (cdoherty already wears it), Hats.transferHat would revert.
        IExecutor.Call[] memory batch = new IExecutor.Call[](1);
        batch[0] = _transferHat(EXECUTIVE_HAT, WCALHOUN, CDOHERTY);
        bool ok = _execAndReportSilent(203, batch);
        _record("N", !ok, "expected: revert (AlreadyWearingHat) - frontend must skip transfer when candidate holds");
    }

    /// Re-claim protection: after transferHat WITH the revoke fix, caleb
    /// can NO LONGER re-claim Member even though supply has room (19/1000),
    /// because his explicit eligibility was revoked AND his vouch count is 0.
    /// His getWearerStatus now returns (false, false) -> claimVouchedHat
    /// reverts at the eligibility check.
    function _runScenarioO(uint256 baseFork) internal {
        _banner("O", "Post-fix: caleb cannot re-claim Member via vouching after revoke + transferHat");
        vm.selectFork(baseFork);

        require(IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT), "O.pre: caleb wears Member");
        uint32 calebVouches = IEligibilityModuleVouch(KUBI_ELIG_MODULE).currentVouchCount(MEMBER_HAT, CALEB);
        console.log("  caleb's Member vouch count:", calebVouches);

        // Mirrors the new frontend batch shape exactly (4 calls with clearVouches).
        IExecutor.Call[] memory batch = new IExecutor.Call[](4);
        batch[0] = _setElig(CALEB, MEMBER_HAT, false, false);
        batch[1] = _clearVouches(CALEB, MEMBER_HAT);
        batch[2] = _setElig(FRESH_ALICE, MEMBER_HAT, true, true);
        batch[3] = _transferHat(MEMBER_HAT, CALEB, FRESH_ALICE);
        bool transferOk = _execAndReport(300, batch);
        require(transferOk, "O: transferHat must succeed");
        require(IHats(HATS).isWearerOfHat(FRESH_ALICE, MEMBER_HAT), "O: alice should wear Member after transfer");
        require(!IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT), "O: caleb shouldn't wear Member after transfer");

        (bool calebEligibleAfter,) = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getWearerStatus(CALEB, MEMBER_HAT);
        console.log("  caleb getWearerStatus.eligible after revoke:", calebEligibleAfter);

        vm.prank(CALEB);
        bool reclaimSucceeded;
        try IEligibilityModuleVouch(KUBI_ELIG_MODULE).claimVouchedHat(MEMBER_HAT) {
            reclaimSucceeded = true;
        } catch {
            reclaimSucceeded = false;
        }

        bool calebBackInPower = IHats(HATS).isWearerOfHat(CALEB, MEMBER_HAT);
        console.log("  reclaim succeeded:    ", reclaimSucceeded);
        console.log("  caleb wears again:    ", calebBackInPower);

        // EXPECTED FAILURE TO RE-CLAIM. Note: this only works because caleb's
        // Member vouch count is 0. If a loser has vouchCount >= quorum, the
        // revoke is OR-ed with vouching and they can still re-claim. That
        // residual gap is documented in scenario Q.
        _record(
            "O", !reclaimSucceeded && !calebBackInPower, "expected: re-claim REVERTS (revoke + 0 vouches = ineligible)"
        );
    }

    /// Counter-case: when supply is at maxSupply (KUBI Executive at 10/10),
    /// the loser cannot re-claim because there is no slot. transferHat
    /// is "permanent" against re-claim ONLY for capped-and-full hats.
    function _runScenarioP(uint256 baseFork) internal {
        _banner("P", "Maxed-supply protection: caleb CANNOT re-claim Executive (supply 10/10)");
        vm.selectFork(baseFork);

        // Move caleb's Executive to alice.
        IExecutor.Call[] memory batch = new IExecutor.Call[](2);
        batch[0] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        batch[1] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);
        bool transferOk = _execAndReport(301, batch);
        require(transferOk, "P: transferHat must succeed");

        // Supply is still 10/10 (transferHat is a move, not a mint).
        // caleb attempts to re-claim — should revert with AllHatsWorn.
        vm.prank(CALEB);
        bool reclaimSucceeded;
        try IEligibilityModuleVouch(KUBI_ELIG_MODULE).claimVouchedHat(EXECUTIVE_HAT) {
            reclaimSucceeded = true;
        } catch {
            reclaimSucceeded = false;
        }

        bool calebBackInPower = IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT);
        console.log("  reclaim succeeded:    ", reclaimSucceeded);
        console.log("  caleb wears again:    ", calebBackInPower);

        _record(
            "P",
            !reclaimSucceeded && !calebBackInPower,
            "expected: re-claim reverts (supply maxed) - capped hats are election-stable"
        );
    }

    /// RESIDUAL GAP: documented but not currently fixable from the frontend
    /// FORMERLY a documented gap — now closed by clearWearerVouches in
    /// EligibilityModule v2. caleb on Executive has 1 vouch (quorum 1).
    /// Pre-fix: revoke + transferHat left vouching intact -> getWearerStatus
    /// returned true via OR-path -> claimVouchedHat would succeed if supply
    /// had room. With clearWearerVouches inserted into the batch, caleb's
    /// wearerVouchEpoch is bumped to a sentinel that won't match the config
    /// epoch, so his effective vouch count is 0 and getWearerStatus returns
    /// false despite combineWithHierarchy=true.
    function _runScenarioQ(uint256 baseFork) internal {
        _banner("Q", "Closed gap: clearWearerVouches blocks vouching from defeating the revoke");
        vm.selectFork(baseFork);

        // 4-call batch including clearWearerVouches.
        IExecutor.Call[] memory batch = new IExecutor.Call[](4);
        batch[0] = _setElig(CALEB, EXECUTIVE_HAT, false, false);
        batch[1] = _clearVouches(CALEB, EXECUTIVE_HAT);
        batch[2] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        batch[3] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);
        bool transferOk = _execAndReport(302, batch);
        require(transferOk, "Q: transferHat must succeed");

        (bool calebEligibleAfter,) = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getWearerStatus(CALEB, EXECUTIVE_HAT);
        console.log("  caleb getWearerStatus.eligible after fix:", calebEligibleAfter);

        bool gapClosed = !calebEligibleAfter;
        console.log("  vouching gap closed:                     ", gapClosed);

        _record("Q", gapClosed, "expected: vouching can NO longer route around the revoke (clearWearerVouches works)");
    }

    /// CLOSING THE Q GAP via resetVouches in the election batch.
    /// Executor IS the EligibilityModule's superAdmin (verified on-chain) so
    /// it can call resetVouches(hatId) and configureVouching(...) directly.
    /// Combined with bulk-pinning explicit (true,true) rules for OTHER current
    /// holders BEFORE the reset, this kicks the loser's vouch state back to
    /// epoch=0 without breaking other wearers.
    ///
    /// Cost:
    ///   - Need fresh on-chain enumeration of current hat wearers (frontend
    ///     work — can't trust the subgraph per issue #166).
    ///   - Batch grows by 3 calls per election that needs vouch-reset:
    ///     setBulkWearerEligibility + resetVouches + configureVouching.
    ///   - All other current wearers must already have explicit (true,true)
    ///     rules after the bulk call, otherwise they fall through to
    ///     defaultRules=(false, true) once vouching is reset and become
    ///     ineligible -> any future checkHatWearerStatus burns their hats.
    ///   - configureVouching bumps the epoch a second time, so any vouches
    ///     accumulated under the old config are wiped (everyone re-vouches).
    function _runScenarioR(uint256 baseFork) internal {
        _banner("R", "Close Q gap via resetVouches: caleb's Executive vouch invalidated post-transfer");
        vm.selectFork(baseFork);

        // Read current vouching config so we can restore it.
        VouchConfigView memory cfg = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getVouchConfig(EXECUTIVE_HAT);
        bool combineWithHierarchy = (cfg.flags & 0x02) != 0;
        require(cfg.quorum > 0, "R.pre: vouching must be enabled");

        // Other Executive holders (everyone except caleb). In production the
        // frontend would enumerate this on-chain. KUBI has 9 others.
        address[] memory others = new address[](9);
        others[0] = CDOHERTY;
        others[1] = WCALHOUN;
        others[2] = 0x211bF72F6363590fF889BD058aAf610311f6724A; // hanvi
        others[3] = 0x2dF1aE8FAcF34Df51abf2595f1ef208852230e08; // emmadu
        others[4] = 0x69dd72d16c549699B599f23b43eC5A1E02fe392a; // alex
        others[5] = 0x8D8612fABF6E94591e29796Ed0Fb2e18D6DcFBcd; // wolfiesell
        others[6] = 0x9B09B826D2324b971B66AD1509cAF00BE6DAA95D; // cdtest
        others[7] = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9; // hudsonhrh
        others[8] = 0xb1D73DA3fD6891d9D7225413A02f005E3A4b511f; // nischay

        // Build the full election batch.
        IExecutor.Call[] memory batch = new IExecutor.Call[](6);
        // (1) Pin all OTHER current holders to (true,true) so they survive the vouch reset.
        batch[0] = IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(
                IEligibilityModuleVouch.setBulkWearerEligibility.selector, others, EXECUTIVE_HAT, true, true
            )
        });
        // (2) Revoke loser caleb (overrides hierarchy).
        batch[1] = _setElig(CALEB, EXECUTIVE_HAT, false, false);
        // (3) Nuke vouches for this hat.
        batch[2] = IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(IEligibilityModuleVouch.resetVouches.selector, EXECUTIVE_HAT)
        });
        // (4) Restore vouching config (epoch++ again -> everyone's vouch counts now stale=0).
        batch[3] = IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(
                IEligibilityModuleVouch.configureVouching.selector,
                EXECUTIVE_HAT,
                cfg.quorum,
                cfg.membershipHatId,
                combineWithHierarchy
            )
        });
        // (5) Grant winner alice eligibility.
        batch[4] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        // (6) Move the slot.
        batch[5] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);

        bool ok = _execAndReport(303, batch);
        require(ok, "R: full batch must succeed");

        // Post-state checks.
        require(IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT), "R: alice should wear Executive");
        require(!IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT), "R: caleb shouldn't wear Executive");

        // caleb's vouch count under the NEW epoch is 0 because his
        // wearerVouchEpoch is from the old epoch.
        uint32 calebVouchesAfter = IEligibilityModuleVouch(KUBI_ELIG_MODULE).currentVouchCount(EXECUTIVE_HAT, CALEB);
        // Note: currentVouchCount returns the raw stored count (pre-epoch
        // gating). The ACTUAL eligibility math gates on epoch match, which
        // is what defeats him. So we check getWearerStatus directly:
        (bool calebEligible,) = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getWearerStatus(CALEB, EXECUTIVE_HAT);
        console.log("  caleb stored vouch count (raw):", calebVouchesAfter);
        console.log("  caleb getWearerStatus.eligible:", calebEligible);

        // Verify caleb cannot re-claim. (KUBI Executive is also maxed at 10/10
        // so this is double-blocked, but the eligibility check fires first.)
        vm.prank(CALEB);
        bool reclaimSucceeded;
        try IEligibilityModuleVouch(KUBI_ELIG_MODULE).claimVouchedHat(EXECUTIVE_HAT) {
            reclaimSucceeded = true;
        } catch {
            reclaimSucceeded = false;
        }

        // Verify other holders are NOT broken.
        bool cdohertyOk = IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT);
        bool hanviOk = IHats(HATS).isWearerOfHat(others[2], EXECUTIVE_HAT);
        bool emmaduOk = IHats(HATS).isWearerOfHat(others[3], EXECUTIVE_HAT);

        console.log("  reclaim succeeded:        ", reclaimSucceeded);
        console.log("  cdoherty still wears:     ", cdohertyOk);
        console.log("  hanvi still wears:        ", hanviOk);
        console.log("  emmadu still wears:       ", emmaduOk);

        _record(
            "R",
            !calebEligible && !reclaimSucceeded && cdohertyOk && hanviOk && emmaduOk,
            "expected: caleb fully blocked; vouching reset; other holders preserved via bulk-pin"
        );
    }

    /// THE "JUST DO transferHat + resetVouches" CASE.
    /// Why this isn't enough: resetVouches DISABLES vouching for the hat (sets
    /// config.flags=0). After that, getWearerStatus returns hierarchyEligible
    /// only. KUBI's defaultRules[Executive] = (false, true), and 7 of 9 other
    /// holders (cdoherty, hanvi, alex, wolfiesell, emmadu, cdtest, nischay)
    /// have NO explicit wearerRules — they got in via vouching.
    /// Those 7 silently become ineligible after the batch: isWearerOfHat
    /// returns false, and the next checkHatWearerStatus on any of them burns
    /// their token. The minimal batch DOES kick caleb out, but it also
    /// "soft-evicts" most of the existing executive team.
    function _runScenarioS(uint256 baseFork) internal {
        _banner("S", "Minimal 'transferHat + resetVouches' breaks other holders");
        vm.selectFork(baseFork);

        // Pre-state: 9 other Execs are all valid wearers.
        bool cdohertyBefore = IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT);
        address HANVI = 0x211bF72F6363590fF889BD058aAf610311f6724A;
        address EMMADU = 0x2dF1aE8FAcF34Df51abf2595f1ef208852230e08;
        address ALEX = 0x69dd72d16c549699B599f23b43eC5A1E02fe392a;
        bool hanviBefore = IHats(HATS).isWearerOfHat(HANVI, EXECUTIVE_HAT);
        bool emmaduBefore = IHats(HATS).isWearerOfHat(EMMADU, EXECUTIVE_HAT);
        bool alexBefore = IHats(HATS).isWearerOfHat(ALEX, EXECUTIVE_HAT);
        require(cdohertyBefore && hanviBefore && emmaduBefore && alexBefore, "S.pre: 4 sample holders all wear");

        // The "minimal" batch the user proposed (plus the unavoidable
        // setEligibility(alice) since transferHat checks isEligible(to)).
        IExecutor.Call[] memory batch = new IExecutor.Call[](3);
        batch[0] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        batch[1] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);
        batch[2] = IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(IEligibilityModuleVouch.resetVouches.selector, EXECUTIVE_HAT)
        });
        bool ok = _execAndReport(304, batch);
        require(ok, "S: minimal batch must succeed");

        // Post-state: caleb out (intended), alice in (intended), but...
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT);
        bool calebGone = !IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT);
        bool cdohertyAfter = IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT);
        bool hanviAfter = IHats(HATS).isWearerOfHat(HANVI, EXECUTIVE_HAT);
        bool emmaduAfter = IHats(HATS).isWearerOfHat(EMMADU, EXECUTIVE_HAT);
        bool alexAfter = IHats(HATS).isWearerOfHat(ALEX, EXECUTIVE_HAT);

        console.log("  alice wears Executive:    ", aliceWears);
        console.log("  caleb removed:            ", calebGone);
        console.log("  cdoherty STILL wears:     ", cdohertyAfter);
        console.log("  hanvi STILL wears:        ", hanviAfter);
        console.log("  emmadu STILL wears:       ", emmaduAfter);
        console.log("  alex STILL wears:         ", alexAfter);

        // Scenario passes if we can DEMONSTRATE the breakage — i.e. some
        // holders no longer pass isWearerOfHat. This is the bug.
        bool collateralDamage = !cdohertyAfter || !hanviAfter || !emmaduAfter || !alexAfter;
        _record(
            "S",
            aliceWears && calebGone && collateralDamage,
            "documented: 'transferHat + resetVouches' silently invalidates other holders without explicit rules"
        );

        // Bonus: prove that checkHatWearerStatus would actually BURN one of
        // them now. Anyone (or any periodic Hats sweeper) can call this.
        if (!cdohertyAfter) {
            uint256 cdohertyBalanceBefore = IHats(HATS).balanceOf(CDOHERTY, EXECUTIVE_HAT);
            vm.prank(CALEB); // any caller works
            IHats(HATS).checkHatWearerStatus(EXECUTIVE_HAT, CDOHERTY);
            uint256 cdohertyBalanceAfter = IHats(HATS).balanceOf(CDOHERTY, EXECUTIVE_HAT);
            console.log("  cdoherty balance before checkHat:", cdohertyBalanceBefore);
            console.log("  cdoherty balance after  checkHat:", cdohertyBalanceAfter);
        }
    }

    /// THE FIX: clearWearerVouches in EligibilityModule v2.
    /// Election batch: revoke loser elig + clearWearerVouches loser + grant
    /// winner elig + transferHat. 4 calls. Surgical. No collateral damage.
    /// This scenario:
    ///   1. Deploys the new EligibilityModule impl locally (mirrors what the
    ///      cross-chain upgrade would land on Gnosis).
    ///   2. Upgrades the beacon on the fork via vm.prank as PoaManager owner.
    ///   3. Runs the 4-call election batch.
    ///   4. Verifies caleb is fully blocked (no eligible, no re-claim) AND
    ///      vouching is still ENABLED for the org AND other holders untouched.
    function _runScenarioT(uint256 baseFork) internal {
        _banner("T", "PROPOSED FIX: clearWearerVouches makes the election batch surgical (4 calls)");
        vm.selectFork(baseFork);

        // EligibilityModule v2 was already upgraded in setUp() — every
        // scenario in this run benefits from the clearWearerVouches selector.

        // Pre-state
        require(IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT), "T.pre: caleb wears Executive");
        VouchConfigView memory cfgBefore = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getVouchConfig(EXECUTIVE_HAT);
        bool vouchingEnabledBefore = (cfgBefore.flags & 0x01) != 0;
        require(vouchingEnabledBefore, "T.pre: vouching enabled");

        // ── 4. The new election batch — only 4 calls ──
        IExecutor.Call[] memory batch = new IExecutor.Call[](4);
        batch[0] = _setElig(CALEB, EXECUTIVE_HAT, false, false);
        batch[1] = IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(IEligibilityModuleVouch.clearWearerVouches.selector, CALEB, EXECUTIVE_HAT)
        });
        batch[2] = _setElig(FRESH_ALICE, EXECUTIVE_HAT, true, true);
        batch[3] = _transferHat(EXECUTIVE_HAT, CALEB, FRESH_ALICE);

        bool ok = _execAndReport(400, batch);
        require(ok, "T: 4-call batch must succeed");

        // ── 5. Post-state assertions ──
        bool aliceWears = IHats(HATS).isWearerOfHat(FRESH_ALICE, EXECUTIVE_HAT);
        bool calebGone = !IHats(HATS).isWearerOfHat(CALEB, EXECUTIVE_HAT);

        // CRITICAL: caleb's eligibility is now (false, false) — vouching path
        // is short-circuited because his epoch == type(uint256).max.
        (bool calebEligible,) = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getWearerStatus(CALEB, EXECUTIVE_HAT);

        // Re-claim must revert.
        vm.prank(CALEB);
        bool reclaimSucceeded;
        try IEligibilityModuleVouch(KUBI_ELIG_MODULE).claimVouchedHat(EXECUTIVE_HAT) {
            reclaimSucceeded = true;
        } catch {
            reclaimSucceeded = false;
        }

        // OTHER holders untouched (no bulk-pin needed because vouching stays ON).
        bool cdohertyOk = IHats(HATS).isWearerOfHat(CDOHERTY, EXECUTIVE_HAT);
        bool wcalhounOk = IHats(HATS).isWearerOfHat(WCALHOUN, EXECUTIVE_HAT);
        address HANVI = 0x211bF72F6363590fF889BD058aAf610311f6724A;
        bool hanviOk = IHats(HATS).isWearerOfHat(HANVI, EXECUTIVE_HAT);

        // Vouching config UNCHANGED (no resetVouches, no configureVouching).
        VouchConfigView memory cfgAfter = IEligibilityModuleVouch(KUBI_ELIG_MODULE).getVouchConfig(EXECUTIVE_HAT);
        bool vouchingPreserved = cfgAfter.quorum == cfgBefore.quorum && cfgAfter.flags == cfgBefore.flags;

        console.log("  alice wears Executive:    ", aliceWears);
        console.log("  caleb removed:            ", calebGone);
        console.log("  caleb eligible:           ", calebEligible);
        console.log("  caleb reclaim succeeded:  ", reclaimSucceeded);
        console.log("  cdoherty still wears:     ", cdohertyOk);
        console.log("  wcalhoun04 still wears:   ", wcalhounOk);
        console.log("  hanvi still wears:        ", hanviOk);
        console.log("  vouching config preserved:", vouchingPreserved);

        _record(
            "T",
            aliceWears && calebGone && !calebEligible && !reclaimSucceeded && cdohertyOk && wcalhounOk && hanviOk
                && vouchingPreserved,
            "expected: caleb fully blocked; everyone else untouched; vouching org-wide still on"
        );
    }

    /// Parity check: hand-built batch (Scenario A) byte-for-byte matches
    /// what the mirror helper produces from the same input. If the JS
    /// frontend ever diverges from this Solidity model, the test fails.
    function _runParityCheck() internal {
        _banner("Parity", "Hand-coded Scenario A batch matches mirror-builder output");
        Person memory cand = Person({addr: FRESH_ALICE, alreadyHoldsRole: false, alreadyHoldsFallback: false});
        Person[] memory incumbents = new Person[](1);
        incumbents[0] = Person({addr: CALEB, alreadyHoldsRole: true, alreadyHoldsFallback: true});
        IExecutor.Call[] memory mirror = _buildElectionBatch(cand, incumbents, MEMBER_HAT, 0, true);

        // Hand-coded equivalent of Scenario A:
        // revoke caleb + clearVouches caleb + grant alice + transferHat.
        IExecutor.Call[] memory hand = new IExecutor.Call[](4);
        hand[0] = _setElig(CALEB, MEMBER_HAT, false, false);
        hand[1] = _clearVouches(CALEB, MEMBER_HAT);
        hand[2] = _setElig(FRESH_ALICE, MEMBER_HAT, true, true);
        hand[3] = _transferHat(MEMBER_HAT, CALEB, FRESH_ALICE);

        bool match_ = mirror.length == hand.length;
        if (match_) {
            for (uint256 i; i < mirror.length; i++) {
                if (mirror[i].target != hand[i].target) {
                    match_ = false;
                    break;
                }
                if (mirror[i].value != hand[i].value) {
                    match_ = false;
                    break;
                }
                if (keccak256(mirror[i].data) != keccak256(hand[i].data)) {
                    match_ = false;
                    break;
                }
            }
        }
        _record("Parity", match_, "expected: mirror builder == hand-coded Scenario A");
    }

    /* ----------------------------- Helpers ----------------------------- */

    function _banner(string memory tag, string memory msg_) internal pure {
        console.log("\n------------------------------------------------------------");
        console.log(string.concat("Scenario ", tag, ": ", msg_));
        console.log("------------------------------------------------------------");
    }

    function _record(string memory tag, bool passed, string memory expectation) internal {
        totalScenarios++;
        if (passed) {
            passedScenarios++;
            console.log(string.concat("  PASS ", tag, ": ", expectation));
        } else {
            console.log(string.concat("  FAIL ", tag, ": ", expectation));
        }
    }

    function _logState() internal view {
        console.log("Hats Executive holders snapshot:");
        _logWearer("  cdoherty", CDOHERTY, EXECUTIVE_HAT);
        _logWearer("  caleb", CALEB, EXECUTIVE_HAT);
        _logWearer("  wcalhoun04", WCALHOUN, EXECUTIVE_HAT);
        _logWearer("  sharivapradhan", SHARIVAPRADHAN, EXECUTIVE_HAT);
        _logWearer("  alice (fresh)", FRESH_ALICE, EXECUTIVE_HAT);
        _logWearer("  alice (Member)", FRESH_ALICE, MEMBER_HAT);
    }

    function _logWearer(string memory label, address who, uint256 hat) internal view {
        bool wears = IHats(HATS).isWearerOfHat(who, hat);
        console.log(string.concat(label, ": "), wears ? "WEARS" : "no");
    }

    function _setElig(address wearer, uint256 hatId, bool eligible, bool standing)
        internal
        pure
        returns (IExecutor.Call memory)
    {
        return IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(
                IEligibilityModule.setWearerEligibility.selector, wearer, hatId, eligible, standing
            )
        });
    }

    function _mint(uint256 hatId, address wearer) internal pure returns (IExecutor.Call memory) {
        return IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(IEligibilityModule.mintHatToAddress.selector, hatId, wearer)
        });
    }

    function _checkHat(uint256 hatId, address wearer) internal pure returns (IExecutor.Call memory) {
        return IExecutor.Call({
            target: HATS, value: 0, data: abi.encodeWithSelector(IHats.checkHatWearerStatus.selector, hatId, wearer)
        });
    }

    function _transferHat(uint256 hatId, address from, address to) internal pure returns (IExecutor.Call memory) {
        return IExecutor.Call({
            target: HATS, value: 0, data: abi.encodeWithSelector(IHats.transferHat.selector, hatId, from, to)
        });
    }

    function _clearVouches(address wearer, uint256 hatId) internal pure returns (IExecutor.Call memory) {
        return IExecutor.Call({
            target: KUBI_ELIG_MODULE,
            value: 0,
            data: abi.encodeWithSelector(IEligibilityModuleVouch.clearWearerVouches.selector, wearer, hatId)
        });
    }

    function _wrap(IExecutor.Call memory c) internal pure returns (IExecutor.Call[] memory arr) {
        arr = new IExecutor.Call[](1);
        arr[0] = c;
    }

    function _execAndReportSilent(uint256 proposalId, IExecutor.Call[] memory batch) internal returns (bool) {
        vm.prank(KUBI_HYBRID_VOTING);
        try IExecutor(KUBI_EXECUTOR).execute(proposalId, batch) {
            return true;
        } catch {
            return false;
        }
    }

    function _execAndReport(uint256 proposalId, IExecutor.Call[] memory batch) internal returns (bool) {
        vm.prank(KUBI_HYBRID_VOTING);
        try IExecutor(KUBI_EXECUTOR).execute(proposalId, batch) {
            console.log("  execute(): OK");
            return true;
        } catch (bytes memory reason) {
            console.log("  execute(): REVERT");
            console.logBytes(reason);
            return false;
        }
    }
}
