// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* ──────────────────  OpenZeppelin v5.3 Upgradeables  ────────────────── */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

import {IExecutor} from "./Executor.sol";

/* ─────────────────────  External interface  ─────────────────────────── */
interface IMembership {
    function roleOf(address) external view returns (bytes32);
    function canVote(address) external view returns (bool);
}

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

    /* ─────────── Constants ─────────── */
    bytes4 public constant MODULE_ID = 0x6464766f; /* "ddvo"  */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION_MIN = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION_MIN = 10; /* spam guard */

    /* ─────────── Storage ─────────── */
    IMembership public membership;
    IExecutor public executor;

    mapping(address => bool) public allowedTarget; // execution allow‑list
    mapping(bytes32 => bool) private _allowedRoles; // who can create proposals

    uint8 public quorumPercentage; // 1‑100

    struct PollOption {
        uint96 votes;
    }

    struct Proposal {
        uint128 totalWeight; // voters × 100
        uint64 endTimestamp;
        PollOption[] options;
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches; // per‑option execution
    }

    Proposal[] private _proposals;

    /* ─────────── Events ─────────── */
    event RoleSet(bytes32 role, bool allowed);
    event NewProposal(uint256 id, string ipfs, uint64 endTs, uint64 created);
    event PollOptionNames(uint256 id, uint256 idx, string name);
    event VoteCast(uint256 id, address voter, uint16[] idxs, uint8[] weights);
    event Winner(uint256 id, uint256 winningIdx, bool valid);
    event ExecutorUpdated(address newExecutor);
    event TargetAllowed(address target, bool allowed);
    event ProposalCleaned(uint256 id, uint256 cleaned);
    event QuorumPercentageSet(uint8 pct);

    /* ─────────── Initialiser ─────────── */
    constructor() initializer {}

    function initialize(
        address membership_,
        address executor_,
        bytes32[] calldata initialRoles,
        address[] calldata initialTargets,
        uint8 quorumPct
    ) external initializer {
        if (membership_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        require(quorumPct > 0 && quorumPct <= 100, "quorum");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        membership = IMembership(membership_);
        executor = IExecutor(executor_);
        quorumPercentage = quorumPct;
        emit QuorumPercentageSet(quorumPct);

        for (uint256 i; i < initialRoles.length; ++i) {
            _allowedRoles[initialRoles[i]] = true;
            emit RoleSet(initialRoles[i], true);
        }
        for (uint256 i; i < initialTargets.length; ++i) {
            allowedTarget[initialTargets[i]] = true;
            emit TargetAllowed(initialTargets[i], true);
        }
    }

    /* ─────────── Admin (executor‑gated) ─────────── */
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

    function setQuorumPercentage(uint8 q) external onlyExecutor {
        require(q > 0 && q <= 100, "quorum");
        quorumPercentage = q;
        emit QuorumPercentageSet(q);
    }

    /* ─────────── Modifiers ─────────── */
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

    /* ────────── Proposal Creation ────────── */
    function createProposal(
        string calldata ipfsCID,
        uint32 minutesDuration,
        string[] calldata names,
        IExecutor.Call[][] calldata batches
    ) external onlyCreator whenNotPaused {
        if (names.length == 0 || names.length != batches.length) revert LengthMismatch();
        if (names.length > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

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
            p.options.push(PollOption(0));
            p.batches.push(batches[i]);
            emit PollOptionNames(id, i, names[i]);
        }
        emit NewProposal(id, ipfsCID, endTs, uint64(block.timestamp));
    }

    /* ─────────── Voting ─────────── */
    function vote(uint256 id, uint16[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();
        if (_msgSender() != address(executor) && !membership.canVote(_msgSender())) revert Unauthorized();

        Proposal storage p = _proposals[id];
        if (p.hasVoted[_msgSender()]) revert AlreadyVoted();

        uint256 seen;
        uint256 sum;
        for (uint256 i; i < idxs.length; ++i) {
            uint16 ix = idxs[i];
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

        p.hasVoted[_msgSender()] = true;
        unchecked {
            p.totalWeight += 100;
        }

        for (uint256 i; i < idxs.length; ++i) {
            unchecked {
                p.options[idxs[i]].votes += uint96(weights[i]);
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
        IExecutor.Call[] storage batch = _proposals[id].batches[winner];

        if (valid && batch.length > 0) {
            for (uint256 i; i < batch.length; ++i) {
                if (batch[i].target == address(this)) revert TargetSelf();
                if (!allowedTarget[batch[i].target]) revert TargetNotAllowed();
            }
            executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }

    /* ─────────── Cleanup ─────────── */
    function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
        Proposal storage p = _proposals[id];
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

    /* ─────────── View helpers ─────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Proposal storage p = _proposals[id];
        uint96 hi;
        uint96 second;
        for (uint256 i; i < p.options.length; ++i) {
            uint96 v = p.options[i].votes;
            if (v > hi) {
                second = hi;
                hi = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
        }
        ok = (uint256(hi) * 100 > uint256(p.totalWeight) * quorumPercentage) && (hi > second);
    }

    function proposalsCount() external view returns (uint256) {
        return _proposals.length;
    }

    /* ─────────── Version / ID ─────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    uint256[60] private __gap; // storage gap
}
