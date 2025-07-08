// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../lib/hats-protocol/src/Interfaces/IHats.sol";
import "../lib/hats-protocol/src/Interfaces/IHatsEligibility.sol";

/**
 * @title EligibilityModule
 * @notice A hat-based module for configuring eligibility and standing
 *         on a per-hat basis in the Hats Protocol, controlled by admin hats.
 *         Now supports optional N-Vouch eligibility system.
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

    /// @notice Configuration for vouching system per hat
    struct VouchConfig {
        uint32 quorum; // Number of vouches required
        uint256 membershipHatId; // Hat ID whose wearers can vouch
        bool enabled; // Whether vouching is enabled for this hat
        bool combineWithHierarchy; // If true, hierarchy OR vouching (default). If false, vouching only.
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

    /// @notice Per-hat vouching configuration
    mapping(uint256 => VouchConfig) public vouchConfigs;

    /// @notice Track whether an address has vouched for a wearer for a specific hat
    /// @dev hatId => wearer => voucher => hasVouched
    mapping(uint256 => mapping(address => mapping(address => bool))) public vouchers;

    /// @notice Count of valid vouches for each wearer for each hat
    /// @dev hatId => wearer => vouchCount
    mapping(uint256 => mapping(address => uint32)) public currentVouchCount;

    /// @notice Track addresses that have met vouch quorum for a hat
    /// @dev hatId => wearer => approved
    mapping(uint256 => mapping(address => bool)) public vouchApproved;

    /// @notice Emitted when an admin updates a wearer's eligibility or standing for a hat
    event WearerEligibilityUpdated(
        address indexed wearer, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );

    /// @notice Emitted when an admin updates the default eligibility for a hat
    event DefaultEligibilityUpdated(uint256 indexed hatId, bool eligible, bool standing, address indexed admin);

    /// @notice Emitted when an admin hat is added or removed
    event AdminHatUpdated(uint256 indexed hatId, bool isAdmin, address indexed admin);

    /// @notice Emitted when admin permissions are updated
    event AdminPermissionUpdated(
        uint256 indexed adminHatId, uint256 indexed targetHatId, bool canControl, address indexed admin
    );

    /// @notice Emitted when bulk wearer eligibility is updated
    event BulkWearerEligibilityUpdated(
        address[] wearers, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );

    /// @notice Emitted when super admin is transferred
    event SuperAdminTransferred(address indexed oldSuperAdmin, address indexed newSuperAdmin);

    /// @notice Emitted when the module is initialized
    event EligibilityModuleInitialized(address indexed superAdmin, address indexed hatsContract);

    /// @notice Emitted when someone vouches for a wearer
    event Vouched(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    /// @notice Emitted when a vouch is revoked
    event VouchRevoked(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);

    /// @notice Emitted when vouch configuration is set
    event VouchConfigSet(
        uint256 indexed hatId, uint32 quorum, uint256 membershipHatId, bool enabled, bool combineWithHierarchy
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
     * @notice Configure vouching system for a specific hat
     * @param hatId The hat ID to configure vouching for
     * @param quorum Number of vouches required (0 to disable)
     * @param membershipHatId Hat ID whose wearers can vouch
     * @param combineWithHierarchy If true, hierarchy OR vouching passes. If false, vouching only.
     */
    function configureVouching(uint256 hatId, uint32 quorum, uint256 membershipHatId, bool combineWithHierarchy)
        external
        onlySuperAdmin
    {
        bool enabled = quorum > 0;
        vouchConfigs[hatId] = VouchConfig({
            quorum: quorum,
            membershipHatId: membershipHatId,
            enabled: enabled,
            combineWithHierarchy: combineWithHierarchy
        });

        emit VouchConfigSet(hatId, quorum, membershipHatId, enabled, combineWithHierarchy);
    }

    /**
     * @notice Vouch for a wearer to receive a specific hat
     * @param wearer The address to vouch for
     * @param hatId The hat ID to vouch for
     */
    function vouchFor(address wearer, uint256 hatId) external {
        VouchConfig memory config = vouchConfigs[hatId];
        require(config.enabled, "Vouching not enabled for this hat");
        require(hats.isWearerOfHat(msg.sender, config.membershipHatId), "Not authorized to vouch");
        require(!vouchers[hatId][wearer][msg.sender], "Already vouched for this wearer");

        // Record the vouch
        vouchers[hatId][wearer][msg.sender] = true;
        currentVouchCount[hatId][wearer]++;

        // Check if quorum is met
        if (currentVouchCount[hatId][wearer] >= config.quorum) {
            vouchApproved[hatId][wearer] = true;
        }

        emit Vouched(msg.sender, wearer, hatId, currentVouchCount[hatId][wearer]);
    }

    /**
     * @notice Revoke a vouch for a wearer
     * @param wearer The address to revoke vouch for
     * @param hatId The hat ID to revoke vouch for
     */
    function revokeVouch(address wearer, uint256 hatId) external {
        VouchConfig memory config = vouchConfigs[hatId];
        require(config.enabled, "Vouching not enabled for this hat");
        require(vouchers[hatId][wearer][msg.sender], "Haven't vouched for this wearer");

        // Remove the vouch
        vouchers[hatId][wearer][msg.sender] = false;
        currentVouchCount[hatId][wearer]--;

        // Check if we need to revoke approval
        if (currentVouchCount[hatId][wearer] < config.quorum) {
            vouchApproved[hatId][wearer] = false;
        }

        emit VouchRevoked(msg.sender, wearer, hatId, currentVouchCount[hatId][wearer]);
    }

    /**
     * @notice Reset all vouches for a specific hat (super admin only)
     * @param hatId The hat ID to reset vouches for
     */
    function resetVouches(uint256 hatId) external onlySuperAdmin {
        delete vouchConfigs[hatId];
        emit VouchConfigSet(hatId, 0, 0, false, false);
    }

    /**
     * @notice The Hats Protocol calls this to determine if `wearer` is eligible
     *         for `hatId`, and if they are in good standing.
     * @param wearer The address wearing or attempting to wear the hat
     * @param hatId The ID of the hat being checked
     * @return eligible bool (false = ineligible, true = eligible)
     * @return standing bool (false = bad standing, true = good standing)
     */
    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing) {
        // Check if vouching is enabled for this hat
        VouchConfig memory config = vouchConfigs[hatId];

        bool hierarchyEligible = false;
        bool hierarchyStanding = false;
        bool vouchEligible = false;
        bool vouchStanding = false;

        // 1. Check hierarchy path (existing logic)
        bool hasSpecific = hasSpecificRules[wearer][hatId];
        if (hasSpecific) {
            WearerRules memory rules = wearerRules[wearer][hatId];
            hierarchyEligible = rules.eligible;
            hierarchyStanding = rules.standing;
        } else {
            WearerRules memory defaultRule = defaultRules[hatId];
            hierarchyEligible = defaultRule.eligible;
            hierarchyStanding = defaultRule.standing;
        }

        // 2. Check vouch path (if enabled)
        if (config.enabled) {
            // Check if wearer has been approved through vouching
            if (vouchApproved[hatId][wearer]) {
                vouchEligible = true;
                vouchStanding = true;
            } else {
                // Check if current vouch count meets quorum
                if (currentVouchCount[hatId][wearer] >= config.quorum) {
                    vouchEligible = true;
                    vouchStanding = true;
                }
            }
        }

        // 3. Combine results based on configuration
        if (config.enabled) {
            if (config.combineWithHierarchy) {
                // OR logic: either hierarchy OR vouching passes
                eligible = hierarchyEligible || vouchEligible;
                standing = hierarchyStanding || vouchStanding;
            } else {
                // Vouching only
                eligible = vouchEligible;
                standing = vouchStanding;
            }
        } else {
            // Vouching disabled, use hierarchy only
            eligible = hierarchyEligible;
            standing = hierarchyStanding;
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

    /**
     * @notice Get vouch configuration for a hat
     * @param hatId The hat ID to get configuration for
     * @return config The vouch configuration
     */
    function getVouchConfig(uint256 hatId) external view returns (VouchConfig memory config) {
        return vouchConfigs[hatId];
    }

    /**
     * @notice Check if an address has vouched for a wearer for a specific hat
     * @param hatId The hat ID
     * @param wearer The wearer address
     * @param voucher The voucher address
     * @return hasVouched Whether the voucher has vouched for the wearer
     */
    function hasVouched(uint256 hatId, address wearer, address voucher) external view returns (bool hasVouched) {
        return vouchers[hatId][wearer][voucher];
    }
}
