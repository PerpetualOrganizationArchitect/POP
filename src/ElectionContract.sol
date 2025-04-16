// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface INFTMembership6 {
    function mintNFT(address recipient, string memory memberTypeName) external;
}

contract ElectionContract is Initializable {
    INFTMembership6 public nftMembership;
    address public votingContract;
    address public owner;
    bool public electionEnabled;

    struct Candidate {
        address candidateAddress;
        string candidateName;
    }

    struct Election {
        bool isActive;
        uint256 winningCandidateIndex;
        bool hasValidWinner;
        Candidate[] candidates;
    }

    mapping(uint256 => uint256) public proposalIdToElectionId;

    Election[] public elections;

    event ElectionCreated(uint256 proposalId, uint256 indexed electionId);
    event CandidateAdded(
        uint256 indexed electionId, uint256 candidateIndex, address candidateAddress, string candidateName
    );
    event ElectionConcluded(uint256 indexed electionId, uint256 winningCandidateIndex, bool hasValidWinner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyVotingContract() {
        require(msg.sender == votingContract, "Only voting contract can call this function");
        _;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor() {}

    function initialize(address _owner, address _nftMembership, address _votingContractAddress) external initializer {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
        nftMembership = INFTMembership6(_nftMembership);
        votingContract = _votingContractAddress;
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

    function createElection(uint256 _proposalId) external onlyVotingContract returns (uint256, uint256) {
        Election memory newElection;
        newElection.isActive = true;
        elections.push(newElection);
        proposalIdToElectionId[_proposalId] = elections.length - 1;

        uint256 electionId = elections.length - 1;
        emit ElectionCreated(electionId, _proposalId);
        return (electionId, _proposalId);
    }

    function addCandidate(uint256 proposalId, address _candidateAddress, string memory _candidateName)
        external
        onlyVotingContract
    {
        uint256 electionId = proposalIdToElectionId[proposalId];

        require(electionId < elections.length, "Invalid election ID");
        require(elections[electionId].isActive, "Election is not active");

        elections[electionId].candidates.push(Candidate(_candidateAddress, _candidateName));
        emit CandidateAdded(electionId, elections[electionId].candidates.length - 1, _candidateAddress, _candidateName);
    }

    function concludeElection(uint256 proposalId, uint256 winningOption) external onlyVotingContract {
        uint256 electionId = proposalIdToElectionId[proposalId];
        require(electionId < elections.length, "Invalid election ID");
        require(elections[electionId].isActive, "Election is already concluded");
        uint256 length = elections[electionId].candidates.length;

        require(length > winningOption, "Invalid winning option");

        Election storage election = elections[electionId];
        election.isActive = false;
        election.winningCandidateIndex = winningOption;
        election.hasValidWinner = true;

        // Mint NFT to the winning candidate
        nftMembership.mintNFT(elections[electionId].candidates[winningOption].candidateAddress, "Executive");

        emit ElectionConcluded(electionId, winningOption, true);
    }

    function getElectionDetails(uint256 electionId) external view returns (bool, uint256, bool) {
        require(electionId < elections.length, "Invalid election ID");
        Election storage election = elections[electionId];
        return (election.isActive, election.winningCandidateIndex, election.hasValidWinner);
    }

    function getCandidates(uint256 electionId) external view returns (Candidate[] memory) {
        require(electionId < elections.length, "Invalid election ID");
        return elections[electionId].candidates;
    }

    function getElectionResults(uint256 electionId) external view returns (uint256, bool) {
        require(electionId < elections.length, "Invalid election ID");
        return (elections[electionId].winningCandidateIndex, elections[electionId].hasValidWinner);
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
