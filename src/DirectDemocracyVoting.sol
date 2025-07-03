// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* ──────────────────  OpenZeppelin v5.3 Upgradeables  ────────────────── */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

import {IExecutor} from "./Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";
import {VotingMath} from "./libs/VotingMath.sol";

/* ──────────────────  Direct‑democracy governor  ─────────────────────── */
contract DirectDemocracyVoting is Initializable {
    /* ─────────── Errors ─────────── */
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
    error EmptyBatch();
    error ZeroAddress();
    error InvalidMetadata();
    error RoleNotAllowed();
    error InvalidQuorum();

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
        uint256[] pollHatIds; // array of specific hat IDs for this poll
        bool restricted; // if true only allowedHats can vote
        mapping(uint256 => bool) pollHatAllowed; // O(1) lookup for poll hat permission
    }

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.directdemocracy.storage
    struct Layout {
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        uint256[] votingHatIds; // Array of voting hat IDs
        uint256[] creatorHatIds; // Array of creator hat IDs
        uint8 quorumPercentage; // 1‑100
        Proposal[] _proposals;
        bool _paused; // Inline pausable state
        uint256 _lock; // Inline reentrancy guard state
    }

    // keccak256("poa.directdemocracy.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x1da04eb4a741346cdb49b5da943a0c13e79399ef962f913efcd36d95ee6d7c38;

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
        require(!_layout()._paused, "Pausable: paused");
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

    /* ─────────── Inline ReentrancyGuard Implementation ─────────── */
    modifier nonReentrant() {
        require(_layout()._lock == 0, "ReentrancyGuard: reentrant call");
        _layout()._lock = 1;
        _;
        _layout()._lock = 0;
    }

    /* ─────────── Events ─────────── */
    event HatSet(uint256 hat, bool allowed);
    event CreatorHatSet(uint256 hat, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created);
    event NewHatProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created, uint256[] hatIds);
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
        uint256[] calldata initialCreatorHats,
        address[] calldata initialTargets,
        uint8 quorumPct
    ) external initializer {
        if (hats_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        VotingMath.validateQuorum(quorumPct);

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.executor = IExecutor(executor_);
        l.quorumPercentage = quorumPct;
        l._paused = false; // Initialize paused state
        l._lock = 0; // Initialize reentrancy guard state
        emit QuorumPercentageSet(quorumPct);

        uint256 len = initialHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.votingHatIds, initialHats[i], true);
            unchecked {
                ++i;
            }
        }
        len = initialCreatorHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.creatorHatIds, initialCreatorHats[i], true);
            unchecked {
                ++i;
            }
        }
        len = initialTargets.length;
        for (uint256 i; i < len;) {
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
        Layout storage l = _layout();
        HatManager.setHatInArray(l.votingHatIds, h, ok);
        emit HatSet(h, ok);
    }

    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.creatorHatIds, h, ok);
        emit CreatorHatSet(h, ok);
    }

    function setTargetAllowed(address t, bool ok) external onlyExecutor {
        _layout().allowedTarget[t] = ok;
        emit TargetAllowed(t, ok);
    }

    function setQuorumPercentage(uint8 q) external onlyExecutor {
        VotingMath.validateQuorum(q);
        _layout().quorumPercentage = q;
        emit QuorumPercentageSet(q);
    }

    /* ─────────── Modifiers ─────────── */
    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canCreate = HatManager.hasAnyHat(l.hats, l.creatorHatIds, _msgSender());
            if (!canCreate) revert Unauthorized();
        }
        _;
    }

    modifier onlyVoter() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canVote = HatManager.hasAnyHat(l.hats, l.votingHatIds, _msgSender());
            if (!canVote) revert Unauthorized();
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
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            uint256 batchLen = batches[i].length;
            if (batchLen > 0) {
                if (batchLen > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < batchLen;) {
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
    function createHatPoll(bytes calldata metadata, uint32 minutesDuration, uint8 numOptions, uint256[] calldata hatIds)
        external
        onlyCreator
        whenNotPaused
    {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            p.options.push(PollOption(0));
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

    /* ─────────── Voting ─────────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        onlyVoter
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();
        Layout storage l = _layout();

        Proposal storage p = l._proposals[id];
        if (p.restricted) {
            bool hasAllowedHat = false;
            // Check if user has any of the poll-specific hats
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

        VotingMath.validateWeights(weights, idxs, p.options.length);

        p.hasVoted[_msgSender()] = true;
        unchecked {
            p.totalWeight += 100;
        }

        uint256 len = idxs.length;
        for (uint256 i; i < len;) {
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
            uint256 len = batch.length;
            for (uint256 i; i < len;) {
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
        uint256 len = voters.length;
        for (uint256 i; i < len && i < 4_000;) {
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
        uint256 len = p.options.length;
        for (uint256 i; i < len;) {
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
        ok = VotingMath.meetsQuorum(hi, second, p.totalWeight, l.quorumPercentage);
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
        return l._proposals[id].pollHatAllowed[hat];
    }

    function pollRestricted(uint256 id) external view returns (bool) {
        Layout storage l = _layout();
        if (id >= l._proposals.length) revert InvalidProposal();
        return l._proposals[id].restricted;
    }

    /* ─────────── Hat Management View Functions ─────────── */
    function getVotingHats() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().votingHatIds);
    }

    function getCreatorHats() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().creatorHatIds);
    }

    function votingHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().votingHatIds);
    }

    function creatorHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().creatorHatIds);
    }

    function isVotingHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().votingHatIds, hatId);
    }

    function isCreatorHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().creatorHatIds, hatId);
    }
}
