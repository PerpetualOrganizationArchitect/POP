// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ImplementationRegistry
 * @dev A contract that tracks implementation versions for different contract types
 */
contract ImplementationRegistry is Ownable {
    // Contract Type -> (Version string -> Implementation address)
    mapping(string => mapping(string => address)) public implementations;

    // Contract type -> all versions array
    mapping(string => string[]) public contractVersions;

    // Contract type -> latest version
    mapping(string => string) public latestVersions;

    // List of all registered contract types
    string[] public contractTypes;

    // Events
    event ImplementationRegistered(string contractType, string version, address implementation);
    event LatestVersionUpdated(string contractType, string version);
    event ContractTypeAdded(string contractType);

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new implementation version for a contract type
     * @param contractType The type of contract (e.g., "Voting", "Membership")
     * @param version The version string (e.g., "v1", "v2")
     * @param implementation The implementation contract address
     * @param setAsLatest Whether to set this as the latest version
     */
    function registerImplementation(
        string memory contractType,
        string memory version,
        address implementation,
        bool setAsLatest
    ) external onlyOwner {
        require(bytes(contractType).length > 0, "Contract type cannot be empty");
        require(bytes(version).length > 0, "Version cannot be empty");
        require(implementation != address(0), "Invalid implementation address");

        // If this is a new contract type, add it to the list
        if (implementations[contractType][version] == address(0) && !_contractTypeExists(contractType)) {
            contractTypes.push(contractType);
            emit ContractTypeAdded(contractType);
        }

        // Only add to versions array if it's a new version
        if (implementations[contractType][version] == address(0)) {
            contractVersions[contractType].push(version);
        }

        implementations[contractType][version] = implementation;
        emit ImplementationRegistered(contractType, version, implementation);

        if (setAsLatest) {
            latestVersions[contractType] = version;
            emit LatestVersionUpdated(contractType, version);
        }
    }

    /**
     * @notice Set a specific version as the latest for a contract type
     * @param contractType The type of contract
     * @param version The version to set as latest
     */
    function setLatestVersion(string memory contractType, string memory version) external onlyOwner {
        require(implementations[contractType][version] != address(0), "Version not registered");
        latestVersions[contractType] = version;
        emit LatestVersionUpdated(contractType, version);
    }

    /**
     * @notice Get the latest implementation address for a contract type
     * @param contractType The type of contract
     * @return The address of the latest implementation
     */
    function getLatestImplementation(string memory contractType) external view returns (address) {
        string memory latestVersion = latestVersions[contractType];
        return implementations[contractType][latestVersion];
    }

    /**
     * @notice Get a specific implementation by contract type and version
     * @param contractType The type of contract
     * @param version The version to get
     * @return The implementation address for the specified version
     */
    function getImplementation(string memory contractType, string memory version) external view returns (address) {
        require(implementations[contractType][version] != address(0), "Version not registered");
        return implementations[contractType][version];
    }

    /**
     * @notice Get the number of registered versions for a contract type
     * @param contractType The type of contract
     * @return The count of versions
     */
    function getVersionCount(string memory contractType) external view returns (uint256) {
        return contractVersions[contractType].length;
    }

    /**
     * @notice Get the number of registered contract types
     * @return The count of contract types
     */
    function getContractTypeCount() external view returns (uint256) {
        return contractTypes.length;
    }

    /**
     * @notice Get a specific version for a contract type by index
     * @param contractType The type of contract
     * @param index The index in the versions array
     * @return The version string
     */
    function getVersionAtIndex(string memory contractType, uint256 index) external view returns (string memory) {
        require(index < contractVersions[contractType].length, "Index out of bounds");
        return contractVersions[contractType][index];
    }

    /**
     * @notice Get a contract type by index
     * @param index The index in the contract types array
     * @return The contract type string
     */
    function getContractTypeAtIndex(uint256 index) external view returns (string memory) {
        require(index < contractTypes.length, "Index out of bounds");
        return contractTypes[index];
    }

    /**
     * @notice Check if a contract type exists
     * @param contractType The type to check
     * @return True if the contract type exists
     */
    function _contractTypeExists(string memory contractType) internal view returns (bool) {
        for (uint256 i = 0; i < contractTypes.length; i++) {
            if (keccak256(bytes(contractTypes[i])) == keccak256(bytes(contractType))) {
                return true;
            }
        }
        return false;
    }
}
