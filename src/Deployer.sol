// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./OrgRegistry.sol";

interface IPoaManager {
    function getBeacon(string memory contractType) external view returns (address);
    function getCurrentImplementation(string memory contractType) external view returns (address);
}

/**
 * @title Deployer
 * @dev A factory-style contract that lets organizations deploy their own beacon proxies
 *      for different contract types
 */
contract Deployer is Ownable {
    using Address for address;

    // Reference to the PoaManager
    IPoaManager public poaManager;
    
    // Reference to the OrgRegistry
    OrgRegistry public orgRegistry;

    // Events
    event ContractDeployed(
        bytes32 indexed orgId,
        string contractType,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address orgOwner
    );

    constructor(address _poaManager, address _orgRegistry) Ownable(msg.sender) {
        require(_poaManager != address(0), "Invalid PoaManager");
        require(_orgRegistry != address(0), "Invalid OrgRegistry");
        poaManager = IPoaManager(_poaManager);
        orgRegistry = OrgRegistry(_orgRegistry);
    }

    /**
     * @notice Deploy a BeaconProxy for a specific contract type
     * @param orgId Unique identifier for the Org
     * @param contractType The type of contract to deploy (e.g., "Voting", "Membership")
     * @param orgOwner The address that will own/admin the module
     * @param autoUpgrade If true, uses Poa's official beacon for auto-upgrades
     * @param customImplementation Custom implementation (only used if autoUpgrade=false)
     * @param initData The initialization data for the proxy
     */
    function deployContract(
        bytes32 orgId,
        string memory contractType,
        address orgOwner,
        bool autoUpgrade,
        address customImplementation,
        bytes memory initData
    ) public returns (address beaconProxy) {
        require(bytes(contractType).length > 0, "Contract type cannot be empty");
        require(orgOwner != address(0), "Invalid org owner");
        require(initData.length > 0, "Initialization data required");

        // 1. Determine beacon address
        address beacon;
        if (autoUpgrade) {
            // The org's BeaconProxy will point directly to Poa's official beacon
            beacon = poaManager.getBeacon(contractType);
            require(beacon != address(0), "Contract type not supported");
        } else {
            // The org does NOT want auto-upgrades -> create a new local beacon
            address implementation = customImplementation;
            if (implementation == address(0)) {
                // Fallback to Poa's current official implementation
                implementation = poaManager.getCurrentImplementation(contractType);
            }
            require(implementation != address(0), "Implementation not found");

            // Create a new beacon owned by the org owner
            UpgradeableBeacon newOrgBeacon = new UpgradeableBeacon(implementation, orgOwner);
            beacon = address(newOrgBeacon);
        }

        // 2. Deploy the BeaconProxy with the initialization data
        BeaconProxy proxy = new BeaconProxy(beacon, initData);

        // 3. Register the contract in the OrgRegistry
        orgRegistry.registerOrgContract(
            orgId,
            contractType,
            address(proxy),
            beacon,
            autoUpgrade,
            orgOwner
        );

        emit ContractDeployed(orgId, contractType, address(proxy), beacon, autoUpgrade, orgOwner);

        return address(proxy);
    }
    
    /**
     * @notice Deploy an organization (creates a Voting contract)
     * @param orgId Unique identifier for the Org
     * @param orgOwner The address that will own the Voting contract
     * @param autoUpgrade If true, uses Poa's official beacon for auto-upgrades
     * @param customImplementation Custom implementation (only used if autoUpgrade=false)
     */
    function deployOrg(
        bytes32 orgId,
        address orgOwner,
        bool autoUpgrade,
        address customImplementation
    ) public returns (address votingProxy) {
        // Register the organization first if it doesn't exist
        if (!_orgExists(orgId)) {
            // Use org ID as the name if no specific name is provided
            string memory orgName = bytes32ToString(orgId);
            orgRegistry.registerOrg(orgId, orgOwner, orgName);
        }
        
        // Create initialization data for Voting contract
        bytes memory initData = abi.encodeWithSignature("initialize(address)", orgOwner);
        
        // Deploy the Voting contract
        return deployContract(
            orgId,
            "Voting",
            orgOwner,
            autoUpgrade,
            customImplementation,
            initData
        );
    }
    
    /**
     * @notice Deploy a Voting contract
     * @param orgId Unique identifier for the Org
     * @param orgOwner The address that will own the Voting contract
     * @param autoUpgrade If true, uses Poa's official beacon for auto-upgrades
     * @param customImplementation Custom implementation (only used if autoUpgrade=false)
     */
    function deployVoting(
        bytes32 orgId,
        address orgOwner,
        bool autoUpgrade,
        address customImplementation
    ) public returns (address votingProxy) {
        // Create initialization data for Voting contract
        bytes memory initData = abi.encodeWithSignature("initialize(address)", orgOwner);
        
        // Deploy the Voting contract
        return deployContract(
            orgId,
            "Voting",
            orgOwner,
            autoUpgrade,
            customImplementation,
            initData
        );
    }
    
    /**
     * @notice Deploy a Membership contract
     * @param orgId Unique identifier for the Org
     * @param orgOwner The address that will own the Membership contract
     * @param orgName The name of the organization for the membership NFT
     * @param autoUpgrade If true, uses Poa's official beacon for auto-upgrades
     * @param customImplementation Custom implementation (only used if autoUpgrade=false)
     */
    function deployMembership(
        bytes32 orgId,
        address orgOwner,
        string memory orgName,
        bool autoUpgrade,
        address customImplementation
    ) public returns (address membershipProxy) {
        // Create initialization data for Membership contract
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,string)",
            orgOwner,
            orgName
        );
        
        // Deploy the Membership contract
        return deployContract(
            orgId,
            "Membership",
            orgOwner,
            autoUpgrade,
            customImplementation,
            initData
        );
    }
    
    /**
     * @notice Deploy both Voting and Membership contracts for an org and link them
     * @param orgId Unique identifier for the Org
     * @param orgOwner The address that will own the contracts
     * @param orgName The name of the organization for the membership NFT
     * @param autoUpgrade If true, uses Poa's official beacon for auto-upgrades
     */
    function deployOrgContracts(
        bytes32 orgId,
        address orgOwner,
        string memory orgName,
        bool autoUpgrade
    ) external returns (address votingProxy, address membershipProxy) {
        // Register the organization first if it doesn't exist
        if (!_orgExists(orgId)) {
            orgRegistry.registerOrg(orgId, orgOwner, orgName);
        }
        
        // Deploy Membership contract
        membershipProxy = deployMembership(
            orgId,
            orgOwner,
            orgName,
            autoUpgrade,
            address(0)
        );
        
        // Deploy Voting contract
        votingProxy = deployOrg(
            orgId,
            orgOwner,
            autoUpgrade,
            address(0)
        );
        
        // Set up the link between Voting and Membership
        // This requires a function call on the deployed Voting contract
        bytes memory callData = abi.encodeWithSignature(
            "setMembershipContract(address)",
            membershipProxy
        );
        
        // Make the call as the orgOwner
        (bool success, ) = votingProxy.call(callData);
        require(success, "Failed to link contracts");
        
        return (votingProxy, membershipProxy);
    }

    /**
     * @notice Helper: Return the current implementation for a beacon
     */
    function getBeaconImplementation(address beaconAddr) public view returns (address impl) {
        (bool success, bytes memory result) = beaconAddr.staticcall(
            abi.encodeWithSignature("implementation()")
        );
        require(success, "Beacon implementation() call failed");
        impl = abi.decode(result, (address));
    }
    
    /**
     * @notice Generate a unique key for each contract based on orgId and contract type
     */
    function _generateContractKey(bytes32 orgId, string memory contractType) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes32ToString(orgId), "-", contractType));
    }
    
    /**
     * @notice Helper to convert bytes32 to string
     */
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < bytesArray.length; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    /**
     * @notice Helper to check if an organization exists
     */
    function _orgExists(bytes32 orgId) internal view returns (bool) {
        try orgRegistry.orgs(orgId) returns (bytes32 id, address owner, string memory name, uint256 contractCount, bool exists) {
            return exists;
        } catch {
            return false;
        }
    }
}
