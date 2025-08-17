// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.30;

/*  OpenZeppelin v5.3 Upgradeables  */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {IExecutor} from "./Executor.sol";
import {HatManager} from "./libs/HatManager.sol";
import {VotingMath} from "./libs/VotingMath.sol";
import {VotingErrors} from "./libs/VotingErrors.sol";

/* ─────────────────── HybridVoting ─────────────────── */
contract HybridVoting is Initializable {

    /* ─────── Constants ─────── */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint8 public constant MAX_CLASSES = 8;
    uint32 public constant MAX_DURATION = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION = 10; /* 10 min   */

    /* ─────── Data Structures ─────── */

    enum ClassStrategy { 
        DIRECT,           // 1 person → 100 raw points
        ERC20_BAL         // balance (or sqrt) scaled
    }

    struct ClassConfig {
        ClassStrategy strategy;        // DIRECT / ERC20_BAL
        uint8 slicePct;                // 1..100; all classes must sum to 100
        bool quadratic;                // only for token strategies
        uint256 minBalance;            // sybil floor for token strategies
        address asset;                 // ERC20 token (if required)
        uint256[] hatIds;              // voter must wear ≥1 (union)
    }

    struct PollOption {
        uint128[] classRaw;            // length = classesSnapshot.length
    }

    struct Proposal {
        uint64 endTimestamp;
        uint256[] classTotalsRaw;      // Σ raw from each class (len = classesSnapshot.length)
        PollOption[] options;          // each option has classRaw[i]
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches;
        uint256[] pollHatIds;          // array of specific hat IDs for this poll
        bool restricted;               // if true only pollHatIds can vote
        mapping(uint256 => bool) pollHatAllowed; // O(1) lookup for poll hat permission
        ClassConfig[] classesSnapshot; // Snapshot the class config to freeze semantics for this proposal
    }

    /* ─────── ERC-7201 Storage ─────── */
    /// @custom:storage-location erc7201:poa.hybridvoting.v2.storage
    struct Layout {
        /* Config / Storage */
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint8 quorumPct; // 1‑100
        ClassConfig[] classes; // global N-class configuration
        /* Vote Bookkeeping */
        Proposal[] _proposals;
        /* Inline State */
        bool _paused; // Inline pausable state
        uint256 _lock; // Inline reentrancy guard state
    }

    // keccak256("poa.hybridvoting.v2.storage") → unique, collision-free slot for v2
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    /* ─────── Storage Getter Enum ─────── */
    enum StorageKey {
        HATS,
        EXECUTOR,
        QUORUM_PCT,
        CREATOR_HATS,
        CREATOR_HAT_COUNT,
        POLL_HAT_ALLOWED,
        POLL_RESTRICTED,
        VERSION,
        PROPOSALS_COUNT,
        CLASSES,
        PROPOSAL_CLASSES
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
        if (_layout()._paused) revert VotingErrors.Paused();
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
    event ProposalCleaned(uint256 id, uint256 cleaned);
    event ClassesReplaced(uint256 version, bytes32 classesHash);

    /* ─────── Initialiser ─────── */
    constructor() initializer {}

    function initialize(
        address hats_,
        address executor_,
        uint256[] calldata initialCreatorHats,
        address[] calldata initialTargets,
        uint8 quorum_,
        ClassConfig[] calldata initialClasses
    ) external initializer {
        if (hats_ == address(0) || executor_ == address(0)) {
            revert VotingErrors.ZeroAddress();
        }
        
        if (initialClasses.length == 0) revert VotingErrors.InvalidClassCount();
        if (initialClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();

        VotingMath.validateQuorum(quorum_);

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.executor = IExecutor(executor_);
        l._paused = false; // Initialize paused state
        l._lock = 0; // Initialize reentrancy guard state

        l.quorumPct = quorum_;
        emit QuorumSet(quorum_);

        // Initialize creator hats and targets
        _initializeCreatorHats(initialCreatorHats);
        _initializeTargets(initialTargets);
        
        // Validate and set initial classes
        uint256 totalSlice;
        for (uint256 i; i < initialClasses.length;) {
            ClassConfig calldata c = initialClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;
            
            if (c.strategy == ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }
            
            l.classes.push(initialClasses[i]);
            unchecked { ++i; }
        }
        
        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();
        
        // Emit new class configuration event
        bytes32 classesHash = keccak256(abi.encode(l.classes));
        emit ClassesReplaced(block.number, classesHash);
    }
    
    function _initializeCreatorHats(uint256[] calldata creatorHats) internal {
        Layout storage l = _layout();
        uint256 len = creatorHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHats[i], true);
            unchecked { ++i; }
        }
    }

    /* ─────── Internal Initialization Helpers ─────── */
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
        if (_msgSender() != address(_layout().executor)) revert VotingErrors.Unauthorized();
        _;
    }

    function pause() external onlyExecutor {
        _pause();
    }

    function unpause() external onlyExecutor {
        _unpause();
    }

    /* ─────── Hat Management ─────── */
    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.creatorHatIds, h, ok);
        emit HatSet(HatType.CREATOR, h, ok);
    }
    
    enum HatType {
        CREATOR
    }

    /* ─────── N-Class Configuration ─────── */
    function setClasses(ClassConfig[] calldata newClasses) external onlyExecutor {
        if (newClasses.length == 0) revert InvalidClassCount();
        if (newClasses.length > MAX_CLASSES) revert TooManyClasses();
        
        uint256 totalSlice;
        for (uint256 i; i < newClasses.length;) {
            ClassConfig calldata c = newClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;
            
            if (c.strategy == ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }
            unchecked { ++i; }
        }
        
        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();
        
        Layout storage l = _layout();
        delete l.classes;
        for (uint256 i; i < newClasses.length;) {
            l.classes.push(newClasses[i]);
            unchecked { ++i; }
        }
        
        bytes32 classesHash = keccak256(abi.encode(newClasses));
        emit ClassesReplaced(block.number, classesHash);
    }
    
    function getClasses() external view returns (ClassConfig[] memory) {
        return _layout().classes;
    }
    
    function getProposalClasses(uint256 id) external view exists(id) returns (ClassConfig[] memory) {
        return _layout()._proposals[id].classesSnapshot;
    }

    /* ─────── Configuration Setters ─────── */
    enum ConfigKey {
        QUORUM,
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
        } else if (key == ConfigKey.TARGET_ALLOWED) {
            (address target, bool allowed) = abi.decode(value, (address, bool));
            l.allowedTarget[target] = allowed;
            emit TargetAllowed(target, allowed);
        } else if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            if (newExecutor == address(0)) revert VotingErrors.ZeroAddress();
            l.executor = IExecutor(newExecutor);
            emit ExecutorUpdated(newExecutor);
        }
    }

    /* ─────── Helpers & modifiers ─────── */
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

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingOpen();
        _;
    }

    /* ─────── Proposal creation ─────── */
    function createProposal(
        bytes calldata metadata,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches
    ) external onlyCreator whenNotPaused {
        if (metadata.length == 0) revert VotingErrors.InvalidMetadata();
        if (numOptions == 0 || numOptions != batches.length) revert VotingErrors.LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert VotingErrors.TooManyOptions();
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) revert VotingErrors.DurationOutOfRange();

        Layout storage l = _layout();
        if (l.classes.length == 0) revert VotingErrors.InvalidClassCount();
        
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        
        // Snapshot the classes configuration
        uint256 classCount = l.classes.length;
        for (uint256 i; i < classCount;) {
            p.classesSnapshot.push(l.classes[i]);
            unchecked { ++i; }
        }
        
        // Initialize classTotalsRaw array
        p.classTotalsRaw = new uint256[](classCount);

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            uint256 batchLen = batches[i].length;
            if (batchLen > 0) {
                if (batchLen > MAX_CALLS) revert VotingErrors.TooManyCalls();
                for (uint256 j; j < batchLen;) {
                    if (!l.allowedTarget[batches[i][j].target]) revert VotingErrors.InvalidTarget();
                    if (batches[i][j].target == address(this)) revert VotingErrors.InvalidTarget();
                    unchecked {
                        ++j;
                    }
                }
            }
            // Initialize each option with classRaw array of correct length
            PollOption storage opt = p.options.push();
            opt.classRaw = new uint128[](classCount);
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
        if (metadata.length == 0) revert VotingErrors.InvalidMetadata();
        if (numOptions == 0) revert VotingErrors.LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert VotingErrors.TooManyOptions();
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) revert VotingErrors.DurationOutOfRange();

        Layout storage l = _layout();
        if (l.classes.length == 0) revert VotingErrors.InvalidClassCount();
        
        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;
        
        // Snapshot the classes configuration
        uint256 classCount = l.classes.length;
        for (uint256 i; i < classCount;) {
            p.classesSnapshot.push(l.classes[i]);
            unchecked { ++i; }
        }
        
        // Initialize classTotalsRaw array
        p.classTotalsRaw = new uint256[](classCount);

        uint256 id = l._proposals.length - 1;
        for (uint256 i; i < numOptions;) {
            // Initialize each option with classRaw array of correct length
            PollOption storage opt = p.options.push();
            opt.classRaw = new uint128[](classCount);
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
        if (idxs.length != weights.length) revert VotingErrors.LengthMismatch();
        if (block.timestamp > _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingExpired();
        
        Layout storage l = _layout();
        Proposal storage p = l._proposals[id];
        address voter = _msgSender();
        
        // Check poll-level restrictions
        if (p.restricted) {
            bool hasAllowedHat = false;
            uint256 len = p.pollHatIds.length;
            for (uint256 i = 0; i < len;) {
                if (l.hats.isWearerOfHat(voter, p.pollHatIds[i])) {
                    hasAllowedHat = true;
                    break;
                }
                unchecked { ++i; }
            }
            if (!hasAllowedHat) revert VotingErrors.RoleNotAllowed();
        }
        
        if (p.hasVoted[voter]) revert VotingErrors.AlreadyVoted();
        
        // Validate weights
        VotingMath.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: p.options.length}));
        
        // Calculate raw power for each class
        uint256 classCount = p.classesSnapshot.length;
        uint256[] memory classRawPowers = new uint256[](classCount);
        
        for (uint256 c; c < classCount;) {
            ClassConfig memory cls = p.classesSnapshot[c];
            uint256 rawPower = _calculateClassPower(voter, cls);
            classRawPowers[c] = rawPower;
            p.classTotalsRaw[c] += rawPower;
            unchecked { ++c; }
        }
        
        // Accumulate deltas for each option
        uint256 len = weights.length;
        for (uint256 i; i < len;) {
            uint8 ix = idxs[i];
            uint8 weight = weights[i];
            
            for (uint256 c; c < classCount;) {
                if (classRawPowers[c] > 0) {
                    uint256 delta = (classRawPowers[c] * weight) / 100;
                    if (delta > 0) {
                        uint256 newVal = p.options[ix].classRaw[c] + delta;
                        require(VotingMath.fitsUint128(newVal), "Class raw overflow");
                        p.options[ix].classRaw[c] = uint128(newVal);
                    }
                }
                unchecked { ++c; }
            }
            unchecked { ++i; }
        }
        
        p.hasVoted[voter] = true;
        emit VoteCast(id, voter, idxs, weights);
    }
    
    function _calculateClassPower(address voter, ClassConfig memory cls) 
        internal view returns (uint256) {
        Layout storage l = _layout();
        
        // Check hat gating for this class
        bool hasClassHat = (voter == address(l.executor)) || 
            (cls.hatIds.length == 0);
        
        // Check if voter has any of the class hats
        if (!hasClassHat && cls.hatIds.length > 0) {
            for (uint256 i; i < cls.hatIds.length;) {
                if (l.hats.isWearerOfHat(voter, cls.hatIds[i])) {
                    hasClassHat = true;
                    break;
                }
                unchecked { ++i; }
            }
        }
        
        if (!hasClassHat) return 0;
        
        if (cls.strategy == ClassStrategy.DIRECT) {
            return 100; // Direct democracy: 1 person = 100 raw points
        } else if (cls.strategy == ClassStrategy.ERC20_BAL) {
            uint256 balance = IERC20(cls.asset).balanceOf(voter);
            if (balance < cls.minBalance) return 0;
            uint256 power = cls.quadratic ? VotingMath.sqrt(balance) : balance;
            return power * 100; // Scale to match existing system
        }
        
        return 0;
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

        // Check if any votes were cast
        bool hasVotes = false;
        for (uint256 i; i < p.classTotalsRaw.length;) {
            if (p.classTotalsRaw[i] > 0) {
                hasVotes = true;
                break;
            }
            unchecked { ++i; }
        }
        
        if (!hasVotes) {
            emit Winner(id, 0, false);
            return (0, false);
        }

        // Build matrix for N-class winner calculation
        uint256 numOptions = p.options.length;
        uint256 numClasses = p.classesSnapshot.length;
        uint256[][] memory perOptionPerClassRaw = new uint256[][](numOptions);
        uint8[] memory slices = new uint8[](numClasses);
        
        for (uint256 opt; opt < numOptions;) {
            perOptionPerClassRaw[opt] = new uint256[](numClasses);
            for (uint256 cls; cls < numClasses;) {
                perOptionPerClassRaw[opt][cls] = p.options[opt].classRaw[cls];
                unchecked { ++cls; }
            }
            unchecked { ++opt; }
        }
        
        for (uint256 cls; cls < numClasses;) {
            slices[cls] = p.classesSnapshot[cls].slicePct;
            unchecked { ++cls; }
        }

        // Use VotingMath to pick winner with N-class logic
        (winner, valid,,) = VotingMath.pickWinnerNSlices(
            perOptionPerClassRaw,
            p.classTotalsRaw,
            slices,
            l.quorumPct,
            true // strict majority required
        );

        IExecutor.Call[] storage batch = p.batches[winner];
        if (valid && batch.length > 0) {
            uint256 batchLen = batch.length;
            for (uint256 i; i < batchLen;) {
                if (!l.allowedTarget[batch[i].target]) revert VotingErrors.InvalidTarget();
                unchecked { ++i; }
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

        if (key == StorageKey.HATS) {
            return abi.encode(l.hats);
        } else if (key == StorageKey.EXECUTOR) {
            return abi.encode(l.executor);
        } else if (key == StorageKey.QUORUM_PCT) {
            return abi.encode(l.quorumPct);
        } else if (key == StorageKey.CREATOR_HATS) {
            return abi.encode(HatManager.getHatArray(l.creatorHatIds));
        } else if (key == StorageKey.CREATOR_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.creatorHatIds));
        } else if (key == StorageKey.POLL_HAT_ALLOWED) {
            (uint256 id, uint256 hat) = abi.decode(params, (uint256, uint256));
            if (id >= l._proposals.length) revert VotingErrors.InvalidProposal();
            return abi.encode(l._proposals[id].pollHatAllowed[hat]);
        } else if (key == StorageKey.POLL_RESTRICTED) {
            uint256 id = abi.decode(params, (uint256));
            if (id >= l._proposals.length) revert VotingErrors.InvalidProposal();
            return abi.encode(l._proposals[id].restricted);
        } else if (key == StorageKey.VERSION) {
            return abi.encode("v1");
        } else if (key == StorageKey.PROPOSALS_COUNT) {
            return abi.encode(l._proposals.length);
        } else if (key == StorageKey.CLASSES) {
            return abi.encode(l.classes);
        } else if (key == StorageKey.PROPOSAL_CLASSES) {
            uint256 id = abi.decode(params, (uint256));
            if (id >= l._proposals.length) revert VotingErrors.InvalidProposal();
            return abi.encode(l._proposals[id].classesSnapshot);
        }

        revert VotingErrors.InvalidIndex();
    }
}
