// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PoaManager
 * @dev Owns and manages the Poa "official" beacon for a given module (Voting, in this example).
 *      This contract can upgrade the beacon to a new implementation.
 */
contract PoaManager is Ownable {
    // The official Poa beacon for the Voting module
    UpgradeableBeacon public poaBeacon;

    event BeaconUpgraded(address indexed newImplementation);

    constructor(address _initialImplementation) Ownable(msg.sender) {
        // Deploy an UpgradeableBeacon that references the initial implementation
        // Transfer ownership of that beacon to this contract so it can upgrade it.
        poaBeacon = new UpgradeableBeacon(_initialImplementation, address(this));
        // This contract (PoaManager) is automatically the owner of the newly deployed beacon.
    }

    /**
     * @notice Upgrade the Poa beacon to a new Voting implementation.
     */
    function upgradeBeacon(address newImplementation) external onlyOwner {
        poaBeacon.upgradeTo(newImplementation);
        emit BeaconUpgraded(newImplementation);
    }

    /**
     * @notice Get the current implementation that the Poa beacon is pointing to.
     */
    function getCurrentImplementation() external view returns (address) {
        return poaBeacon.implementation();
    }
}
