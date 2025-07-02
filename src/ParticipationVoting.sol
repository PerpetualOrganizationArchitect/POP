// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutor} from "./Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

/// Participation‑weighted governor (power = balance or √balance)
contract ParticipationVoting is Initializable, ContextUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /* ─────────────── Errors ─────────────── */
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
    error ZeroAddress();
    error MinBalance();
    error Overflow();
    error InvalidMetadata();
    error RoleNotAllowed();

    /* ───────────── Constants ───────────── */
    bytes4 public constant MODULE_ID = 0x70766F74; /* "pvot" */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION_MIN = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION_MIN = 10;

    /* ─────────── Hat Type Enum ─────────── */
    enum HatType {
        VOTING,
        CREATOR
    }

    /* ───────────── Data Structures ───────────── */
    struct PollOption {
        uint128 votes;
    }

    struct Proposal {
        uint128 totalWeight; // sum(power)
        uint64 endTimestamp;
        PollOption[] options;
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches; // can be empty
        uint256[] pollHatIds; // array of specific hat IDs for this poll
        bool restricted; // if true only pollHatIds can vote
        mapping(uint256 => bool) pollHatAllowed; // O(1) lookup for poll hat permission
    }

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.participationvoting.storage
    struct Layout {
        IERC20 participationToken;
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget;
        uint256[] votingHatIds; // enumeration array for voting hats
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint8 quorumPercentage; // 1‑100
        bool quadraticVoting; // toggle
        uint256 MIN_BAL; /* sybil floor */
        Proposal[] _proposals;
    }

    // keccak256("poa.participationvoting.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x961be98db34d61d2a5ef5b5cbadc7db40d3e0d4bad8902c41a8b75d5c73b5961;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───────────── Events ───────────── */
    event HatSet(uint256 hat, bool allowed);
    event CreatorHatSet(uint256 hat, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 createdAt);
    event NewHatProposal(
        uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 createdAt, uint256[] hatIds
    );
    event VoteCast(uint256 id, address voter, uint8[] idxs, uint8[] weights);
    event Winner(uint256 id, uint256 winningIdx, bool valid);
    event ExecutorUpdated(address newExecutor);
    event TargetAllowed(address target, bool allowed);
    event ProposalCleaned(uint256 id, uint256 cleaned);
    event QuorumPercentageSet(uint8 pct);
    event QuadraticToggled(bool enabled);
    event MinBalanceSet(uint256 newMinBalance);

    modifier onlyExecutor() {
        if (_msgSender() != address(_layout().executor)) revert Unauthorized();
        _;
    }

    /* ─────────── Initialiser ─────────── */
    constructor() initializer {}

    function initialize(
        address executor_,
        address hats_,
        address token_,
        uint256[] calldata initialHats,
        uint256[] calldata initialCreatorHats,
        address[] calldata initialTargets,
        uint8 quorumPct,
        bool quadratic_,
        uint256 minBalance_
    ) external initializer {
        if (hats_ == address(0) || token_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        require(quorumPct > 0 && quorumPct <= 100, "quorum");
        require(minBalance_ > 0, "minBalance");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.participationToken = IERC20(token_);
        l.executor = IExecutor(executor_);
        l.quorumPercentage = quorumPct;
        l.quadraticVoting = quadratic_;
        l.MIN_BAL = minBalance_;

        emit QuorumPercentageSet(quorumPct);
        emit QuadraticToggled(quadratic_);
        emit MinBalanceSet(minBalance_);

        for (uint256 i; i < initialHats.length; ++i) {
            _setHatAllowed(initialHats[i], true, HatType.VOTING);
        }
        for (uint256 i; i < initialCreatorHats.length; ++i) {
            _setHatAllowed(initialCreatorHats[i], true, HatType.CREATOR);
        }
        for (uint256 i; i < initialTargets.length; ++i) {
            l.allowedTarget[initialTargets[i]] = true;
            emit TargetAllowed(initialTargets[i], true);
        }
    }

    /* ───────────── Governance setters ───────────── */
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
        _setHatAllowed(h, ok, HatType.VOTING);
    }

    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.CREATOR);
    }

    function _setHatAllowed(uint256 h, bool ok, HatType hatType) internal {
        Layout storage l = _layout();

        if (hatType == HatType.VOTING) {
            // Find if hat already exists
            uint256 existingIndex = type(uint256).max;
            for (uint256 i = 0; i < l.votingHatIds.length; i++) {
                if (l.votingHatIds[i] == h) {
                    existingIndex = i;
                    break;
                }
            }

            if (ok && existingIndex == type(uint256).max) {
                // Adding new hat (not found)
                l.votingHatIds.push(h);
                emit HatSet(h, true);
            } else if (!ok && existingIndex != type(uint256).max) {
                // Removing hat (found at existingIndex)
                l.votingHatIds[existingIndex] = l.votingHatIds[l.votingHatIds.length - 1];
                l.votingHatIds.pop();
                emit HatSet(h, false);
            }
        } else {
            // Find if hat already exists
            uint256 existingIndex = type(uint256).max;
            for (uint256 i = 0; i < l.creatorHatIds.length; i++) {
                if (l.creatorHatIds[i] == h) {
                    existingIndex = i;
                    break;
                }
            }

            if (ok && existingIndex == type(uint256).max) {
                // Adding new hat (not found)
                l.creatorHatIds.push(h);
                emit CreatorHatSet(h, true);
            } else if (!ok && existingIndex != type(uint256).max) {
                // Removing hat (found at existingIndex)
                l.creatorHatIds[existingIndex] = l.creatorHatIds[l.creatorHatIds.length - 1];
                l.creatorHatIds.pop();
                emit CreatorHatSet(h, false);
            }
        }
    }

    function setTargetAllowed(address t, bool ok) external onlyExecutor {
        if (t == address(0)) revert ZeroAddress();
        _layout().allowedTarget[t] = ok;
        emit TargetAllowed(t, ok);
    }

    function setQuorumPercentage(uint8 q) external onlyExecutor {
        require(q > 0 && q <= 100, "quorum");
        _layout().quorumPercentage = q;
        emit QuorumPercentageSet(q);
    }

    function toggleQuadratic() external onlyExecutor {
        Layout storage l = _layout();
        l.quadraticVoting = !l.quadraticVoting;
        emit QuadraticToggled(l.quadraticVoting);
    }

    function setMinBalance(uint256 n) external onlyExecutor {
        _layout().MIN_BAL = n;
        emit MinBalanceSet(n);
    }

    /* ───────────── Modifiers ───────────── */
    modifier onlyCreator() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canCreate = _hasHat(_msgSender(), HatType.CREATOR);
            if (!canCreate) revert Unauthorized();
        }
        _;
    }

    modifier onlyVoter() {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canVote = _hasHat(_msgSender(), HatType.VOTING);
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
        IExecutor.Call[][] calldata optionBatches
    ) external onlyCreator whenNotPaused {
        if (metadata.length == 0) revert InvalidMetadata();
        if (numOptions == 0 || numOptions != optionBatches.length) revert LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions; ++i) {
            if (optionBatches[i].length > 0) {
                if (optionBatches[i].length > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < optionBatches[i].length; ++j) {
                    if (!l.allowedTarget[optionBatches[i][j].target]) revert TargetNotAllowed();
                    if (optionBatches[i][j].target == address(this)) revert TargetSelf();
                }
            }
            p.options.push(PollOption(0));
            p.batches.push(optionBatches[i]);
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
        for (uint256 i; i < numOptions; ++i) {
            p.options.push(PollOption(0));
            p.batches.push();
        }
        for (uint256 i; i < hatIds.length; ++i) {
            p.pollHatIds.push(hatIds[i]);
            p.pollHatAllowed[hatIds[i]] = true;
        }
        emit NewHatProposal(id, metadata, numOptions, endTs, uint64(block.timestamp), hatIds);
    }

    /* ───────────── Voting ───────────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        onlyVoter
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();

        Layout storage l = _layout();

        uint256 bal = l.participationToken.balanceOf(_msgSender());
        if (bal < l.MIN_BAL) revert MinBalance();
        uint256 power = l.quadraticVoting ? Math.sqrt(bal) : bal;
        require(power > 0, "power=0");

        Proposal storage p = l._proposals[id];
        if (p.restricted) {
            bool hasAllowedHat = false;
            // Check if user has any of the poll-specific hats
            for (uint256 i = 0; i < p.pollHatIds.length; i++) {
                if (l.hats.isWearerOfHat(_msgSender(), p.pollHatIds[i])) {
                    hasAllowedHat = true;
                    break;
                }
            }
            if (!hasAllowedHat) revert RoleNotAllowed();
        }
        if (p.hasVoted[_msgSender()]) revert AlreadyVoted();

        uint256 seen;
        uint256 sum;
        for (uint256 i; i < idxs.length; ++i) {
            uint8 ix = idxs[i];
            if (ix >= p.options.length) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;

            uint8 w = weights[i];
            if (w > 100) revert InvalidWeight();
            unchecked {
                sum += w;
            }
        }
        if (sum != 100) revert WeightSumNot100(sum);

        uint256 newTW = uint256(p.totalWeight) + power;
        if (newTW > type(uint128).max) revert Overflow();
        p.totalWeight = uint128(newTW);
        p.hasVoted[_msgSender()] = true;

        for (uint256 i; i < idxs.length; ++i) {
            uint256 add = power * weights[i];
            uint256 newVotes = uint256(p.options[idxs[i]].votes) + add;
            if (newVotes > type(uint128).max) revert Overflow();
            p.options[idxs[i]].votes = uint128(newVotes);
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
            for (uint256 i; i < batch.length; ++i) {
                if (batch[i].target == address(this)) revert TargetSelf();
                if (!l.allowedTarget[batch[i].target]) revert TargetNotAllowed();
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
        for (uint256 i; i < voters.length && i < 4_000; ++i) {
            if (p.hasVoted[voters[i]]) {
                delete p.hasVoted[voters[i]];
                ++cleaned;
            }
        }
        if (cleaned == 0 && p.batches.length > 0) delete p.batches;
        emit ProposalCleaned(id, cleaned);
    }

    /* ───────────── View helpers ───────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];
        uint128 high;
        uint128 second;
        for (uint256 i; i < p.options.length; ++i) {
            uint128 v = p.options[i].votes;
            if (v > high) {
                second = high;
                high = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
        }
        ok = (uint256(high) * 100 > uint256(p.totalWeight) * l.quorumPercentage) && (high > second);
    }

    function proposalsCount() external view returns (uint256) {
        return _layout()._proposals.length;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    /* ─────────── Public getters for storage variables ─────────── */
    function MIN_BAL() external view returns (uint256) {
        return _layout().MIN_BAL;
    }

    function participationToken() external view returns (IERC20) {
        return _layout().participationToken;
    }

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

    function quadraticVoting() external view returns (bool) {
        return _layout().quadraticVoting;
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

    /* ───────────── Internal Helper Functions ───────────── */
    /// @dev Returns true if `user` wears *any* hat of the requested type.
    function _hasHat(address user, HatType hatType) internal view returns (bool) {
        Layout storage l = _layout();
        uint256[] storage ids = hatType == HatType.VOTING ? l.votingHatIds : l.creatorHatIds;

        uint256 len = ids.length;
        if (len == 0) return false;
        if (len == 1) return l.hats.isWearerOfHat(user, ids[0]); // micro-optimise 1-ID case

        // Build calldata in memory (cheap because ≤ 3)
        address[] memory wearers = new address[](len);
        uint256[] memory hatIds = new uint256[](len);
        for (uint256 i; i < len; ++i) {
            wearers[i] = user;
            hatIds[i] = ids[i];
        }
        uint256[] memory balances = l.hats.balanceOfBatch(wearers, hatIds);
        for (uint256 i; i < balances.length; ++i) {
            if (balances[i] > 0) return true;
        }
        return false;
    }
}
