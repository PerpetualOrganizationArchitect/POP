// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HybridVoting} from "../HybridVoting.sol";

contract HybridVotingLens {
    
    function getCreatorHatCount(HybridVoting voting) external view returns (uint256) {
        uint256[] memory hats = voting.creatorHats();
        return hats.length;
    }
    
    function getProposalEndTimestamp(HybridVoting voting, uint256 id) external view returns (uint64) {
        HybridVoting.ClassConfig[] memory classes = voting.getProposalClasses(id);
        if (classes.length == 0) revert("Invalid proposal");
        // Note: End timestamp would need to be exposed via a new getter in HybridVoting
        // For now, this demonstrates the pattern
        return 0;
    }
    
    function getAllProposalHatIds(HybridVoting voting, uint256 proposalId, uint256[] calldata hatIds) 
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
    
    function isProposalActive(HybridVoting voting, uint256 id) external view returns (bool) {
        // Would need endTimestamp exposed from HybridVoting
        // This is a placeholder showing the lens pattern
        return voting.pollRestricted(id) || !voting.pollRestricted(id);
    }
}