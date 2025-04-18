// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IParticipationToken2 is IERC20 {
    function mint(address to, uint256 amount) external;
}

interface INFTMembership11 {
    function checkMemberTypeByAddress(address user) external view returns (string memory);
    function checkIsExecutive(address user) external view returns (bool);
}

contract EducationHub {
    struct Module {
        uint256 id;
        string name;
        string ipfsHash;
        bool exists;
        uint256 payout;
        uint8 correctAnswer;
    }

    mapping(uint256 => Module) public modules;
    mapping(address => mapping(uint256 => bool)) public completedModules; // Tracks completion per user per module

    uint256 public nextModuleId;

    IParticipationToken2 public token;
    INFTMembership11 public nftMembership;

    event ModuleCreated(uint256 indexed id, string name, string ipfsHash, uint256 payout, uint8 correctAnswer);
    event ModuleCompleted(uint256 indexed id, address indexed completer);

    constructor(address _token, address _nftMembership) {
        token = IParticipationToken2(_token);
        nftMembership = INFTMembership11(_nftMembership);
    }

    modifier isMember() {
        string memory memberType = nftMembership.checkMemberTypeByAddress(msg.sender);
        require(bytes(memberType).length != 0, "Not a member");
        _;
    }

    modifier isExecutive() {
        require(nftMembership.checkIsExecutive(msg.sender), "Not an executive");
        _;
    }

    function createModule(string memory _name, string memory _ipfsHash, uint256 _payout, uint8 _correctAnswer)
        public
        isExecutive
    {
        require(_payout > 0, "Payout must be greater than zero");

        uint256 moduleId = nextModuleId++;
        require(!modules[moduleId].exists, "Module already exists");

        modules[moduleId] = Module({
            id: moduleId,
            name: _name,
            ipfsHash: _ipfsHash,
            exists: true,
            payout: _payout,
            correctAnswer: _correctAnswer
        });

        emit ModuleCreated(moduleId, _name, _ipfsHash, _payout, _correctAnswer);
    }

    function completeModule(uint256 _moduleId, uint8 _answer) public isMember {
        Module memory module = modules[_moduleId];
        require(module.exists, "Module does not exist");
        require(_answer == module.correctAnswer, "Incorrect answer");
        require(!completedModules[msg.sender][_moduleId], "Module already completed");

        token.mint(msg.sender, module.payout);
        completedModules[msg.sender][_moduleId] = true;

        emit ModuleCompleted(_moduleId, msg.sender);
    }

    function removeModule(uint256 _moduleId) public isExecutive {
        require(modules[_moduleId].exists, "Module does not exist");

        delete modules[_moduleId];
    }
}
