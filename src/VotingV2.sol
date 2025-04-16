// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title VotingV2
 * @dev An upgraded version of the Voting contract with additional features
 */
contract VotingV2 is Initializable {
    address public owner;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(bool => uint256)) public votes;
    mapping(uint256 => bool) public proposalPassed;
    
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool vote);
    event ProposalFinalized(uint256 indexed proposalId, bool passed);
    
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
    }
    
    function vote(uint256 proposalId, bool voteValue) external {
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        
        hasVoted[proposalId][msg.sender] = true;
        votes[proposalId][voteValue]++;
        
        emit VoteCast(msg.sender, proposalId, voteValue);
    }
    
    function getVotes(uint256 proposalId) external view returns (uint256 yes, uint256 no) {
        return (votes[proposalId][true], votes[proposalId][false]);
    }
    
    // New function in V2
    function finalizeProposal(uint256 proposalId) external {
        require(msg.sender == owner, "Only owner can finalize");
        
        uint256 yesVotes = votes[proposalId][true];
        uint256 noVotes = votes[proposalId][false];
        
        bool passed = yesVotes > noVotes;
        proposalPassed[proposalId] = passed;
        
        emit ProposalFinalized(proposalId, passed);
    }
    
    // Version identifier to help with testing upgrades
    function version() external pure returns (string memory) {
        return "v2";
    }
} 