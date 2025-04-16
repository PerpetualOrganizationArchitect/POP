// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OrgRegistry
 * @dev A contract that tracks organizations and their deployed contracts
 */
contract OrgRegistry is Ownable {
    // A struct to track deployed contract info
    struct ContractInfo {
        address beaconProxy;       // The contract's BeaconProxy address
        address beacon;            // The beacon that the proxy uses
        bool autoUpgrade;          // Whether the contract auto-upgrades
        address owner;             // The contract's owner (for reference)
    }
    
    // Organization info
    struct OrgInfo {
        bytes32 orgId;             // Organization ID
        address owner;             // Organization owner
        string name;               // Organization name
        uint256 contractCount;     // Number of contracts for this org
        bool exists;               // Whether the org exists
    }

    // orgId -> OrgInfo
    mapping(bytes32 => OrgInfo) public orgs;
    
    // contractId -> ContractInfo (contractId is typically orgId-contractType)
    mapping(bytes32 => ContractInfo) public contracts;
    
    // orgId -> contract type -> contract address
    mapping(bytes32 => mapping(string => address)) public orgContracts;
    
    // List of all organization IDs
    bytes32[] public orgIds;
    
    // List of all contract IDs
    bytes32[] public contractIds;

    // Events
    event OrgRegistered(bytes32 indexed orgId, address owner, string name);
    event ContractRegistered(
        bytes32 indexed contractId,
        bytes32 indexed orgId, 
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address owner
    );

    constructor() Ownable(msg.sender) {}
    
    /**
     * @notice Register a new organization
     * @param orgId Unique identifier for the organization
     * @param owner The owner of the organization
     * @param name The name of the organization
     */
    function registerOrg(
        bytes32 orgId,
        address owner,
        string memory name
    ) external onlyOwner {
        require(orgId != bytes32(0), "Invalid org ID");
        require(owner != address(0), "Invalid owner");
        require(!orgs[orgId].exists, "Org already registered");
        
        OrgInfo memory info = OrgInfo({
            orgId: orgId,
            owner: owner,
            name: name,
            contractCount: 0,
            exists: true
        });
        
        orgs[orgId] = info;
        orgIds.push(orgId);
        
        emit OrgRegistered(orgId, owner, name);
    }

    /**
     * @notice Register a new contract for an organization
     * @param contractId Unique identifier for the contract (typically orgId-contractType)
     * @param beaconProxy The contract's BeaconProxy address
     * @param beacon The beacon that the proxy uses
     * @param autoUpgrade Whether the contract auto-upgrades
     * @param owner The contract's owner
     */
    function registerContract(
        bytes32 contractId,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address owner
    ) public onlyOwner {
        require(contractId != bytes32(0), "Invalid contract ID");
        require(beaconProxy != address(0), "Invalid proxy address");
        require(beacon != address(0), "Invalid beacon address");
        require(owner != address(0), "Invalid owner");
        require(contracts[contractId].beaconProxy == address(0), "Contract already registered");

        ContractInfo memory info = ContractInfo({
            beaconProxy: beaconProxy,
            beacon: beacon,
            autoUpgrade: autoUpgrade,
            owner: owner
        });
        
        contracts[contractId] = info;
        contractIds.push(contractId);
        
        emit ContractRegistered(
            contractId,
            bytes32(0), // No specific orgId, as contractId is the primary key
            beaconProxy,
            beacon,
            autoUpgrade,
            owner
        );
    }
    
    /**
     * @notice Register a contract with a specific organization and contract type
     * @param orgId The organization ID
     * @param contractType The type of contract (e.g., "Voting", "Membership")
     * @param beaconProxy The contract's BeaconProxy address
     * @param beacon The beacon that the proxy uses
     * @param autoUpgrade Whether the contract auto-upgrades
     * @param owner The contract's owner
     */
    function registerOrgContract(
        bytes32 orgId,
        string memory contractType,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address owner
    ) external onlyOwner {
        require(orgs[orgId].exists, "Org not registered");
        require(bytes(contractType).length > 0, "Invalid contract type");
        require(orgContracts[orgId][contractType] == address(0), "Contract type already registered for org");
        
        // Generate a unique contract ID
        bytes32 contractId = keccak256(abi.encodePacked(orgId, "-", contractType));
        
        // Register the contract
        registerContract(contractId, beaconProxy, beacon, autoUpgrade, owner);
        
        // Link the contract to the organization
        orgContracts[orgId][contractType] = beaconProxy;
        
        // Increment the org's contract count
        orgs[orgId].contractCount++;
        
        // Emit with the orgId included
        emit ContractRegistered(
            contractId,
            orgId,
            beaconProxy,
            beacon,
            autoUpgrade,
            owner
        );
    }

    /**
     * @notice Get the contract address for an organization by contract type
     * @param orgId The organization ID
     * @param contractType The type of contract
     * @return The contract address
     */
    function getOrgContract(bytes32 orgId, string memory contractType) external view returns (address) {
        require(orgs[orgId].exists, "Org not registered");
        address contractAddress = orgContracts[orgId][contractType];
        require(contractAddress != address(0), "Contract not found for org");
        return contractAddress;
    }
    
    /**
     * @notice Get the beacon for a specific contract
     * @param contractId The contract ID
     * @return The beacon address
     */
    function getContractBeacon(bytes32 contractId) external view returns (address) {
        ContractInfo memory info = contracts[contractId];
        require(info.beaconProxy != address(0), "Contract not found");
        return info.beacon;
    }
    
    /**
     * @notice Check if a contract auto-upgrades
     * @param contractId The contract ID
     * @return Whether the contract auto-upgrades
     */
    function isContractAutoUpgrade(bytes32 contractId) external view returns (bool) {
        ContractInfo memory info = contracts[contractId];
        require(info.beaconProxy != address(0), "Contract not found");
        return info.autoUpgrade;
    }
    
    /**
     * @notice Get the number of registered organizations
     * @return The count of organizations
     */
    function getOrgCount() external view returns (uint256) {
        return orgIds.length;
    }
    
    /**
     * @notice Get the number of registered contracts
     * @return The count of contracts
     */
    function getContractCount() external view returns (uint256) {
        return contractIds.length;
    }
} 