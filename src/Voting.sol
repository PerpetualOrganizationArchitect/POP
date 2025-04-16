// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface IMembership {
    function isMember(address account) external view returns (bool);
}

/**
 * @title Voting
 * @dev A simple voting contract that only allows members to vote
 */
contract Voting is Initializable {
    // Organization owner
    address public owner;
    
    // Membership contract address
    address public membershipContract;
    
    // Voting data
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(bool => uint256)) public votes;
    
    // Events
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool vote);
    event MembershipContractSet(address indexed membershipContract);
    
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
     * @dev Cast a vote on a proposal, only available to members
     */
    function vote(uint256 proposalId, bool voteValue) external {
        // Check if membership contract is set
        require(membershipContract != address(0), "Membership contract not set");
        
        // Check if sender is a member
        require(IMembership(membershipContract).isMember(msg.sender), "Only members can vote");
        
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
     * @dev Check if an address is eligible to vote
     */
    function canVote(address account) external view returns (bool) {
        if (membershipContract == address(0)) return false;
        return IMembership(membershipContract).isMember(account);
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
