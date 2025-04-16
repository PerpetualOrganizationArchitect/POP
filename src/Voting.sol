// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Voting
 * @dev A simple voting contract that can be used as the implementation for the beacon proxy
 */
contract Voting is Initializable {
    address public owner;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => mapping(bool => uint256)) public votes;
    
    event VoteCast(address indexed voter, uint256 indexed proposalId, bool vote);
    
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
    
    // Version identifier to help with testing upgrades
    function version() external pure returns (string memory) {
        return "v1";
    }
}
