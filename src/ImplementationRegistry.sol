// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ImplementationRegistry
 * @dev A contract that tracks implementation versions and their addresses
 */
contract ImplementationRegistry is Ownable {
    // Version string -> Implementation address
    mapping(string => address) public implementations;
    
    // Array to keep track of all versions
    string[] public allVersions;
    
    // Latest version
    string public latestVersion;
    
    event ImplementationRegistered(string version, address implementation);
    event LatestVersionUpdated(string version);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new implementation version
     * @param version The version string (e.g., "v1", "v2")
     * @param implementation The implementation contract address
     * @param setAsLatest Whether to set this as the latest version
     */
    function registerImplementation(
        string memory version,
        address implementation,
        bool setAsLatest
    ) external onlyOwner {
        require(bytes(version).length > 0, "Version cannot be empty");
        require(implementation != address(0), "Invalid implementation address");
        
        // Only add to versions array if it's a new version
        if (implementations[version] == address(0)) {
            allVersions.push(version);
        }
        
        implementations[version] = implementation;
        emit ImplementationRegistered(version, implementation);
        
        if (setAsLatest) {
            latestVersion = version;
            emit LatestVersionUpdated(version);
        }
    }
    
    /**
     * @notice Set a specific version as the latest
     * @param version The version to set as latest
     */
    function setLatestVersion(string memory version) external onlyOwner {
        require(implementations[version] != address(0), "Version not registered");
        latestVersion = version;
        emit LatestVersionUpdated(version);
    }
    
    /**
     * @notice Get the latest implementation address
     * @return The address of the latest implementation
     */
    function getLatestImplementation() external view returns (address) {
        return implementations[latestVersion];
    }
    
    /**
     * @notice Get a specific implementation by version
     * @param version The version to get
     * @return The implementation address for the specified version
     */
    function getImplementation(string memory version) external view returns (address) {
        require(implementations[version] != address(0), "Version not registered");
        return implementations[version];
    }
    
    /**
     * @notice Get the number of registered versions
     * @return The count of versions
     */
    function getVersionCount() external view returns (uint256) {
        return allVersions.length;
    }
} 