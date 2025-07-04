// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.30;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {IExecutor} from "./Executor.sol";
import {HatManager} from "./libs/HatManager.sol";
import {VotingMath} from "./libs/VotingMath.sol";

/* ─────────────────── HybridVoting ─────────────────── */
contract HybridVoting is Initializable {
    /* ─────── Errors ─────── */
    error Unauthorized();
    error AlreadyVoted();
    error InvalidProposal();
    error VotingExpired();
    error VotingOpen();
    error InvalidIndex();
    error LengthMismatch();
    error DurationOutOfRange();
    error TooManyOptions();
    error TooManyCalls();
    error InvalidTarget();
    error ZeroAddress();
    error InvalidMetadata();
    error RoleNotAllowed();
    error Paused();

    /* ─────── Constants ─────── */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION = 10; /* 10 min   */

    /* ─────── Data Structures ─────── */

    struct PollOption {
        uint128 ddRaw; // sum of DD raw points (0‑100 per voter)
        uint128 ptRaw; // sum of PT raw points (power×weight)
    }

    struct Proposal {
        uint64 endTimestamp;
        uint256 ddTotalRaw; // grows +100 per DD voter
        uint256 ptTotalRaw; // grows +(ptPower×100) per PT voter
        PollOption[] options;
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches;
        uint256[] pollHatIds; // array of specific hat IDs for this poll
        bool restricted; // if true only pollHatIds can vote
        mapping(uint256 => bool) pollHatAllowed; // O(1) lookup for poll hat permission
    }

    /* ─────── ERC-7201 Storage ─────── */
    /// @custom:storage-location erc7201:poa.hybridvoting.storage
    struct Layout {
        /* Config / Storage */
        IERC20 participationToken;
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        uint256[] votingHatIds; // enumeration array for voting hats
        uint256[] democracyHatIds; // enumeration array for democracy hats
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint8 quorumPct; // 1‑100
        uint8 ddSharePct; // e.g. 50 = 50 %
        bool quadraticVoting;
        uint256 MIN_BAL; // min PT balance to participate
        /* Vote Bookkeeping */
        Proposal[] _proposals;
        /* Inline State */
        bool _paused; // Inline pausable state
        uint256 _lock; // Inline reentrancy guard state
    }

    // keccak256("poa.hybridvoting.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x5ca2a7292ae8f852850852b5f984e5237d39f3240052e7ba31e27bf071bdb62b;

    /* ─────── Storage Getter Enum ─────── */
    enum StorageKey {
        PARTICIPATION_TOKEN,
        HATS,
        EXECUTOR,
        QUORUM_PCT,
        DD_SHARE_PCT,
        QUADRATIC_VOTING,
        MIN_BAL,
        VOTING_HATS,
        DEMOCRACY_HATS,
        CREATOR_HATS,
        VOTING_HAT_COUNT,
        DEMOCRACY_HAT_COUNT,
        CREATOR_HAT_COUNT,
        POLL_HAT_ALLOWED,
        POLL_RESTRICTED,
        VERSION,
        PROPOSALS_COUNT
    }

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────────── Inline Context Implementation ─────────── */
    function _msgSender() internal view returns (address addr) {
        assembly {
            addr := caller()
        }
    }

    /* ─────────── Inline Pausable Implementation ─────────── */
    modifier whenNotPaused() {
        if (_layout()._paused) revert Paused();
        _;
    }

    function paused() external view returns (bool) {
        return _layout()._paused;
    }

    function _pause() internal {
        _layout()._paused = true;
    }

    function _unpause() internal {
        _layout()._paused = false;
    }

    /* ─────── Events ─────── */
    event HatSet(HatType hatType, uint256 hat, bool allowed);
    event TargetAllowed(address target, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created);
    event NewHatProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created, uint256[] hatIds);
    event VoteCast(uint256 id, address voter, uint8[] idxs, uint8[] weights);
    event Winner(uint256 id, uint256 winningIdx, bool valid);
    event ExecutorUpdated(address newExec);
    event QuorumSet(uint8 pct);
    event SplitSet(uint8 ddShare);
    event QuadraticToggled(bool enabled);
    event MinBalanceSet(uint256 newMinBalance);
    event ProposalCleaned(uint256 id, uint256 cleaned);

    /* ─────── Initialiser ─────── */
    constructor() initializer {}

    function initialize(
        address hats_,
        address token_,
        address executor_,
        uint256[] calldata initialVotingHats,
        uint256[] calldata initialDemocracyHats,
        uint256[] calldata initialCreatorHats,
        address[] calldata initialTargets,
        uint8 quorum_,
        uint8 ddShare_,
        bool quadratic_,
        uint256 minBalance_
    ) external initializer {
        if (hats_ == address(0) || token_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }

        VotingMath.validateQuorum(quorum_);
        VotingMath.validateSplit(ddShare_);
        VotingMath.validateMinBalance(minBalance_);

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.participationToken = IERC20(token_);
        l.executor = IExecutor(executor_);
        l._paused = false; // Initialize paused state
        l._lock = 0; // Initialize reentrancy guard state

        l.quorumPct = quorum_;
        emit QuorumSet(quorum_);
        l.ddSharePct = ddShare_;
        emit SplitSet(ddShare_);
        l.quadraticVoting = quadratic_;
        emit QuadraticToggled(quadratic_);
        l.MIN_BAL = minBalance_;
        emit MinBalanceSet(minBalance_);

        _initializeHats(initialVotingHats, initialDemocracyHats, initialCreatorHats);
        _initializeTargets(initialTargets);
    }

    /* ─────── Internal Initialization Helpers ─────── */
    function _initializeHats(
        uint256[] calldata votingHats,
        uint256[] calldata democracyHats,
        uint256[] calldata creatorHats
    ) internal {
        Layout storage l = _layout();

        uint256 len = votingHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.votingHatIds, votingHats[i], true);
            unchecked {
                ++i;
            }
        }
        len = democracyHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.democracyHatIds, democracyHats[i], true);
            unchecked {
                ++i;
            }
        }
        len = creatorHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHats[i], true);
            unchecked {
                ++i;
            }
        }
    }

    function _initializeTargets(address[] calldata targets) internal {
        Layout storage l = _layout();
        uint256 len = targets.length;
        for (uint256 i; i < len;) {
            l.allowedTarget[targets[i]] = true;
            emit TargetAllowed(targets[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /* ─────── Governance setters (executor‑gated) ─────── */
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

    /* ─────── Hat Management ─────── */
    enum HatType {
        VOTING,
        CREATOR,
        DEMOCRACY
    }

        function setHatAllowed(HatType hatType, uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        
        if (hatType == HatType.VOTING) {
            HatManager.setHatInArray(l.votingHatIds, h, ok);
        } else if (hatType == HatType.CREATOR) {
            HatManager.setHatInArray(l.creatorHatIds, h, ok);
        } else if (hatType == HatType.DEMOCRACY) {
            HatManager.setHatInArray(l.democracyHatIds, h, ok);
        }
        
        emit HatSet(hatType, h, ok);
    }

    /* ─────── Configuration Setters ─────── */
    enum ConfigKey {
        QUORUM,
        SPLIT,
        QUADRATIC,
        MIN_BALANCE,
        TARGET_ALLOWED,
        EXECUTOR
    }

    function setConfig(ConfigKey key, bytes calldata value) external onlyExecutor {
        Layout storage l = _layout();

        if (key == ConfigKey.QUORUM) {
            uint8 q = abi.decode(value, (uint8));
            VotingMath.validateQuorum(q);
            l.quorumPct = q;
            emit QuorumSet(q);
        } else if (key == ConfigKey.SPLIT) {
            uint8 s = abi.decode(value, (uint8));
            VotingMath.validateSplit(s);
            l.ddSharePct = s;
            emit SplitSet(s);
        } else if (key == ConfigKey.QUADRATIC) {
            bool enabled = abi.decode(value, (bool));
            l.quadraticVoting = enabled;
            emit QuadraticToggled(enabled);
        } else if (key == ConfigKey.MIN_BALANCE) {
            uint256 n = abi.decode(value, (uint256));
            VotingMath.validateMinBalance(n);
            l.MIN_BAL = n;
            emit MinBalanceSet(n);
        } else if (key == ConfigKey.TARGET_ALLOWED) {
            (address target, bool allowed) = abi.decode(value, (address, bool));
            l.allowedTarget[target] = allowed;
            emit TargetAllowed(target, allowed);
        } else if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            if (newExecutor == address(0)) revert ZeroAddress();
            l.executor = IExecutor(newExecutor);
            emit ExecutorUpdated(newExecutor);
        }
    }

    /* ─────── Helpers & modifiers ─────── */
    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canCreate = HatManager.hasAnyHat(l.hats, l.creatorHatIds, _msgSender());
            if (!canCreate) revert Unauthorized();
        }
        _;
    }

    modifier exists(uint256 id) {
        if (id >= _layout()._proposals.length) revert InvalidProposal();
        _;
    }

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _layout()._proposals[id].endTimestamp) revert VotingOpen();
        _;
    }

    /* ─────── Proposal creation ─────── */
    function createProposal(
        bytes calldata metadata,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches
    ) external onlyCreator whenNotPaused {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0 || numOptions != batches.length) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            uint256 batchLen = batches[i].length;
            if (batchLen > 0) {
                if (batchLen > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < batchLen;) {
                    if (!l.allowedTarget[batches[i][j].target]) revert InvalidTarget();
                    if (batches[i][j].target == address(this)) revert InvalidTarget();
                    unchecked {
                        ++j;
                    }
                }
            }
            p.options.push(PollOption(0, 0));
            p.batches.push(batches[i]);
            unchecked {
                ++i;
            }
        }
        emit NewProposal(id, metadata, numOptions, endTs, uint64(block.timestamp));
    }

    /// @notice Create a poll restricted to certain hats. Execution is disabled.
    function createHatPoll(bytes calldata metadata, uint32 minutesDuration, uint8 numOptions, uint256[] calldata hatIds)
        external
        onlyCreator
        whenNotPaused
    {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            p.options.push(PollOption(0, 0));
            p.batches.push();
            unchecked {
                ++i;
            }
        }
        uint256 len = hatIds.length;
        for (uint256 i; i < len;) {
            p.pollHatIds.push(hatIds[i]);
            p.pollHatAllowed[hatIds[i]] = true;
            unchecked {
                ++i;
            }
        }
        emit NewHatProposal(id, metadata, numOptions, endTs, uint64(block.timestamp), hatIds);
    }

    /* ─────── Voting ─────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights) external exists(id) whenNotPaused {
        if (idxs.length != weights.length) revert LengthMismatch();
        if (block.timestamp > _layout()._proposals[id].endTimestamp) revert VotingExpired();
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canVote = HatManager.hasAnyHat(l.hats, l.votingHatIds, _msgSender());
            if (!canVote) revert RoleNotAllowed();
        }
        Proposal storage p = l._proposals[id];
        if (p.restricted) {
            bool hasAllowedHat = false;
            uint256 len = p.pollHatIds.length;
            for (uint256 i = 0; i < len;) {
                if (l.hats.isWearerOfHat(_msgSender(), p.pollHatIds[i])) {
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

        /* collect raw powers */
        bool hasDemocracyHat =
            (_msgSender() == address(l.executor)) || HatManager.hasAnyHat(l.hats, l.democracyHatIds, _msgSender());

        uint256 bal = l.participationToken.balanceOf(_msgSender());
        (uint256 ddRawVoter, uint256 ptRawVoter) =
            VotingMath.calculateRawPowers(hasDemocracyHat, bal, l.MIN_BAL, l.quadraticVoting);

        /* weight sanity */
        VotingMath.validateWeights(weights, idxs, p.options.length);

        /* store raws */
        uint256 len = weights.length;
        for (uint256 i; i < len;) {
            uint8 ix = idxs[i];
            uint8 w = weights[i];
            if (ddRawVoter > 0) p.options[ix].ddRaw += uint128(ddRawVoter * w / 100);
            if (ptRawVoter > 0) p.options[ix].ptRaw += uint128(ptRawVoter * w / 100);
            unchecked {
                ++i;
            }
        }
        p.ddTotalRaw += ddRawVoter;
        p.ptTotalRaw += ptRawVoter;
        p.hasVoted[_msgSender()] = true;

        emit VoteCast(id, _msgSender(), idxs, weights);
    }

    /* ─────── Winner & execution ─────── */
    function announceWinner(uint256 id)
        external
        exists(id)
        isExpired(id)
        whenNotPaused
        returns (uint256 winner, bool valid)
    {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];

        if (p.ddTotalRaw == 0 && p.ptTotalRaw == 0) {
            emit Winner(id, 0, false);
            return (0, false);
        }

        (uint256 sliceDD, uint256 slicePT) = VotingMath.calculateSlicePercentages(l.ddSharePct);
        uint256 hi;
        uint256 second;

        uint256 len = p.options.length;
        for (uint256 i; i < len;) {
            /* scale each slice to its fixed share */
            uint256 scaledDD = VotingMath.calculateScaledPower(p.options[i].ddRaw, p.ddTotalRaw, sliceDD);
            uint256 scaledPT = VotingMath.calculateScaledPower(p.options[i].ptRaw, p.ptTotalRaw, slicePT);
            uint256 totalScaled = VotingMath.calculateTotalScaledPower(scaledDD, scaledPT);

            if (totalScaled > hi) {
                second = hi;
                hi = totalScaled;
                winner = i;
            } else if (totalScaled > second) {
                second = totalScaled;
            }
            unchecked {
                ++i;
            }
        }

        valid = VotingMath.meetsQuorum(hi, second, sliceDD + slicePT, l.quorumPct);

        IExecutor.Call[] storage batch = p.batches[winner];
        if (valid && batch.length > 0) {
            uint256 len = batch.length;
            for (uint256 i; i < len;) {
                if (!l.allowedTarget[batch[i].target]) revert InvalidTarget();
                unchecked {
                    ++i;
                }
            }
            l.executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }

    /* ─────── Cleanup (storage‑refund helper) ─────── */
    // function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
    //     Layout storage l = _layout();
    //     Proposal storage p = l._proposals[id];

    //     // nothing to do?
    //     require(p.batches.length > 0 || voters.length > 0, "nothing");

    //     uint256 cleaned;
    //     // cap loop to stay well below the 4 million refund limit
    //     uint256 len = voters.length;
    //     for (uint256 i; i < len && i < 4_000;) {
    //         if (p.hasVoted[voters[i]]) {
    //             delete p.hasVoted[voters[i]];
    //             unchecked {
    //                 ++cleaned;
    //             }
    //         }
    //         unchecked {
    //             ++i;
    //         }
    //     }

    //     // once all voters are wiped you can also clear the call‑batches
    //     if (cleaned == 0 && p.batches.length > 0) {
    //         delete p.batches;
    //     }

    //     emit ProposalCleaned(id, cleaned);
    // }

    /* ─────── Unified Storage Getter ─────── */
    function getStorage(StorageKey key, bytes calldata params) external view returns (bytes memory) {
        Layout storage l = _layout();

        if (key == StorageKey.PARTICIPATION_TOKEN) {
            return abi.encode(l.participationToken);
        } else if (key == StorageKey.HATS) {
            return abi.encode(l.hats);
        } else if (key == StorageKey.EXECUTOR) {
            return abi.encode(l.executor);
        } else if (key == StorageKey.QUORUM_PCT) {
            return abi.encode(l.quorumPct);
        } else if (key == StorageKey.DD_SHARE_PCT) {
            return abi.encode(l.ddSharePct);
        } else if (key == StorageKey.QUADRATIC_VOTING) {
            return abi.encode(l.quadraticVoting);
        } else if (key == StorageKey.MIN_BAL) {
            return abi.encode(l.MIN_BAL);
        } else if (key == StorageKey.VOTING_HATS) {
            return abi.encode(HatManager.getHatArray(l.votingHatIds));
        } else if (key == StorageKey.DEMOCRACY_HATS) {
            return abi.encode(HatManager.getHatArray(l.democracyHatIds));
        } else if (key == StorageKey.CREATOR_HATS) {
            return abi.encode(HatManager.getHatArray(l.creatorHatIds));
        } else if (key == StorageKey.VOTING_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.votingHatIds));
        } else if (key == StorageKey.DEMOCRACY_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.democracyHatIds));
        } else if (key == StorageKey.CREATOR_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.creatorHatIds));
        } else if (key == StorageKey.POLL_HAT_ALLOWED) {
            (uint256 id, uint256 hat) = abi.decode(params, (uint256, uint256));
            if (id >= l._proposals.length) revert InvalidProposal();
            return abi.encode(l._proposals[id].pollHatAllowed[hat]);
        } else if (key == StorageKey.POLL_RESTRICTED) {
            uint256 id = abi.decode(params, (uint256));
            if (id >= l._proposals.length) revert InvalidProposal();
            return abi.encode(l._proposals[id].restricted);
        } else if (key == StorageKey.VERSION) {
            return abi.encode("v1");
        } else if (key == StorageKey.PROPOSALS_COUNT) {
            return abi.encode(l._proposals.length);
        }

        revert InvalidIndex();
    }
}
