// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IExecutor} from "./Executor.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";
import {VotingMath} from "./libs/VotingMath.sol";
import {VotingErrors} from "./libs/VotingErrors.sol";

/// Participation‑weighted governor (power = balance or √balance)
contract ParticipationVoting is Initializable {

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
        if (_msgSender() != address(_layout().executor)) revert VotingErrors.Unauthorized();
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
            revert VotingErrors.ZeroAddress();
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
            if (target == address(0)) revert VotingErrors.ZeroAddress();
            l.allowedTarget[target] = allowed;
            emit TargetAllowed(target, allowed);
        } else if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            if (newExecutor == address(0)) revert VotingErrors.ZeroAddress();
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
            if (!canCreate) revert VotingErrors.Unauthorized();
        }
        _;
    }

    modifier exists(uint256 id) {
        if (id >= _layout()._proposals.length) revert VotingErrors.InvalidProposal();
        _;
    }

    modifier notExpired(uint256 id) {
        if (block.timestamp > _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingExpired();
        _;
    }

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingOpen();
        _;
    }

    /* ─────── Internal Helper Functions ─────── */
    function _validateDuration(uint32 minutesDuration) internal pure {
        if (minutesDuration < MIN_DURATION_MIN || minutesDuration > MAX_DURATION_MIN) {
            revert VotingErrors.DurationOutOfRange();
        }
    }

    function _validateTargets(IExecutor.Call[] calldata batch, Layout storage l) internal view {
        uint256 batchLen = batch.length;
        if (batchLen > MAX_CALLS) revert VotingErrors.TooManyCalls();
        for (uint256 j; j < batchLen;) {
            if (!l.allowedTarget[batch[j].target]) revert VotingErrors.TargetNotAllowed();
            if (batch[j].target == address(this)) revert VotingErrors.TargetSelf();
            unchecked { ++j; }
        }
    }

    function _initProposal(
        bytes calldata metadata,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) internal returns (uint256) {
        if (metadata.length == 0) revert VotingErrors.InvalidMetadata();
        if (numOptions == 0) revert VotingErrors.LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert VotingErrors.TooManyOptions();
        _validateDuration(minutesDuration);

        Layout storage l = _layout();
        
        bool isExecuting = false;
        if (batches.length > 0) {
            if (numOptions != batches.length) revert VotingErrors.LengthMismatch();
            for (uint256 i; i < numOptions;) {
                if (batches[i].length > 0) {
                    isExecuting = true;
                    _validateTargets(batches[i], l);
                }
                unchecked { ++i; }
            }
        }
        
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;
        
        uint256 id = l._proposals.length - 1;
        
        for (uint256 i; i < numOptions;) {
            p.options.push(PollOption(0));
            unchecked { ++i; }
        }
        
        if (isExecuting) {
            for (uint256 i; i < numOptions;) {
                p.batches.push(batches[i]);
                unchecked { ++i; }
            }
        } else {
            for (uint256 i; i < numOptions;) {
                p.batches.push();
                unchecked { ++i; }
            }
        }
        
        if (hatIds.length > 0) {
            uint256 len = hatIds.length;
            for (uint256 i; i < len;) {
                p.pollHatIds.push(hatIds[i]);
                p.pollHatAllowed[hatIds[i]] = true;
                unchecked { ++i; }
            }
        }
        
        return id;
    }

    /* ────────── Proposal Creation ────────── */
    function createProposal(
        bytes calldata metadata,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) external onlyCreator whenNotPaused {
        uint256 id = _initProposal(metadata, minutesDuration, numOptions, batches, hatIds);
        
        uint64 endTs = _layout()._proposals[id].endTimestamp;
        
        if (hatIds.length > 0) {
            emit NewHatProposal(id, metadata, numOptions, endTs, uint64(block.timestamp), hatIds);
        } else {
            emit NewProposal(id, metadata, numOptions, endTs, uint64(block.timestamp));
        }
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
            if (!canVote) revert VotingErrors.Unauthorized();
        }
        if (idxs.length != weights.length) revert VotingErrors.LengthMismatch();

        uint256 bal = l.participationToken.balanceOf(_msgSender());
        VotingMath.checkMinBalance(bal, l.MIN_BAL);
        // Use VotingMath for power calculation
        uint256 power = VotingMath.powerPT(bal, l.MIN_BAL, l.quadraticVoting);
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
            if (!hasAllowedHat) revert VotingErrors.RoleNotAllowed();
        }
        if (p.hasVoted[_msgSender()]) revert VotingErrors.AlreadyVoted();

        // Use VotingMath for weight validation
        VotingMath.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: p.options.length}));

        uint256 newTW = uint256(p.totalWeight) + power;
        VotingMath.checkOverflow(newTW);
        p.totalWeight = uint128(newTW);
        p.hasVoted[_msgSender()] = true;

        // Use VotingMath to calculate deltas
        uint256[] memory deltas = VotingMath.deltasPT(power, idxs, weights);
        uint256 idxLen = idxs.length;
        for (uint256 i; i < idxLen;) {
            uint256 newVotes = uint256(p.options[idxs[i]].votes) + deltas[i];
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
                if (batch[i].target == address(this)) revert VotingErrors.TargetSelf();
                if (!l.allowedTarget[batch[i].target]) revert VotingErrors.TargetNotAllowed();
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


    /* ───────────── View helpers ───────────── */
    function _calcWinner(uint256 id) internal view returns (uint256 win, bool ok) {
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];

        // Build option scores array for VoteCalc
        uint256 len = p.options.length;
        uint256[] memory optionScores = new uint256[](len);
        for (uint256 i; i < len;) {
            optionScores[i] = p.options[i].votes;
            unchecked {
                ++i;
            }
        }

        // Use VotingMath to pick winner with strict majority requirement
        (win, ok,,) = VotingMath.pickWinnerMajority(
            optionScores,
            p.totalWeight,
            l.quorumPercentage,
            true // requireStrictMajority
        );
    }

    /* ─────────── Targeted View Functions ─────────── */
    function proposalsCount() external view returns (uint256) {
        return _layout()._proposals.length;
    }
    
    function quorumPercentage() external view returns (uint8) {
        return _layout().quorumPercentage;
    }
    
    function isTargetAllowed(address target) external view returns (bool) {
        return _layout().allowedTarget[target];
    }
    
    function executor() external view returns (address) {
        return address(_layout().executor);
    }
    
    function hats() external view returns (address) {
        return address(_layout().hats);
    }
    
    function participationToken() external view returns (address) {
        return address(_layout().participationToken);
    }
    
    function quadraticVoting() external view returns (bool) {
        return _layout().quadraticVoting;
    }
    
    function minBalance() external view returns (uint256) {
        return _layout().MIN_BAL;
    }
    
    function pollRestricted(uint256 id) external view exists(id) returns (bool) {
        return _layout()._proposals[id].restricted;
    }
    
    function pollHatAllowed(uint256 id, uint256 hat) external view exists(id) returns (bool) {
        return _layout()._proposals[id].pollHatAllowed[hat];
    }
    
    function votingHats() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().votingHatIds);
    }
    
    function creatorHats() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().creatorHatIds);
    }
    
    function votingHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().votingHatIds);
    }
    
    function creatorHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().creatorHatIds);
    }
    
    function version() external pure returns (string memory) {
        return "v1";
    }
}
