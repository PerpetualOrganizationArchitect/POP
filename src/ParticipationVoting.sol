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

/* ─────────── External Interfaces ─────────── */
interface IMembership {
    function roleOf(address) external view returns (bytes32);
    function canVote(address) external view returns (bool);
}

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

    /* ───────────── Constants ───────────── */
    bytes4 public constant MODULE_ID = 0x70766F74; /* "pvot" */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION_MIN = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION_MIN = 10;

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
    }

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.participationvoting.storage
    struct Layout {
        IERC20 participationToken;
        IMembership membership;
        IExecutor executor;
        mapping(address => bool) allowedTarget;
        mapping(bytes32 => bool) _allowedRoles;
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
    event RoleSet(bytes32 role, bool allowed);
    event NewProposal(uint256 id, bytes metadata, uint64 endTs, uint64 createdAt);
    event PollOptionNames(uint256 id, uint256 idx, string name);
    event VoteCast(uint256 id, address voter, uint16[] idxs, uint8[] weights);
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
        address membership_,
        address token_,
        bytes32[] calldata initialRoles,
        address[] calldata initialTargets,
        uint8 quorumPct,
        bool quadratic_,
        uint256 minBalance_
    ) external initializer {
        if (membership_ == address(0) || token_ == address(0) || executor_ == address(0)) {
            revert ZeroAddress();
        }
        require(quorumPct > 0 && quorumPct <= 100, "quorum");
        require(minBalance_ > 0, "minBalance");

        __Context_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.membership = IMembership(membership_);
        l.participationToken = IERC20(token_);
        l.executor = IExecutor(executor_);
        l.quorumPercentage = quorumPct;
        l.quadraticVoting = quadratic_;
        l.MIN_BAL = minBalance_;

        emit QuorumPercentageSet(quorumPct);
        emit QuadraticToggled(quadratic_);
        emit MinBalanceSet(minBalance_);

        for (uint256 i; i < initialRoles.length; ++i) {
            l._allowedRoles[initialRoles[i]] = true;
            emit RoleSet(initialRoles[i], true);
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

    function setRoleAllowed(bytes32 r, bool ok) external onlyExecutor {
        _layout()._allowedRoles[r] = ok;
        emit RoleSet(r, ok);
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
        if (_msgSender() != address(l.executor) && !l._allowedRoles[l.membership.roleOf(_msgSender())]) {
            revert Unauthorized();
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
        string[] calldata optionNames,
        IExecutor.Call[][] calldata optionBatches
    ) external onlyCreator whenNotPaused {
        if (metadata.length == 0) revert InvalidMetadata();
        if (optionNames.length == 0 || optionNames.length != optionBatches.length) revert LengthMismatch();
        if (optionNames.length > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) revert DurationOutOfRange();

        Layout storage l = _layout();
        uint64 endTs = uint64(block.timestamp + minutesDuration * 1 minutes);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < optionNames.length; ++i) {
            if (optionBatches[i].length > 0) {
                if (optionBatches[i].length > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < optionBatches[i].length; ++j) {
                    if (!l.allowedTarget[optionBatches[i][j].target]) revert TargetNotAllowed();
                    if (optionBatches[i][j].target == address(this)) revert TargetSelf();
                }
            }
            p.options.push(PollOption(0));
            p.batches.push(optionBatches[i]);
            emit PollOptionNames(id, i, optionNames[i]);
        }
        emit NewProposal(id, metadata, endTs, uint64(block.timestamp));
    }

    /* ───────────── Voting ───────────── */
    function vote(uint256 id, uint16[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        if (idxs.length != weights.length) revert LengthMismatch();

        Layout storage l = _layout();
        uint256 bal = l.participationToken.balanceOf(_msgSender());
        if (bal < l.MIN_BAL) revert MinBalance();
        uint256 power = l.quadraticVoting ? Math.sqrt(bal) : bal;
        require(power > 0, "power=0");

        Proposal storage p = l._proposals[id];
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

    function membership() external view returns (IMembership) {
        return _layout().membership;
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
}
