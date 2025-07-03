// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

/**
 * @title EligibilityModule
 * @notice An ownership-based module for configuring eligibility and standing
 *         on a per-hat basis in the Hats Protocol. controlled by the admin.
 */

//TODO: make specific to wearers

contract EligibilityModule {
    /// @notice The admin who can update eligibility settings
    address public admin;

    /// @notice Per-hat configuration for eligibility and standing
    /// @dev hatId => (eligible, standing)
    struct HatRules {
        bool eligible;
        bool standing;
    }

    /// @notice Store the rules for each hat
    mapping(uint256 => HatRules) public hatRules;

    /// @notice Emitted when the admin updates a hat's eligibility or standing
    event HatRulesUpdated(uint256 indexed hatId, bool eligible, bool standing);

    /**
     * @dev Set the admin
     */
    constructor(address _admin) {
        admin = _admin;
    }

    /**
     * @dev Restricts certain calls so only the admin can perform them
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not module admin");
        _;
    }

    /**
     * @notice Sets a hat's eligibility and standing in one call
     * @param hatId The hat ID to update
     * @param _eligible Whether the wearer is eligible (true) or not (false)
     * @param _standing Whether the wearer is in good standing (true) or bad (false)
     */
    function setHatRules(uint256 hatId, bool _eligible, bool _standing) external onlyAdmin {
        hatRules[hatId] = HatRules(_eligible, _standing);
        emit HatRulesUpdated(hatId, _eligible, _standing);
    }

    /**
     * @notice The Hats Protocol calls this to determine if `wearer` is eligible
     *         for `hatId`, and if they are in good standing.
     * @param wearer The address wearing or attempting to wear the hat
     * @param hatId The ID of the hat being checked
     * @return eligible uint256 (0 = ineligible, 1 = eligible)
     * @return standing uint256 (0 = bad standing, 1 = good standing)
     */
    function getWearerStatus(address wearer, uint256 hatId)
        external
        view
        returns (uint256 eligible, uint256 standing)
    {
        // If this hatId has not been set, default to ineligible or adapt as needed
        HatRules memory rules = hatRules[hatId];

        if (rules.eligible) {
            eligible = 1;
        } else {
            eligible = 0;
        }

        if (rules.standing) {
            standing = 1;
        } else {
            standing = 0;
        }
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
