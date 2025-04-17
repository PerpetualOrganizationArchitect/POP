// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────── Interface to membership module that mints EXEC_ROLE ──────────*/
interface INFTMembership {
    function mintOrChange(address member, bytes32 roleId) external;
}

contract ElectionContract is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*──────────────────────────── Errors ─────────────────────────────*/
    error AlreadyLinked();
    error ElectionInactive();
    error InvalidElection();
    error CandidateDup();
    error NoCandidates();
    error InvalidWinner();
    error TooManyCandidates();
    error AlreadyCleaned();

    /*────────────────────────── Constants ───────────────────────────*/
    bytes32 public constant EXEC_ROLE = keccak256("EXECUTIVE");
    uint256 private constant MAX_CANDIDATES = 100;

    /*─────────────────────────── Storage ────────────────────────────*/
    INFTMembership public nftMembership;
    address public votingContract;

    struct Candidate {
        address candidateAddress;
        bytes32 nameHash;
    }

    struct Election {
        bool isActive;
        bool cleaned;
        uint256 winningCandidateIndex;
        bool hasValidWinner;
        Candidate[] candidates;
        mapping(address => bool) addrTaken;
        mapping(bytes32 => bool) nameTaken;
    }

    mapping(uint256 => uint256) public proposalToElection;
    mapping(uint256 => bool) private _proposalLinked;

    Election[] private _elections;

    /*──────────────────────────── Events ─────────────────────────────*/
    event ElectionCreated(uint256 indexed electionId, uint256 indexed proposalId);
    event CandidateAdded(
        uint256 indexed electionId, uint256 indexed candidateIndex, address candidateAddress, string candidateName
    );
    event ElectionConcluded(uint256 indexed electionId, uint256 winningCandidateIndex);
    event CandidatesCleared(uint256 indexed electionId);

    /*────────────────────────── Initializer ─────────────────────────*/
    function initialize(address _owner, address _membership, address _voting) external initializer {
        require(_owner != address(0) && _membership != address(0) && _voting != address(0), "addr=0");
        __Ownable_init(_owner);
        __ReentrancyGuard_init();

        nftMembership = INFTMembership(_membership);
        votingContract = _voting;
    }

    /*────────────────────── Modifiers / Access ──────────────────────*/
    modifier onlyVoting() {
        require(msg.sender == votingContract, "voting-only");
        _;
    }

    /*────────────────────── Election Lifecycle ──────────────────────*/
    function createElection(uint256 proposalId) external onlyVoting returns (uint256 electionId) {
        if (_proposalLinked[proposalId]) revert AlreadyLinked();

        electionId = _elections.length;
        _elections.push();
        _elections[electionId].isActive = true;

        proposalToElection[proposalId] = electionId;
        _proposalLinked[proposalId] = true;

        emit ElectionCreated(electionId, proposalId);
    }

    function addCandidate(uint256 proposalId, address candidateAddr, string calldata candidateName)
        external
        onlyVoting
    {
        uint256 id = _mapped(proposalId);
        Election storage e = _elections[id];
        if (!e.isActive) revert ElectionInactive();
        if (candidateAddr == address(0) || e.addrTaken[candidateAddr]) revert CandidateDup();
        if (e.candidates.length >= MAX_CANDIDATES) revert TooManyCandidates();

        bytes32 nameHash = _nameHash(candidateName);
        if (e.nameTaken[nameHash]) revert CandidateDup();

        e.addrTaken[candidateAddr] = true;
        e.nameTaken[nameHash] = true;
        e.candidates.push(Candidate(candidateAddr, nameHash));

        emit CandidateAdded(id, e.candidates.length - 1, candidateAddr, candidateName);
    }

    function concludeElection(uint256 proposalId, uint256 winningIdx) external onlyVoting nonReentrant {
        uint256 id = _mapped(proposalId);
        Election storage e = _elections[id];
        if (!e.isActive) revert ElectionInactive();

        uint256 len = e.candidates.length;
        if (len == 0) revert NoCandidates();
        if (winningIdx >= len) revert InvalidWinner();

        e.isActive = false;
        e.hasValidWinner = true;
        e.winningCandidateIndex = winningIdx;

        nftMembership.mintOrChange(e.candidates[winningIdx].candidateAddress, EXEC_ROLE);

        emit ElectionConcluded(id, winningIdx);
    }

    /*──────────────── Candidate Cleanup ────────────────*/
    function clearCandidates(uint256 electionId) external nonReentrant {
        if (electionId >= _elections.length) revert InvalidElection();
        Election storage e = _elections[electionId];
        if (e.isActive) revert ElectionInactive();
        if (e.cleaned) revert AlreadyCleaned();

        delete e.candidates;
        e.cleaned = true;

        emit CandidatesCleared(electionId);
    }

    /*─────────────────────────── Views ──────────────────────────────*/
    function getElection(uint256 id)
        external
        view
        returns (bool active, uint256 winner, bool hasWinner, uint256 candidateCount)
    {
        if (id >= _elections.length) revert InvalidElection();
        Election storage e = _elections[id];
        return (e.isActive, e.winningCandidateIndex, e.hasValidWinner, e.candidates.length);
    }

    function getCandidate(uint256 electionId, uint256 index) external view returns (address addr, bytes32 nameHash) {
        if (electionId >= _elections.length) revert InvalidElection();
        Election storage e = _elections[electionId];
        if (index >= e.candidates.length) revert InvalidWinner();
        Candidate storage c = e.candidates[index];
        return (c.candidateAddress, c.nameHash);
    }

    function candidatesCount(uint256 electionId) external view returns (uint256) {
        if (electionId >= _elections.length) revert InvalidElection();
        return _elections[electionId].candidates.length;
    }

    /*────────────────────── Internal Helpers ───────────────────────*/
    function _mapped(uint256 proposalId) private view returns (uint256 id) {
        id = proposalToElection[proposalId];
        if (!_proposalLinked[proposalId] || id >= _elections.length) revert InvalidElection();
    }

    function _nameHash(string calldata s) private pure returns (bytes32) {
        bytes memory lower = bytes(s);
        for (uint256 i; i < lower.length;) {
            uint8 c = uint8(lower[i]);
            if (c >= 65 && c <= 90) lower[i] = bytes1(c + 32);
            unchecked {
                ++i;
            }
        }
        return keccak256(lower);
    }

    /*─────────────── Upgrade storage gap ───────────────*/
    uint256[44] private __gap;
}
