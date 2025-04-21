// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/* ─────────── OpenZeppelin v5.3 Upgradeables ─────────── */
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/* ─────────── External Interfaces ─────────── */
interface IMembership {
    function roleOf(address user) external view returns (bytes32);
    function canVote(address user) external view returns (bool);
}

interface ITreasury {
    function sendTokens(address token, address to, uint256 amount) external;
    function withdrawEther(address payable to, uint256 amount) external;
}

interface IElections {
    function createElection(uint256 proposalId) external returns (uint256 electionId);
    function addCandidate(uint256 proposalId, address candidate, string memory name) external;
    function concludeElection(uint256 electionId, uint256 winningOption) external;
}

contract DirectDemocracyVoting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /* ─────────────── Errors ─────────────── */
    error Unauthorized();
    error AlreadyVoted();
    error InvalidProposal();
    error VotingExpired();
    error VotingOpen();
    error WeightsMustSum100();
    error InvalidOption();
    error LengthMismatch();
    error InvalidWeight();
    error DurationOverflow();
    error DuplicateOption();
    error TooManyVoters();

    /* ───────────── Constants ───────────── */
    bytes4 public constant MODULE_ID = 0x6464766f; /* "ddvo" */

    /* ───────────── Enums ───────────── */
    enum TokenType {
        ETHER,
        ERC20,
        WRAPPED,
        CUSTOM
    }

    /* ───────────── Storage ───────────── */
    IMembership public membership;
    ITreasury public treasury;
    IElections public elections;

    uint256 public quorumPercentage; // 1‑100

    struct PollOption {
        uint256 votes;
    }

    struct Proposal {
        uint256 totalVotes;
        uint48 endTimestamp;
        uint16 payoutTriggerIdx;
        bool transferEnabled;
        bool electionEnabled;
        TokenType tokenType;
        address payable recipient;
        address transferToken;
        uint256 amount;
        PollOption[] options;
        mapping(address => bool) hasVoted;
    }

    Proposal[] private _proposals;
    mapping(bytes32 => bool) private _allowedRoles;

    /* ───────────── Events ───────────── */
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
    event Voted(uint256 indexed proposalId, address indexed voter, uint16[] optionIndices, uint8[] weights);
    event PollOptionNames(uint256 indexed proposalId, uint256 indexed optionIndex, string name);
    event WinnerAnnounced(uint256 indexed proposalId, uint256 winningOptionIndex, bool hasValidWinner);
    event ElectionContractSet(address indexed electionContract);
    event VotesCleaned(uint256 indexed proposalId, uint256 count);

    /* ─────────── Initialiser ─────────── */
    constructor() initializer {}


    function initialize(
        address _owner,
        address _membership,
        bytes32[] calldata roleHashes, // hashed roleIds
        address _treasuryAddress,
        uint256 _quorumPercentage
    ) external initializer {
        require(_owner != address(0), "owner=0");
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        membership = IMembership(_membership);
        treasury = ITreasury(_treasuryAddress);
        quorumPercentage = _quorumPercentage;

        for (uint256 i; i < roleHashes.length; ++i) {
            _allowedRoles[roleHashes[i]] = true;
            emit RoleAllowed(roleHashes[i]);
        }
    }

    /* ─────────────────────────────── Modifiers ─────────────────────────────── */
    modifier onlyAllowedRole() {
        bytes32 roleHash = membership.roleOf(msg.sender);
        if (!_allowedRoles[roleHash]) revert Unauthorized();
        _;
    }

    modifier proposalExists(uint256 id) {
        if (id >= _proposals.length) revert InvalidProposal();
        _;
    }

    modifier whenNotExpired(uint256 id) {
        if (block.timestamp > _proposals[id].endTimestamp) revert VotingExpired();
        _;
    }

    modifier whenExpired(uint256 id) {
        if (block.timestamp <= _proposals[id].endTimestamp) revert VotingOpen();
        _;
    }

    /* ─────────────────────────── Proposal Creation ─────────────────────────── */
    function createProposal(
        string memory ipfsHash,
        uint256 minutesDuration,
        string[] memory optionNames,
        uint16 payoutTriggerIdx,
        address payable recipient,
        uint256 amount,
        bool transferEnabled,
        TokenType tokenType,
        address transferToken,
        bool electionEnabled,
        address[] memory candidateAddresses,
        string[] memory candidateNames
    ) external onlyAllowedRole {
        if (candidateAddresses.length != candidateNames.length) revert LengthMismatch();
        if (optionNames.length > type(uint16).max) revert LengthMismatch();

        uint48 endTs = uint48(block.timestamp + minutesDuration * 1 minutes);
        if (endTs > type(uint48).max) revert DurationOverflow();

        Proposal storage p = _proposals.push();
        p.endTimestamp = endTs;
        p.payoutTriggerIdx = payoutTriggerIdx;
        p.recipient = recipient;
        p.amount = amount;
        p.transferEnabled = transferEnabled;
        p.transferToken = transferToken;
        p.tokenType = tokenType;
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

    /* ──────────────────────────────── Voting ───────────────────────────────── */
    function vote(uint256 _proposalId, uint16[] memory _optionIndices, uint8[] memory _weights)
        external
        proposalExists(_proposalId)
        whenNotExpired(_proposalId)
    {
        if (_optionIndices.length != _weights.length) revert LengthMismatch();

        if (!membership.canVote(msg.sender)) revert Unauthorized();

        Proposal storage p = _proposals[_proposalId];
        if (p.hasVoted[msg.sender]) revert AlreadyVoted();

        // ensure indices are unique
        for (uint256 i; i < _optionIndices.length; ++i) {
            for (uint256 j = i + 1; j < _optionIndices.length; ++j) {
                if (_optionIndices[i] == _optionIndices[j]) revert DuplicateOption();
            }
        }

        uint256 weightSum;
        for (uint256 i; i < _weights.length;) {
            uint256 w = _weights[i];
            if (w > 100) revert InvalidWeight();
            unchecked {
                weightSum += w;
                ++i;
            }
        }
        if (weightSum != 100) revert WeightsMustSum100();

        p.hasVoted[msg.sender] = true;
        unchecked {
            ++p.totalVotes;
        }

        for (uint256 i; i < _optionIndices.length;) {
            uint256 option = _optionIndices[i];
            if (option >= p.options.length) revert InvalidOption();
            p.options[option].votes += _weights[i];
            unchecked {
                ++i;
            }
        }

        emit Voted(_proposalId, msg.sender, _optionIndices, _weights);
    }

    /* ─────────────────────────── Finalize & Payout ─────────────────────────── */
    function announceWinner(uint256 _proposalId)
        external
        nonReentrant
        proposalExists(_proposalId)
        whenExpired(_proposalId)
        returns (uint256 winner, bool valid)
    {
        (winner, valid) = _getWinner(_proposalId);
        Proposal storage p = _proposals[_proposalId];

        if (valid && p.transferEnabled && winner == p.payoutTriggerIdx) {
            if (p.tokenType == TokenType.ETHER) {
                treasury.withdrawEther(p.recipient, p.amount);
            } else {
                treasury.sendTokens(p.transferToken, p.recipient, p.amount);
            }
        }

        if (p.electionEnabled && valid) {
            elections.concludeElection(_proposalId, winner);
        }

        emit WinnerAnnounced(_proposalId, winner, valid);
    }

    /* ────────────────────────────── View Helpers ───────────────────────────── */
    function _getWinner(uint256 _proposalId) internal view returns (uint256 winningOption, bool hasValidWinner) {
        Proposal storage p = _proposals[_proposalId];
        if (p.totalVotes == 0) return (0, false);

        uint256 highestVotes;
        uint256 len = p.options.length;
        for (uint256 i; i < len;) {
            uint256 v = p.options[i].votes;
            if (v > highestVotes) {
                highestVotes = v;
                winningOption = i;
                hasValidWinner = highestVotes > p.totalVotes * quorumPercentage;
            }
            unchecked {
                ++i;
            }
        }
    }

    function getProposal(uint256 id)
        external
        view
        proposalExists(id)
        returns (
            uint256 totalVotes,
            uint48 endTimestamp,
            uint16 payoutTriggerIdx,
            address payable recipient,
            uint256 amount,
            bool transferEnabled,
            address transferToken,
            TokenType tokenType,
            bool electionEnabled,
            uint256 optionsCount
        )
    {
        Proposal storage p = _proposals[id];
        return (
            p.totalVotes,
            p.endTimestamp,
            p.payoutTriggerIdx,
            p.recipient,
            p.amount,
            p.transferEnabled,
            p.transferToken,
            p.tokenType,
            p.electionEnabled,
            p.options.length
        );
    }

    function getOptionVotes(uint256 id, uint256 option) external view proposalExists(id) returns (uint256) {
        Proposal storage p = _proposals[id];
        if (option >= p.options.length) revert InvalidOption();
        return p.options[option].votes;
    }

    function proposalsCount() external view returns (uint256) {
        return _proposals.length;
    }

    /* ───────────────────────────── Cleanup Helper ───────────────────────────── */
    /**
     * @notice Deletes `hasVoted` flags after a proposal ends to reclaim gas (EIP‑3529).
     *         Gas refunds are capped to 20 percent of tx.gasUsed. Keep batches ≤4 000.
     * @param voters list of addresses to delete
     */
    function cleanupVotes(uint256 id, address[] calldata voters) external proposalExists(id) whenExpired(id) {
        if (voters.length > 4_000) revert TooManyVoters();
        Proposal storage p = _proposals[id];

        uint256 cleaned;
        for (uint256 i; i < voters.length;) {
            delete p.hasVoted[voters[i]];
            unchecked {
                ++i;
                ++cleaned;
            }
        }
        emit VotesCleaned(id, cleaned);
    }

    /* ─────────────────────────── External Management ───────────────────────── */
    function setElectionsContract(address _elections) external {
        if (address(elections) != address(0)) {
            _checkOwner();
        }
        elections = IElections(_elections);
        emit ElectionContractSet(_elections);
    }

    /* ───────────────────────────── Upgrade Helpers ─────────────────────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    uint256[49] private __gap;
}
