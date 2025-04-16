// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface IMembershipV2 {
    function isMember(address account) external view returns (bool);
    function hasRole(address member, string memory role) external view returns (bool);
}

/**
 * @title VotingV2
 * @dev An upgraded voting contract with enhanced functionality
 */
contract VotingV2 is Initializable {
    // Organization owner
    address public owner;
    
    // Membership contract address
    address public membershipContract;
    
    // Voting data
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(bool => uint256)) public votes;
    
    // Proposal data
    mapping(uint256 => bool) public proposalPassed;
    mapping(uint256 => bool) public proposalFinalized;
    mapping(uint256 => string) public proposalMetadata;
    mapping(uint256 => string) public requiredRole; // Empty string means any member can vote
    
    // Events
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool vote);
    event MembershipContractSet(address indexed membershipContract);
    event ProposalCreated(uint256 indexed proposalId, string metadata, string requiredRole);
    event ProposalFinalized(uint256 indexed proposalId, bool passed);
    
    /**
     * @dev Initialize the contract with an owner
     */
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
    }
    
    /**
     * @dev Modifier to restrict function access to the organization owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not org owner");
        _;
    }
    
    /**
     * @dev Set the membership contract address
     */
    function setMembershipContract(address _membershipContract) external {
        require(_membershipContract != address(0), "Invalid membership contract");
        membershipContract = _membershipContract;
        emit MembershipContractSet(_membershipContract);
    }
    
    /**
     * @dev Create a new proposal with metadata and role requirement
     */
    function createProposal(uint256 proposalId, string memory metadata, string memory _requiredRole) external onlyOwner {
        require(!proposalFinalized[proposalId], "Proposal already finalized");
        proposalMetadata[proposalId] = metadata;
        requiredRole[proposalId] = _requiredRole;
        emit ProposalCreated(proposalId, metadata, _requiredRole);
    }
    
    /**
     * @dev Cast a vote on a proposal, only available to members with appropriate role
     */
    function vote(uint256 proposalId, bool voteValue) external {
        // Check if membership contract is set
        require(membershipContract != address(0), "Membership contract not set");
        
        // Check if proposal is finalized
        require(!proposalFinalized[proposalId], "Proposal already finalized");
        
        // Check if sender is a member
        require(IMembershipV2(membershipContract).isMember(msg.sender), "Only members can vote");
        
        // Check if this proposal has a required role
        string memory role = requiredRole[proposalId];
        if (bytes(role).length > 0) {
            require(
                IMembershipV2(membershipContract).hasRole(msg.sender, role),
                "Member doesn't have required role"
            );
        }
        
        // Check if sender has already voted
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        // Record the vote
        hasVoted[proposalId][msg.sender] = true;
        votes[proposalId][voteValue]++;
        
        emit VoteCast(msg.sender, proposalId, voteValue);
    }
    
    /**
     * @dev Get the vote counts for a proposal
     */
    function getVotes(uint256 proposalId) external view returns (uint256 yes, uint256 no) {
        return (votes[proposalId][true], votes[proposalId][false]);
    }
    
    /**
     * @dev Check if an address is eligible to vote on a specific proposal
     */
    function canVote(address account, uint256 proposalId) external view returns (bool) {
        if (membershipContract == address(0)) return false;
        if (!IMembershipV2(membershipContract).isMember(account)) return false;
        if (hasVoted[proposalId][account]) return false;
        if (proposalFinalized[proposalId]) return false;
        
        string memory role = requiredRole[proposalId];
        if (bytes(role).length > 0) {
            return IMembershipV2(membershipContract).hasRole(account, role);
        }
        
        return true;
    }
    
    /**
     * @dev Finalize a proposal and determine if it passed
     */
    function finalizeProposal(uint256 proposalId) external onlyOwner {
        require(!proposalFinalized[proposalId], "Proposal already finalized");
        
        uint256 yesVotes = votes[proposalId][true];
        uint256 noVotes = votes[proposalId][false];
        
        bool passed = yesVotes > noVotes;
        proposalPassed[proposalId] = passed;
        proposalFinalized[proposalId] = true;
        
        emit ProposalFinalized(proposalId, passed);
    }
    
    /**
     * @dev Get proposal details
     */
    function getProposalDetails(uint256 proposalId) external view returns (
        string memory metadata,
        string memory role,
        uint256 yesVotes,
        uint256 noVotes,
        bool isFinalized,
        bool didPass
    ) {
        metadata = proposalMetadata[proposalId];
        role = requiredRole[proposalId];
        yesVotes = votes[proposalId][true];
        noVotes = votes[proposalId][false];
        isFinalized = proposalFinalized[proposalId];
        didPass = proposalPassed[proposalId];
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v2";
    }
} 