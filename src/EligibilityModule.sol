// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../lib/hats-protocol/src/Interfaces/IHats.sol";
import "../lib/hats-protocol/src/Interfaces/IHatsEligibility.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/**
 * @notice Minimal interface for ToggleModule - only includes functions we actually use
 */
interface IToggleModule {
    function setHatStatus(uint256 hatId, bool _active) external;
}

/**
 * @title EligibilityModule
 * @notice A hat-based module for configuring eligibility and standing
 *         on a per-hat basis in the Hats Protocol, controlled by admin hats.
 *         Now supports optional N-Vouch eligibility system.
 */
contract EligibilityModule is Initializable, IHatsEligibility {
    /*═══════════════════════════════════════════ ERRORS ═══════════════════════════════════════════*/

    error NotSuperAdmin();
    error NotAuthorizedAdmin();
    error ZeroAddress();
    error InvalidQuorum();
    error InvalidMembershipHat();
    error CannotVouchForSelf();
    error InvalidHatId();
    error InvalidUser();
    error InvalidJoinTime();
    error ArrayLengthMismatch();
    error VouchingNotEnabled();
    error NotAuthorizedToVouch();
    error AlreadyVouched();
    error HasNotVouched();
    error VouchingRateLimitExceeded();
    error NewUserVouchingRestricted();

    /*═════════════════════════════════════════ STRUCTS ═════════════════════════════════════════*/

    /// @notice Per-wearer per-hat configuration for eligibility and standing (packed)
    struct WearerRules {
        uint8 flags; // Packed flags: bit 0 = eligible, bit 1 = standing
    }

    /// @notice Configuration for vouching system per hat (optimized packing)
    struct VouchConfig {
        uint32 quorum; // Number of vouches required
        uint256 membershipHatId; // Hat ID whose wearers can vouch
        uint8 flags; // Packed flags: bit 0 = enabled, bit 1 = combineWithHierarchy
    }

    /// @notice Parameters for creating a hat with eligibility configuration
    struct CreateHatParams {
        uint256 parentHatId;
        string details;
        uint32 maxSupply;
        bool _mutable;
        string imageURI;
        bool defaultEligible;
        bool defaultStanding;
        address[] mintToAddresses;
        bool[] wearerEligibleFlags;
        bool[] wearerStandingFlags;
    }

    /*═════════════════════════════════════ ERC-7201 STORAGE ═════════════════════════════════════*/

    /// @custom:storage-location erc7201:poa.eligibilitymodule.storage
    struct Layout {
        // Slot 1: Core addresses (40 bytes + 24 bytes padding)
        IHats hats; // 20 bytes
        address superAdmin; // 20 bytes
        // Slot 2: Module addresses + hat ID (20 + 20 + 32 = 72 bytes across 3 slots)
        address toggleModule; // 20 bytes
        uint256 eligibilityModuleAdminHat; // 32 bytes (separate slot)
        // Emergency pause state
        bool _paused;
        // Mappings (separate slots each)
        mapping(address => mapping(uint256 => WearerRules)) wearerRules;
        mapping(address => mapping(uint256 => bool)) hasSpecificWearerRules;
        mapping(uint256 => WearerRules) defaultRules;
        mapping(uint256 => VouchConfig) vouchConfigs;
        mapping(uint256 => mapping(address => mapping(address => bool))) vouchers;
        mapping(uint256 => mapping(address => uint32)) currentVouchCount;
        // Rate limiting for vouching
        mapping(address => uint256) userJoinTime;
        mapping(address => mapping(uint256 => uint32)) dailyVouchCount; // user => day => count
    }

    // keccak256("poa.eligibilitymodule.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x8f7c0d6a29b3e7e2f1a0c9b8d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b9c8d7e6;

    /// @dev Use assembly for gas-optimized storage access
    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*═══════════════════════════════════════ REENTRANCY PROTECTION ═══════════════════════════════════*/

    uint256 private _notEntered = 1;

    modifier nonReentrant() {
        require(_notEntered == 1, "ReentrancyGuard: reentrant call");
        _notEntered = 2;
        _;
        _notEntered = 1;
    }

    modifier whenNotPaused() {
        require(!_layout()._paused, "Contract is paused");
        _;
    }

    /*═══════════════════════════════════════ FLAG CONSTANTS ═══════════════════════════════════════*/

    uint8 private constant ELIGIBLE_FLAG = 0x01; // bit 0
    uint8 private constant STANDING_FLAG = 0x02; // bit 1
    uint8 private constant ENABLED_FLAG = 0x01; // bit 0
    uint8 private constant COMBINE_HIERARCHY_FLAG = 0x02; // bit 1

    /*═══════════════════════════════════ RATE LIMITING CONSTANTS ═══════════════════════════════════*/

    uint32 private constant MAX_DAILY_VOUCHES = 3;
    uint256 private constant NEW_USER_RESTRICTION_DAYS = 0; // Removed wait period for immediate vouching
    uint256 private constant SECONDS_PER_DAY = 86400;

    /*═══════════════════════════════════════════ EVENTS ═══════════════════════════════════════════*/

    event WearerEligibilityUpdated(
        address indexed wearer, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );
    event DefaultEligibilityUpdated(uint256 indexed hatId, bool eligible, bool standing, address indexed admin);

    event BulkWearerEligibilityUpdated(
        address[] wearers, uint256 indexed hatId, bool eligible, bool standing, address indexed admin
    );
    event SuperAdminTransferred(address indexed oldSuperAdmin, address indexed newSuperAdmin);
    event EligibilityModuleInitialized(address indexed superAdmin, address indexed hatsContract);
    event Vouched(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);
    event VouchRevoked(address indexed voucher, address indexed wearer, uint256 indexed hatId, uint32 newCount);
    event VouchConfigSet(
        uint256 indexed hatId, uint32 quorum, uint256 membershipHatId, bool enabled, bool combineWithHierarchy
    );
    event UserJoinTimeSet(address indexed user, uint256 indexed joinTime);
    event VouchingRateLimitExceededEvent(address indexed user);
    event NewUserVouchingRestrictedEvent(address indexed user);
    event EligibilityModuleAdminHatSet(uint256 indexed hatId);
    event HatAutoMinted(address indexed wearer, uint256 indexed hatId, uint32 vouchCount);
    event HatCreatedWithEligibility(
        address indexed creator,
        uint256 indexed parentHatId,
        uint256 indexed newHatId,
        bool defaultEligible,
        bool defaultStanding,
        uint256 mintedCount
    );
    event Paused(address indexed account);
    event Unpaused(address indexed account);

    /*═════════════════════════════════════════ MODIFIERS ═════════════════════════════════════════*/

    modifier onlySuperAdmin() {
        if (msg.sender != _layout().superAdmin) revert NotSuperAdmin();
        _;
    }

    modifier onlyHatAdmin(uint256 targetHatId) {
        Layout storage l = _layout();
        if (msg.sender != l.superAdmin && !l.hats.isAdminOfHat(msg.sender, targetHatId)) revert NotAuthorizedAdmin();
        _;
    }

    /*═══════════════════════════════════════ INITIALIZATION ═══════════════════════════════════════*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _superAdmin, address _hats, address _toggleModule) external initializer {
        if (_superAdmin == address(0) || _hats == address(0)) revert ZeroAddress();

        Layout storage l = _layout();
        l.superAdmin = _superAdmin;
        l.hats = IHats(_hats);
        l.toggleModule = _toggleModule;
        l._paused = false;
        emit EligibilityModuleInitialized(_superAdmin, _hats);
    }

    /*═══════════════════════════════════ PAUSE MANAGEMENT ═══════════════════════════════════════*/

    function pause() external onlySuperAdmin {
        _layout()._paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlySuperAdmin {
        _layout()._paused = false;
        emit Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return _layout()._paused;
    }

    /*═══════════════════════════════════ AUTHORIZATION LOGIC ═══════════════════════════════════════*/

    // Authorization is now handled natively by the Hats tree structure using onlyHatAdmin modifier

    /*═══════════════════════════════════ ELIGIBILITY MANAGEMENT ═══════════════════════════════════════*/

    function setWearerEligibility(address wearer, uint256 hatId, bool _eligible, bool _standing)
        external
        onlyHatAdmin(hatId)
        whenNotPaused
    {
        if (wearer == address(0)) revert ZeroAddress();
        _setWearerEligibilityInternal(wearer, hatId, _eligible, _standing);
    }

    function setDefaultEligibility(uint256 hatId, bool _eligible, bool _standing)
        external
        onlyHatAdmin(hatId)
        whenNotPaused
    {
        Layout storage l = _layout();
        l.defaultRules[hatId] = WearerRules(_packWearerFlags(_eligible, _standing));
        emit DefaultEligibilityUpdated(hatId, _eligible, _standing, msg.sender);
    }

    function clearWearerEligibility(address wearer, uint256 hatId) external onlyHatAdmin(hatId) whenNotPaused {
        if (wearer == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        delete l.wearerRules[wearer][hatId];
        delete l.hasSpecificWearerRules[wearer][hatId];
        emit WearerEligibilityUpdated(wearer, hatId, false, false, msg.sender);
    }

    function setBulkWearerEligibility(address[] calldata wearers, uint256 hatId, bool _eligible, bool _standing)
        external
        onlyHatAdmin(hatId)
    {
        uint256 length = wearers.length;
        if (length == 0) revert ArrayLengthMismatch();

        uint8 packedFlags = _packWearerFlags(_eligible, _standing);
        Layout storage l = _layout();

        // Use unchecked for gas optimization in the loop only
        for (uint256 i; i < length;) {
            address wearer = wearers[i];
            if (wearer == address(0)) revert ZeroAddress();
            l.wearerRules[wearer][hatId] = WearerRules(packedFlags);
            l.hasSpecificWearerRules[wearer][hatId] = true;
            unchecked {
                ++i;
            }
        }
        emit BulkWearerEligibilityUpdated(wearers, hatId, _eligible, _standing, msg.sender);
    }

    /// @dev Internal function to reduce code duplication
    function _setWearerEligibilityInternal(address wearer, uint256 hatId, bool _eligible, bool _standing) internal {
        Layout storage l = _layout();
        l.wearerRules[wearer][hatId] = WearerRules(_packWearerFlags(_eligible, _standing));
        l.hasSpecificWearerRules[wearer][hatId] = true;
        emit WearerEligibilityUpdated(wearer, hatId, _eligible, _standing, msg.sender);
    }

    /*═══════════════════════════════════ BATCH OPERATIONS ═══════════════════════════════════════*/

    function batchSetWearerEligibility(
        uint256 hatId,
        address[] calldata wearers,
        bool[] calldata eligibleFlags,
        bool[] calldata standingFlags
    ) external onlyHatAdmin(hatId) {
        uint256 length = wearers.length;
        if (length != eligibleFlags.length || length != standingFlags.length) {
            revert ArrayLengthMismatch();
        }

        Layout storage l = _layout();

        // Use unchecked for gas optimization
        unchecked {
            for (uint256 i; i < length; ++i) {
                address wearer = wearers[i];
                l.wearerRules[wearer][hatId] = WearerRules(_packWearerFlags(eligibleFlags[i], standingFlags[i]));
                l.hasSpecificWearerRules[wearer][hatId] = true;
                emit WearerEligibilityUpdated(wearer, hatId, eligibleFlags[i], standingFlags[i], msg.sender);
            }
        }
    }

    /*═══════════════════════════════════ HAT CREATION ═══════════════════════════════════════*/

    function createHatWithEligibility(CreateHatParams calldata params)
        external
        onlyHatAdmin(params.parentHatId)
        returns (uint256 newHatId)
    {
        Layout storage l = _layout();

        // Create the new hat
        newHatId = l.hats
            .createHat(
                params.parentHatId,
                params.details,
                params.maxSupply,
                address(this),
                l.toggleModule,
                params._mutable,
                params.imageURI
            );

        // Set default eligibility rules
        l.defaultRules[newHatId] = WearerRules(_packWearerFlags(params.defaultEligible, params.defaultStanding));

        // Automatically activate the hat
        IToggleModule(l.toggleModule).setHatStatus(newHatId, true);

        emit DefaultEligibilityUpdated(newHatId, params.defaultEligible, params.defaultStanding, msg.sender);

        // Handle initial minting if specified
        uint256 mintLength = params.mintToAddresses.length;
        if (mintLength > 0) {
            _handleInitialMinting(
                newHatId, params.mintToAddresses, params.wearerEligibleFlags, params.wearerStandingFlags, mintLength
            );
        }

        emit HatCreatedWithEligibility(
            msg.sender, params.parentHatId, newHatId, params.defaultEligible, params.defaultStanding, mintLength
        );
    }

    /// @notice Register a hat that was created externally and emit the HatCreatedWithEligibility event
    /// @dev Used by HatsTreeSetup to emit events for subgraph indexing without needing admin rights to create hats
    /// @param hatId The ID of the hat that was created
    /// @param parentHatId The ID of the parent hat
    /// @param defaultEligible Whether wearers are eligible by default
    /// @param defaultStanding Whether wearers have good standing by default
    function registerHatCreation(uint256 hatId, uint256 parentHatId, bool defaultEligible, bool defaultStanding)
        external
        onlyHatAdmin(parentHatId)
    {
        Layout storage l = _layout();
        l.defaultRules[hatId] = WearerRules(_packWearerFlags(defaultEligible, defaultStanding));
        emit DefaultEligibilityUpdated(hatId, defaultEligible, defaultStanding, msg.sender);
        emit HatCreatedWithEligibility(msg.sender, parentHatId, hatId, defaultEligible, defaultStanding, 0);
    }

    /// @dev Internal function to handle initial minting logic
    function _handleInitialMinting(
        uint256 hatId,
        address[] calldata addresses,
        bool[] calldata eligibleFlags,
        bool[] calldata standingFlags,
        uint256 length
    ) internal {
        Layout storage l = _layout();

        // If specific eligibility flags provided, validate and set them
        if (eligibleFlags.length > 0) {
            if (length != eligibleFlags.length || length != standingFlags.length) {
                revert ArrayLengthMismatch();
            }

            // Set specific eligibility and mint
            unchecked {
                for (uint256 i; i < length; ++i) {
                    address wearer = addresses[i];
                    l.wearerRules[wearer][hatId] = WearerRules(_packWearerFlags(eligibleFlags[i], standingFlags[i]));
                    l.hasSpecificWearerRules[wearer][hatId] = true;

                    bool success = l.hats.mintHat(hatId, wearer);
                    require(success, "Hat minting failed");

                    emit WearerEligibilityUpdated(wearer, hatId, eligibleFlags[i], standingFlags[i], msg.sender);
                }
            }
        } else {
            // Just mint with default eligibility
            unchecked {
                for (uint256 i; i < length; ++i) {
                    bool success = l.hats.mintHat(hatId, addresses[i]);
                    require(success, "Hat minting failed");
                }
            }
        }
    }

    /*═══════════════════════════════════ MODULE MANAGEMENT ═══════════════════════════════════════*/

    function setEligibilityModuleAdminHat(uint256 hatId) external onlySuperAdmin {
        _layout().eligibilityModuleAdminHat = hatId;
        emit EligibilityModuleAdminHatSet(hatId);
    }

    function mintHatToAddress(uint256 hatId, address wearer) external onlySuperAdmin {
        bool success = _layout().hats.mintHat(hatId, wearer);
        require(success, "Hat minting failed");
    }

    function setToggleModule(address _toggleModule) external onlySuperAdmin {
        _layout().toggleModule = _toggleModule;
    }

    function transferSuperAdmin(address newSuperAdmin) external onlySuperAdmin {
        if (newSuperAdmin == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        address oldSuperAdmin = l.superAdmin;
        l.superAdmin = newSuperAdmin;
        emit SuperAdminTransferred(oldSuperAdmin, newSuperAdmin);
    }

    function setUserJoinTime(address user, uint256 joinTime) external onlySuperAdmin {
        _layout().userJoinTime[user] = joinTime;
        emit UserJoinTimeSet(user, joinTime);
    }

    function setUserJoinTimeNow(address user) external onlySuperAdmin {
        _layout().userJoinTime[user] = block.timestamp;
        emit UserJoinTimeSet(user, block.timestamp);
    }

    /*═══════════════════════════════════ VOUCHING SYSTEM ═══════════════════════════════════════*/

    function configureVouching(uint256 hatId, uint32 quorum, uint256 membershipHatId, bool combineWithHierarchy)
        external
        onlySuperAdmin
    {
        Layout storage l = _layout();
        bool enabled = quorum > 0;
        l.vouchConfigs[hatId] = VouchConfig({
            quorum: quorum, membershipHatId: membershipHatId, flags: _packVouchFlags(enabled, combineWithHierarchy)
        });

        emit VouchConfigSet(hatId, quorum, membershipHatId, enabled, combineWithHierarchy);
    }

    function vouchFor(address wearer, uint256 hatId) external whenNotPaused {
        if (wearer == address(0)) revert ZeroAddress();
        if (wearer == msg.sender) revert CannotVouchForSelf();

        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];
        if (!_isVouchingEnabled(config.flags)) revert VouchingNotEnabled();
        if (!l.hats.isWearerOfHat(msg.sender, config.membershipHatId)) revert NotAuthorizedToVouch();
        if (l.vouchers[hatId][wearer][msg.sender]) revert AlreadyVouched();

        // SECURITY: Rate limiting checks
        _checkVouchingRateLimit(msg.sender);

        // Record the vouch
        l.vouchers[hatId][wearer][msg.sender] = true;
        uint32 newCount = l.currentVouchCount[hatId][wearer] + 1;
        l.currentVouchCount[hatId][wearer] = newCount;

        // Update daily vouch count
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        uint32 dailyCount = l.dailyVouchCount[msg.sender][currentDay] + 1;
        l.dailyVouchCount[msg.sender][currentDay] = dailyCount;

        emit Vouched(msg.sender, wearer, hatId, newCount);

        // Auto-mint hat if quorum is reached and wearer doesn't already have it
        if (newCount >= config.quorum && !l.hats.isWearerOfHat(wearer, hatId)) {
            bool success = l.hats.mintHat(hatId, wearer);
            if (success) {
                emit HatAutoMinted(wearer, hatId, newCount);
            }
        }
    }

    function _checkVouchingRateLimit(address user) internal view {
        Layout storage l = _layout();

        // Check if user has been around long enough to vouch
        // NEW_USER_RESTRICTION_DAYS = 0, so anyone can vouch immediately
        uint256 joinTime = l.userJoinTime[user];
        if (joinTime != 0) {
            // Only check if join time is set
            uint256 daysSinceJoined = (block.timestamp - joinTime) / SECONDS_PER_DAY;
            if (daysSinceJoined < NEW_USER_RESTRICTION_DAYS) {
                revert NewUserVouchingRestricted();
            }
        }
        // If joinTime is 0 (never set), allow vouching since NEW_USER_RESTRICTION_DAYS = 0

        // Check daily vouch limit
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        if (l.dailyVouchCount[user][currentDay] >= MAX_DAILY_VOUCHES) {
            revert VouchingRateLimitExceeded();
        }
    }

    function revokeVouch(address wearer, uint256 hatId) external whenNotPaused {
        if (wearer == address(0)) revert ZeroAddress();

        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];
        if (!_isVouchingEnabled(config.flags)) revert VouchingNotEnabled();
        if (!l.vouchers[hatId][wearer][msg.sender]) revert HasNotVouched();

        // Remove the vouch
        l.vouchers[hatId][wearer][msg.sender] = false;
        uint32 newCount = l.currentVouchCount[hatId][wearer] - 1;
        l.currentVouchCount[hatId][wearer] = newCount;

        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        uint32 dailyCount = l.dailyVouchCount[msg.sender][currentDay] - 1;
        l.dailyVouchCount[msg.sender][currentDay] = dailyCount;

        emit VouchRevoked(msg.sender, wearer, hatId, newCount);

        // Handle hat revocation if needed
        if (
            !_shouldCombineWithHierarchy(config.flags) && newCount < config.quorum
                && l.hats.isWearerOfHat(wearer, hatId) && !l.hasSpecificWearerRules[wearer][hatId]
        ) {
            l.hats.setHatWearerStatus(hatId, wearer, false, false);
        }
    }

    function resetVouches(uint256 hatId) external onlySuperAdmin {
        delete _layout().vouchConfigs[hatId];
        emit VouchConfigSet(hatId, 0, 0, false, false);
    }

    /*═══════════════════════════════════ ELIGIBILITY INTERFACE ═══════════════════════════════════════*/

    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing) {
        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];

        bool hierarchyEligible;
        bool hierarchyStanding;
        bool vouchEligible;
        bool vouchStanding;

        // Check hierarchy path
        WearerRules memory rules;
        if (l.hasSpecificWearerRules[wearer][hatId]) {
            rules = l.wearerRules[wearer][hatId];
        } else {
            rules = l.defaultRules[hatId];
        }
        (hierarchyEligible, hierarchyStanding) = _unpackWearerFlags(rules.flags);

        // Check vouch path if enabled
        if (_isVouchingEnabled(config.flags) && l.currentVouchCount[hatId][wearer] >= config.quorum) {
            vouchEligible = true;
            vouchStanding = true;
        }

        // Combine results
        if (_isVouchingEnabled(config.flags)) {
            if (_shouldCombineWithHierarchy(config.flags)) {
                eligible = hierarchyEligible || vouchEligible;
                standing = hierarchyStanding || vouchStanding;
            } else {
                eligible = vouchEligible;
                standing = vouchStanding;
            }
        } else {
            eligible = hierarchyEligible;
            standing = hierarchyStanding;
        }

        // If standing is false, eligibility MUST also be false per IHatsEligibility interface
        if (!standing) {
            eligible = false;
        }
    }

    /*═════════════════════════════════════ VIEW FUNCTIONS ═════════════════════════════════════════*/

    function getVouchConfig(uint256 hatId) external view returns (VouchConfig memory) {
        return _layout().vouchConfigs[hatId];
    }

    function isVouchingEnabled(uint256 hatId) external view returns (bool) {
        return _isVouchingEnabled(_layout().vouchConfigs[hatId].flags);
    }

    function combinesWithHierarchy(uint256 hatId) external view returns (bool) {
        return _shouldCombineWithHierarchy(_layout().vouchConfigs[hatId].flags);
    }

    function getWearerRules(address wearer, uint256 hatId) external view returns (bool eligible, bool standing) {
        Layout storage l = _layout();
        if (l.hasSpecificWearerRules[wearer][hatId]) {
            return _unpackWearerFlags(l.wearerRules[wearer][hatId].flags);
        } else {
            return _unpackWearerFlags(l.defaultRules[hatId].flags);
        }
    }

    function getDefaultRules(uint256 hatId) external view returns (bool eligible, bool standing) {
        return _unpackWearerFlags(_layout().defaultRules[hatId].flags);
    }

    function hasVouched(uint256 hatId, address wearer, address voucher) external view returns (bool) {
        return _layout().vouchers[hatId][wearer][voucher];
    }

    function hasAdminRights(address user, uint256 targetHatId) external view returns (bool) {
        Layout storage l = _layout();
        return user == l.superAdmin || l.hats.isAdminOfHat(user, targetHatId);
    }

    function getUserJoinTime(address user) external view returns (uint256) {
        return _layout().userJoinTime[user];
    }

    function getDailyVouchCount(address user, uint256 day) external view returns (uint32) {
        return _layout().dailyVouchCount[user][day];
    }

    function getCurrentDailyVouchCount(address user) external view returns (uint32) {
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        return _layout().dailyVouchCount[user][currentDay];
    }

    function canUserVouch(address user) external view returns (bool) {
        Layout storage l = _layout();

        // Check if user has been around long enough
        uint256 joinTime = l.userJoinTime[user];
        if (joinTime == 0) return false;

        uint256 daysSinceJoined = (block.timestamp - joinTime) / SECONDS_PER_DAY;
        if (daysSinceJoined < NEW_USER_RESTRICTION_DAYS) return false;

        // Check daily vouch limit
        uint256 currentDay = block.timestamp / SECONDS_PER_DAY;
        return l.dailyVouchCount[user][currentDay] < MAX_DAILY_VOUCHES;
    }

    function hasSpecificWearerRules(address wearer, uint256 hatId) external view returns (bool) {
        return _layout().hasSpecificWearerRules[wearer][hatId];
    }

    /*═════════════════════════════════════ PUBLIC GETTERS ═════════════════════════════════════════*/

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function superAdmin() external view returns (address) {
        return _layout().superAdmin;
    }

    function wearerRules(address wearer, uint256 hatId) external view returns (WearerRules memory) {
        return _layout().wearerRules[wearer][hatId];
    }

    function defaultRules(uint256 hatId) external view returns (WearerRules memory) {
        return _layout().defaultRules[hatId];
    }

    function vouchConfigs(uint256 hatId) external view returns (VouchConfig memory) {
        return _layout().vouchConfigs[hatId];
    }

    function vouchers(uint256 hatId, address wearer, address voucher) external view returns (bool) {
        return _layout().vouchers[hatId][wearer][voucher];
    }

    function currentVouchCount(uint256 hatId, address wearer) external view returns (uint32) {
        return _layout().currentVouchCount[hatId][wearer];
    }

    function eligibilityModuleAdminHat() external view returns (uint256) {
        return _layout().eligibilityModuleAdminHat;
    }

    function toggleModule() external view returns (address) {
        return _layout().toggleModule;
    }

    /*═════════════════════════════════════ PURE HELPERS ═════════════════════════════════════════*/

    /// @dev Gas-optimized flag packing using assembly
    function _packWearerFlags(bool eligible, bool standing) internal pure returns (uint8 flags) {
        assembly {
            flags := or(eligible, shl(1, standing))
        }
    }

    /// @dev Gas-optimized flag unpacking using assembly
    function _unpackWearerFlags(uint8 flags) internal pure returns (bool eligible, bool standing) {
        assembly {
            eligible := and(flags, 1)
            standing := and(shr(1, flags), 1)
        }
    }

    function _packVouchFlags(bool enabled, bool combineWithHierarchy) internal pure returns (uint8 flags) {
        assembly {
            flags := or(enabled, shl(1, combineWithHierarchy))
        }
    }

    function _isEligible(uint8 flags) internal pure returns (bool) {
        return (flags & ELIGIBLE_FLAG) != 0;
    }

    function _hasGoodStanding(uint8 flags) internal pure returns (bool) {
        return (flags & STANDING_FLAG) != 0;
    }

    function _isVouchingEnabled(uint8 flags) internal pure returns (bool) {
        return (flags & ENABLED_FLAG) != 0;
    }

    function _shouldCombineWithHierarchy(uint8 flags) internal pure returns (bool) {
        return (flags & COMBINE_HIERARCHY_FLAG) != 0;
    }
}
