// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "../HybridVoting.sol";
import "./VotingErrors.sol";
import "./VotingMath.sol";
import "./HatManager.sol";
import "./ValidationLib.sol";
import {IExecutor} from "../Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

library HybridVotingProposals {
    bytes32 private constant _STORAGE_SLOT = keccak256("poa.hybridvoting.v2.storage");

    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION = 43_200;
    uint32 public constant MIN_DURATION = 10;

    event NewProposal(uint256 id, bytes title, bytes32 descriptionHash, uint8 numOptions, uint64 endTs, uint64 created);
    event NewHatProposal(
        uint256 id,
        bytes title,
        bytes32 descriptionHash,
        uint8 numOptions,
        uint64 endTs,
        uint64 created,
        uint256[] hatIds
    );

    function _layout() private pure returns (HybridVoting.Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /// Default proposal creation. Snapshots on-chain eligibility from the
    /// effective hat array (pollHatIds when restricted, creatorHatIds when
    /// not) so async-majority early-close is enabled out of the box.
    function createProposal(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) external {
        uint256 id = _initProposal(title, descriptionHash, minutesDuration, numOptions, batches, hatIds, 0);

        uint64 endTs = _layout()._proposals[id].endTimestamp;

        if (hatIds.length > 0) {
            emit NewHatProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp), hatIds);
        } else {
            emit NewProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp));
        }
    }

    /// Variant that lets the caller supply a higher eligibility hint than
    /// on-chain truth. Useful when the proposer expects hats to be granted
    /// (or transferred in) before the proposal closes and wants to keep the
    /// early-close threshold conservative. The stored snapshot is
    /// max(callerEligibleHint, on-chain hatSupply sum) — under-count is
    /// impossible by construction; over-count makes early-close stricter.
    function createProposalWithEligibleSnapshot(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds,
        uint64 callerEligibleHint
    ) external {
        uint256 id = _initProposal(title, descriptionHash, minutesDuration, numOptions, batches, hatIds, callerEligibleHint);

        uint64 endTs = _layout()._proposals[id].endTimestamp;

        if (hatIds.length > 0) {
            emit NewHatProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp), hatIds);
        } else {
            emit NewProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp));
        }
    }

    /// Variant that explicitly opts out of async-majority early-close, even
    /// when the timer is unexpired. snapshotEligibleVoters is set to
    /// type(uint64).max so the early-close gate can never be satisfied. Use
    /// for proposals that should always run their full duration (e.g., sprint
    /// priority votes).
    function createProposalLegacyTimerOnly(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) external {
        uint256 id = _initProposal(title, descriptionHash, minutesDuration, numOptions, batches, hatIds, type(uint64).max);

        uint64 endTs = _layout()._proposals[id].endTimestamp;

        if (hatIds.length > 0) {
            emit NewHatProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp), hatIds);
        } else {
            emit NewProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp));
        }
    }

    function _initProposal(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds,
        uint64 callerEligibleHint
    ) internal returns (uint256) {
        ValidationLib.requireValidTitle(title);
        if (numOptions == 0) revert VotingErrors.LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert VotingErrors.TooManyOptions();
        _validateDuration(minutesDuration);

        HybridVoting.Layout storage l = _layout();
        if (l.classes.length == 0) revert VotingErrors.InvalidClassCount();

        bool isExecuting = false;
        if (batches.length > 0) {
            if (numOptions != batches.length) revert VotingErrors.LengthMismatch();
            for (uint256 i; i < numOptions;) {
                if (batches[i].length > 0) {
                    isExecuting = true;
                    _validateTargets(batches[i]);
                }
                unchecked {
                    ++i;
                }
            }
        }

        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        HybridVoting.Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;

        _snapshotClasses(p, l);
        uint256 classCount = l.classes.length;
        _initOptions(p, numOptions, classCount);

        uint256 id = l._proposals.length - 1;

        if (isExecuting) {
            for (uint256 i; i < numOptions;) {
                p.batches.push(batches[i]);
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i; i < numOptions;) {
                p.batches.push();
                unchecked {
                    ++i;
                }
            }
        }

        if (hatIds.length > 0) {
            uint256 len = hatIds.length;
            for (uint256 i; i < len;) {
                p.pollHatIds.push(hatIds[i]);
                p.pollHatAllowed[hatIds[i]] = true;
                unchecked {
                    ++i;
                }
            }
        }

        // Snapshot eligibility. type(uint64).max is the explicit timer-only
        // opt-out sentinel; otherwise sum on-chain hatSupply across the
        // effective hat array (pollHatIds when restricted, creatorHatIds
        // when not) and take the max with the caller's hint.
        if (callerEligibleHint == type(uint64).max) {
            p.snapshotEligibleVoters = type(uint64).max;
        } else {
            uint256[] memory eligibleHatIds;
            if (p.restricted) {
                eligibleHatIds = new uint256[](hatIds.length);
                for (uint256 i; i < hatIds.length;) {
                    eligibleHatIds[i] = hatIds[i];
                    unchecked { ++i; }
                }
            } else {
                uint256 ccLen = l.creatorHatIds.length;
                eligibleHatIds = new uint256[](ccLen);
                for (uint256 i; i < ccLen;) {
                    eligibleHatIds[i] = l.creatorHatIds[i];
                    unchecked { ++i; }
                }
            }
            uint64 onChainUpperBound = _eligibleVotersUpperBound(eligibleHatIds);
            p.snapshotEligibleVoters = callerEligibleHint > onChainUpperBound
                ? callerEligibleHint
                : onChainUpperBound;
        }

        return id;
    }

    /// Sum of IHats.hatSupply across hatIds, capped at uint64.max. Used at
    /// createProposal to seed the early-close eligibility snapshot. NOTE:
    /// addresses wearing multiple eligible hats are double-counted; this is
    /// acceptable because over-counting raises the threshold (i.e. requires
    /// more voters before early-close fires) which is the safer direction.
    function _eligibleVotersUpperBound(uint256[] memory hatIds) internal view returns (uint64) {
        HybridVoting.Layout storage l = _layout();
        uint256 total;
        uint256 len = hatIds.length;
        for (uint256 i; i < len;) {
            total += l.hats.hatSupply(hatIds[i]);
            unchecked { ++i; }
        }
        return total > type(uint64).max ? type(uint64).max : uint64(total);
    }

    function _validateDuration(uint32 minutesDuration) internal pure {
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) {
            revert VotingErrors.DurationOutOfRange();
        }
    }

    function _validateTargets(IExecutor.Call[] calldata batch) internal pure {
        uint256 batchLen = batch.length;
        if (batchLen > MAX_CALLS) revert VotingErrors.TooManyCalls();
    }

    function _snapshotClasses(HybridVoting.Proposal storage p, HybridVoting.Layout storage l) internal {
        uint256 classCount = l.classes.length;
        for (uint256 i; i < classCount;) {
            p.classesSnapshot.push(l.classes[i]);
            unchecked {
                ++i;
            }
        }
        p.classTotalsRaw = new uint256[](classCount);
    }

    function _initOptions(HybridVoting.Proposal storage p, uint8 numOptions, uint256 classCount) internal {
        for (uint256 i; i < numOptions;) {
            HybridVoting.PollOption storage opt = p.options.push();
            opt.classRaw = new uint128[](classCount);
            unchecked {
                ++i;
            }
        }
    }
}
