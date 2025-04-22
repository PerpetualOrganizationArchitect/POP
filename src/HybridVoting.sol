// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* ─────────── External interfaces ─────────── */
interface IMembership {
    function roleOf(address) external view returns (bytes32);
}

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

    /* ─────── Constants ─────── */
    bytes4 public constant MODULE_ID = 0x68766f74; /* "hfot" */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION = 10; /* 10 min   */

    /* ─────── Config / storage ─────── */
    IERC20 public participationToken;
    IMembership public membership;
    IExecutor public executor;

    mapping(address => bool) public allowedTarget; // execution allow‑list
    mapping(bytes32 => bool) private _allowedRoles; // who can create

    uint8 public quorumPct; // 1‑100
    uint8 public ddSharePct; // e.g. 50 = 50 %
    bool public quadraticVoting;
    uint256 public MIN_BAL; // min PT balance to participate

    /* ─────── Vote bookkeeping ───────
       We store RAW points:

       * Each DD voter contributes **100** raw points in total,
         distributed per‑option according to weights.
       * Each PT voter contributes **ptPower×100** raw points in total.
    */
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

    Proposal[] private _proposals;

    /* ─────── Events ─────── */
    event RoleSet(bytes32 role, bool allowed);
    event TargetAllowed(address target, bool allowed);
    event NewProposal(uint256 id, string ipfsCID, uint64 endTs, uint64 created);
    event PollOptionNames(uint256 id, uint256 idx, string name);
    event VoteCast(uint256 id, address voter, uint16[] idxs, uint8[] weights);
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
        address membership_,
        address token_,
        address executor_,
        bytes32[] calldata initialRoles,
        address[] calldata initialTargets,
        uint8 quorum_,
        uint8 ddShare_,
        bool quadratic_,
        uint256 minBalance_
    ) external initializer {
        if (membership_ == address(0) || token_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }

        require(quorum_ > 0 && quorum_ <= 100, "quorum");
        require(ddShare_ <= 100, "split");
        require(minBalance_ > 0, "minBalance");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        membership = IMembership(membership_);
        participationToken = IERC20(token_);
        executor = IExecutor(executor_);

        quorumPct = quorum_;
        emit QuorumSet(quorum_);
        ddSharePct = ddShare_;
        emit SplitSet(ddShare_);
        quadraticVoting = quadratic_;
        emit QuadraticToggled(quadratic_);
        MIN_BAL = minBalance_;
        emit MinBalanceSet(minBalance_);

        for (uint256 i; i < initialRoles.length; ++i) {
            _allowedRoles[initialRoles[i]] = true;
            emit RoleSet(initialRoles[i], true);
        }
        for (uint256 i; i < initialTargets.length; ++i) {
            allowedTarget[initialTargets[i]] = true;
            emit TargetAllowed(initialTargets[i], true);
        }
    }

    /* ─────── Governance setters (executor‑gated) ─────── */
    modifier onlyExecutor() {
        if (_msgSender() != address(executor)) revert Unauthorized();
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
        executor = IExecutor(a);
        emit ExecutorUpdated(a);
    }

    function setRoleAllowed(bytes32 r, bool ok) external onlyExecutor {
        _allowedRoles[r] = ok;
        emit RoleSet(r, ok);
    }

    function setTargetAllowed(address t, bool ok) external onlyExecutor {
        allowedTarget[t] = ok;
        emit TargetAllowed(t, ok);
    }

    function setQuorum(uint8 q) external onlyExecutor {
        require(q > 0 && q <= 100, "quorum");
        quorumPct = q;
        emit QuorumSet(q);
    }

    function setSplit(uint8 s) external onlyExecutor {
        require(s <= 100, "split");
        ddSharePct = s;
        emit SplitSet(s);
    }

    function toggleQuadratic() external onlyExecutor {
        quadraticVoting = !quadraticVoting;
        emit QuadraticToggled(quadraticVoting);
    }

    function setMinBalance(uint256 n) external onlyExecutor {
        MIN_BAL = n;
        emit MinBalanceSet(n);
    }

    /* ─────── Helpers & modifiers ─────── */
    modifier onlyCreator() {
        if (_msgSender() != address(executor) && !_allowedRoles[membership.roleOf(_msgSender())]) {
            revert Unauthorized();
        }
        _;
    }

    modifier exists(uint256 id) {
        if (id >= _proposals.length) revert InvalidProposal();
        _;
    }

    modifier notExpired(uint256 id) {
        if (block.timestamp > _proposals[id].endTimestamp) revert VotingExpired();
        _;
    }

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _proposals[id].endTimestamp) revert VotingOpen();
        _;
    }

    /* ─────── Proposal creation ─────── */
    function createProposal(
        string calldata ipfsCID,
        uint32 minutesDuration,
        string[] calldata names,
        IExecutor.Call[][] calldata batches
    ) external onlyCreator whenNotPaused {
        if (names.length == 0 || names.length != batches.length) revert LengthMismatch();
        if (names.length > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) revert DurationOutOfRange();

        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = _proposals.push();
        p.endTimestamp = endTs;

        uint256 id = _proposals.length - 1;
        for (uint256 i; i < names.length; ++i) {
            if (batches[i].length > 0) {
                if (batches[i].length > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < batches[i].length; ++j) {
                    if (!allowedTarget[batches[i][j].target]) revert TargetNotAllowed();
                    if (batches[i][j].target == address(this)) revert TargetSelf();
                }
            }
            p.options.push(PollOption(0, 0));
            p.batches.push(batches[i]);
            emit PollOptionNames(id, i, names[i]);
        }
        emit NewProposal(id, ipfsCID, endTs, uint64(block.timestamp));
    }

    /* ─────── Voting ─────── */
    function vote(uint256 id, uint16[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();

        Proposal storage p = _proposals[id];
        if (p.hasVoted[_msgSender()]) revert AlreadyVoted();

        /* collect raw powers */
        bool hasRole = _allowedRoles[membership.roleOf(_msgSender())];
        uint256 ddRawVoter = hasRole ? 100 : 0; // always 0 or 100
        uint256 bal = participationToken.balanceOf(_msgSender());
        if (bal < MIN_BAL) bal = 0;
        uint256 ptPower = (bal == 0) ? 0 : (quadraticVoting ? Math.sqrt(bal) : bal);
        uint256 ptRawVoter = ptPower * 100; // raw numerator

        if (ddRawVoter == 0 && ptRawVoter == 0) revert Unauthorized();

        /* weight sanity */
        uint256 sum;
        uint256 seen;
        for (uint256 i; i < weights.length; ++i) {
            uint16 ix = idxs[i];
            if (ix >= p.options.length) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;
            if (weights[i] > 100) revert InvalidWeight();
            sum += weights[i];
        }
        if (sum != 100) revert WeightSumNot100(sum);

        /* store raws */
        for (uint256 i; i < weights.length; ++i) {
            uint16 ix = idxs[i];
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
        Proposal storage p = _proposals[id];

        if (p.ddTotalRaw == 0 && p.ptTotalRaw == 0) {
            emit Winner(id, 0, false);
            return (0, false);
        }

        uint256 sliceDD = ddSharePct;
        uint256 slicePT = 100 - ddSharePct;
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

        valid = (hi * 100 >= uint256(sliceDD + slicePT) * quorumPct) && (hi > second);

        IExecutor.Call[] storage batch = p.batches[winner];
        if (valid && batch.length > 0) {
            for (uint256 i; i < batch.length; ++i) {
                if (!allowedTarget[batch[i].target]) revert TargetNotAllowed();
            }
            executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }
    /* ─────── Cleanup (storage‑refund helper) ─────── */

    function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
        Proposal storage p = _proposals[id];

        // nothing to do?
        require(p.batches.length > 0 || voters.length > 0, "nothing");

        uint256 cleaned;
        // cap loop to stay well below the 4 million refund limit
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
        return _proposals.length;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    uint256[60] private __gap;
}
