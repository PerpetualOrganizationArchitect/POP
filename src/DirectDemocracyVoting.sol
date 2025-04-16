// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface INFTMembership2 {
    function checkMemberTypeByAddress(address user) external view returns (string memory);
}

interface ITreasury {
    function sendTokens(address _token, address _to, uint256 _amount) external;
    function setVotingContract(address _votingContract) external;
    function withdrawEther(address payable _to, uint256 _amount) external;
}

interface IElections {
    function createElection(uint256 _proposalId) external returns (uint256, uint256);

    function addCandidate(uint256 _proposalId, address _candidateAddress, string memory _candidateName) external;

    function concludeElection(uint256 _electionId, uint256 winningOption) external;
}

contract DirectDemocracyVoting is Initializable {
    // State variables
    address public owner;
    IERC20 public DirectDemocracyToken;
    INFTMembership2 public nftMembership;
    ITreasury public treasury;
    IElections public elections;

    bool private electionSet = false;

    uint256 public quorumPercentage = 50;

    struct PollOption {
        uint256 votes;
    }

    struct Proposal {
        uint256 totalVotes;
        mapping(address => bool) hasVoted;
        uint256 timeInMinutes;
        uint256 creationTimestamp;
        PollOption[] options;
        uint256 transferTriggerOptionIndex;
        address payable transferRecipient;
        uint256 transferAmount;
        bool transferEnabled;
        address transferToken;
        bool electionEnabled;
    }

    Proposal[] private proposals;

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
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    mapping(string => bool) private allowedRoles;

    // Constructor is removed for proxy compatibility
    constructor() {}

    /**
     * @dev Initialize the contract for proxy pattern
     */
    function initialize(
        address _owner,
        address _ddToken,
        address _nftMembership,
        string[] memory _allowedRoleNames,
        address _treasuryAddress,
        uint256 _quorumPercentage
    ) external initializer {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
        quorumPercentage = _quorumPercentage;
        DirectDemocracyToken = IERC20(_ddToken);
        nftMembership = INFTMembership2(_nftMembership);
        treasury = ITreasury(_treasuryAddress);

        for (uint256 i = 0; i < _allowedRoleNames.length; i++) {
            allowedRoles[_allowedRoleNames[i]] = true;
        }
    }

    /**
     * @dev Modifier to restrict function access to the owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    /**
     * @dev Transfer ownership of the contract to a new account
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    modifier canCreateProposal() {
        string memory memberType = nftMembership.checkMemberTypeByAddress(msg.sender);
        require(allowedRoles[memberType], "Not authorized to create proposal");
        _;
    }

    modifier whenNotExpired(uint256 _proposalId) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        require(
            block.timestamp <= proposal.creationTimestamp + proposal.timeInMinutes * 1 minutes, "Voting time expired"
        );
        _;
    }

    modifier whenExpired(uint256 _proposalId) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        require(
            block.timestamp > proposal.creationTimestamp + proposal.timeInMinutes * 1 minutes,
            "Voting is not yet closed"
        );
        _;
    }

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
        bool _electionEnabled,
        address[] memory _candidateAddresses,
        string[] memory _candidateNames
    ) external canCreateProposal {
        require(_candidateAddresses.length == _candidateNames.length, "Candidates and names length mismatch");

        Proposal storage newProposal = proposals.push();
        newProposal.totalVotes = 0;
        newProposal.timeInMinutes = _timeInMinutes;
        newProposal.creationTimestamp = block.timestamp;
        newProposal.transferTriggerOptionIndex = _transferTriggerOptionIndex;
        newProposal.transferRecipient = _transferRecipient;
        newProposal.transferAmount = _transferAmount;
        newProposal.transferEnabled = _transferEnabled;
        newProposal.transferToken = _transferToken;
        newProposal.electionEnabled = _electionEnabled;

        uint256 proposalId = proposals.length - 1;

        for (uint256 i = 0; i < _optionNames.length; i++) {
            newProposal.options.push(PollOption(0));
            emit PollOptionNames(proposalId, i, _optionNames[i]);
        }

        uint256 electionId;

        if (_electionEnabled) {
            (electionId,) = elections.createElection(proposalId);
            for (uint256 i = 0; i < _candidateAddresses.length; i++) {
                elections.addCandidate(proposalId, _candidateAddresses[i], _candidateNames[i]);
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

    function vote(uint256 _proposalId, uint256[] memory _optionIndices, uint256[] memory _weights)
        external
        whenNotExpired(_proposalId)
    {
        address voter = msg.sender;
        uint256 balance = DirectDemocracyToken.balanceOf(voter);
        require(balance > 0, "No democracy tokens");

        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        require(!proposal.hasVoted[voter], "Already voted");

        // Sum of weights must be 100 (for percentage-based voting)
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < _weights.length; i++) {
            totalWeight += _weights[i];
        }
        require(totalWeight == 100, "Total weight must be 100");

        proposal.hasVoted[voter] = true;
        proposal.totalVotes += 1;

        for (uint256 i = 0; i < _optionIndices.length; i++) {
            uint256 optionIndex = _optionIndices[i];
            require(optionIndex < proposal.options.length, "Invalid option index");

            proposal.options[optionIndex].votes += _weights[i];
        }

        emit Voted(_proposalId, voter, _optionIndices, _weights);
    }

    function announceWinner(uint256 _proposalId) external whenExpired(_proposalId) returns (uint256, bool) {
        require(_proposalId < proposals.length, "Invalid proposal ID");

        (uint256 winningOptionIndex, bool hasValidWinner) = getWinner(_proposalId);

        if (
            hasValidWinner && proposals[_proposalId].transferEnabled
                && winningOptionIndex == proposals[_proposalId].transferTriggerOptionIndex
        ) {
            if (proposals[_proposalId].transferToken == address(0x0000000000000000000000000000000000001010)) {
                treasury.withdrawEther(proposals[_proposalId].transferRecipient, proposals[_proposalId].transferAmount);
            } else {
                treasury.sendTokens(
                    address(proposals[_proposalId].transferToken),
                    proposals[_proposalId].transferRecipient,
                    proposals[_proposalId].transferAmount
                );
            }
        }

        if (proposals[_proposalId].electionEnabled && hasValidWinner) {
            elections.concludeElection(_proposalId, winningOptionIndex);
        }

        emit WinnerAnnounced(_proposalId, winningOptionIndex, hasValidWinner);

        return (winningOptionIndex, hasValidWinner);
    }

    function getWinner(uint256 _proposalId) public view returns (uint256, bool) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        uint256 highestVotes = 0;
        uint256 winningOptionIndex = 0;
        bool hasValidWinner = false;
        // if no votes, no winner
        if (proposal.totalVotes == 0) {
            return (winningOptionIndex, hasValidWinner);
        }

        uint256 quorumThreshold = (proposal.totalVotes * quorumPercentage);

        // Determine the option with the highest votes that meets or exceeds the quorum
        for (uint256 i = 0; i < proposal.options.length; i++) {
            if (proposal.options[i].votes > highestVotes) {
                highestVotes = proposal.options[i].votes;
                winningOptionIndex = i;
                hasValidWinner = highestVotes > quorumThreshold;
            }
        }

        return (winningOptionIndex, hasValidWinner);
    }

    function getOptionsCount(uint256 _proposalId) public view returns (uint256) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        return proposal.options.length;
    }

    function getOptionVotes(uint256 _proposalId, uint256 _optionIndex) public view returns (uint256 votes) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        require(_optionIndex < proposal.options.length, "Invalid option index");
        return (proposal.options[_optionIndex].votes);
    }

    // Getter function to access a specific proposal by its ID
    function getProposal(uint256 _proposalId)
        public
        view
        returns (
            uint256 totalVotes,
            uint256 timeInMinutes,
            uint256 creationTimestamp,
            uint256 transferTriggerOptionIndex,
            address payable transferRecipient,
            uint256 transferAmount,
            bool transferEnabled,
            address transferToken
        )
    {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];

        return (
            proposal.totalVotes,
            proposal.timeInMinutes,
            proposal.creationTimestamp,
            proposal.transferTriggerOptionIndex,
            proposal.transferRecipient,
            proposal.transferAmount,
            proposal.transferEnabled,
            proposal.transferToken
        );
    }

    // Getter function to access the vote count for a specific option of a proposal
    function getProposalOptionVotes(uint256 _proposalId, uint256 _optionIndex) public view returns (uint256 votes) {
        require(_proposalId < proposals.length, "Invalid proposal ID");
        Proposal storage proposal = proposals[_proposalId];
        require(_optionIndex < proposal.options.length, "Invalid option index");

        PollOption storage option = proposal.options[_optionIndex];
        return (option.votes);
    }

    // Getter function to get the number of proposals
    function getProposalsCount() public view returns (uint256) {
        return proposals.length;
    }

    function setElectionsContract(address _electionsContract) public {
        require(!electionSet, "Election contract already set");
        elections = IElections(_electionsContract);
        electionSet = true;
        emit ElectionContractSet(_electionsContract);
    }

    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
