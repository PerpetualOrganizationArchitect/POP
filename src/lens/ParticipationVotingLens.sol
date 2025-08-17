// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ParticipationVoting} from "../ParticipationVoting.sol";

contract ParticipationVotingLens {
    
    function getVotingHatCount(ParticipationVoting voting) external view returns (uint256) {
        uint256[] memory hats = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.VOTING_HATS, ""), (uint256[]));
        return hats.length;
    }
    
    function getCreatorHatCount(ParticipationVoting voting) external view returns (uint256) {
        uint256[] memory hats = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.CREATOR_HATS, ""), (uint256[]));
        return hats.length;
    }
    
    function getAllProposalHatIds(ParticipationVoting voting, uint256 proposalId, uint256[] calldata hatIds) 
        external 
        view 
        returns (bool[] memory) 
    {
        bool[] memory allowed = new bool[](hatIds.length);
        for (uint256 i = 0; i < hatIds.length; i++) {
            allowed[i] = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.POLL_HAT_ALLOWED, abi.encode(proposalId, hatIds[i])), (bool));
        }
        return allowed;
    }
    
    function getVotingConfig(ParticipationVoting voting) 
        external 
        view 
        returns (
            address participationToken,
            bool quadraticVoting,
            uint256 minBalance,
            uint8 quorumPercentage
        ) 
    {
        participationToken = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.PARTICIPATION_TOKEN, ""), (address));
        quadraticVoting = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.QUADRATIC_VOTING, ""), (bool));
        minBalance = abi.decode(voting.getStorage(ParticipationVoting.StorageKey.MIN_BALANCE, ""), (uint256));
        quorumPercentage = voting.quorumPercentage();
    }
}