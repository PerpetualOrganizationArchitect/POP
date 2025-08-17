// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DirectDemocracyVoting} from "../DirectDemocracyVoting.sol";

contract DirectDemocracyVotingLens {
    
    function getAllVotingHats(DirectDemocracyVoting voting) 
        external 
        view 
        returns (uint256[] memory hats, uint256 count) 
    {
        hats = abi.decode(voting.getStorage(DirectDemocracyVoting.StorageKey.VOTING_HATS, ""), (uint256[]));
        count = hats.length;
    }
    
    function getAllCreatorHats(DirectDemocracyVoting voting) 
        external 
        view 
        returns (uint256[] memory hats, uint256 count) 
    {
        hats = abi.decode(voting.getStorage(DirectDemocracyVoting.StorageKey.CREATOR_HATS, ""), (uint256[]));
        count = hats.length;
    }
    
    function getAllProposalHatIds(DirectDemocracyVoting voting, uint256 proposalId, uint256[] calldata hatIds) 
        external 
        view 
        returns (bool[] memory) 
    {
        bool[] memory allowed = new bool[](hatIds.length);
        for (uint256 i = 0; i < hatIds.length; i++) {
            allowed[i] = abi.decode(voting.getStorage(DirectDemocracyVoting.StorageKey.POLL_HAT_ALLOWED, abi.encode(proposalId, hatIds[i])), (bool));
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
        executor = abi.decode(voting.getStorage(DirectDemocracyVoting.StorageKey.EXECUTOR, ""), (address));
        hats = abi.decode(voting.getStorage(DirectDemocracyVoting.StorageKey.HATS, ""), (address));
        quorumPercentage = voting.quorumPct();
        proposalCount = voting.proposalsCount();
    }
}