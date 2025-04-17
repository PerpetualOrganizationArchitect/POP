// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

interface INFTMembership2 {
    function roleOf(address user) external view returns (bytes32);
    function canVote(address user) external view returns (bool);
}

interface ITreasury {
    function sendTokens(address _token, address _to, uint256 _amount) external;
    function setVotingContract(address _votingContract) external;
    function withdrawEther(address payable _to, uint256 _amount) external;
}

interface IElections {
    function createElection(uint256 _proposalId) external returns (uint256 electionId, uint256 _unused);
    function addCandidate(uint256 _proposalId, address _candidateAddress, string memory _candidateName) external;
    function concludeElection(uint256 _electionId, uint256 winningOption) external;
}

contract DirectDemocracyVoting is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /* ───────────────────────────── Custom Errors ───────────────────────────── */
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

    /* ─────────────────────────────── Constants ─────────────────────────────── */
    bytes4 public constant MODULE_ID = 0x6464766f; /* "ddvo" */

    /* ────────────────────────────── Enumerations ───────────────────────────── */
    enum TokenType { ETHER, ERC20, WRAPPED, CUSTOM }

    /* ────────────────────────────── State Storage ──────────────────────────── */
    INFTMembership2 public nftMembership;
    ITreasury public treasury;
    IElections public elections;

    /// @notice quorum percentage 1‑100
    uint256 public quorumPercentage;

    // reserved for future EIP‑712 (unused until AA or 4337)
    bytes32 private _domainSeparator;
    mapping(address => uint256) private _sigNonces;

    struct PollOption { uint256 votes; }

    struct Proposal {
        uint256 totalVotes;
        uint48  endTimestamp;
        uint16  transferTriggerIndex;
        bool    transferEnabled;
        bool    electionEnabled;
        TokenType tokenType;
        address payable transferRecipient;
        address transferToken;
        uint256 transferAmount;
        PollOption[] options;
        mapping(address => bool) hasVoted;
    }

    Proposal[] private _proposals;
    mapping(bytes32 => bool) private _allowedRoles;

    /* ──────────────────────────────── Events ───────────────────────────────── */
    event NewProposal(
        uint256 indexed proposalId,
        string name,
        string description,
        uint256 timeInMinutes,
        uint256 creationTimestamp,
        uint256 transferTriggerOptionIndex,
        address transferRecipient,
        uint256 transferAmount,
        bool transferEnabled,
        address transferToken,
        bool electionEnabled,
        uint256 electionId
    );

    event Voted(uint256 indexed proposalId, address indexed voter, uint256[] optionIndices, uint256[] weights);
    event PollOptionNames(uint256 indexed proposalId, uint256 indexed optionIndex, string name);
    event WinnerAnnounced(uint256 indexed proposalId, uint256 winningOptionIndex, bool hasValidWinner);
    event ElectionContractSet(address indexed electionContract);
    event VotesCleaned(uint256 indexed proposalId, uint256 count);

    /* ───────────────────────────── Initialiser ─────────────────────────────── */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @param _quorumPercentage whole numbers 1‑100
     */
    function initialize(
        address _owner,
        address _nftMembership,
        string[] memory _allowedRoleNames,
        address _treasuryAddress,
        uint256 _quorumPercentage
    ) external initializer {
        require(_owner != address(0), "owner=0");
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        nftMembership        = INFTMembership2(_nftMembership);
        treasury             = ITreasury(_treasuryAddress);
        quorumPercentage     = _quorumPercentage;

        for (uint256 i; i < _allowedRoleNames.length; ) {
            _allowedRoles[keccak256(bytes(_allowedRoleNames[i]))] = true;
            unchecked { ++i; }
        }
    }

    /* ─────────────────────────────── Modifiers ─────────────────────────────── */
    modifier onlyAllowedRole() {
        bytes32 roleHash = nftMembership.roleOf(msg.sender);
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
        string memory _name,
        string memory _description,
        uint256 _timeInMinutes,
        string[] memory _optionNames,
        uint256 _transferTriggerOptionIndex,
        address payable _transferRecipient,
        uint256 _transferAmount,
        bool _transferEnabled,
        address _transferToken,
        TokenType _tokenType,
        bool _electionEnabled,
        address[] memory _candidateAddresses,
        string[] memory _candidateNames
    ) external onlyAllowedRole {
        if (_candidateAddresses.length != _candidateNames.length) revert LengthMismatch();
        if (_optionNames.length > type(uint16).max) revert LengthMismatch();

        uint256 closing = block.timestamp + _timeInMinutes * 1 minutes;
        if (closing > type(uint48).max) revert DurationOverflow();

        Proposal storage p = _proposals.push();
        p.endTimestamp           = uint48(closing);
        p.transferTriggerIndex   = uint16(_transferTriggerOptionIndex);
        p.transferRecipient      = _transferRecipient;
        p.transferAmount         = _transferAmount;
        p.transferEnabled        = _transferEnabled;
        p.transferToken          = _transferToken;
        p.tokenType              = _tokenType;
        p.electionEnabled        = _electionEnabled;

        uint256 proposalId = _proposals.length - 1;

        for (uint256 i; i < _optionNames.length; ) {
            p.options.push(PollOption(0));
            emit PollOptionNames(proposalId, i, _optionNames[i]);
            unchecked { ++i; }
        }

        uint256 electionId;
        if (_electionEnabled) {
            (electionId,) = elections.createElection(proposalId);
            for (uint256 i; i < _candidateAddresses.length; ) {
                elections.addCandidate(proposalId, _candidateAddresses[i], _candidateNames[i]);
                unchecked { ++i; }
            }
        }

        emit NewProposal(
            proposalId,
            _name,
            _description,
            _timeInMinutes,
            block.timestamp,
            _transferTriggerOptionIndex,
            _transferRecipient,
            _transferAmount,
            _transferEnabled,
            _transferToken,
            _electionEnabled,
            electionId
        );
    }

    /* ──────────────────────────────── Voting ───────────────────────────────── */
    function vote(
        uint256 _proposalId,
        uint256[] memory _optionIndices,
        uint256[] memory _weights
    ) external proposalExists(_proposalId) whenNotExpired(_proposalId) {
        if (_optionIndices.length != _weights.length) revert LengthMismatch();
        
        if (!nftMembership.canVote(msg.sender)) revert Unauthorized();

        Proposal storage p = _proposals[_proposalId];
        if (p.hasVoted[msg.sender]) revert AlreadyVoted();

        // ensure indices are unique
        for (uint256 i; i < _optionIndices.length; ++i) {
            for (uint256 j = i + 1; j < _optionIndices.length; ++j) {
                if (_optionIndices[i] == _optionIndices[j]) revert DuplicateOption();
            }
        }

        uint256 weightSum;
        for (uint256 i; i < _weights.length; ) {
            uint256 w = _weights[i];
            if (w > 100) revert InvalidWeight();
            unchecked { weightSum += w; ++i; }
        }
        if (weightSum != 100) revert WeightsMustSum100();

        p.hasVoted[msg.sender] = true;
        unchecked { ++p.totalVotes; }

        for (uint256 i; i < _optionIndices.length; ) {
            uint256 option = _optionIndices[i];
            if (option >= p.options.length) revert InvalidOption();
            p.options[option].votes += _weights[i];
            unchecked { ++i; }
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

        if (valid && p.transferEnabled && winner == p.transferTriggerIndex) {
            if (p.tokenType == TokenType.ETHER) {
                treasury.withdrawEther(p.transferRecipient, p.transferAmount);
            } else {
                treasury.sendTokens(p.transferToken, p.transferRecipient, p.transferAmount);
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
        for (uint256 i; i < len; ) {
            uint256 v = p.options[i].votes;
            if (v > highestVotes) {
                highestVotes   = v;
                winningOption  = i;
                hasValidWinner = highestVotes > p.totalVotes * quorumPercentage;
            }
            unchecked { ++i; }
        }
    }

    function getProposal(uint256 id)
        external
        view
        proposalExists(id)
        returns (
            uint256 totalVotes,
            uint256 endTimestamp,
            uint256 transferTriggerOptionIndex,
            address payable transferRecipient,
            uint256 transferAmount,
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
            p.transferTriggerIndex,
            p.transferRecipient,
            p.transferAmount,
            p.transferEnabled,
            p.transferToken,
            p.tokenType,
            p.electionEnabled,
            p.options.length
        );
    }

    function getOptionVotes(uint256 id, uint256 option)
        external
        view
        proposalExists(id)
        returns (uint256)
    {
        Proposal storage p = _proposals[id];
        if (option >= p.options.length) revert InvalidOption();
        return p.options[option].votes;
    }

    function proposalsCount() external view returns (uint256) { return _proposals.length; }

    /* ───────────────────────────── Cleanup Helper ───────────────────────────── */
    /**
     * @notice Deletes `hasVoted` flags after a proposal ends to reclaim gas (EIP‑3529).
     *         Gas refunds are capped to 20 percent of tx.gasUsed. Keep batches ≤4 000.
     * @param voters list of addresses to delete
     */
    function cleanupVotes(uint256 id, address[] calldata voters)
        external
        proposalExists(id)
        whenExpired(id)
    {
        if (voters.length > 4_000) revert TooManyVoters();
        Proposal storage p = _proposals[id];

        uint256 cleaned;
        for (uint256 i; i < voters.length; ) {
            delete p.hasVoted[voters[i]];
            unchecked { ++i; ++cleaned; }
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
    function version() external pure returns (string memory) { return "v1"; }

    uint256[49] private __gap;
}
