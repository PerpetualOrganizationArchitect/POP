// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @title ToggleModule
 * @notice A module for toggling Hats active or inactive.
 *
 *         The Hats Protocol calls getHatStatus(uint256) and expects a uint256:
 *         1 indicates "active," and 0 indicates "inactive."
 */
contract ToggleModule {
    /// @notice The amdin who can toggle hat status
    address public admin;

    /// @notice Whether each hat is active or not
    /// @dev hatId => bool (true = active, false = inactive)
    mapping(uint256 => bool) public hatActive;

    /// @notice Emitted when a hat's status is toggled
    event HatToggled(uint256 indexed hatId, bool newStatus);

    /**
     * @dev Set the admin on construction
     */
    constructor(address _admin) {
        admin = _admin;
    }

    /**
     * @dev Restricts certain calls so only the admin can perform them
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not toggle admin");
        _;
    }

    /**
     * @notice Sets an individual hat's active status
     * @param hatId The ID of the hat being toggled
     * @param _active Whether this hat is active (true) or inactive (false)
     */
    function setHatStatus(uint256 hatId, bool _active) external onlyAdmin {
        hatActive[hatId] = _active;
        emit HatToggled(hatId, _active);
    }

    /**
     * @notice The Hats Protocol calls this function to determine if `hatId` is active.
     * @param hatId The ID of the hat being checked
     * @return status 1 if active, 0 if inactive
     */
    function getHatStatus(uint256 hatId) external view returns (uint256 status) {
        // Return 1 for active, 0 for inactive
        return hatActive[hatId] ? 1 : 0;
    }

    /**
     * @notice Transfer admin rights of this module to a new admin
     * @param newAdmin The new admin address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        admin = newAdmin;
    }
}
