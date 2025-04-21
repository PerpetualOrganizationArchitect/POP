// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* OpenZeppelin v5.3 Upgradeables */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/* ─────────── External Interfaces ─────────── */
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function canVote(address user) external view returns (bool);
}

interface IExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function execute(uint256 proposalId, Call[] calldata batch) external;
}

/// @notice Direct‑democracy governor: every eligible voter gets **100 points** per proposal
///         to distribute across options.  _Quorum is weight‑based_.
contract DirectDemocracyVoting is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
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
    error EmptyBatch();
    error ZeroAddress();

    /* ───────────── Constants ───────────── */
    bytes4 public constant MODULE_ID = 0x6464766f; /* "ddvo" */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION_MIN = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION_MIN = 10; /* spam guard */

    /* ───────────── Storage ───────────── */
    IMembership public membership;
    IExecutor public executor;

    mapping(address => bool) public allowedTarget; // executor allow‑list
    mapping(bytes32 => bool) private _allowedRoles;

    uint8 public quorumPercentage; // 1‑100

    struct PollOption {
        uint96 votes;
    }

    struct Proposal {
        uint128 totalWeight; // each voter adds exactly 100
        uint64 endTimestamp;
        PollOption[] options;
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches; // winner batch forwarded to executor
    }

    Proposal[] private _proposals;

    /* ───────────── Events ───────────── */
    event RoleSet(bytes32 role, bool allowed);
    event NewProposal(uint256 indexed id, string ipfsCID, uint64 endTs, uint64 createdAt);
    event PollOptionNames(uint256 indexed id, uint256 indexed idx, string name);
    event VoteCast(uint256 indexed id, address indexed voter, uint16[] idxs, uint8[] weights);
    event Winner(uint256 indexed id, uint256 winningIdx, bool valid);
    event ExecutorUpdated(address newExecutor);
    event TargetAllowed(address target, bool allowed);
    event ProposalCleaned(uint256 indexed id, uint256 cleaned);
    event QuorumPercentageSet(uint8 newQuorumPct);
    /* ─────────── Initialiser ─────────── */

    constructor() initializer {}

    function initialize(
        address owner_,
        address membership_,
        address executor_,
        bytes32[] calldata initialRoles,
        address[] calldata initialTargets,
        uint8 quorumPct
    ) external initializer {
        if (owner_ == address(0) || membership_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        require(quorumPct > 0 && quorumPct <= 100, "quorum");

        __Ownable_init(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();

        membership = IMembership(membership_);
        executor = IExecutor(executor_);
        quorumPercentage = quorumPct;

        for (uint256 i; i < initialRoles.length; ++i) {
            _allowedRoles[initialRoles[i]] = true;
            emit RoleSet(initialRoles[i], true);
        }
        for (uint256 i; i < initialTargets.length; ++i) {
            allowedTarget[initialTargets[i]] = true;
            emit TargetAllowed(initialTargets[i], true);
        }
    }

    /* ────────── Guardian helpers ────────── */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ─────────── Governance setters ─────────── */
    function setExecutor(address newExec) external onlyOwner {
        if (newExec == address(0)) revert ZeroAddress();
        executor = IExecutor(newExec);
        emit ExecutorUpdated(newExec);
    }

    function setRoleAllowed(bytes32 role, bool allowed) external onlyOwner {
        _allowedRoles[role] = allowed;
        emit RoleSet(role, allowed);
    }

    function setTargetAllowed(address target, bool allowed) external onlyOwner {
        allowedTarget[target] = allowed;
        emit TargetAllowed(target, allowed);
    }

    function setQuorumPercentage(uint8 newQuorumPct) external onlyOwner {
        require(newQuorumPct > 0 && newQuorumPct <= 100, "quorum");
        quorumPercentage = newQuorumPct;
        emit QuorumPercentageSet(newQuorumPct);
    }

    /* ───────────── Modifiers ───────────── */
    modifier onlyCreator() {
        if (!_allowedRoles[membership.roleOf(msg.sender)]) revert Unauthorized();
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
        string[] calldata optionNames,
        IExecutor.Call[][] calldata optionBatches
    ) external onlyCreator whenNotPaused {
        if (optionNames.length == 0 || optionNames.length != optionBatches.length) {
            revert LengthMismatch();
        }
        if (optionNames.length > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) {
            revert DurationOutOfRange();
        }

        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = _proposals.push();
        p.endTimestamp = endTs;

        uint256 id = _proposals.length - 1;
        for (uint256 i; i < optionNames.length; ++i) {
            if (optionBatches[i].length == 0) revert EmptyBatch();
            if (optionBatches[i].length > MAX_CALLS) revert TooManyCalls();

            for (uint256 j; j < optionBatches[i].length; ++j) {
                if (!allowedTarget[optionBatches[i][j].target]) revert TargetNotAllowed();
                if (optionBatches[i][j].target == address(this)) revert TargetSelf();
            }
            p.options.push(PollOption(0));
            p.batches.push(optionBatches[i]);
            emit PollOptionNames(id, i, optionNames[i]);
        }
        emit NewProposal(id, ipfsCID, endTs, uint64(block.timestamp));
    }

    /* ─────────────── Voting ─────────────── */
    function vote(uint256 id, uint16[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();
        if (!membership.canVote(msg.sender)) revert Unauthorized();

        Proposal storage p = _proposals[id];
        if (p.hasVoted[msg.sender]) revert AlreadyVoted();

        uint256 seen;
        uint256 sum;
        uint256 len = idxs.length;

        for (uint256 i; i < len; ++i) {
            uint16 ix = idxs[i];
            if (ix >= p.options.length) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;

            uint8 wt = weights[i];
            if (wt > 100) revert InvalidWeight();
            unchecked {
                sum += wt;
            }
        }
        if (sum != 100) revert WeightSumNot100(sum);

        p.hasVoted[msg.sender] = true;
        unchecked {
            p.totalWeight += 100;
        } // each voter contributes 100

        for (uint256 i; i < len; ++i) {
            unchecked {
                p.options[idxs[i]].votes += uint96(weights[i]);
            }
        }
        emit VoteCast(id, msg.sender, idxs, weights);
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
        if (valid) {
            IExecutor.Call[] storage batch = _proposals[id].batches[winner];
            for (uint256 i; i < batch.length; ++i) {
                if (!allowedTarget[batch[i].target]) revert TargetNotAllowed();
            }
            executor.execute(id, batch);
        }
        emit Winner(id, winner, valid);
    }

    /**
     * @notice Delete heavy storage of an expired proposal to save refund gas.
     *  Anyone can call, but cap batch size to avoid OOG.
     */
    function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
        Proposal storage p = _proposals[id];
        require(p.batches.length > 0 || voters.length > 0, "nothing");
        uint256 cleaned;
        for (uint256 i; i < voters.length && i < 4_000; ++i) {
            // 4k ≈ refund cap
            if (p.hasVoted[voters[i]]) {
                delete p.hasVoted[voters[i]];
                unchecked {
                    ++cleaned;
                }
            }
        }
        if (cleaned == 0 && p.batches.length > 0) {
            delete p.batches; // one‑shot after first call
        }
        emit ProposalCleaned(id, cleaned);
    }

    /* ───────────── View helpers ───────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Proposal storage p = _proposals[id];
        uint96 high;
        uint96 second;
        for (uint256 i; i < p.options.length; ++i) {
            uint96 v = p.options[i].votes;
            if (v > high) {
                second = high;
                high = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
        }
        ok = (uint256(high) * 100 > uint256(p.totalWeight) * quorumPercentage) && (high > second);
    }

    function proposalsCount() external view returns (uint256) {
        return _proposals.length;
    }

    /* ───────────── Version ───────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    /* ───────────── Storage gap ───────────── */
    uint256[50] private __gap; // storage gap
}
