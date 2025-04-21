// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* ───────────────────────────  OpenZeppelin v5.3 Upgradeables  ──────────── */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* ───────────────────────────  External Interfaces  ─────────────────────── */
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function canVote(address user) external view returns (bool);
}

interface ITreasury {
    function sendTokens(address token, address to, uint256 amt) external;
    function withdrawEther(address payable to, uint256 amt) external;
}

interface IElections {
    function createElection(uint256 proposalId) external returns (uint256 electionId);
    function addCandidate(uint256 proposalId, address candidate, string memory name) external;
    function concludeElection(uint256 electionId, uint256 winningOption) external;
}

/* ───────────────────────────  Contract  ─────────────────────────────────── */
contract ParticipationVoting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    /* ──────────────────────────  Errors  ─────────────────────────────── */
    error Unauthorized();
    error ProposalClosed();
    error ProposalOpen();
    error InvalidProposal();
    error AlreadyVoted();
    error WeightSumNot100();
    error InvalidIndex();
    error DurationTooLong();
    error TooManyOptions();
    error TransferExecuted();
    error QuorumOutOfRange();
    error DuplicateIndex();
    error TooManyVoters();
    error MinBalance();
    error AlreadyClean();

    /* ──────────────────────────  Constants  ──────────────────────────── */
    uint256 private constant MAX_DURATION_MIN = 43_200; // 30 days
    uint256 private constant MAX_OPTIONS = 50;
    uint256 private constant MIN_BAL = 4; // Sybil floor
    bytes4 public constant MODULE_ID = 0x70766f74; // "pvot"

    /* ──────────────────────────  Enums  ─────────────────────────────── */
    enum TokenType {
        ETHER,
        ERC20,
        WRAPPED,
        CUSTOM
    }

    /* ──────────────────────────  Storage  ───────────────────────────── */
    IERC20 public participationToken;
    IMembership public membership;
    ITreasury public treasury;
    IElections public elections;

    uint8 public quorumPercentage; // 1‑100
    bool public quadraticVotingEnabled;

    mapping(bytes32 => bool) private _allowedRoles; // roleHash to proposal‑creator flag

    struct PollOption {
        uint256 votes;
    }

    struct Proposal {
        uint256 totalWeight; // sum of voting power (not voter count)
        uint48 endTimestamp; // deadline
        uint16 payoutTriggerIdx; // option that triggers payout
        bool transferEnabled;
        bool executed; // prevents double‑execute
        bool electionEnabled;
        uint256 electionId;
        TokenType tokenType;
        address payable recipient;
        address transferToken; // ERC‑20 if tokenType==ERC20
        uint256 amount;
        PollOption[] options;
        mapping(address => bool) hasVoted;
    }

    Proposal[] private _proposals;

    /* ──────────────────────────  Events  ─────────────────────────────── */
    event RoleAllowed(bytes32 role);
    event NewProposal(
        uint256 indexed proposalId,
        string ipfsHash,
        uint48 endTimestamp,
        uint48 creationTimestamp,
        uint16 payoutTriggerIdx,
        address recipient,
        uint256 amount,
        bool transferEnabled,
        TokenType tokenType,
        address transferToken,
        bool electionEnabled,
        uint256 electionId
    );
    event PollOptionNames(uint256 indexed proposalId, uint256 indexed optionIndex, string name);
    event Voted(uint256 indexed id, address indexed voter, uint16[] indices, uint8[] weights);
    event Winner(uint256 indexed id, uint256 option, bool valid);
    event VotesCleaned(uint256 indexed id, uint256 cleaned);
    event QuorumChanged(uint8 newQuorum);
    event QuadraticVotingToggled(bool enabled);
    event ElectionContractSet(address indexed newAddress);
    /* ─────────────────────── Initializer  ────────────────────────────── */
    function initialize(
        address _owner,
        address _token,
        address _membership,
        address _treasury,
        address _elections,
        uint8 _quorumPercentage, // 1‑100
        bytes32[] calldata roleHashes,
        bool _quadratic
    ) external initializer {
        if (_owner == address(0) || _token == address(0) || _membership == address(0) || _treasury == address(0)) {
            revert Unauthorized();
        }
        if (_quorumPercentage == 0 || _quorumPercentage > 100) revert QuorumOutOfRange();

        __Ownable_init(_owner);
        __ReentrancyGuard_init();
        __Pausable_init();

        participationToken = IERC20(_token);
        membership = IMembership(_membership);
        treasury = ITreasury(_treasury);
        elections = IElections(_elections);
        quorumPercentage = _quorumPercentage;
        quadraticVotingEnabled = _quadratic;

        for (uint256 i; i < roleHashes.length; ++i) {
            _allowedRoles[roleHashes[i]] = true;
        }
    }

    /* ───────────────────────────  Modifiers  ─────────────────────────── */
    modifier onlyCreator() {
        if (!_allowedRoles[membership.roleOf(msg.sender)]) revert Unauthorized();
        _;
    }

    modifier exists(uint256 id) {
        if (id >= _proposals.length) revert InvalidProposal();
        _;
    }

    modifier notExpired(uint256 id) {
        if (block.timestamp > _proposals[id].endTimestamp) revert ProposalClosed();
        _;
    }

    modifier isExpired(uint256 id) {
        if (block.timestamp <= _proposals[id].endTimestamp) revert ProposalOpen();
        _;
    }

    /* ─────────────────────── Proposal Creation  ──────────────────────── */
    function createProposal(
        string calldata ipfsHash,
        uint32 minutesDuration, // ≤ MAX_DURATION_MIN
        string[] calldata optionNames, // ≤ MAX_OPTIONS
        uint16 payoutTriggerIdx,
        address payable recipient,
        uint256 amount,
        bool transferEnabled,
        TokenType tokenType,
        address transferToken,
        bool electionEnabled,
        address[] calldata candidateAddresses,
        string[] calldata candidateNames
    ) external onlyCreator whenNotPaused {
        if (optionNames.length == 0 || optionNames.length > MAX_OPTIONS) revert TooManyOptions();
        if (minutesDuration == 0 || minutesDuration > MAX_DURATION_MIN) revert DurationTooLong();

        uint48 endTs = uint48(block.timestamp + minutesDuration * 1 minutes);

        Proposal storage p = _proposals.push();
        p.endTimestamp = endTs;
        p.payoutTriggerIdx = payoutTriggerIdx;
        p.recipient = recipient;
        p.amount = amount;
        p.transferEnabled = transferEnabled;
        p.tokenType = tokenType;
        p.transferToken = transferToken;
        p.electionEnabled = electionEnabled;
        uint256 proposalId = _proposals.length - 1;

        for (uint256 i; i < optionNames.length;) {
            p.options.push(PollOption(0));
            emit PollOptionNames(proposalId, i, optionNames[i]);
            unchecked {
                ++i;
            }
        }

        uint256 electionId;
        if (electionEnabled) {
            electionId = elections.createElection(proposalId);

            for (uint256 i = 0; i < candidateAddresses.length;) {
                elections.addCandidate(proposalId, candidateAddresses[i], candidateNames[i]);
                unchecked {
                    ++i;
                }
            }
        }

        emit NewProposal(
            proposalId,
            ipfsHash,
            endTs,
            uint48(block.timestamp),
            payoutTriggerIdx,
            recipient,
            amount,
            transferEnabled,
            tokenType,
            transferToken,
            electionEnabled,
            electionId
        );
    }

    /* ───────────────────────────── Voting  ───────────────────────────── */
    function vote(uint256 id, uint16[] calldata indices, uint8[] calldata weights)
        external
        exists(id)
        notExpired(id)
        whenNotPaused
    {
        Proposal storage p = _proposals[id];
        if (p.hasVoted[msg.sender]) revert AlreadyVoted();
        if (indices.length != weights.length) revert WeightSumNot100();
        if (!membership.canVote(msg.sender)) revert Unauthorized();

        uint256 seen;
        uint256 weightSum;
        for (uint256 i; i < indices.length; ++i) {
            uint16 idx = indices[i];
            if (idx >= p.options.length) revert InvalidIndex();
            if ((seen >> idx) & 1 != 0) revert DuplicateIndex();
            seen |= 1 << idx;

            uint8 w = weights[i];
            weightSum += w;
        }
        if (weightSum != 100) revert WeightSumNot100();

        uint256 balance = participationToken.balanceOf(msg.sender);
        if (balance < MIN_BAL) revert MinBalance();

        uint256 power = quadraticVotingEnabled ? Math.sqrt(balance) : balance;

        // apply votes
        for (uint256 i; i < indices.length; ++i) {
            p.options[indices[i]].votes += power * weights[i];
        }
        unchecked {
            p.totalWeight += power;
        }
        p.hasVoted[msg.sender] = true;

        emit Voted(id, msg.sender, indices, weights);
    }

    /* ─────────────────────── Finalise & Execute  ─────────────────────── */
    function announceWinner(uint256 id)
        external
        nonReentrant
        exists(id)
        isExpired(id)
        whenNotPaused
        returns (uint256 winner, bool valid)
    {
        Proposal storage p = _proposals[id];
        if (p.executed) revert TransferExecuted();

        (winner, valid) = _calcWinner(p);

        p.executed = true;

        if (valid && p.transferEnabled && winner == p.payoutTriggerIdx) {
            if (p.tokenType == TokenType.ETHER) {
                treasury.withdrawEther(p.recipient, p.amount);
            } else {
                treasury.sendTokens(p.transferToken, p.recipient, p.amount);
            }
        }

        if (p.electionEnabled && valid) {
            elections.concludeElection(p.electionId, winner);
        }

        emit Winner(id, winner, valid);
    }

    /* ───────────────────── Vote‑cleanup ──────────────────────── */
    function cleanupVotes(uint256 id, address[] calldata voters) external exists(id) isExpired(id) whenNotPaused {
        if (voters.length > 4_000) revert TooManyVoters();
        Proposal storage p = _proposals[id];
        uint256 cleaned;
        for (uint256 i; i < voters.length; ++i) {
            if (p.hasVoted[voters[i]]) {
                delete p.hasVoted[voters[i]];
                ++cleaned;
            }
        }
        if (cleaned == 0) revert AlreadyClean();
        emit VotesCleaned(id, cleaned);
    }

    /* ───────────────────── Governance Setters ───────────────────────── */
    function setQuorum(uint8 newQuorum) external onlyOwner {
        if (newQuorum == 0 || newQuorum > 100) revert QuorumOutOfRange();
        quorumPercentage = newQuorum;
        emit QuorumChanged(newQuorum);
    }

    function toggleQuadratic() external onlyOwner {
        quadraticVotingEnabled = !quadraticVotingEnabled;
        emit QuadraticVotingToggled(quadraticVotingEnabled);
    }

    /* ─────────────────────────  View helpers  ───────────────────────── */
    function proposalsCount() external view returns (uint256) {
        return _proposals.length;
    }

    function getProposal(uint256 id)
        external
        view
        exists(id)
        returns (uint48 endTs, uint256 totalWeight, bool executed, uint256 options, TokenType tokenType, bool electionEnabled, uint256 electionId)
    {
        Proposal storage p = _proposals[id];
        return (p.endTimestamp, p.totalWeight, p.executed, p.options.length, p.tokenType, p.electionEnabled, p.electionId);
    }

    function getOptionVotes(uint256 id, uint16 index) external view exists(id) returns (uint256) {
        Proposal storage p = _proposals[id];
        if (index >= p.options.length) revert InvalidIndex();
        return p.options[index].votes;
    }

    /* ───────────────────────  Internal utils  ───────────────────────── */
    function _calcWinner(Proposal storage p) internal view returns (uint256 win, bool valid) {
        uint256 high;
        uint256 len = p.options.length;
        uint256 thresh = (p.totalWeight * quorumPercentage + 99) / 100; // G‑A4 (round‑up safe division)
        for (uint256 i; i < len; ++i) {
            uint256 v = p.options[i].votes;
            if (v > high) {
                high = v;
                win = i;
                valid = high >= thresh;
            }
        }
    }

    /* ───────────────────────────  Pausable  ─────────────────────────── */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ─────────────────────────── External Management ───────────────────────── */
    function setElectionsContract(address _elections) external {
        if (address(elections) != address(0)) {
            _checkOwner();
        }
        elections = IElections(_elections);
        emit ElectionContractSet(_elections);
    }

    /* ───────────────────────────  Version  ──────────────────────────── */
    function moduleId() external pure returns (bytes4) {
        return MODULE_ID;
    }

    function version() external pure returns (string memory) {
        return "v1";
    }

    /* ─────────────── storage gap (46 slots left) ─────────────── */
    uint256[46] private __gap;
}
