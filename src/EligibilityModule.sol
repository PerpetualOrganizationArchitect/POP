// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../lib/hats-protocol/src/Interfaces/IHats.sol";
import "../lib/hats-protocol/src/Interfaces/IHatsEligibility.sol";

/**
 * @title EligibilityModule
 * @notice A hat-based module for configuring eligibility and standing
 *         on a per-hat basis in the Hats Protocol, controlled by admin hats.
 */

contract EligibilityModule is IHatsEligibility {
    /// @notice The Hats Protocol contract
    IHats public immutable hats;

    /// @notice The super admin who can manage admin hats and their permissions, the executor contract
    address public superAdmin;

    /// @notice Per-wearer per-hat configuration for eligibility and standing
    /// @dev wearer => hatId => (eligible, standing)
    struct WearerRules {
        bool eligible;
        bool standing;
    }

    /// @notice Store the rules for each wearer for each hat
    mapping(address => mapping(uint256 => WearerRules)) public wearerRules;

    /// @notice Store the default rules for each hat (applied when no specific wearer rules exist)
    mapping(uint256 => WearerRules) public defaultRules;

    /// @notice Track whether specific rules have been set for a wearer-hat combination
    mapping(address => mapping(uint256 => bool)) public hasSpecificRules;

    /// @notice Track which hats are admin hats
    mapping(uint256 => bool) public adminHats;

    /// @notice Track which hats each admin hat can control
    /// @dev adminHatId => targetHatId => canControl
    mapping(uint256 => mapping(uint256 => bool)) public adminPermissions;

    /// @notice Array to track all admin hat IDs for efficient iteration
    uint256[] public adminHatIds;

    /// @notice Emitted when an admin updates a wearer's eligibility or standing for a hat
    event WearerEligibilityUpdated(
        address indexed wearer, 
        uint256 indexed hatId, 
        bool eligible, 
        bool standing,
        address indexed admin
    );

    /// @notice Emitted when an admin updates the default eligibility for a hat
    event DefaultEligibilityUpdated(
        uint256 indexed hatId, 
        bool eligible, 
        bool standing,
        address indexed admin
    );

    /// @notice Emitted when an admin hat is added or removed
    event AdminHatUpdated(uint256 indexed hatId, bool isAdmin, address indexed admin);

    /// @notice Emitted when admin permissions are updated
    event AdminPermissionUpdated(
        uint256 indexed adminHatId, 
        uint256 indexed targetHatId, 
        bool canControl,
        address indexed admin
    );

    /// @notice Emitted when bulk wearer eligibility is updated
    event BulkWearerEligibilityUpdated(
        address[] wearers,
        uint256 indexed hatId,
        bool eligible,
        bool standing,
        address indexed admin
    );

    /// @notice Emitted when super admin is transferred
    event SuperAdminTransferred(
        address indexed oldSuperAdmin,
        address indexed newSuperAdmin
    );

    /// @notice Emitted when the module is initialized
    event EligibilityModuleInitialized(
        address indexed superAdmin,
        address indexed hatsContract
    );

    /**
     * @dev Set the super admin and Hats contract
     */
    constructor(address _superAdmin, address _hats) {
        superAdmin = _superAdmin;
        hats = IHats(_hats);
        emit EligibilityModuleInitialized(_superAdmin, _hats);
    }

    /**
     * @dev Restricts certain calls so only the super admin can perform them
     */
    modifier onlySuperAdmin() {
        require(msg.sender == superAdmin, "Not super admin");
        _;
    }

    /**
     * @dev Restricts calls to admin hats with permission for the specific target hat
     */
    modifier onlyAuthorizedAdmin(uint256 targetHatId) {
        require(isAuthorizedAdmin(msg.sender, targetHatId), "Not authorized admin for this hat");
        _;
    }

    /**
     * @notice Check if an address is authorized to control a specific target hat
     * @param user The address to check
     * @param targetHatId The target hat ID
     * @return authorized Whether the user is authorized
     */
    function isAuthorizedAdmin(address user, uint256 targetHatId) public view returns (bool authorized) {
        // Super admin can control any hat
        if (user == superAdmin) {
            return true;
        }

        // Check if user is wearing any admin hat that has permission for this target hat
        for (uint256 i = 0; i < adminHatIds.length; i++) {
            uint256 adminHatId = adminHatIds[i];
            if (adminPermissions[adminHatId][targetHatId] && hats.isWearerOfHat(user, adminHatId)) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Sets a wearer's eligibility and standing for a specific hat
     * @param wearer The address whose eligibility to update
     * @param hatId The hat ID to update eligibility for
     * @param _eligible Whether the wearer is eligible (true) or not (false)
     * @param _standing Whether the wearer is in good standing (true) or bad (false)
     */
    function setWearerEligibility(address wearer, uint256 hatId, bool _eligible, bool _standing)
        external
        onlyAuthorizedAdmin(hatId)
    {
        wearerRules[wearer][hatId] = WearerRules(_eligible, _standing);
        hasSpecificRules[wearer][hatId] = true;
        emit WearerEligibilityUpdated(wearer, hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Sets default eligibility for a hat that applies to all wearers who don't have specific rules
     * @param hatId The hat ID to set default eligibility for
     * @param _eligible Whether wearers are eligible by default (true) or not (false)
     * @param _standing Whether wearers are in good standing by default (true) or bad (false)
     */
    function setDefaultEligibility(uint256 hatId, bool _eligible, bool _standing) external onlyAuthorizedAdmin(hatId) {
        defaultRules[hatId] = WearerRules(_eligible, _standing);
        emit DefaultEligibilityUpdated(hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Sets eligibility and standing for multiple wearers for a specific hat
     * @param wearers Array of addresses whose eligibility to update
     * @param hatId The hat ID to update eligibility for
     * @param _eligible Whether the wearers are eligible (true) or not (false)
     * @param _standing Whether the wearers are in good standing (true) or bad (false)
     */
    function setBulkWearerEligibility(address[] calldata wearers, uint256 hatId, bool _eligible, bool _standing)
        external
        onlyAuthorizedAdmin(hatId)
    {
        for (uint256 i = 0; i < wearers.length; i++) {
            wearerRules[wearers[i]][hatId] = WearerRules(_eligible, _standing);
            hasSpecificRules[wearers[i]][hatId] = true;
        }
        emit BulkWearerEligibilityUpdated(wearers, hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Add or remove an admin hat
     * @param hatId The hat ID to add or remove as admin
     * @param isAdmin Whether this hat should be an admin (true) or not (false)
     */
    function setAdminHat(uint256 hatId, bool isAdmin) external onlySuperAdmin {
        bool wasAdmin = adminHats[hatId];
        adminHats[hatId] = isAdmin;

        if (isAdmin && !wasAdmin) {
            // Adding new admin hat
            adminHatIds.push(hatId);
        } else if (!isAdmin && wasAdmin) {
            // Removing admin hat - find and remove from array
            for (uint256 i = 0; i < adminHatIds.length; i++) {
                if (adminHatIds[i] == hatId) {
                    adminHatIds[i] = adminHatIds[adminHatIds.length - 1];
                    adminHatIds.pop();
                    break;
                }
            }
        }

        emit AdminHatUpdated(hatId, isAdmin, msg.sender);
    }

    /**
     * @notice Set permissions for an admin hat to control specific target hats
     * @param adminHatId The admin hat ID
     * @param targetHatIds Array of target hat IDs that this admin can control
     * @param canControl Array of booleans indicating permission for each target hat
     */
    function setAdminPermissions(uint256 adminHatId, uint256[] calldata targetHatIds, bool[] calldata canControl)
        external
        onlySuperAdmin
    {
        require(adminHats[adminHatId], "Not an admin hat");
        require(targetHatIds.length == canControl.length, "Array length mismatch");

        for (uint256 i = 0; i < targetHatIds.length; i++) {
            adminPermissions[adminHatId][targetHatIds[i]] = canControl[i];
            emit AdminPermissionUpdated(adminHatId, targetHatIds[i], canControl[i], msg.sender);
        }
    }

    /**
     * @notice The Hats Protocol calls this to determine if `wearer` is eligible
     *         for `hatId`, and if they are in good standing.
     * @param wearer The address wearing or attempting to wear the hat
     * @param hatId The ID of the hat being checked
     * @return eligible uint256 (0 = ineligible, 1 = eligible)
     * @return standing uint256 (0 = bad standing, 1 = good standing)
     */
    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing) {
        bool hasSpecific = hasSpecificRules[wearer][hatId];
        
        // If specific rules have been set for this wearer-hat combination, use them
        if (hasSpecific) {
            WearerRules memory rules = wearerRules[wearer][hatId];
            eligible = rules.eligible;
            standing = rules.standing;
        } else {
            // Otherwise, use default rules for this hat
            WearerRules memory defaultRule = defaultRules[hatId];
            eligible = defaultRule.eligible;
            standing = defaultRule.standing;
        }
    }

    /**
     * @notice Transfer super admin rights of this module to a new super admin
     * @param newSuperAdmin The new super admin address
     */
    function transferSuperAdmin(address newSuperAdmin) external onlySuperAdmin {
        require(newSuperAdmin != address(0), "Zero address");
        address oldSuperAdmin = superAdmin;
        superAdmin = newSuperAdmin;
        emit SuperAdminTransferred(oldSuperAdmin, newSuperAdmin);
    }

    /**
     * @notice Check if a hat is an admin hat
     * @param hatId The hat ID to check
     * @return isAdmin Whether the hat is an admin hat
     */
    function isAdminHat(uint256 hatId) external view returns (bool isAdmin) {
        return adminHats[hatId];
    }

    /**
     * @notice Check if an admin hat can control a specific target hat
     * @param adminHatId The admin hat ID
     * @param targetHatId The target hat ID
     * @return canControl Whether the admin hat can control the target hat
     */
    function canAdminControlHat(uint256 adminHatId, uint256 targetHatId) external view returns (bool canControl) {
        return adminHats[adminHatId] && adminPermissions[adminHatId][targetHatId];
    }

    /**
     * @notice Get all admin hat IDs
     * @return adminHats Array of all admin hat IDs
     */
    function getAdminHatIds() external view returns (uint256[] memory) {
        return adminHatIds;
    }
}
