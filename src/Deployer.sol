// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

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

    // A simple struct to track each org's info (optional for convenience)
    struct OrgInfo {
        address beaconProxy;       // The org's BeaconProxy address
        address beacon;            // The beacon that the proxy uses (either Poa's or a custom org-owned)
        bool autoUpgrade;          // Whether the org is auto-upgrading
        address owner;             // The org's owner (for reference)
    }

    // orgId (or any unique key) -> OrgInfo
    mapping(bytes32 => OrgInfo) public orgs;

    // Reference to the PoaManager (which manages Poa's official Voting beacon).
    IPoaManager public poaManager;

    event OrgDeployed(
        bytes32 indexed orgId,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address orgOwner
    );

    constructor(address _poaManager) Ownable(msg.sender) {
        require(_poaManager != address(0), "Invalid PoaManager");
        poaManager = IPoaManager(_poaManager);
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
        require(orgs[orgId].beaconProxy == address(0), "Org already deployed");
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

        // 3. Store org info
        OrgInfo memory info = OrgInfo({
            beaconProxy: address(proxy),
            beacon: beacon,
            autoUpgrade: autoUpgrade,
            owner: orgOwner
        });
        orgs[orgId] = info;

        emit OrgDeployed(orgId, address(proxy), beacon, autoUpgrade, orgOwner);

        return address(proxy);
    }

    /**
     * @notice Helper: Return the current Voting implementation for an org.
     *         If autoUpgrade=true, returns Poa's official logic. Otherwise returns the org's local logic.
     * @dev This requires us to do a staticcall to the org's beacon's .implementation().
     */
    function getOrgImplementation(bytes32 orgId) external view returns (address) {
        OrgInfo memory info = orgs[orgId];
        require(info.beacon != address(0), "Org not found");

        // If the beacon is an UpgradeableBeacon, we can call .implementation() directly.
        // If it's Poa's official beacon, same approach applies (since it is also an UpgradeableBeacon).
        return _getBeaconImplementation(info.beacon);
    }

    function _getBeaconImplementation(address beaconAddr) internal view returns (address impl) {
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
