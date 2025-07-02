// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {IExecutor} from "./Executor.sol";

/* ─────────────────── HybridVoting ─────────────────── */
contract HybridVoting is Initializable, ContextUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    /* ─────── Errors ─────── */
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
    error InvalidMetadata();

    /* ─────── Constants ─────── */
    bytes4 public constant MODULE_ID = 0x68766f74; /* "hfot" */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION = 10; /* 10 min   */
    
    /* ─────── Hat Type Enum ─────── */
    enum HatType { VOTING, DEMOCRACY, CREATOR }
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
    }

    /* ─────── ERC-7201 Storage ─────── */
    /// @custom:storage-location erc7201:poa.hybridvoting.storage
    struct Layout {
        /* Config / Storage */
        IERC20 participationToken;
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        uint256[] _votingHatIds; // array of allowed voting hat IDs (permission to vote)
        uint256[] _democracyHatIds; // array of democracy power hat IDs (DD voting power)
        uint256[] _creatorHatIds; // array of allowed creator hat IDs
        uint8 quorumPct; // 1‑100
        uint8 ddSharePct; // e.g. 50 = 50 %
        bool quadraticVoting;
        uint256 MIN_BAL; // min PT balance to participate
        /* Vote Bookkeeping */
        Proposal[] _proposals;
    }

    // keccak256("poa.hybridvoting.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x5ca2a7292ae8f852850852b5f984e5237d39f3240052e7ba31e27bf071bdb62b;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────── Events ─────── */
    event HatSet(uint256 hat, bool allowed);
    event DemocracyHatSet(uint256 hat, bool allowed);
    event CreatorHatSet(uint256 hat, bool allowed);
    event TargetAllowed(address target, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint8 numOptions, uint64 endTs, uint64 created);
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

        require(quorum_ > 0 && quorum_ <= 100, "quorum");
        require(ddShare_ <= 100, "split");
        require(minBalance_ > 0, "minBalance");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.participationToken = IERC20(token_);
        l.executor = IExecutor(executor_);

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
        
        for (uint256 i; i < votingHats.length; ++i) {
            l._votingHatIds.push(votingHats[i]);
            emit HatSet(votingHats[i], true);
        }
        for (uint256 i; i < democracyHats.length; ++i) {
            l._democracyHatIds.push(democracyHats[i]);
            emit DemocracyHatSet(democracyHats[i], true);
        }
        for (uint256 i; i < creatorHats.length; ++i) {
            l._creatorHatIds.push(creatorHats[i]);
            emit CreatorHatSet(creatorHats[i], true);
        }
    }

    function _initializeTargets(address[] calldata targets) internal {
        Layout storage l = _layout();
        for (uint256 i; i < targets.length; ++i) {
            l.allowedTarget[targets[i]] = true;
            emit TargetAllowed(targets[i], true);
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

    function setExecutor(address a) external onlyExecutor {
        if (a == address(0)) revert ZeroAddress();
        _layout().executor = IExecutor(a);
        emit ExecutorUpdated(a);
    }

    /* ─────── Consolidated Hat Management ─────── */
    function setHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.VOTING);
        emit HatSet(h, ok);
    }

    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.CREATOR);
        emit CreatorHatSet(h, ok);
    }

    function setTargetAllowed(address t, bool ok) external onlyExecutor {
        _layout().allowedTarget[t] = ok;
        emit TargetAllowed(t, ok);
    }

    function setQuorum(uint8 q) external onlyExecutor {
        require(q > 0 && q <= 100, "quorum");
        _layout().quorumPct = q;
        emit QuorumSet(q);
    }

    function setSplit(uint8 s) external onlyExecutor {
        require(s <= 100, "split");
        _layout().ddSharePct = s;
        emit SplitSet(s);
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

    function setDemocracyHatAllowed(uint256 h, bool ok) external onlyExecutor {
        _setHatAllowed(h, ok, HatType.DEMOCRACY);
        emit DemocracyHatSet(h, ok);
    }

    function _setHatAllowed(uint256 h, bool ok, HatType hatType) internal {
        Layout storage l = _layout();
        
        if (hatType == HatType.VOTING) {
            _updateHatArray(l._votingHatIds, h, ok);
        } else if (hatType == HatType.DEMOCRACY) {
            _updateHatArray(l._democracyHatIds, h, ok);
        } else {
            _updateHatArray(l._creatorHatIds, h, ok);
        }
    }

    function _updateHatArray(uint256[] storage hatArray, uint256 h, bool ok) internal {
        (bool wasAllowed, uint256 existingIndex) = _findHatIndex(hatArray, h);
        
        if (ok && !wasAllowed) {
            hatArray.push(h);
        } else if (!ok && wasAllowed) {
            hatArray[existingIndex] = hatArray[hatArray.length - 1];
            hatArray.pop();
        }
    }

    function _findHatIndex(uint256[] storage hatArray, uint256 h) internal view returns (bool found, uint256 index) {
        for (uint256 i = 0; i < hatArray.length; i++) {
            if (hatArray[i] == h) {
                return (true, i);
            }
        }
        return (false, 0);
    }

    /* ─────── Helpers & modifiers ─────── */
    function _checkPermission(HatType requiredType) internal view {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor) && !_hasHat(_msgSender(), requiredType)) {
            revert Unauthorized();
        }
    }

    modifier onlyCreator() {
        _checkPermission(HatType.CREATOR);
        _;
    }

    modifier onlyVoter() {
        _checkPermission(HatType.VOTING);
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
        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions; ++i) {
            if (batches[i].length > 0) {
                if (batches[i].length > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < batches[i].length; ++j) {
                    if (!l.allowedTarget[batches[i][j].target]) revert TargetNotAllowed();
                    if (batches[i][j].target == address(this)) revert TargetSelf();
                }
            }
            p.options.push(PollOption(0, 0));
            p.batches.push(batches[i]);
        }
        emit NewProposal(id, metadata, numOptions, endTs, uint64(block.timestamp));
    }

    /* ─────── Voting ─────── */
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
        if (p.hasVoted[_msgSender()]) revert AlreadyVoted();

        /* collect raw powers */
        bool hasDemocracyHat = (_msgSender() == address(l.executor)) || _hasHat(_msgSender(), HatType.DEMOCRACY);
        
        uint256 ddRawVoter = hasDemocracyHat ? 100 : 0; // DD power only if has democracy hat
        uint256 bal = l.participationToken.balanceOf(_msgSender());
        if (bal < l.MIN_BAL) bal = 0;
        uint256 ptPower = (bal == 0) ? 0 : (l.quadraticVoting ? Math.sqrt(bal) : bal);
        uint256 ptRawVoter = ptPower * 100; // raw numerator

        /* weight sanity */
        uint256 sum;
        uint256 seen;
        for (uint256 i; i < weights.length; ++i) {
            uint8 ix = idxs[i];
            if (ix >= p.options.length) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;
            if (weights[i] > 100) revert InvalidWeight();
            sum += weights[i];
        }
        if (sum != 100) revert WeightSumNot100(sum);

        /* store raws */
        for (uint256 i; i < weights.length; ++i) {
            uint8 ix = idxs[i];
            uint8 w = weights[i];
            if (ddRawVoter > 0) p.options[ix].ddRaw += uint128(ddRawVoter * w / 100);
            if (ptRawVoter > 0) p.options[ix].ptRaw += uint128(ptRawVoter * w / 100);
        }
        p.ddTotalRaw += ddRawVoter;
        p.ptTotalRaw += ptRawVoter;
        p.hasVoted[_msgSender()] = true;

        emit VoteCast(id, _msgSender(), idxs, weights);
    }

    /* ─────── Winner & execution ─────── */
    function announceWinner(uint256 id)
        external
        nonReentrant
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

        uint256 sliceDD = l.ddSharePct;
        uint256 slicePT = 100 - l.ddSharePct;
        uint256 hi;
        uint256 second;

        for (uint256 i; i < p.options.length; ++i) {
            /* scale each slice to its fixed share */
            uint256 scaledDD = (p.ddTotalRaw == 0) ? 0 : (uint256(p.options[i].ddRaw) * sliceDD) / p.ddTotalRaw;

            uint256 scaledPT = (p.ptTotalRaw == 0) ? 0 : (uint256(p.options[i].ptRaw) * slicePT) / p.ptTotalRaw;

            uint256 totalScaled = scaledDD + scaledPT; // ∈ [0,100]

            if (totalScaled > hi) {
                second = hi;
                hi = totalScaled;
                winner = i;
            } else if (totalScaled > second) {
                second = totalScaled;
            }
        }

        valid = (hi * 100 >= uint256(sliceDD + slicePT) * l.quorumPct) && (hi > second);

        IExecutor.Call[] storage batch = p.batches[winner];
        if (valid && batch.length > 0) {
            for (uint256 i; i < batch.length; ++i) {
                if (!l.allowedTarget[batch[i].target]) revert TargetNotAllowed();
            }
            l.executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }

    /* ─────── Cleanup (storage‑refund helper) ─────── */
    function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];

        // nothing to do?
        require(p.batches.length > 0 || voters.length > 0, "nothing");

        uint256 cleaned;
        // cap loop to stay well below the 4 million refund limit
        for (uint256 i; i < voters.length && i < 4_000; ++i) {
            if (p.hasVoted[voters[i]]) {
                delete p.hasVoted[voters[i]];
                unchecked {
                    ++cleaned;
                }
            }
        }

        // once all voters are wiped you can also clear the call‑batches
        if (cleaned == 0 && p.batches.length > 0) {
            delete p.batches;
        }

        emit ProposalCleaned(id, cleaned);
    }

    /* ─────── View helpers ─────── */
    function proposalsCount() external view returns (uint256) {
        return _layout()._proposals.length;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    /* ─────── Public getters for storage variables ─────── */
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

    function quorumPct() external view returns (uint8) {
        return _layout().quorumPct;
    }

    function ddSharePct() external view returns (uint8) {
        return _layout().ddSharePct;
    }

    function quadraticVoting() external view returns (bool) {
        return _layout().quadraticVoting;
    }

    function MIN_BAL() external view returns (uint256) {
        return _layout().MIN_BAL;
    }

    /* ─────── Consolidated Hat Checking ─────── */
    function _hasHat(address user, HatType hatType) internal view returns (bool) {
        Layout storage l = _layout();
        
        if (hatType == HatType.VOTING) {
            return _checkHatArray(l._votingHatIds, user, l.hats);
        } else if (hatType == HatType.DEMOCRACY) {
            return _checkHatArray(l._democracyHatIds, user, l.hats);
        } else {
            return _checkHatArray(l._creatorHatIds, user, l.hats);
        }
    }

    function _checkHatArray(uint256[] storage hatArray, address user, IHats hatsContract) internal view returns (bool) {
        for (uint256 i = 0; i < hatArray.length; i++) {
            if (hatsContract.isWearerOfHat(user, hatArray[i])) {
                return true;
            }
        }
        return false;
    }

    /* ─────── Legacy Helper Functions (for compatibility) ─────── */
    function _hasVotingHat(address user) internal view returns (bool) {
        return _hasHat(user, HatType.VOTING);
    }

    function _hasCreatorHat(address user) internal view returns (bool) {
        return _hasHat(user, HatType.CREATOR);
    }

    function _hasDemocracyHat(address user) internal view returns (bool) {
        return _hasHat(user, HatType.DEMOCRACY);
    }
}
