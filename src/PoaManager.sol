// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ImplementationRegistry.sol";

/**
 * @title PoaManager
 * @dev Owns and manages the Poa "official" beacon for a given module (Voting, in this example).
 *      This contract can upgrade the beacon to a new implementation.
 */
contract PoaManager is Ownable {
    // The official Poa beacon for the Voting module
    UpgradeableBeacon public poaBeacon;
    
    // Reference to the implementation registry
    ImplementationRegistry public implementationRegistry;
    
    // Initial implementation address (saved for registerInitialImplementation)
    address public initialImplementation;

    event BeaconUpgraded(address indexed newImplementation);

    constructor(address _initialImplementation, address _implementationRegistry) Ownable(msg.sender) {
        require(_initialImplementation != address(0), "Invalid implementation");
        require(_implementationRegistry != address(0), "Invalid registry");
        
        // Store the implementation registry
        implementationRegistry = ImplementationRegistry(_implementationRegistry);
        
        // Deploy an UpgradeableBeacon that references the initial implementation
        poaBeacon = new UpgradeableBeacon(_initialImplementation, address(this));
        
        // Save the initial implementation for later registration
        initialImplementation = _initialImplementation;
    }
    
    /**
     * @notice Register the initial implementation after ownership of the registry has been transferred to this contract
     */
    function registerInitialImplementation() external {
        // Register the initial implementation as "v1"
        implementationRegistry.registerImplementation("v1", initialImplementation, true);
    }

    /**
     * @notice Upgrade the Poa beacon to a new Voting implementation.
     * @param newImplementation The address of the new implementation
     * @param version The version string for this implementation
     */
    function upgradeBeacon(address newImplementation, string memory version) external onlyOwner {
        // Register the new implementation in the registry
        implementationRegistry.registerImplementation(version, newImplementation, true);
        
        // Upgrade the beacon
        poaBeacon.upgradeTo(newImplementation);
        emit BeaconUpgraded(newImplementation);
    }

    /**
     * @notice Get the current implementation that the Poa beacon is pointing to.
     */
    function getCurrentImplementation() external view returns (address) {
        return poaBeacon.implementation();
    }
    
    /**
     * @notice Get the implementation for a specific version.
     */
    function getImplementationByVersion(string memory version) external view returns (address) {
        return implementationRegistry.getImplementation(version);
    }
    
    /**
     * @notice Get the latest registered implementation.
     */
    function getLatestImplementation() external view returns (address) {
        return implementationRegistry.getLatestImplementation();
    }
}
