// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ParticipationVoting} from "../ParticipationVoting.sol";

contract ParticipationVotingLens {
    function getVotingHatCount(ParticipationVoting voting) external view returns (uint256) {
        uint256[] memory hats = voting.votingHats();
        return hats.length;
    }

    function getCreatorHatCount(ParticipationVoting voting) external view returns (uint256) {
        uint256[] memory hats = voting.creatorHats();
        return hats.length;
    }

    function getAllProposalHatIds(ParticipationVoting voting, uint256 proposalId, uint256[] calldata hatIds)
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

    function getVotingConfig(ParticipationVoting voting)
        external
        view
        returns (address participationToken, bool quadraticVoting, uint256 minBalance, uint8 quorumPercentage)
    {
        participationToken = voting.participationToken();
        quadraticVoting = voting.quadraticVoting();
        minBalance = voting.minBalance();
        quorumPercentage = voting.quorumPercentage();
    }
}
