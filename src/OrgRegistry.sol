// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title OrgRegistry
 * @dev A contract that tracks organizations and their deployment details
 */
contract OrgRegistry is Ownable {
    // A struct to track each org's info
    struct OrgInfo {
        address beaconProxy;       // The org's BeaconProxy address
        address beacon;            // The beacon that the proxy uses (either Poa's or a custom org-owned)
        bool autoUpgrade;          // Whether the org is auto-upgrading
        address owner;             // The org's owner (for reference)
    }

    // orgId (or any unique key) -> OrgInfo
    mapping(bytes32 => OrgInfo) public orgs;

    event OrgRegistered(
        bytes32 indexed orgId,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address orgOwner
    );

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a new organization in the registry
     * @param orgId Unique identifier for the Org
     * @param beaconProxy The org's BeaconProxy address
     * @param beacon The beacon that the proxy uses
     * @param autoUpgrade Whether the org auto-upgrades
     * @param orgOwner The address that owns the org
     */
    function registerOrg(
        bytes32 orgId,
        address beaconProxy,
        address beacon,
        bool autoUpgrade,
        address orgOwner
    ) external onlyOwner {
        require(orgs[orgId].beaconProxy == address(0), "Org already registered");
        require(beaconProxy != address(0), "Invalid proxy address");
        require(beacon != address(0), "Invalid beacon address");
        require(orgOwner != address(0), "Invalid org owner");

        OrgInfo memory info = OrgInfo({
            beaconProxy: beaconProxy,
            beacon: beacon,
            autoUpgrade: autoUpgrade,
            owner: orgOwner
        });
        orgs[orgId] = info;

        emit OrgRegistered(orgId, beaconProxy, beacon, autoUpgrade, orgOwner);
    }

    /**
     * @notice Get the implementation for an org's beacon
     * @param orgId The unique identifier for the org
     * @return The implementation address
     */
    function getOrgBeacon(bytes32 orgId) external view returns (address) {
        OrgInfo memory info = orgs[orgId];
        require(info.beacon != address(0), "Org not found");
        return info.beacon;
    }

    /**
     * @notice Get the proxy address for an org
     * @param orgId The unique identifier for the org
     * @return The proxy address
     */
    function getOrgProxy(bytes32 orgId) external view returns (address) {
        OrgInfo memory info = orgs[orgId];
        require(info.beaconProxy != address(0), "Org not found");
        return info.beaconProxy;
    }

    /**
     * @notice Check if an org is using auto-upgrade
     * @param orgId The unique identifier for the org
     * @return Whether the org is auto-upgrading
     */
    function isOrgAutoUpgrade(bytes32 orgId) external view returns (bool) {
        OrgInfo memory info = orgs[orgId];
        require(info.beaconProxy != address(0), "Org not found");
        return info.autoUpgrade;
    }
} 