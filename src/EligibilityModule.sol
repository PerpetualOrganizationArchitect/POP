// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../lib/hats-protocol/src/Interfaces/IHats.sol";
import "../lib/hats-protocol/src/Interfaces/IHatsEligibility.sol";
import "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @title EligibilityModule
 * @notice A hat-based module for configuring eligibility and standing
 *         on a per-hat basis in the Hats Protocol, controlled by admin hats.
 *         Now supports optional N-Vouch eligibility system.
 */
contract EligibilityModule is Initializable, IHatsEligibility {
    using EnumerableSet for EnumerableSet.UintSet;

    /*═══════════════════════════════════════════ ERRORS ═══════════════════════════════════════════*/

    error NotSuperAdmin();
    error NotAuthorizedAdmin();
    error ZeroAddress();
    error NotAnAdminHat();
    error ArrayLengthMismatch();
    error VouchingNotEnabled();
    error NotAuthorizedToVouch();
    error AlreadyVouched();
    error HasNotVouched();

    /*═════════════════════════════════════════ STRUCTS ═════════════════════════════════════════*/

    /// @notice Per-wearer per-hat configuration for eligibility and standing (packed)
    /// @dev wearer => hatId => flags (bit 0 = eligible, bit 1 = standing)
    struct WearerRules {
        uint8 flags; // Packed flags: bit 0 = eligible, bit 1 = standing
    }

    /// @notice Configuration for vouching system per hat (packed)
    struct VouchConfig {
        uint32 quorum; // Number of vouches required
        uint256 membershipHatId; // Hat ID whose wearers can vouch
        uint8 flags; // Packed flags: bit 0 = enabled, bit 1 = combineWithHierarchy
    }

    /*═════════════════════════════════════ ERC-7201 STORAGE ═════════════════════════════════════*/

    /// @custom:storage-location erc7201:poa.eligibilitymodule.storage
    struct Layout {
        /// @notice The Hats Protocol contract
        IHats hats;
        /// @notice The super admin who can manage admin hats and their permissions, the executor contract
        address superAdmin;
        /// @notice The hat that this eligibility module wears for administrative purposes
        uint256 eligibilityModuleAdminHat;
        /// @notice Store the rules for each wearer for each hat
        mapping(address => mapping(uint256 => WearerRules)) wearerRules;
        /// @notice Track whether specific wearer rules have been explicitly set (to distinguish from default)
        /// @dev wearer => hatId => hasSpecificRules
        mapping(address => mapping(uint256 => bool)) hasSpecificWearerRules;
        /// @notice Store the default rules for each hat (applied when no specific wearer rules exist)
        mapping(uint256 => WearerRules) defaultRules;
        /// @notice Track which hats are admin hats (legacy - still used for compatibility)
        mapping(uint256 => bool) adminHats;
        /// @notice Track which hats each admin hat can control
        /// @dev adminHatId => targetHatId => canControl
        mapping(uint256 => mapping(uint256 => bool)) adminPermissions;
        /// @notice Set of all admin hat IDs for efficient iteration
        EnumerableSet.UintSet adminHatIds;
        /// @notice Track which admin hats each user currently wears
        /// @dev user => set of adminHatIds they currently wear
        mapping(address => EnumerableSet.UintSet) userAdminHats;
        /// @notice Track which admin hats are currently active
        /// @dev adminHatId => bool (isAdminHat and currently active)
        mapping(uint256 => bool) adminHatActive;
        /// @notice Per-hat vouching configuration
        mapping(uint256 => VouchConfig) vouchConfigs;
        /// @notice Track whether an address has vouched for a wearer for a specific hat
        /// @dev hatId => wearer => voucher => hasVouched
        mapping(uint256 => mapping(address => mapping(address => bool))) vouchers;
        /// @notice Count of valid vouches for each wearer for each hat
        /// @dev hatId => wearer => vouchCount
        mapping(uint256 => mapping(address => uint32)) currentVouchCount;
    }

    // keccak256("poa.eligibilitymodule.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x8f7c0d6a29b3e7e2f1a0c9b8d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*═══════════════════════════════════════ FLAG CONSTANTS ═══════════════════════════════════════*/

    /// @notice WearerRules flag constants
    uint8 internal constant ELIGIBLE_FLAG = 0x01; // bit 0
    uint8 internal constant STANDING_FLAG = 0x02; // bit 1

    /// @notice VouchConfig flag constants
    uint8 internal constant ENABLED_FLAG = 0x01; // bit 0
    uint8 internal constant COMBINE_HIERARCHY_FLAG = 0x02; // bit 1

    /*═══════════════════════════════════ USER ADMIN HAT MANAGEMENT ═══════════════════════════════════*/

    /// @notice Add an admin hat to a user's active set
    /// @param user The user address
    /// @param adminHatId The admin hat ID to add
    function _addUserAdminHat(address user, uint256 adminHatId) internal {
        Layout storage l = _layout();
        if (l.adminHatActive[adminHatId]) {
            l.userAdminHats[user].add(adminHatId);
            emit UserAdminHatAdded(user, adminHatId);
        }
    }

    /// @notice Remove an admin hat from a user's active set
    /// @param user The user address
    /// @param adminHatId The admin hat ID to remove
    function _removeUserAdminHat(address user, uint256 adminHatId) internal {
        Layout storage l = _layout();
        if (l.userAdminHats[user].remove(adminHatId)) {
            emit UserAdminHatRemoved(user, adminHatId);
        }
    }

    /// @notice Update a user's admin hat status based on current hat ownership
    /// @param user The user address
    /// @param adminHatId The admin hat ID
    function _updateUserAdminHat(address user, uint256 adminHatId) internal {
        Layout storage l = _layout();
        bool isWearing = l.hats.isWearerOfHat(user, adminHatId);
        bool hasInSet = l.userAdminHats[user].contains(adminHatId);

        if (isWearing && !hasInSet) {
            _addUserAdminHat(user, adminHatId);
        } else if (!isWearing && hasInSet) {
            _removeUserAdminHat(user, adminHatId);
        }
    }

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

    /// @notice Emitted when a user gains an admin hat
    event UserAdminHatAdded(address indexed user, uint256 indexed adminHatId);

    /// @notice Emitted when a user loses an admin hat
    event UserAdminHatRemoved(address indexed user, uint256 indexed adminHatId);

    /// @notice Emitted when the eligibility module admin hat is set
    event EligibilityModuleAdminHatSet(uint256 indexed hatId);

    /// @notice Emitted when a hat is automatically minted due to vouching
    event HatAutoMinted(address indexed wearer, uint256 indexed hatId, uint32 vouchCount);

    /**
     * @notice Initialize the module with super admin and Hats contract
     * @param _superAdmin The super admin address
     * @param _hats The Hats contract address
     */
    function initialize(address _superAdmin, address _hats) external initializer {
        Layout storage l = _layout();
        l.superAdmin = _superAdmin;
        l.hats = IHats(_hats);
        emit EligibilityModuleInitialized(_superAdmin, _hats);
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Restricts certain calls so only the super admin can perform them
     */
    modifier onlySuperAdmin() {
        if (msg.sender != _layout().superAdmin) revert NotSuperAdmin();
        _;
    }

    /**
     * @dev Restricts calls to admin hats with permission for the specific target hat
     */
    modifier onlyAuthorizedAdmin(uint256 targetHatId) {
        if (!isAuthorizedAdmin(msg.sender, targetHatId)) revert NotAuthorizedAdmin();
        _;
    }

    /**
     * @notice Check if an address is authorized to control a specific target hat (runtime check)
     * @param user The address to check
     * @param targetHatId The target hat ID
     * @return authorized Whether the user is authorized
     */
    function isAuthorizedAdmin(address user, uint256 targetHatId) public view returns (bool authorized) {
        Layout storage l = _layout();

        // Super admin can control any hat
        if (user == l.superAdmin) {
            return true;
        }

        // Check all admin hats that the user currently wears
        EnumerableSet.UintSet storage userHats = l.userAdminHats[user];
        uint256 len = userHats.length();
        for (uint256 i; i < len; ++i) {
            uint256 adminHat = userHats.at(i);
            if (l.adminHatActive[adminHat] && l.adminPermissions[adminHat][targetHatId]) {
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
        Layout storage l = _layout();
        l.wearerRules[wearer][hatId] = WearerRules(_packWearerFlags(_eligible, _standing));
        l.hasSpecificWearerRules[wearer][hatId] = true;
        emit WearerEligibilityUpdated(wearer, hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Sets default eligibility for a hat that applies to all wearers who don't have specific rules
     * @param hatId The hat ID to set default eligibility for
     * @param _eligible Whether wearers are eligible by default (true) or not (false)
     * @param _standing Whether wearers are in good standing by default (true) or bad (false)
     */
    function setDefaultEligibility(uint256 hatId, bool _eligible, bool _standing) external onlyAuthorizedAdmin(hatId) {
        Layout storage l = _layout();
        l.defaultRules[hatId] = WearerRules(_packWearerFlags(_eligible, _standing));
        emit DefaultEligibilityUpdated(hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Clear specific rules for a wearer, reverting them to default rules
     * @param wearer The address whose specific rules to clear
     * @param hatId The hat ID to clear specific rules for
     */
    function clearWearerEligibility(address wearer, uint256 hatId) external onlyAuthorizedAdmin(hatId) {
        Layout storage l = _layout();
        delete l.wearerRules[wearer][hatId];
        delete l.hasSpecificWearerRules[wearer][hatId];
        emit WearerEligibilityUpdated(wearer, hatId, false, false, msg.sender);
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
        Layout storage l = _layout();
        uint8 packedFlags = _packWearerFlags(_eligible, _standing);
        for (uint256 i = 0; i < wearers.length; i++) {
            l.wearerRules[wearers[i]][hatId] = WearerRules(packedFlags);
            l.hasSpecificWearerRules[wearers[i]][hatId] = true;
        }
        emit BulkWearerEligibilityUpdated(wearers, hatId, _eligible, _standing, msg.sender);
    }

    /**
     * @notice Add or remove an admin hat
     * @param hatId The hat ID to add or remove as admin
     * @param isAdmin Whether this hat should be an admin (true) or not (false)
     */
    function setAdminHat(uint256 hatId, bool isAdmin) external onlySuperAdmin {
        Layout storage l = _layout();
        bool wasAdmin = l.adminHats[hatId];
        l.adminHats[hatId] = isAdmin;
        l.adminHatActive[hatId] = isAdmin;

        if (isAdmin && !wasAdmin) {
            // Adding new admin hat
            l.adminHatIds.add(hatId);
        } else if (!isAdmin && wasAdmin) {
            // Removing admin hat - find and remove from set
            l.adminHatIds.remove(hatId);

            // Clear all admin permissions for this hat
            // Note: Individual users will lose access automatically via runtime check
            // since _adminHatActive[hatId] is now false
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
        Layout storage l = _layout();
        if (!l.adminHats[adminHatId]) revert NotAnAdminHat();
        if (targetHatIds.length != canControl.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < targetHatIds.length; i++) {
            uint256 targetHatId = targetHatIds[i];

            // Update the permission
            l.adminPermissions[adminHatId][targetHatId] = canControl[i];

            emit AdminPermissionUpdated(adminHatId, targetHatIds[i], canControl[i], msg.sender);
        }

        // No sync needed - runtime check will use new permissions immediately
    }

    /**
     * @notice Update a user's admin hat status based on current hat ownership
     * @dev Should be called when a user gains or loses an admin hat
     * @param user The user address
     * @param adminHatId The admin hat ID to update
     */
    function updateUserAdminHat(address user, uint256 adminHatId) external onlySuperAdmin {
        Layout storage l = _layout();
        if (!l.adminHats[adminHatId]) revert NotAnAdminHat();
        _updateUserAdminHat(user, adminHatId);
    }

    /**
     * @notice Batch update multiple users' admin hat status
     * @param users Array of user addresses
     * @param adminHatIds Array of admin hat IDs (must match users length)
     */
    function batchUpdateUserAdminHats(address[] calldata users, uint256[] calldata adminHatIds)
        external
        onlySuperAdmin
    {
        Layout storage l = _layout();
        if (users.length != adminHatIds.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < users.length; i++) {
            if (!l.adminHats[adminHatIds[i]]) revert NotAnAdminHat();
            _updateUserAdminHat(users[i], adminHatIds[i]);
        }
    }

    /**
     * @notice Update all admin hats for a specific user
     * @param user The user address
     */
    function updateAllUserAdminHats(address user) external onlySuperAdmin {
        Layout storage l = _layout();
        // Check all admin hats in the system
        for (uint256 i = 0; i < l.adminHatIds.length(); i++) {
            uint256 adminHatId = l.adminHatIds.at(i);
            _updateUserAdminHat(user, adminHatId);
        }
    }

    /**
     * @notice Set the eligibility module admin hat (only during deployment)
     * @param hatId The hat ID that this module will wear for admin purposes
     */
    function setEligibilityModuleAdminHat(uint256 hatId) external onlySuperAdmin {
        Layout storage l = _layout();
        l.eligibilityModuleAdminHat = hatId;
        emit EligibilityModuleAdminHatSet(hatId);
    }

    /**
     * @notice Mint a hat to a specific address (only callable by super admin or the module itself)
     * @dev This allows the EligibilityModule to mint hats since it's now the admin of role hats
     * @param hatId The hat ID to mint
     * @param wearer The address to mint the hat to
     */
    function mintHatToAddress(uint256 hatId, address wearer) external onlySuperAdmin {
        Layout storage l = _layout();
        bool success = l.hats.mintHat(hatId, wearer);
        require(success, "Hat minting failed");
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
        Layout storage l = _layout();
        bool enabled = quorum > 0;
        l.vouchConfigs[hatId] = VouchConfig({
            quorum: quorum,
            membershipHatId: membershipHatId,
            flags: _packVouchFlags(enabled, combineWithHierarchy)
        });

        emit VouchConfigSet(hatId, quorum, membershipHatId, enabled, combineWithHierarchy);
    }

    /**
     * @notice Vouch for a wearer to receive a specific hat
     * @param wearer The address to vouch for
     * @param hatId The hat ID to vouch for
     */
    function vouchFor(address wearer, uint256 hatId) external {
        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];
        if (!_isVouchingEnabled(config.flags)) revert VouchingNotEnabled();
        if (!l.hats.isWearerOfHat(msg.sender, config.membershipHatId)) revert NotAuthorizedToVouch();
        if (l.vouchers[hatId][wearer][msg.sender]) revert AlreadyVouched();

        // Record the vouch
        l.vouchers[hatId][wearer][msg.sender] = true;
        l.currentVouchCount[hatId][wearer]++;

        emit Vouched(msg.sender, wearer, hatId, l.currentVouchCount[hatId][wearer]);

        // Auto-mint hat if quorum is reached and wearer doesn't already have it
        if (l.currentVouchCount[hatId][wearer] >= config.quorum && !l.hats.isWearerOfHat(wearer, hatId)) {
            bool success = l.hats.mintHat(hatId, wearer);
            if (success) {
                emit HatAutoMinted(wearer, hatId, l.currentVouchCount[hatId][wearer]);
            }
        }
    }

    /**
     * @notice Revoke a vouch for a wearer
     * @param wearer The address to revoke vouch for
     * @param hatId The hat ID to revoke vouch for
     */
    function revokeVouch(address wearer, uint256 hatId) external {
        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];
        if (!_isVouchingEnabled(config.flags)) revert VouchingNotEnabled();
        if (!l.vouchers[hatId][wearer][msg.sender]) revert HasNotVouched();

        // Remove the vouch
        l.vouchers[hatId][wearer][msg.sender] = false;
        l.currentVouchCount[hatId][wearer]--;

        emit VouchRevoked(msg.sender, wearer, hatId, l.currentVouchCount[hatId][wearer]);

        // If vouching is the only path (not combined with hierarchy) and 
        // vouch count drops below quorum, revoke the hat
        if (!_shouldCombineWithHierarchy(config.flags) && 
            l.currentVouchCount[hatId][wearer] < config.quorum && 
            l.hats.isWearerOfHat(wearer, hatId)) {
            // Check if the wearer doesn't have specific admin-granted eligibility
            if (!l.hasSpecificWearerRules[wearer][hatId]) {
                // Only revoke if they don't have admin-granted eligibility
                l.hats.setHatWearerStatus(hatId, wearer, false, false);
            }
        }
    }

    /**
     * @notice Reset all vouches for a specific hat (super admin only)
     * @param hatId The hat ID to reset vouches for
     */
    function resetVouches(uint256 hatId) external onlySuperAdmin {
        Layout storage l = _layout();
        delete l.vouchConfigs[hatId];
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
        Layout storage l = _layout();
        // Check if vouching is enabled for this hat
        VouchConfig memory config = l.vouchConfigs[hatId];

        bool hierarchyEligible = false;
        bool hierarchyStanding = false;
        bool vouchEligible = false;
        bool vouchStanding = false;

        // 1. Check hierarchy path (existing logic)
        if (l.hasSpecificWearerRules[wearer][hatId]) {
            // Specific rules exist for this wearer
            WearerRules memory rules = l.wearerRules[wearer][hatId];
            (hierarchyEligible, hierarchyStanding) = _unpackWearerFlags(rules.flags);
        } else {
            // Use default rules
            WearerRules memory defaultRule = l.defaultRules[hatId];
            (hierarchyEligible, hierarchyStanding) = _unpackWearerFlags(defaultRule.flags);
        }

        // 2. Check vouch path (if enabled)
        if (_isVouchingEnabled(config.flags)) {
            // Check if current vouch count meets quorum
            if (l.currentVouchCount[hatId][wearer] >= config.quorum) {
                vouchEligible = true;
                vouchStanding = true;
            }
        }

        // 3. Combine results based on configuration
        if (_isVouchingEnabled(config.flags)) {
            if (_shouldCombineWithHierarchy(config.flags)) {
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
        if (newSuperAdmin == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        address oldSuperAdmin = l.superAdmin;
        l.superAdmin = newSuperAdmin;
        emit SuperAdminTransferred(oldSuperAdmin, newSuperAdmin);
    }

    /**
     * @notice Check if a hat is an admin hat
     * @param hatId The hat ID to check
     * @return isAdmin Whether the hat is an admin hat
     */
    function isAdminHat(uint256 hatId) external view returns (bool isAdmin) {
        return _layout().adminHats[hatId];
    }

    /**
     * @notice Check if an admin hat can control a specific target hat
     * @param adminHatId The admin hat ID
     * @param targetHatId The target hat ID
     * @return canControl Whether the admin hat can control the target hat
     */
    function canAdminControlHat(uint256 adminHatId, uint256 targetHatId) external view returns (bool canControl) {
        Layout storage l = _layout();
        return l.adminHats[adminHatId] && l.adminPermissions[adminHatId][targetHatId];
    }

    /**
     * @notice Get all admin hat IDs
     * @return adminHats Array of all admin hat IDs
     */
    function getAdminHatIds() external view returns (uint256[] memory) {
        return _layout().adminHatIds.values();
    }

    /**
     * @notice Get vouch configuration for a hat
     * @param hatId The hat ID to get configuration for
     * @return config The vouch configuration with unpacked boolean values
     */
    function getVouchConfig(uint256 hatId) external view returns (VouchConfig memory config) {
        config = _layout().vouchConfigs[hatId];
        // Note: The returned config contains packed flags - use helper functions to decode
    }

    /**
     * @notice Check if vouching is enabled for a hat
     * @param hatId The hat ID to check
     * @return enabled Whether vouching is enabled
     */
    function isVouchingEnabled(uint256 hatId) external view returns (bool enabled) {
        return _isVouchingEnabled(_layout().vouchConfigs[hatId].flags);
    }

    /**
     * @notice Check if a hat combines hierarchy with vouching
     * @param hatId The hat ID to check
     * @return combineWithHierarchy Whether hierarchy is combined with vouching
     */
    function combinesWithHierarchy(uint256 hatId) external view returns (bool combineWithHierarchy) {
        return _shouldCombineWithHierarchy(_layout().vouchConfigs[hatId].flags);
    }

    /**
     * @notice Get unpacked wearer rules for debugging/inspection
     * @param wearer The wearer address
     * @param hatId The hat ID
     * @return eligible Whether the wearer is eligible
     * @return standing Whether the wearer has good standing
     */
    function getWearerRules(address wearer, uint256 hatId) external view returns (bool eligible, bool standing) {
        Layout storage l = _layout();
        if (l.hasSpecificWearerRules[wearer][hatId]) {
            WearerRules memory rules = l.wearerRules[wearer][hatId];
            return _unpackWearerFlags(rules.flags);
        } else {
            return _unpackWearerFlags(l.defaultRules[hatId].flags);
        }
    }

    /**
     * @notice Get unpacked default rules for a hat
     * @param hatId The hat ID
     * @return eligible Whether wearers are eligible by default
     * @return standing Whether wearers have good standing by default
     */
    function getDefaultRules(uint256 hatId) external view returns (bool eligible, bool standing) {
        return _unpackWearerFlags(_layout().defaultRules[hatId].flags);
    }

    /**
     * @notice Check if an address has vouched for a wearer for a specific hat
     * @param hatId The hat ID
     * @param wearer The wearer address
     * @param voucher The voucher address
     * @return hasVouched Whether the voucher has vouched for the wearer
     */
    function hasVouched(uint256 hatId, address wearer, address voucher) external view returns (bool hasVouched) {
        return _layout().vouchers[hatId][wearer][voucher];
    }

    /**
     * @notice Check if a user has admin rights for a specific target hat (same as isAuthorizedAdmin)
     * @param user The user address
     * @param targetHatId The target hat ID
     * @return hasRights Whether the user has admin rights for the target hat
     */
    function hasAdminRights(address user, uint256 targetHatId) external view returns (bool hasRights) {
        return isAuthorizedAdmin(user, targetHatId);
    }

    /**
     * @notice Get all admin hats that a user currently has in their active set
     * @param user The user address
     * @return adminHatIds Array of admin hat IDs the user currently has
     */
    function getUserAdminHats(address user) external view returns (uint256[] memory adminHatIds) {
        Layout storage l = _layout();
        EnumerableSet.UintSet storage userHats = l.userAdminHats[user];
        uint256 length = userHats.length();
        adminHatIds = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            adminHatIds[i] = userHats.at(i);
        }
    }

    /**
     * @notice Get the number of admin hats a user currently has
     * @param user The user address
     * @return count Number of admin hats the user currently has
     */
    function getUserAdminHatCount(address user) external view returns (uint256 count) {
        return _layout().userAdminHats[user].length();
    }

    /**
     * @notice Check if a user has a specific admin hat in their active set
     * @param user The user address
     * @param adminHatId The admin hat ID to check
     * @return hasHat Whether the user has the admin hat
     */
    function userHasAdminHat(address user, uint256 adminHatId) external view returns (bool hasHat) {
        return _layout().userAdminHats[user].contains(adminHatId);
    }

    /**
     * @notice Check if an admin hat is currently active
     * @param adminHatId The admin hat ID
     * @return isActive Whether the admin hat is active
     */
    function isAdminHatActive(uint256 adminHatId) external view returns (bool isActive) {
        return _layout().adminHatActive[adminHatId];
    }

    /**
     * @notice Check if a wearer has specific rules set (explicitly configured)
     * @param wearer The wearer address
     * @param hatId The hat ID
     * @return hasSpecific Whether the wearer has specific rules
     */
    function hasSpecificWearerRules(address wearer, uint256 hatId) external view returns (bool hasSpecific) {
        return _layout().hasSpecificWearerRules[wearer][hatId];
    }

    /*═════════════════════════════════════ PUBLIC GETTERS ═════════════════════════════════════════*/

    /// @notice Get the Hats Protocol contract
    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    /// @notice Get the super admin address
    function superAdmin() external view returns (address) {
        return _layout().superAdmin;
    }

    /// @notice Get wearer rules for a specific wearer and hat
    function wearerRules(address wearer, uint256 hatId) external view returns (WearerRules memory) {
        return _layout().wearerRules[wearer][hatId];
    }

    /// @notice Get default rules for a specific hat
    function defaultRules(uint256 hatId) external view returns (WearerRules memory) {
        return _layout().defaultRules[hatId];
    }

    /// @notice Check if a hat is an admin hat (legacy compatibility)
    function adminHats(uint256 hatId) external view returns (bool) {
        return _layout().adminHats[hatId];
    }

    /// @notice Check admin permissions for a specific admin hat and target hat
    function adminPermissions(uint256 adminHatId, uint256 targetHatId) external view returns (bool) {
        return _layout().adminPermissions[adminHatId][targetHatId];
    }

    /// @notice Get vouch configuration for a specific hat
    function vouchConfigs(uint256 hatId) external view returns (VouchConfig memory) {
        return _layout().vouchConfigs[hatId];
    }

    /// @notice Check if a voucher has vouched for a wearer for a specific hat
    function vouchers(uint256 hatId, address wearer, address voucher) external view returns (bool) {
        return _layout().vouchers[hatId][wearer][voucher];
    }

    /// @notice Get current vouch count for a wearer for a specific hat
    function currentVouchCount(uint256 hatId, address wearer) external view returns (uint32) {
        return _layout().currentVouchCount[hatId][wearer];
    }

    /// @notice Get the eligibility module admin hat ID
    function eligibilityModuleAdminHat() external view returns (uint256) {
        return _layout().eligibilityModuleAdminHat;
    }

    /*═════════════════════════════════════ PURE VIEW HELPERS ═════════════════════════════════════*/

    /// @notice Pack WearerRules boolean values into flags
    /// @param eligible Whether the wearer is eligible
    /// @param standing Whether the wearer is in good standing
    /// @return flags Packed uint8 flags
    function _packWearerFlags(bool eligible, bool standing) internal pure returns (uint8 flags) {
        if (eligible) flags |= ELIGIBLE_FLAG;
        if (standing) flags |= STANDING_FLAG;
    }

    /// @notice Unpack WearerRules flags into boolean values
    /// @param flags Packed uint8 flags
    /// @return eligible Whether the wearer is eligible
    /// @return standing Whether the wearer is in good standing
    function _unpackWearerFlags(uint8 flags) internal pure returns (bool eligible, bool standing) {
        eligible = (flags & ELIGIBLE_FLAG) != 0;
        standing = (flags & STANDING_FLAG) != 0;
    }

    /// @notice Pack VouchConfig boolean values into flags
    /// @param enabled Whether vouching is enabled
    /// @param combineWithHierarchy Whether to combine with hierarchy
    /// @return flags Packed uint8 flags
    function _packVouchFlags(bool enabled, bool combineWithHierarchy) internal pure returns (uint8 flags) {
        if (enabled) flags |= ENABLED_FLAG;
        if (combineWithHierarchy) flags |= COMBINE_HIERARCHY_FLAG;
    }

    /// @notice Unpack VouchConfig flags into boolean values
    /// @param flags Packed uint8 flags
    /// @return enabled Whether vouching is enabled
    /// @return combineWithHierarchy Whether to combine with hierarchy
    function _unpackVouchFlags(uint8 flags) internal pure returns (bool enabled, bool combineWithHierarchy) {
        enabled = (flags & ENABLED_FLAG) != 0;
        combineWithHierarchy = (flags & COMBINE_HIERARCHY_FLAG) != 0;
    }

    /// @notice Check if a wearer is eligible using packed flags
    /// @param flags Packed uint8 flags
    /// @return eligible Whether the wearer is eligible
    function _isEligible(uint8 flags) internal pure returns (bool eligible) {
        return (flags & ELIGIBLE_FLAG) != 0;
    }

    /// @notice Check if a wearer has good standing using packed flags
    /// @param flags Packed uint8 flags
    /// @return standing Whether the wearer is in good standing
    function _hasGoodStanding(uint8 flags) internal pure returns (bool standing) {
        return (flags & STANDING_FLAG) != 0;
    }

    /// @notice Check if vouching is enabled using packed flags
    /// @param flags Packed uint8 flags
    /// @return enabled Whether vouching is enabled
    function _isVouchingEnabled(uint8 flags) internal pure returns (bool enabled) {
        return (flags & ENABLED_FLAG) != 0;
    }

    /// @notice Check if hierarchy should be combined using packed flags
    /// @param flags Packed uint8 flags
    /// @return combineWithHierarchy Whether to combine with hierarchy
    function _shouldCombineWithHierarchy(uint8 flags) internal pure returns (bool combineWithHierarchy) {
        return (flags & COMBINE_HIERARCHY_FLAG) != 0;
    }
}
