// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutor} from "./Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";
import {VotingMath} from "./libs/VotingMath.sol";

/// Participation‑weighted governor (power = balance or √balance)
contract ParticipationVoting is Initializable {
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
    error Overflow();
    error InvalidMetadata();
    error RoleNotAllowed();

    /* ───────────── Constants ───────────── */
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
        uint256[] votingHatIds; // Array of voting hat IDs
        uint256[] creatorHatIds; // Array of creator hat IDs
        uint8 quorumPercentage; // 1‑100
        bool quadraticVoting; // toggle
        uint256 MIN_BAL; /* sybil floor */
        Proposal[] _proposals;
        bool _paused; // Inline pausable state
        uint256 _lock; // Inline reentrancy guard state
    }

    // keccak256("poa.participationvoting.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x961be98db34d61d2a5ef5b5cbadc7db40d3e0d4bad8902c41a8b75d5c73b5961;

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

    /* ───────────── Events ───────────── */
    event HatSet(HatType hatType, uint256 hat, bool allowed);
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

    /* ─────── Hat Management ─────── */
    enum HatType {
        VOTING,
        CREATOR
    }

    /* ─────── Storage Getter Enum ─────── */
    enum StorageKey {
        PARTICIPATION_TOKEN,
        HATS,
        EXECUTOR,
        QUORUM_PERCENTAGE,
        QUADRATIC_VOTING,
        MIN_BAL,
        VOTING_HATS,
        CREATOR_HATS,
        VOTING_HAT_COUNT,
        CREATOR_HAT_COUNT,
        POLL_HAT_ALLOWED,
        POLL_RESTRICTED,
        VERSION,
        PROPOSALS_COUNT,
        ALLOWED_TARGET
    }

    /* ─────── Configuration Setters ─────── */
    enum ConfigKey {
        QUORUM,
        QUADRATIC,
        MIN_BALANCE,
        TARGET_ALLOWED,
        EXECUTOR,
        HAT_ALLOWED
    }

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
        VotingMath.validateQuorum(quorumPct);
        VotingMath.validateMinBalance(minBalance_);

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.participationToken = IERC20(token_);
        l.executor = IExecutor(executor_);
        l.quorumPercentage = quorumPct;
        l.quadraticVoting = quadratic_;
        l.MIN_BAL = minBalance_;
        l._paused = false; // Initialize paused state
        l._lock = 0; // Initialize reentrancy guard state

        emit QuorumPercentageSet(quorumPct);
        emit QuadraticToggled(quadratic_);
        emit MinBalanceSet(minBalance_);

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

    /* ───────────── Governance setters ───────────── */
    function pause() external onlyExecutor {
        _pause();
    }

    function unpause() external onlyExecutor {
        _unpause();
    }


    function setConfig(ConfigKey key, bytes calldata value) external onlyExecutor {
        Layout storage l = _layout();
        
        if (key == ConfigKey.QUORUM) {
            uint8 q = abi.decode(value, (uint8));
            VotingMath.validateQuorum(q);
            l.quorumPercentage = q;
            emit QuorumPercentageSet(q);
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
            if (target == address(0)) revert ZeroAddress();
            l.allowedTarget[target] = allowed;
            emit TargetAllowed(target, allowed);
        } else if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            if (newExecutor == address(0)) revert ZeroAddress();
            l.executor = IExecutor(newExecutor);
            emit ExecutorUpdated(newExecutor);
        } else if (key == ConfigKey.HAT_ALLOWED) {
            (HatType hatType, uint256 hat, bool allowed) = abi.decode(value, (HatType, uint256, bool));
            
            if (hatType == HatType.VOTING) {
                HatManager.setHatInArray(l.votingHatIds, hat, allowed);
            } else if (hatType == HatType.CREATOR) {
                HatManager.setHatInArray(l.creatorHatIds, hat, allowed);
            }
            
            emit HatSet(hatType, hat, allowed);
        }
    }

    /* ───────────── Modifiers ───────────── */
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
        for (uint256 i; i < numOptions;) {
            uint256 batchLen = optionBatches[i].length;
            if (batchLen > 0) {
                if (batchLen > MAX_CALLS) revert TooManyCalls();
                for (uint256 j; j < batchLen;) {
                    if (!l.allowedTarget[optionBatches[i][j].target]) revert TargetNotAllowed();
                    if (optionBatches[i][j].target == address(this)) revert TargetSelf();
                    unchecked {
                        ++j;
                    }
                }
            }
            p.options.push(PollOption(0));
            p.batches.push(optionBatches[i]);
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

    /* ───────────── Voting ───────────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canVote = HatManager.hasAnyHat(l.hats, l.votingHatIds, _msgSender());
            if (!canVote) revert Unauthorized();
        }
        if (idxs.length != weights.length) revert LengthMismatch();

        uint256 bal = l.participationToken.balanceOf(_msgSender());
        VotingMath.checkMinBalance(bal, l.MIN_BAL);
        uint256 power = VotingMath.calculateVotingPower(bal, l.quadraticVoting);
        require(power > 0, "power=0");

        Proposal storage p = l._proposals[id];
        if (p.restricted) {
            bool hasAllowedHat = false;
            // Check if user has any of the poll-specific hats
            uint256 hatLen = p.pollHatIds.length;
            for (uint256 i = 0; i < hatLen;) {
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

        uint256 seen;
        uint256 sum;
        uint256 idxLen = idxs.length;
        for (uint256 i; i < idxLen;) {
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

        uint256 newTW = uint256(p.totalWeight) + power;
        VotingMath.checkOverflow(newTW);
        p.totalWeight = uint128(newTW);
        p.hasVoted[_msgSender()] = true;

        for (uint256 i; i < idxLen;) {
            uint256 add = power * weights[i];
            uint256 newVotes = uint256(p.options[idxs[i]].votes) + add;
            VotingMath.checkOverflow(newVotes);
            p.options[idxs[i]].votes = uint128(newVotes);
            unchecked {
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
    // function cleanupProposal(uint256 id, address[] calldata voters) external exists(id) isExpired(id) {
    //     Layout storage l = _layout();
    //     Proposal storage p = l._proposals[id];
    //     require(p.batches.length > 0 || voters.length > 0, "nothing");
    //     uint256 cleaned;
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
    //     if (cleaned == 0 && p.batches.length > 0) delete p.batches;
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
        } else if (key == StorageKey.QUORUM_PERCENTAGE) {
            return abi.encode(l.quorumPercentage);
        } else if (key == StorageKey.QUADRATIC_VOTING) {
            return abi.encode(l.quadraticVoting);
        } else if (key == StorageKey.MIN_BAL) {
            return abi.encode(l.MIN_BAL);
        } else if (key == StorageKey.VOTING_HATS) {
            return abi.encode(HatManager.getHatArray(l.votingHatIds));
        } else if (key == StorageKey.CREATOR_HATS) {
            return abi.encode(HatManager.getHatArray(l.creatorHatIds));
        } else if (key == StorageKey.VOTING_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.votingHatIds));
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
        } else if (key == StorageKey.ALLOWED_TARGET) {
            address target = abi.decode(params, (address));
            return abi.encode(l.allowedTarget[target]);
        }
        
        revert InvalidIndex();
    }

    /* ───────────── View helpers ───────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];
        uint128 high;
        uint128 second;
        uint256 len = p.options.length;
        for (uint256 i; i < len;) {
            uint128 v = p.options[i].votes;
            if (v > high) {
                second = high;
                high = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
            unchecked {
                ++i;
            }
        }
        ok = (uint256(high) * 100 > uint256(p.totalWeight) * l.quorumPercentage) && (high > second);
    }


}
