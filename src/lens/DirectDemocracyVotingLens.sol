// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DirectDemocracyVoting} from "../DirectDemocracyVoting.sol";

contract DirectDemocracyVotingLens {
    
    function getAllVotingHats(DirectDemocracyVoting voting) 
        external 
        view 
        returns (uint256[] memory hats, uint256 count) 
    {
        hats = voting.votingHats();
        count = voting.votingHatCount();
    }
    
    function getAllCreatorHats(DirectDemocracyVoting voting) 
        external 
        view 
        returns (uint256[] memory hats, uint256 count) 
    {
        hats = voting.creatorHats();
        count = voting.creatorHatCount();
    }
    
    function getAllProposalHatIds(DirectDemocracyVoting voting, uint256 proposalId, uint256[] calldata hatIds) 
        external 
        view 
        returns (bool[] memory) 
    {
        bool[] memory allowed = new bool[](hatIds.length);
        for (uint256 i = 0; i < hatIds.length; i++) {
            allowed[i] = voting.pollHatAllowed(proposalId, hatIds[i]);
        }
        return allowed;
    }
    
    function getGovernanceConfig(DirectDemocracyVoting voting) 
        external 
        view 
        returns (
            address executor,
            address hats,
            uint8 quorumPercentage,
            uint256 proposalCount
        ) 
    {
        executor = voting.executor();
        hats = voting.hats();
        quorumPercentage = voting.quorumPercentage();
        proposalCount = voting.proposalsCount();
    }
}