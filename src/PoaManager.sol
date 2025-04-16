// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ImplementationRegistry.sol";

/**
 * @title PoaManager
 * @dev Manages the official beacons for different contract types
 */
contract PoaManager is Ownable {
    // Contract type -> Beacon
    mapping(string => UpgradeableBeacon) public beacons;

    // Reference to the implementation registry
    ImplementationRegistry public implementationRegistry;

    // List of contract types
    string[] public contractTypes;

    // Initial implementations - contract type -> implementation address
    mapping(string => address) public initialImplementations;

    // Events
    event BeaconUpgraded(string indexed contractType, address indexed newImplementation);
    event BeaconCreated(string indexed contractType, address indexed beaconAddress, address indexed implementation);

    constructor(address _implementationRegistry) Ownable(msg.sender) {
        require(_implementationRegistry != address(0), "Invalid registry");
        implementationRegistry = ImplementationRegistry(_implementationRegistry);
    }

    /**
     * @notice Add a new contract type with initial implementation
     * @param contractType The type of contract (e.g., "Voting", "Membership")
     * @param initialImplementation The initial implementation address
     */
    function addContractType(string memory contractType, address initialImplementation) external onlyOwner {
        require(bytes(contractType).length > 0, "Contract type cannot be empty");
        require(initialImplementation != address(0), "Invalid implementation");
        require(address(beacons[contractType]) == address(0), "Contract type already exists");

        // Deploy a new beacon for this contract type
        UpgradeableBeacon beacon = new UpgradeableBeacon(initialImplementation, address(this));

        // Register the contract type
        beacons[contractType] = beacon;
        contractTypes.push(contractType);
        initialImplementations[contractType] = initialImplementation;

        emit BeaconCreated(contractType, address(beacon), initialImplementation);
    }

    /**
     * @notice Register the initial implementation for a contract type
     * @param contractType The type of contract to register
     */
    function registerInitialImplementation(string memory contractType) external {
        require(address(beacons[contractType]) != address(0), "Contract type not found");
        address implementation = initialImplementations[contractType];

        // Register the initial implementation as "v1"
        implementationRegistry.registerImplementation(contractType, "v1", implementation, true);
    }

    /**
     * @notice Upgrade the beacon for a contract type to a new implementation
     * @param contractType The type of contract to upgrade
     * @param newImplementation The address of the new implementation
     * @param version The version string for this implementation
     */
    function upgradeBeacon(string memory contractType, address newImplementation, string memory version)
        external
        onlyOwner
    {
        require(address(beacons[contractType]) != address(0), "Contract type not found");
        require(newImplementation != address(0), "Invalid implementation");

        // Register the new implementation in the registry
        implementationRegistry.registerImplementation(contractType, version, newImplementation, true);

        // Upgrade the beacon
        beacons[contractType].upgradeTo(newImplementation);
        emit BeaconUpgraded(contractType, newImplementation);
    }

    /**
     * @notice Get the beacon address for a contract type
     * @param contractType The type of contract
     * @return The beacon address
     */
    function getBeacon(string memory contractType) external view returns (address) {
        require(address(beacons[contractType]) != address(0), "Contract type not found");
        return address(beacons[contractType]);
    }

    /**
     * @notice Get the current implementation for a contract type
     * @param contractType The type of contract
     * @return The current implementation address
     */
    function getCurrentImplementation(string memory contractType) external view returns (address) {
        require(address(beacons[contractType]) != address(0), "Contract type not found");
        return beacons[contractType].implementation();
    }

    /**
     * @notice Get the implementation for a specific version of a contract type
     * @param contractType The type of contract
     * @param version The version string
     * @return The implementation address
     */
    function getImplementationByVersion(string memory contractType, string memory version)
        external
        view
        returns (address)
    {
        return implementationRegistry.getImplementation(contractType, version);
    }

    /**
     * @notice Get the latest registered implementation for a contract type
     * @param contractType The type of contract
     */
    function getLatestImplementation(string memory contractType) external view returns (address) {
        return implementationRegistry.getLatestImplementation(contractType);
    }

    /**
     * @notice Get the number of contract types
     * @return The count of contract types
     */
    function getContractTypeCount() external view returns (uint256) {
        return contractTypes.length;
    }
}
