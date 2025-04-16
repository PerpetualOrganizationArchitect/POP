// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./OrgRegistry.sol";

interface IPoaManager {
    function poaBeacon() external view returns (address); // The official Poa beacon
    function getCurrentImplementation() external view returns (address);
}

/**
 * @title Deployer
 * @dev A factory-style contract that lets any Org deploy their own beacon proxy for Voting.
 *      - If auto-upgrade = true, the Org's proxy will point directly to Poa's official beacon.
 *      - If auto-upgrade = false, the Deployer creates a new local UpgradeableBeacon for that Org,
 *        pointing to either Poa's current Voting implementation or a custom one.
 */
contract Deployer is Ownable {
    using Address for address;

    // Reference to the PoaManager (which manages Poa's official Voting beacon)
    IPoaManager public poaManager;
    
    // Reference to the OrgRegistry for tracking organizations
    OrgRegistry public orgRegistry;

    event OrgDeployed(
        bytes32 indexed orgId,
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
     * @notice Deploy a BeaconProxy for a new org.
     * @param orgId Unique identifier for the Org (e.g., keccak256 of org name).
     * @param orgOwner The address that will own/admin the Voting module (see `initialize`).
     * @param autoUpgrade If true, the org points directly to Poa's official beacon and auto-upgrades.
     * @param customImplementation If autoUpgrade=false and `customImplementation != address(0)`, 
     *                             we use that as the org's dedicated Voting logic.
     */
    function deployOrg(
        bytes32 orgId,
        address orgOwner,
        bool autoUpgrade,
        address customImplementation
    ) external returns (address beaconProxy) {
        require(orgOwner != address(0), "Invalid org owner");

        // 1. Determine beacon address
        address beacon;
        if (autoUpgrade) {
            // The org's BeaconProxy will point directly to Poa's official beacon
            beacon = poaManager.poaBeacon();
        } else {
            // The org does NOT want auto-upgrades -> create a new local beacon
            // pointing to either the Poa's current impl or a custom one.
            address implementation = customImplementation;
            if (implementation == address(0)) {
                // fallback to Poa's current official implementation
                implementation = poaManager.getCurrentImplementation();
            }

            UpgradeableBeacon newOrgBeacon = new UpgradeableBeacon(implementation, orgOwner);
            // Note: The beacon is already owned by orgOwner due to the constructor parameter
            beacon = address(newOrgBeacon);
        }

        // 2. Deploy the BeaconProxy
        //    We want to initialize it by calling `initialize(address orgOwner)` on the Voting logic
        bytes memory initData = abi.encodeWithSignature("initialize(address)", orgOwner);
        BeaconProxy proxy = new BeaconProxy(beacon, initData);

        // 3. Register the org in the OrgRegistry
        orgRegistry.registerOrg(
            orgId,
            address(proxy),
            beacon,
            autoUpgrade,
            orgOwner
        );

        emit OrgDeployed(orgId, address(proxy), beacon, autoUpgrade, orgOwner);

        return address(proxy);
    }

    /**
     * @notice Helper: Return the current Voting implementation for an org's beacon.
     * @dev This requires us to do a staticcall to the beacon's .implementation().
     */
    function getBeaconImplementation(address beaconAddr) public view returns (address impl) {
        // The standard OZ UpgradeableBeacon doesn't expose implementation() externally,
        // but we can get it via a staticcall to the beacon's public function:
        //   function implementation() external view returns (address)
        (bool success, bytes memory result) = beaconAddr.staticcall(
            abi.encodeWithSignature("implementation()")
        );
        require(success, "Beacon implementation() call failed");
        impl = abi.decode(result, (address));
    }
}
