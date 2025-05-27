// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* ──────────────────  OpenZeppelin v5.3 Upgradeables  ────────────────── */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IExecutor} from "./Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

/* ──────────────────  Direct‑democracy governor  ─────────────────────── */
contract DirectDemocracyVoting is Initializable, ContextUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /* ─────────── Errors (same id set) ─────────── */
    error Unauthorized();
    error AlreadyVoted();
    error InvalidProposal();
    error VotingExpired();
    error VotingOpen();
    error WeightSumNot100(uint256);
    error InvalidIndex();
    error LengthMismatch();
    error InvalidWeight();
    error DurationOutOfRange();
    error DuplicateIndex();
    error TooManyOptions();
    error TooManyCalls();
    error TargetNotAllowed();
    error TargetSelf();
    error EmptyBatch(); // no longer used, kept for layout
    error ZeroAddress();
    error InvalidMetadata();
    error RoleNotAllowed();

    /* ─────────── Constants ─────────── */
    bytes4 public constant MODULE_ID = 0x6464766f; /* "ddvo"  */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION_MIN = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION_MIN = 10; /* spam guard */

    /* ─────────── Data Structures ─────────── */
    struct PollOption {
        uint96 votes;
    }

    struct Proposal {
        uint128 totalWeight; // voters × 100
        uint64 endTimestamp;
        PollOption[] options;
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches; // per‑option execution
        mapping(uint256 => bool) allowedHats; // which hats can vote
        bool restricted; // if true only allowedHats can vote
    }

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.directdemocracy.storage
    struct Layout {
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        mapping(uint256 => bool) _allowedHats; // which hats can create proposals
        uint8 quorumPercentage; // 1‑100
        Proposal[] _proposals;
    }

    // keccak256("poa.directdemocracy.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x1da04eb4a741346cdb49b5da943a0c13e79399ef962f913efcd36d95ee6d7c38;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────────── Events ─────────── */
    event HatSet(uint256 hat, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created);
    event VoteCast(uint256 id, address voter, uint8[] idxs, uint8[] weights);
    event Winner(uint256 id, uint256 winningIdx, bool valid);
    event ExecutorUpdated(address newExecutor);
    event TargetAllowed(address target, bool allowed);
    event ProposalCleaned(uint256 id, uint256 cleaned);
    event QuorumPercentageSet(uint8 pct);

    /* ─────────── Initialiser ─────────── */
    constructor() initializer {}

    function initialize(
        address hats_,
        address executor_,
        uint256[] calldata initialHats,
        address[] calldata initialTargets,
        uint8 quorumPct
    ) external initializer {
        if (hats_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        require(quorumPct > 0 && quorumPct <= 100, "quorum");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.executor = IExecutor(executor_);
        l.quorumPercentage = quorumPct;
        emit QuorumPercentageSet(quorumPct);

        for (uint256 i; i < initialHats.length;) {
            l._allowedHats[initialHats[i]] = true;
            emit HatSet(initialHats[i], true);
            unchecked {
                ++i;
            }
        }
        for (uint256 i; i < initialTargets.length;) {
            l.allowedTarget[initialTargets[i]] = true;
            emit TargetAllowed(initialTargets[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /* ─────────── Admin (executor‑gated) ─────────── */
    modifier onlyExecutor() {
        if (_msgSender() != address(_layout().executor)) revert Unauthorized();
        _;
    }

    function pause() external onlyExecutor {
        _pause();
    }

    function unpause() external onlyExecutor {
        _unpause();
    }

    function setExecutor(address a) external onlyExecutor {
        if (a == address(0)) revert ZeroAddress();
        _layout().executor = IExecutor(a);
        emit ExecutorUpdated(a);
    }

    function setHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _layout()._allowedHats[h] = ok;
        emit HatSet(h, ok);
    }

    function setTargetAllowed(address t, bool ok) external onlyExecutor {
        _layout().allowedTarget[t] = ok;
        emit TargetAllowed(t, ok);
    }

    function setQuorumPercentage(uint8 q) external onlyExecutor {
        require(q > 0 && q <= 100, "quorum");
        _layout().quorumPercentage = q;
        emit QuorumPercentageSet(q);
    }

    /* ─────────── Modifiers ─────────── */
    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canCreate = false;
            for (uint256 i; i < 256;) {
                if (l._allowedHats[i] && l.hats.isWearerOfHat(_msgSender(), i)) {
                    canCreate = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            if (!canCreate) revert Unauthorized();
        }
        _;
    }

    modifier exists(uint256 id) {
        if (id >= _layout()._proposals.length) revert InvalidProposal();
        _;
    }

    modifier notExpired(uint256 id) {
        if (block.timestamp > _layout()._proposals[id].endTimestamp) revert VotingExpired();
        _;
    }

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _layout()._proposals[id].endTimestamp) revert VotingOpen();
        _;
    }

    /* ────────── Proposal Creation ────────── */
    function createProposal(
        bytes calldata metadata,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches
    ) external onlyCreator whenNotPaused {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0 || numOptions != batches.length) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            uint256 len = batches[i].length;
            if (len > 0) {
                if (len > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < len;) {
                    if (!l.allowedTarget[batches[i][j].target]) revert TargetNotAllowed();
                    if (batches[i][j].target == address(this)) revert TargetSelf();
                    unchecked {
                        ++j;
                    }
                }
            }
            p.options.push(PollOption(0));
            p.batches.push(batches[i]);
            unchecked {
                ++i;
            }
        }
        emit NewProposal(id, metadata, numOptions, endTs, uint64(block.timestamp));
    }

    /// @notice Create a poll restricted to certain hats. Execution is disabled.
    function createHatPoll(bytes calldata metadata, uint32 minutesDuration, uint8 numOptions, uint256[] calldata hats)
        external
        onlyCreator
        whenNotPaused
    {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hats.length > 0;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            p.options.push(PollOption(0));
            p.batches.push();
            unchecked {
                ++i;
            }
        }
        for (uint256 i; i < hats.length;) {
            p.allowedHats[hats[i]] = true;
            unchecked {
                ++i;
            }
        }
        emit NewProposal(id, metadata, numOptions, endTs, uint64(block.timestamp));
    }

    /* ─────────── Voting ─────────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();
        Layout storage l = _layout();
        
        // Check if voter is executor or has a voting hat
        if (_msgSender() != address(l.executor)) {
            bool canVote = false;
            for (uint256 i; i < 256;) {
                if (l._allowedHats[i] && l.hats.isWearerOfHat(_msgSender(), i)) {
                    canVote = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            if (!canVote) revert Unauthorized();
        }

        Proposal storage p = l._proposals[id];
        if (p.restricted) {
            bool hasAllowedHat = false;
            for (uint256 i; i < 256;) {
                if (p.allowedHats[i] && l.hats.isWearerOfHat(_msgSender(), i)) {
                    hasAllowedHat = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            if (!hasAllowedHat) revert RoleNotAllowed();
        }
        if (p.hasVoted[_msgSender()]) revert AlreadyVoted();

        uint256 seen;
        uint256 sum;
        for (uint256 i; i < idxs.length;) {
            uint8 ix = idxs[i];
            if (ix >= p.options.length) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;

            uint8 w = weights[i];
            if (w > 100) revert InvalidWeight();
            unchecked {
                sum += w;
            }
            unchecked {
                ++i;
            }
        }
        if (sum != 100) revert WeightSumNot100(sum);

        p.hasVoted[_msgSender()] = true;
        unchecked {
            p.totalWeight += 100;
        }

        for (uint256 i; i < idxs.length;) {
            unchecked {
                p.options[idxs[i]].votes += uint96(weights[i]);
                ++i;
            }
        }
        emit VoteCast(id, _msgSender(), idxs, weights);
    }

    /* ─────────── Finalise & Execute ─────────── */
    function announceWinner(uint256 id)
        external
        nonReentrant
        exists(id)
        isExpired(id)
        whenNotPaused
        returns (uint256 winner, bool valid)
    {
        (winner, valid) = _calcWinner(id);
        Layout storage l = _layout();
        IExecutor.Call[] storage batch = l._proposals[id].batches[winner];

        if (valid && batch.length > 0) {
            for (uint256 i; i < batch.length;) {
                if (batch[i].target == address(this)) revert TargetSelf();
                if (!l.allowedTarget[batch[i].target]) revert TargetNotAllowed();
                unchecked {
                    ++i;
                }
            }
            l.executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }

    /* ─────────── Cleanup ─────────── */
    function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];
        require(p.batches.length > 0 || voters.length > 0, "nothing");
        uint256 cleaned;
        for (uint256 i; i < voters.length && i < 4_000;) {
            if (p.hasVoted[voters[i]]) {
                delete p.hasVoted[voters[i]];
                unchecked {
                    ++cleaned;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (cleaned == 0 && p.batches.length > 0) delete p.batches;
        emit ProposalCleaned(id, cleaned);
    }

    /* ─────────── View helpers ─────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];
        uint96 hi;
        uint96 second;
        for (uint256 i; i < p.options.length;) {
            uint96 v = p.options[i].votes;
            if (v > hi) {
                second = hi;
                hi = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
            unchecked {
                ++i;
            }
        }
        ok = (uint256(hi) * 100 > uint256(p.totalWeight) * l.quorumPercentage) && (hi > second);
    }

    function proposalsCount() external view returns (uint256) {
        return _layout()._proposals.length;
    }

    /* ─────────── Version / ID ─────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    /* ─────────── Public getters for storage variables ─────────── */
    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function executor() external view returns (IExecutor) {
        return _layout().executor;
    }

    function allowedTarget(address target) external view returns (bool) {
        return _layout().allowedTarget[target];
    }

    function quorumPercentage() external view returns (uint8) {
        return _layout().quorumPercentage;
    }

    function pollHatAllowed(uint256 id, uint256 hat) external view returns (bool) {
        Layout storage l = _layout();
        if (id >= l._proposals.length) revert InvalidProposal();
        return l._proposals[id].allowedHats[hat];
    }

    function pollRestricted(uint256 id) external view returns (bool) {
        Layout storage l = _layout();
        if (id >= l._proposals.length) revert InvalidProposal();
        return l._proposals[id].restricted;
    }
}
