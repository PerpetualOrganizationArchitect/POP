// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.13 ^0.8.17 ^0.8.20 ^0.8.30;

// lib/hats-protocol/src/Interfaces/HatsErrors.sol

// Copyright (C) 2023 Haberdasher Labs
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

interface HatsErrors {
    /// @notice Emitted when `user` is attempting to perform an action on `hatId` but is not wearing one of `hatId`'s admin hats
    /// @dev Can be equivalent to `NotHatWearer(buildHatId(hatId))`, such as when emitted by `approveLinkTopHatToTree` or `relinkTopHatToTree`
    error NotAdmin(address user, uint256 hatId);

    /// @notice Emitted when attempting to perform an action as or for an account that is not a wearer of a given hat
    error NotHatWearer();

    /// @notice Emitted when attempting to perform an action that requires being either an admin or wearer of a given hat
    error NotAdminOrWearer();

    /// @notice Emitted when attempting to mint `hatId` but `hatId`'s maxSupply has been reached
    error AllHatsWorn(uint256 hatId);

    /// @notice Emitted when attempting to create a hat with a level 14 hat as its admin
    error MaxLevelsReached();

    /// @notice Emitted when an attempted hat id has empty intermediate level(s)
    error InvalidHatId();

    /// @notice Emitted when attempting to mint `hatId` to a `wearer` who is already wearing the hat
    error AlreadyWearingHat(address wearer, uint256 hatId);

    /// @notice Emitted when attempting to mint a non-existant hat
    error HatDoesNotExist(uint256 hatId);

    /// @notice Emmitted when attempting to mint or transfer a hat that is not active
    error HatNotActive();

    /// @notice Emitted when attempting to mint or transfer a hat to an ineligible wearer
    error NotEligible();

    /// @notice Emitted when attempting to check or set a hat's status from an account that is not that hat's toggle module
    error NotHatsToggle();

    /// @notice Emitted when attempting to check or set a hat wearer's status from an account that is not that hat's eligibility module
    error NotHatsEligibility();

    /// @notice Emitted when array arguments to a batch function have mismatching lengths
    error BatchArrayLengthMismatch();

    /// @notice Emitted when attempting to mutate or transfer an immutable hat
    error Immutable();

    /// @notice Emitted when attempting to change a hat's maxSupply to a value lower than its current supply
    error NewMaxSupplyTooLow();

    /// @notice Emitted when attempting to link a tophat to a new admin for which the tophat serves as an admin
    error CircularLinkage();

    /// @notice Emitted when attempting to link or relink a tophat to a separate tree
    error CrossTreeLinkage();

    /// @notice Emitted when attempting to link a tophat without a request
    error LinkageNotRequested();

    /// @notice Emitted when attempting to unlink a tophat that does not have a wearer
    /// @dev This ensures that unlinking never results in a bricked tophat
    error InvalidUnlink();

    /// @notice Emmited when attempting to change a hat's eligibility or toggle module to the zero address
    error ZeroAddress();

    /// @notice Emmitted when attempting to change a hat's details or imageURI to a string with over 7000 bytes (~characters)
    /// @dev This protects against a DOS attack where an admin iteratively extend's a hat's details or imageURI
    ///      to be so long that reading it exceeds the block gas limit, breaking `uri()` and `viewHat()`
    error StringTooLong();
}

// lib/hats-protocol/src/Interfaces/HatsEvents.sol

// Copyright (C) 2023 Haberdasher Labs
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

interface HatsEvents {
    /// @notice Emitted when a new hat is created
    /// @param id The id for the new hat
    /// @param details A description of the Hat
    /// @param maxSupply The total instances of the Hat that can be worn at once
    /// @param eligibility The address that can report on the Hat wearer's status
    /// @param toggle The address that can deactivate the Hat
    /// @param mutable_ Whether the hat's properties are changeable after creation
    /// @param imageURI The image uri for this hat and the fallback for its
    event HatCreated(
        uint256 id,
        string details,
        uint32 maxSupply,
        address eligibility,
        address toggle,
        bool mutable_,
        string imageURI
    );

    /// @notice Emitted when a hat wearer's standing is updated
    /// @dev Eligibility is excluded since the source of truth for eligibility is the eligibility module and may change without a transaction
    /// @param hatId The id of the wearer's hat
    /// @param wearer The wearer's address
    /// @param wearerStanding Whether the wearer is in good standing for the hat
    event WearerStandingChanged(uint256 hatId, address wearer, bool wearerStanding);

    /// @notice Emitted when a hat's status is updated
    /// @param hatId The id of the hat
    /// @param newStatus Whether the hat is active
    event HatStatusChanged(uint256 hatId, bool newStatus);

    /// @notice Emitted when a hat's details are updated
    /// @param hatId The id of the hat
    /// @param newDetails The updated details
    event HatDetailsChanged(uint256 hatId, string newDetails);

    /// @notice Emitted when a hat's eligibility module is updated
    /// @param hatId The id of the hat
    /// @param newEligibility The updated eligibiliy module
    event HatEligibilityChanged(uint256 hatId, address newEligibility);

    /// @notice Emitted when a hat's toggle module is updated
    /// @param hatId The id of the hat
    /// @param newToggle The updated toggle module
    event HatToggleChanged(uint256 hatId, address newToggle);

    /// @notice Emitted when a hat's mutability is updated
    /// @param hatId The id of the hat
    event HatMutabilityChanged(uint256 hatId);

    /// @notice Emitted when a hat's maximum supply is updated
    /// @param hatId The id of the hat
    /// @param newMaxSupply The updated max supply
    event HatMaxSupplyChanged(uint256 hatId, uint32 newMaxSupply);

    /// @notice Emitted when a hat's image URI is updated
    /// @param hatId The id of the hat
    /// @param newImageURI The updated image URI
    event HatImageURIChanged(uint256 hatId, string newImageURI);

    /// @notice Emitted when a tophat linkage is requested by its admin
    /// @param domain The domain of the tree tophat to link
    /// @param newAdmin The tophat's would-be admin in the parent tree
    event TopHatLinkRequested(uint32 domain, uint256 newAdmin);

    /// @notice Emitted when a tophat is linked to a another tree
    /// @param domain The domain of the newly-linked tophat
    /// @param newAdmin The tophat's new admin in the parent tree
    event TopHatLinked(uint32 domain, uint256 newAdmin);
}

// lib/hats-protocol/src/Interfaces/IHatsIdUtilities.sol

// Copyright (C) 2023 Haberdasher Labs
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

interface IHatsIdUtilities {
    function buildHatId(uint256 _admin, uint16 _newHat) external pure returns (uint256 id);

    function getHatLevel(uint256 _hatId) external view returns (uint32 level);

    function getLocalHatLevel(uint256 _hatId) external pure returns (uint32 level);

    function isTopHat(uint256 _hatId) external view returns (bool _topHat);

    function isLocalTopHat(uint256 _hatId) external pure returns (bool _localTopHat);

    function isValidHatId(uint256 _hatId) external view returns (bool validHatId);

    function getAdminAtLevel(uint256 _hatId, uint32 _level) external view returns (uint256 admin);

    function getAdminAtLocalLevel(uint256 _hatId, uint32 _level) external pure returns (uint256 admin);

    function getTopHatDomain(uint256 _hatId) external view returns (uint32 domain);

    function getTippyTopHatDomain(uint32 _topHatDomain) external view returns (uint32 domain);

    function noCircularLinkage(uint32 _topHatDomain, uint256 _linkedAdmin) external view returns (bool notCircular);

    function sameTippyTopHatDomain(uint32 _topHatDomain, uint256 _newAdminHat)
        external
        view
        returns (bool sameDomain);
}

// src/interfaces/IHatsModules.sol

interface IEligibilityModule {
    function setToggleModule(address) external;
    function setWearerEligibility(address wearer, uint256 hatId, bool eligible, bool standing) external;
    function setDefaultEligibility(uint256 hatId, bool eligible, bool standing) external;
    function setEligibilityModuleAdminHat(uint256) external;
    function mintHatToAddress(uint256 hatId, address wearer) external;
    function transferSuperAdmin(address) external;
    function getWearerStatus(address wearer, uint256 hatId) external view returns (bool eligible, bool standing);
    function vouchFor(address wearer, uint256 hatId) external;
    function revokeVouch(address wearer, uint256 hatId) external;
    function currentVouchCount(uint256 hatId, address wearer) external view returns (uint32);
    function claimVouchedHat(uint256 hatId) external;
    function registerHatCreation(uint256 hatId, uint256 parentHatId, bool defaultEligible, bool defaultStanding)
        external;
    // Batch operations for gas optimization
    function batchSetWearerEligibilityMultiHat(
        address[] calldata wearers,
        uint256[] calldata hatIds,
        bool eligible,
        bool standing
    ) external;
    function batchSetDefaultEligibility(uint256[] calldata hatIds, bool[] calldata eligibles, bool[] calldata standings)
        external;
    function batchMintHats(uint256[] calldata hatIds, address[] calldata wearers) external;
    function batchRegisterHatCreation(
        uint256[] calldata hatIds,
        uint256[] calldata parentHatIds,
        bool[] calldata defaultEligibles,
        bool[] calldata defaultStandings
    ) external;
    function batchRegisterHatCreationWithMetadata(
        uint256[] calldata hatIds,
        uint256[] calldata parentHatIds,
        bool[] calldata defaultEligibles,
        bool[] calldata defaultStandings,
        string[] calldata names,
        bytes32[] calldata metadataCIDs
    ) external;
    function batchConfigureVouching(
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external;
    // Metadata management
    function updateHatMetadata(uint256 hatId, string memory name, bytes32 metadataCID) external;
}

interface IToggleModule {
    function setEligibilityModule(address) external;
    function setHatStatus(uint256 hatId, bool active) external;
    function batchSetHatStatus(uint256[] calldata hatIds, bool[] calldata actives) external;
    function transferAdmin(address) external;
}

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/utils/Initializable.sol)

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```solidity
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 *
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
abstract contract Initializable {
    /**
     * @dev Storage of the initializable contract.
     *
     * It's implemented on a custom ERC-7201 namespace to reduce the risk of storage collisions
     * when using with upgradeable contracts.
     *
     * @custom:storage-location erc7201:openzeppelin.storage.Initializable
     */
    struct InitializableStorage {
        /**
         * @dev Indicates that the contract has been initialized.
         */
        uint64 _initialized;
        /**
         * @dev Indicates that the contract is in the process of being initialized.
         */
        bool _initializing;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Initializable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INITIALIZABLE_STORAGE = 0xf0c57e16840df040f15088dc2f81fe391c3923bec73e23a9662efc9c229c6a00;

    /**
     * @dev The contract is already initialized.
     */
    error InvalidInitialization();

    /**
     * @dev The contract is not initializing.
     */
    error NotInitializing();

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint64 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that in the context of a constructor an `initializer` may be invoked any
     * number of times. This behavior in the constructor can be useful during testing and is not expected to be used in
     * production.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        // Cache values to avoid duplicated sloads
        bool isTopLevelCall = !$._initializing;
        uint64 initialized = $._initialized;

        // Allowed calls:
        // - initialSetup: the contract is not in the initializing state and no previous version was
        //                 initialized
        // - construction: the contract is initialized at version 1 (no reininitialization) and the
        //                 current contract is just being deployed
        bool initialSetup = initialized == 0 && isTopLevelCall;
        bool construction = initialized == 1 && address(this).code.length == 0;

        if (!initialSetup && !construction) {
            revert InvalidInitialization();
        }
        $._initialized = 1;
        if (isTopLevelCall) {
            $._initializing = true;
        }
        _;
        if (isTopLevelCall) {
            $._initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: Setting the version to 2**64 - 1 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint64 version) {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing || $._initialized >= version) {
            revert InvalidInitialization();
        }
        $._initialized = version;
        $._initializing = true;
        _;
        $._initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        _checkInitializing();
        _;
    }

    /**
     * @dev Reverts if the contract is not in an initializing state. See {onlyInitializing}.
     */
    function _checkInitializing() internal view virtual {
        if (!_isInitializing()) {
            revert NotInitializing();
        }
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        // solhint-disable-next-line var-name-mixedcase
        InitializableStorage storage $ = _getInitializableStorage();

        if ($._initializing) {
            revert InvalidInitialization();
        }
        if ($._initialized != type(uint64).max) {
            $._initialized = type(uint64).max;
            emit Initialized(type(uint64).max);
        }
    }

    /**
     * @dev Returns the highest version that has been initialized. See {reinitializer}.
     */
    function _getInitializedVersion() internal view returns (uint64) {
        return _getInitializableStorage()._initialized;
    }

    /**
     * @dev Returns `true` if the contract is currently initializing. See {onlyInitializing}.
     */
    function _isInitializing() internal view returns (bool) {
        return _getInitializableStorage()._initializing;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        assembly {
            $.slot := INITIALIZABLE_STORAGE
        }
    }
}

// src/libs/RoleConfigStructs.sol

/**
 * @title RoleConfigStructs
 * @notice Shared struct definitions for role configuration
 * @dev Used across OrgDeployer, GovernanceFactory, and HatsTreeSetup to avoid duplication
 *      and eliminate the need for type conversion functions
 */
library RoleConfigStructs {
    /// @notice Vouching configuration for a role
    /// @dev Allows roles to require vouches before claiming/minting
    struct RoleVouchingConfig {
        bool enabled; // Enable vouching for this role
        uint32 quorum; // Number of vouches required
        uint256 voucherRoleIndex; // Index of role that can vouch (in roles array)
        bool combineWithHierarchy; // Allow child hats to vouch too
    }

    /// @notice Default eligibility settings for a role
    /// @dev Controls whether new wearers are eligible/in good standing by default
    struct RoleEligibilityDefaults {
        bool eligible; // Default eligibility status
        bool standing; // Default standing status
    }

    /// @notice Hierarchy configuration for a role
    /// @dev Controls the parent-child relationship in the Hats tree
    struct RoleHierarchyConfig {
        uint256 adminRoleIndex; // Index of parent/admin role (type(uint256).max = use ELIGIBILITY_ADMIN or auto)
    }

    /// @notice Initial distribution configuration for a role
    /// @dev Controls who gets the role minted to them initially
    struct RoleDistributionConfig {
        bool mintToDeployer; // Mint to deployer address
        bool mintToExecutor; // Mint to executor contract
        address[] additionalWearers; // Additional addresses to mint to
    }

    /// @notice Hat-specific configuration from Hats Protocol
    /// @dev Controls Hats Protocol native features
    struct HatConfig {
        uint32 maxSupply; // Maximum number of wearers (0 = unlimited, default: type(uint32).max)
        bool mutableHat; // Whether hat properties can be changed after creation (default: true)
    }

    /// @notice Complete configuration for a single role
    /// @dev Encompasses all aspects of role setup: metadata, hierarchy, vouching, distribution
    struct RoleConfig {
        string name; // Role name (e.g., "MEMBER", "ADMIN")
        string image; // IPFS hash or URI for role image
        bytes32 metadataCID; // IPFS CID for extended role metadata JSON
        bool canVote; // Whether this role can participate in voting
        RoleVouchingConfig vouching; // Vouching configuration
        RoleEligibilityDefaults defaults; // Default eligibility settings
        RoleHierarchyConfig hierarchy; // Parent-child relationship
        RoleDistributionConfig distribution; // Initial hat distribution
        HatConfig hatConfig; // Hats Protocol configuration
    }
}

// src/libs/ValidationLib.sol

/**
 * @title ValidationLib
 * @notice Library for common validation operations
 * @dev Reduces bytecode by extracting validation logic into reusable functions
 */
library ValidationLib {
    /* ─────────── Errors ─────────── */
    error ZeroAddress();
    error InvalidString();
    error InvalidPayout();
    error CapBelowCommitted();
    error EmptyTitle();
    error TitleTooLong();

    /* ─────────── Constants ─────────── */
    uint256 internal constant MAX_PAYOUT = 1e24; // 1 000 000 tokens (18 dec)
    uint96 internal constant MAX_PAYOUT_96 = 1e24; // same as above, but as uint96
    uint256 internal constant MAX_TITLE_LENGTH = 256; // max title length in bytes

    /* ─────────── Core Functions ─────────── */

    /**
     * @notice Validate that an address is not zero
     * @param addr The address to validate
     */
    function requireNonZeroAddress(address addr) internal pure {
        if (addr == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Validate that a string/bytes is not empty
     * @param data The bytes data to validate
     */
    function requireNonEmptyBytes(bytes calldata data) internal pure {
        if (data.length == 0) revert InvalidString();
    }

    /**
     * @notice Validate that a title is not empty and within length limits
     * @param title The title to validate (dynamic bytes)
     */
    function requireValidTitle(bytes calldata title) internal pure {
        if (title.length == 0) revert EmptyTitle();
        if (title.length > MAX_TITLE_LENGTH) revert TitleTooLong();
    }

    /**
     * @notice Validate payout amount (non-zero and within limits)
     * @param payout The payout amount to validate
     */
    function requireValidPayout(uint256 payout) internal pure {
        if (payout == 0 || payout > MAX_PAYOUT) revert InvalidPayout();
    }

    /**
     * @notice Validate payout amount for uint96 (non-zero and within limits)
     * @param payout The payout amount to validate
     */
    function requireValidPayout96(uint256 payout) internal pure {
        if (payout == 0 || payout > MAX_PAYOUT_96) revert InvalidPayout();
    }

    /**
     * @notice Validate bounty payout (can be zero, but if non-zero must be within limits)
     * @param payout The bounty payout amount to validate
     */
    function requireValidBountyPayout(uint256 payout) internal pure {
        if (payout > MAX_PAYOUT_96) revert InvalidPayout();
    }

    /**
     * @notice Validate bounty token and payout combination
     * @param bountyToken The bounty token address
     * @param bountyPayout The bounty payout amount
     */
    function requireValidBountyConfig(address bountyToken, uint256 bountyPayout) internal pure {
        // If bounty payout > 0, token must not be zero address
        if (bountyPayout > 0 && bountyToken == address(0)) revert ZeroAddress();

        // If token is set, payout must be > 0
        if (bountyToken != address(0) && bountyPayout == 0) revert InvalidPayout();

        // Validate bounty payout amount
        requireValidBountyPayout(bountyPayout);
    }

    /**
     * @notice Validate that a new cap is not below committed amount
     * @param newCap The new cap to validate
     * @param committed The currently committed/spent amount
     */
    function requireValidCap(uint256 newCap, uint256 committed) internal pure {
        if (newCap != 0 && newCap < committed) revert CapBelowCommitted();
    }

    /**
     * @notice Validate cap amount (within max limits)
     * @param cap The cap amount to validate
     */
    function requireValidCapAmount(uint256 cap) internal pure {
        if (cap > MAX_PAYOUT) revert InvalidPayout();
    }

    /**
     * @notice Validate that an application hash is not empty
     * @param applicationHash The application hash to validate
     */
    function requireValidApplicationHash(bytes32 applicationHash) internal pure {
        if (applicationHash == bytes32(0)) revert InvalidString();
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Ownable
    struct OwnableStorage {
        address _owner;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Ownable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant OwnableStorageLocation = 0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;

    function _getOwnableStorage() private pure returns (OwnableStorage storage $) {
        assembly {
            $.slot := OwnableStorageLocation
        }
    }

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    function __Ownable_init(address initialOwner) internal onlyInitializing {
        __Ownable_init_unchained(initialOwner);
    }

    function __Ownable_init_unchained(address initialOwner) internal onlyInitializing {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        OwnableStorage storage $ = _getOwnableStorage();
        return $._owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        OwnableStorage storage $ = _getOwnableStorage();
        address oldOwner = $._owner;
        $._owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// lib/hats-protocol/src/Interfaces/IHats.sol

// Copyright (C) 2023 Haberdasher Labs
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

interface IHats is IHatsIdUtilities, HatsErrors, HatsEvents {
    function mintTopHat(address _target, string memory _details, string memory _imageURI)
        external
        returns (uint256 topHatId);

    function createHat(
        uint256 _admin,
        string calldata _details,
        uint32 _maxSupply,
        address _eligibility,
        address _toggle,
        bool _mutable,
        string calldata _imageURI
    ) external returns (uint256 newHatId);

    function batchCreateHats(
        uint256[] calldata _admins,
        string[] calldata _details,
        uint32[] calldata _maxSupplies,
        address[] memory _eligibilityModules,
        address[] memory _toggleModules,
        bool[] calldata _mutables,
        string[] calldata _imageURIs
    ) external returns (bool success);

    function getNextId(uint256 _admin) external view returns (uint256 nextId);

    function mintHat(uint256 _hatId, address _wearer) external returns (bool success);

    function batchMintHats(uint256[] calldata _hatIds, address[] calldata _wearers) external returns (bool success);

    function setHatStatus(uint256 _hatId, bool _newStatus) external returns (bool toggled);

    function checkHatStatus(uint256 _hatId) external returns (bool toggled);

    function setHatWearerStatus(uint256 _hatId, address _wearer, bool _eligible, bool _standing)
        external
        returns (bool updated);

    function checkHatWearerStatus(uint256 _hatId, address _wearer) external returns (bool updated);

    function renounceHat(uint256 _hatId) external;

    function transferHat(uint256 _hatId, address _from, address _to) external;

    /*//////////////////////////////////////////////////////////////
                              HATS ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function makeHatImmutable(uint256 _hatId) external;

    function changeHatDetails(uint256 _hatId, string memory _newDetails) external;

    function changeHatEligibility(uint256 _hatId, address _newEligibility) external;

    function changeHatToggle(uint256 _hatId, address _newToggle) external;

    function changeHatImageURI(uint256 _hatId, string memory _newImageURI) external;

    function changeHatMaxSupply(uint256 _hatId, uint32 _newMaxSupply) external;

    function requestLinkTopHatToTree(uint32 _topHatId, uint256 _newAdminHat) external;

    function approveLinkTopHatToTree(
        uint32 _topHatId,
        uint256 _newAdminHat,
        address _eligibility,
        address _toggle,
        string calldata _details,
        string calldata _imageURI
    ) external;

    function unlinkTopHatFromTree(uint32 _topHatId, address _wearer) external;

    function relinkTopHatWithinTree(
        uint32 _topHatDomain,
        uint256 _newAdminHat,
        address _eligibility,
        address _toggle,
        string calldata _details,
        string calldata _imageURI
    ) external;

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function viewHat(uint256 _hatId)
        external
        view
        returns (
            string memory details,
            uint32 maxSupply,
            uint32 supply,
            address eligibility,
            address toggle,
            string memory imageURI,
            uint16 lastHatId,
            bool mutable_,
            bool active
        );

    function isWearerOfHat(address _user, uint256 _hatId) external view returns (bool isWearer);

    function isAdminOfHat(address _user, uint256 _hatId) external view returns (bool isAdmin);

    function isInGoodStanding(address _wearer, uint256 _hatId) external view returns (bool standing);

    function isEligible(address _wearer, uint256 _hatId) external view returns (bool eligible);

    function getHatEligibilityModule(uint256 _hatId) external view returns (address eligibility);

    function getHatToggleModule(uint256 _hatId) external view returns (address toggle);

    function getHatMaxSupply(uint256 _hatId) external view returns (uint32 maxSupply);

    function hatSupply(uint256 _hatId) external view returns (uint32 supply);

    function getImageURIForHat(uint256 _hatId) external view returns (string memory _uri);

    function balanceOf(address wearer, uint256 hatId) external view returns (uint256 balance);

    function balanceOfBatch(address[] calldata _wearers, uint256[] calldata _hatIds)
        external
        view
        returns (uint256[] memory);

    function uri(uint256 id) external view returns (string memory _uri);
}

// src/UniversalAccountRegistry.sol
// SPDX‑License‑Identifier: MIT

/*──────────────────── OpenZeppelin Upgradeables ────────────────────*/

contract UniversalAccountRegistry is Initializable, OwnableUpgradeable {
    /*────────────────────────── Custom Errors ──────────────────────────*/
    error UsernameEmpty();
    error UsernameTooLong();
    error InvalidChars();
    error UsernameTaken();
    error AccountExists();
    error AccountUnknown();
    error ArrayLenMismatch();

    /*─────────────────────────── Constants ─────────────────────────────*/
    uint256 private constant MAX_LEN = 64;
    address private constant BURN_ADDRESS = address(0xdead);

    /*──────────────────────── ERC-7201 Storage ──────────────────────────*/
    /// @custom:storage-location erc7201:poa.universalaccountregistry.storage
    struct Layout {
        mapping(address => string) addressToUsername;
        mapping(bytes32 => address) ownerOfUsernameHash;
    }

    // keccak256("poa.universalaccountregistry.storage") to unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x7930448747c45b59575e0d27c83e46a902e6071fea71aa7dda420fff16e39ee5;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────────────────────── Events ───────────────────────────────*/
    event UserRegistered(address indexed user, string username);
    event UsernameChanged(address indexed user, string newUsername);
    event UserDeleted(address indexed user, string oldUsername);
    event BatchRegistered(uint256 count);

    /*────────────────────────── Initializer ────────────────────────────*/
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert InvalidChars();
        __Ownable_init(initialOwner);
    }

    /*──────────────────── Public Registration API ─────────────────────*/
    function registerAccount(string calldata username) external {
        _register(msg.sender, username);
    }

    /**
     * @notice Permission‑less QuickJoin path. Anyone can call but the
     *         `newUser` must NOT already have a username and the handle
     *         must still be free.
     */
    function registerAccountQuickJoin(string calldata username, address newUser) external {
        _register(newUser, username);
    }

    /**
     * @notice Batch onboarding helper (gas‑friendlier for DAOs).
     * @dev Arrays must be equal length and ≤ 100 to stay within block gas.
     */
    function registerBatch(address[] calldata users, string[] calldata names) external {
        uint256 len = users.length;
        if (len != names.length) revert ArrayLenMismatch();
        require(len <= 100, "batch>100");

        for (uint256 i; i < len;) {
            _register(users[i], names[i]);
            unchecked {
                ++i;
            }
        }
        emit BatchRegistered(len);
    }

    /*──────────── Username mutation & voluntary delete ────────────────*/
    function changeUsername(string calldata newUsername) external {
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        (bytes32 newHash, string memory norm) = _validate(newUsername);
        if (l.ownerOfUsernameHash[newHash] != address(0)) revert UsernameTaken();

        // reserve new
        l.ownerOfUsernameHash[newHash] = msg.sender;

        // keep old reserved forever by burning ownership
        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        l.ownerOfUsernameHash[oldHash] = BURN_ADDRESS;

        l.addressToUsername[msg.sender] = norm;
        emit UsernameChanged(msg.sender, norm);
    }

    /**
     * @notice Delete address ↔ username link.  Name remains permanently
     *         reserved (cannot be claimed by others).
     */
    function deleteAccount() external {
        Layout storage l = _layout();
        string storage oldName = l.addressToUsername[msg.sender];
        if (bytes(oldName).length == 0) revert AccountUnknown();

        bytes32 oldHash = keccak256(bytes(_toLower(oldName)));
        l.ownerOfUsernameHash[oldHash] = BURN_ADDRESS;
        delete l.addressToUsername[msg.sender];

        emit UserDeleted(msg.sender, oldName);
    }

    /*────────────────────────── View Helpers ──────────────────────────*/
    function addressToUsername(address user) external view returns (string memory) {
        return _layout().addressToUsername[user];
    }

    function ownerOfUsernameHash(bytes32 hash) external view returns (address) {
        return _layout().ownerOfUsernameHash[hash];
    }

    function getUsername(address user) external view returns (string memory) {
        return _layout().addressToUsername[user];
    }

    function getAddressOfUsername(string calldata name) external view returns (address) {
        return _layout().ownerOfUsernameHash[keccak256(bytes(_toLower(name)))];
    }

    /*──────────────────── Internal Registration ───────────────────────*/
    function _register(address user, string calldata username) internal {
        Layout storage l = _layout();
        if (bytes(l.addressToUsername[user]).length != 0) revert AccountExists();

        (bytes32 hash, string memory norm) = _validate(username);
        if (l.ownerOfUsernameHash[hash] != address(0)) revert UsernameTaken();

        l.ownerOfUsernameHash[hash] = user;
        l.addressToUsername[user] = norm;

        emit UserRegistered(user, norm);
    }

    /*──────────────────── Username Validation ─────────────────────────*/
    function _validate(string calldata raw) internal pure returns (bytes32 hash, string memory normalized) {
        uint256 len = bytes(raw).length;
        if (len == 0) revert UsernameEmpty();
        if (len > MAX_LEN) revert UsernameTooLong();

        bytes memory lower = bytes(raw);
        for (uint256 i; i < len;) {
            uint8 c = uint8(lower[i]);
            if (c >= 65 && c <= 90) c += 32;
            if (
                // a‑z
                // 0‑9
                !((c >= 97 && c <= 122) || (c >= 48 && c <= 57) || (c == 95) || (c == 45)) // _ or -
            ) revert InvalidChars();
            lower[i] = bytes1(c);
            unchecked {
                ++i;
            }
        }
        normalized = string(lower);
        hash = keccak256(lower);
    }

    function _toLower(string memory s) internal pure returns (string memory) {
        bytes memory b = bytes(s);
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) b[i] = bytes1(c + 32);
        }
        return string(b);
    }
}

// src/OrgRegistry.sol
// SPDX‑License‑Identifier: MIT

/* ─────────── Custom errors ─────────── */
error InvalidParam();
error OrgExists();
error OrgUnknown();
error TypeTaken();
error ContractUnknown();
error NotOrgExecutor();
error OwnerOnlyDuringBootstrap(); // deployer tried after bootstrap
error AutoUpgradeRequired(); // deployer must set autoUpgrade=true

/* ────────────────── Org Registry ────────────────── */
contract OrgRegistry is Initializable, OwnableUpgradeable {
    /* ───── Data structs ───── */
    struct ContractInfo {
        address proxy; // BeaconProxy address
        address beacon; // Beacon address
        bool autoUpgrade; // true ⇒ proxy follows beacon
        address owner; // module owner (immutable metadata)
    }

    struct OrgInfo {
        address executor; // DAO / governor / timelock that controls the org
        uint32 contractCount;
        bool bootstrap; // TRUE until the executor (or deployer via `lastRegister`)
        // finishes initial deployment. Afterwards the registry
        // owner can no longer add contracts.
        bool exists;
    }

    /**
     * @dev Struct for batch contract registration
     * @param typeId The module type identifier (keccak256 of module name)
     * @param proxy The BeaconProxy address
     * @param beacon The Beacon address
     * @param owner The module owner address
     */
    struct ContractRegistration {
        bytes32 typeId;
        address proxy;
        address beacon;
        address owner;
    }

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgregistry.storage
    struct Layout {
        /* ───── Storage ───── */
        mapping(bytes32 => OrgInfo) orgOf; // orgId to OrgInfo
        mapping(bytes32 => ContractInfo) contractOf; // contractId to ContractInfo
        mapping(bytes32 => mapping(bytes32 => address)) proxyOf; // (orgId,typeId) to proxy
        mapping(bytes32 => uint256) topHatOf; // orgId to topHatId
        mapping(bytes32 => mapping(uint256 => uint256)) roleHatOf; // orgId => roleIndex => hatId
        bytes32[] orgIds;
        uint256 totalContracts;
    }

    // keccak256("poa.orgregistry.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x3ffb0627b419b7b77c77f589dd229844c112a8c125dceec0d56dda0674b35489;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───── Events ───── */
    event OrgRegistered(bytes32 indexed orgId, address indexed executor, bytes name, bytes32 metadataHash);
    event MetaUpdated(bytes32 indexed orgId, bytes newName, bytes32 newMetadataHash);
    event ContractRegistered(
        bytes32 indexed contractId,
        bytes32 indexed orgId,
        bytes32 indexed typeId,
        address proxy,
        address beacon,
        bool autoUpgrade,
        address owner
    );
    event AutoUpgradeSet(bytes32 indexed contractId, bool enabled);
    event HatsTreeRegistered(bytes32 indexed orgId, uint256 topHatId, uint256[] roleHatIds);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract, replacing the constructor for upgradeable pattern
     * @param initialOwner The address that will own this registry
     */
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert InvalidParam();
        __Ownable_init(initialOwner);
    }

    /* ═════════════════ ORG  LOGIC ═════════════════ */
    function registerOrg(bytes32 orgId, address executorAddr, bytes calldata name, bytes32 metadataHash)
        external
        onlyOwner
    {
        ValidationLib.requireValidTitle(name);
        if (orgId == bytes32(0) || executorAddr == address(0)) revert InvalidParam();

        Layout storage l = _layout();
        if (l.orgOf[orgId].exists) revert OrgExists();

        l.orgOf[orgId] = OrgInfo({
            executor: executorAddr,
            contractCount: 0,
            bootstrap: true, // owner can add modules while true
            exists: true
        });
        l.orgIds.push(orgId);
        emit OrgRegistered(orgId, executorAddr, name, metadataHash);
    }

    /**
     * @dev Creates an org in bootstrap mode without an executor (for deployment scenarios)
     * @param orgId The org identifier
     * @param name Name of the org (required, raw UTF-8)
     * @param metadataHash IPFS CID sha256 digest (optional, bytes32(0) is valid)
     */
    function createOrgBootstrap(bytes32 orgId, bytes calldata name, bytes32 metadataHash) external onlyOwner {
        ValidationLib.requireValidTitle(name);
        if (orgId == bytes32(0)) revert InvalidParam();

        Layout storage l = _layout();
        if (l.orgOf[orgId].exists) revert OrgExists();

        l.orgOf[orgId] = OrgInfo({
            executor: address(0), // no executor yet
            contractCount: 0,
            bootstrap: true, // in bootstrap mode
            exists: true
        });
        l.orgIds.push(orgId);
        emit OrgRegistered(orgId, address(0), name, metadataHash);
    }

    /**
     * @dev Sets the executor for an org (only during bootstrap)
     * @param orgId The org identifier
     * @param executorAddr The executor address
     */
    function setOrgExecutor(bytes32 orgId, address executorAddr) external onlyOwner {
        if (orgId == bytes32(0) || executorAddr == address(0)) revert InvalidParam();

        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();

        o.executor = executorAddr;
    }

    function updateOrgMeta(bytes32 orgId, bytes calldata newName, bytes32 newMetadataHash) external {
        ValidationLib.requireValidTitle(newName);
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        emit MetaUpdated(orgId, newName, newMetadataHash);
    }

    /* ══════════ CONTRACT  REGISTRATION  ══════════ */
    /**
     *  ‑ During **bootstrap** (`o.bootstrap == true`) the registry owner _may_
     *    register contracts **if and only if `autoUpgrade == true`.**
     *  ‑ Pass `lastRegister = true` on the deployer's final call, or let the
     *    executor register at least once, to end the bootstrap phase.
     *
     *  @param lastRegister  set TRUE when this is the deployer's last module;
     *                       it flips `bootstrap` to false.
     */
    function registerOrgContract(
        bytes32 orgId,
        bytes32 typeId,
        address proxy,
        address beacon,
        bool autoUp,
        address moduleOwner,
        bool lastRegister
    ) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();

        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap, _and_ must opt‑in to auto‑upgrade
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
            if (!autoUp) revert AutoUpgradeRequired();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        if (typeId == bytes32(0) || proxy == address(0) || beacon == address(0) || moduleOwner == address(0)) {
            revert InvalidParam();
        }
        if (l.proxyOf[orgId][typeId] != address(0)) revert TypeTaken();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));

        l.contractOf[contractId] = ContractInfo({proxy: proxy, beacon: beacon, autoUpgrade: autoUp, owner: moduleOwner});
        l.proxyOf[orgId][typeId] = proxy;

        unchecked {
            ++o.contractCount;
            ++l.totalContracts;
        }
        emit ContractRegistered(contractId, orgId, typeId, proxy, beacon, autoUp, moduleOwner);

        // Finish bootstrap if executor registered OR deployer signalled completion
        if ((o.executor != address(0) && callerIsExecutor) || (callerIsOwner && lastRegister)) {
            o.bootstrap = false;
        }
    }

    /**
     * @notice Register multiple contracts in a single transaction (batch operation)
     * @dev Optimized for standard 10-contract deployments. Reduces gas by ~60-80k vs individual calls.
     * @param orgId The organization identifier
     * @param registrations Array of contracts to register
     * @param autoUpgrade Whether contracts auto-upgrade with their beacons
     * @param lastRegister Set true when this is the final batch; finalizes bootstrap phase
     */
    function batchRegisterOrgContracts(
        bytes32 orgId,
        ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];

        // Validation
        if (!o.exists) revert OrgUnknown();
        if (registrations.length == 0) revert InvalidParam();

        // Check caller permissions (same logic as single registration)
        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap, and must opt-in to auto-upgrade
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
            if (!autoUpgrade) revert AutoUpgradeRequired();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        // Batch register all contracts
        uint256 len = registrations.length;
        for (uint256 i = 0; i < len; i++) {
            ContractRegistration calldata reg = registrations[i];

            // Validate parameters
            if (
                reg.typeId == bytes32(0) || reg.proxy == address(0) || reg.beacon == address(0)
                    || reg.owner == address(0)
            ) {
                revert InvalidParam();
            }

            // Check not already registered
            if (l.proxyOf[orgId][reg.typeId] != address(0)) {
                revert TypeTaken();
            }

            // Store contract info
            bytes32 contractId = keccak256(abi.encodePacked(orgId, reg.typeId));
            l.contractOf[contractId] =
                ContractInfo({proxy: reg.proxy, beacon: reg.beacon, autoUpgrade: autoUpgrade, owner: reg.owner});
            l.proxyOf[orgId][reg.typeId] = reg.proxy;

            // Emit event for each contract
            emit ContractRegistered(contractId, orgId, reg.typeId, reg.proxy, reg.beacon, autoUpgrade, reg.owner);
        }

        // Update counts once at the end
        unchecked {
            o.contractCount += uint32(len);
            l.totalContracts += len;
        }

        // Finalize bootstrap if executor registered OR deployer signalled completion
        if ((o.executor != address(0) && callerIsExecutor) || (callerIsOwner && lastRegister)) {
            o.bootstrap = false;
        }
    }

    function setAutoUpgrade(bytes32 orgId, bytes32 typeId, bool enabled) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        address proxy = l.proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));
        l.contractOf[contractId].autoUpgrade = enabled;

        emit AutoUpgradeSet(contractId, enabled);
    }

    /* ═════════════════  VIEW HELPERS  ═════════════════ */
    function getOrgContract(bytes32 orgId, bytes32 typeId) external view returns (address proxy) {
        Layout storage l = _layout();
        if (!l.orgOf[orgId].exists) revert OrgUnknown();
        proxy = l.proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();
    }

    function getContractBeacon(bytes32 contractId) external view returns (address beacon) {
        Layout storage l = _layout();
        beacon = l.contractOf[contractId].beacon;
        if (beacon == address(0)) revert ContractUnknown();
    }

    function isAutoUpgrade(bytes32 contractId) external view returns (bool) {
        Layout storage l = _layout();
        ContractInfo storage c = l.contractOf[contractId];
        if (c.proxy == address(0)) revert ContractUnknown();
        return c.autoUpgrade;
    }

    /* enumeration helpers */
    function orgCount() external view returns (uint256) {
        return _layout().orgIds.length;
    }

    function getOrgIds() external view returns (bytes32[] memory) {
        return _layout().orgIds;
    }

    /* Public getters for storage variables */
    function orgOf(bytes32 orgId)
        external
        view
        returns (address executor, uint32 contractCount, bool bootstrap, bool exists)
    {
        OrgInfo storage o = _layout().orgOf[orgId];
        return (o.executor, o.contractCount, o.bootstrap, o.exists);
    }

    function contractOf(bytes32 contractId)
        external
        view
        returns (address proxy, address beacon, bool autoUpgrade, address owner)
    {
        ContractInfo storage c = _layout().contractOf[contractId];
        return (c.proxy, c.beacon, c.autoUpgrade, c.owner);
    }

    function proxyOf(bytes32 orgId, bytes32 typeId) external view returns (address) {
        return _layout().proxyOf[orgId][typeId];
    }

    function totalContracts() external view returns (uint256) {
        return _layout().totalContracts;
    }

    function orgIds(uint256 index) external view returns (bytes32) {
        return _layout().orgIds[index];
    }

    /* ══════════ HATS TREE REGISTRATION ══════════ */
    function registerHatsTree(bytes32 orgId, uint256 topHatId, uint256[] calldata roleHatIds) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();

        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        l.topHatOf[orgId] = topHatId;
        for (uint256 i = 0; i < roleHatIds.length; i++) {
            l.roleHatOf[orgId][i] = roleHatIds[i];
        }

        emit HatsTreeRegistered(orgId, topHatId, roleHatIds);
    }

    function getTopHat(bytes32 orgId) external view returns (uint256) {
        return _layout().topHatOf[orgId];
    }

    function getRoleHat(bytes32 orgId, uint256 roleIndex) external view returns (uint256) {
        return _layout().roleHatOf[orgId][roleIndex];
    }
}

// src/HatsTreeSetup.sol

/**
 * @title HatsTreeSetup
 * @notice Temporary contract for setting up Hats Protocol trees
 * @dev This contract is deployed temporarily to handle all Hats operations and reduce Deployer size
 */
contract HatsTreeSetup {
    /*════════════════  CONSTANTS  ════════════════*/

    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

    /*════════════════  SETUP STRUCTS  ════════════════*/

    struct SetupResult {
        uint256 topHatId;
        uint256[] roleHatIds;
        address eligibilityModule;
        address toggleModule;
    }

    struct SetupParams {
        IHats hats;
        OrgRegistry orgRegistry;
        bytes32 orgId;
        address eligibilityModule;
        address toggleModule;
        address deployer;
        address deployerAddress; // Address to receive ADMIN hat
        address executor;
        address accountRegistry; // UniversalAccountRegistry for username registration
        string orgName;
        string deployerUsername; // Optional username for deployer (empty string = skip registration)
        RoleConfigStructs.RoleConfig[] roles; // Complete role configuration
    }

    /**
     * @notice Sets up a complete Hats tree for an organization with custom hierarchy
     * @dev This function handles arbitrary tree structures, not just linear hierarchies
     * @dev Deployer must transfer superAdmin rights to this contract before calling
     * @param params Complete setup parameters including role configurations
     * @return result Setup result containing topHat, roleHatIds, and module addresses
     */
    function setupHatsTree(SetupParams memory params) external returns (SetupResult memory result) {
        result.eligibilityModule = params.eligibilityModule;
        result.toggleModule = params.toggleModule;

        // Configure module relationships
        IEligibilityModule(params.eligibilityModule).setToggleModule(params.toggleModule);
        IToggleModule(params.toggleModule).setEligibilityModule(params.eligibilityModule);

        // Create top hat - mint to this contract so it can create child hats
        result.topHatId = params.hats.mintTopHat(address(this), string(abi.encodePacked("ipfs://", params.orgName)), "");
        IEligibilityModule(params.eligibilityModule).setWearerEligibility(address(this), result.topHatId, true, true);
        IToggleModule(params.toggleModule).setHatStatus(result.topHatId, true);

        // Create eligibility admin hat - this hat can mint any role
        uint256 eligibilityAdminHatId = params.hats
            .createHat(
                result.topHatId,
                "ELIGIBILITY_ADMIN",
                1,
                params.eligibilityModule,
                params.toggleModule,
                true,
                "ELIGIBILITY_ADMIN"
            );
        IEligibilityModule(params.eligibilityModule)
            .setWearerEligibility(params.eligibilityModule, eligibilityAdminHatId, true, true);
        IToggleModule(params.toggleModule).setHatStatus(eligibilityAdminHatId, true);
        params.hats.mintHat(eligibilityAdminHatId, params.eligibilityModule);
        IEligibilityModule(params.eligibilityModule).setEligibilityModuleAdminHat(eligibilityAdminHatId);
        // Register hat creation for subgraph indexing
        IEligibilityModule(params.eligibilityModule)
            .registerHatCreation(eligibilityAdminHatId, result.topHatId, true, true);

        // Create role hats sequentially to properly handle hierarchies
        uint256 len = params.roles.length;
        result.roleHatIds = new uint256[](len);

        // Arrays for batch registration (collected during hat creation)
        uint256[] memory regHatIds = new uint256[](len);
        uint256[] memory regParentHatIds = new uint256[](len);
        bool[] memory regDefaultEligibles = new bool[](len);
        bool[] memory regDefaultStandings = new bool[](len);
        string[] memory regNames = new string[](len);
        bytes32[] memory regMetadataCIDs = new bytes32[](len);

        // Multi-pass: resolve dependencies and create hats in correct order
        bool[] memory created = new bool[](len);
        uint256 createdCount = 0;

        while (createdCount < len) {
            uint256 passCreatedCount = 0;

            for (uint256 i = 0; i < len; i++) {
                if (created[i]) continue;

                RoleConfigStructs.RoleConfig memory role = params.roles[i];

                // Determine admin hat ID
                uint256 adminHatId;
                bool canCreate = false;

                if (role.hierarchy.adminRoleIndex == type(uint256).max) {
                    adminHatId = eligibilityAdminHatId;
                    canCreate = true;
                } else if (created[role.hierarchy.adminRoleIndex]) {
                    adminHatId = result.roleHatIds[role.hierarchy.adminRoleIndex];
                    canCreate = true;
                }

                if (canCreate) {
                    // Create hat with configuration
                    uint32 maxSupply = role.hatConfig.maxSupply == 0 ? type(uint32).max : role.hatConfig.maxSupply;
                    string memory details = _formatHatDetails(role.name, role.metadataCID);
                    uint256 newHatId = params.hats
                        .createHat(
                            adminHatId,
                            details,
                            maxSupply,
                            params.eligibilityModule,
                            params.toggleModule,
                            role.hatConfig.mutableHat,
                            role.image
                        );
                    result.roleHatIds[i] = newHatId;

                    // Collect registration data for batch call later
                    regHatIds[i] = newHatId;
                    regParentHatIds[i] = adminHatId;
                    regDefaultEligibles[i] = role.defaults.eligible;
                    regDefaultStandings[i] = role.defaults.standing;
                    regNames[i] = role.name;
                    regMetadataCIDs[i] = role.metadataCID;

                    created[i] = true;
                    createdCount++;
                    passCreatedCount++;
                }
            }

            // Circular dependency check
            if (passCreatedCount == 0 && createdCount < len) {
                revert("Circular dependency in role hierarchy");
            }
        }

        // Batch register all hat creations with metadata for subgraph indexing (replaces N individual calls)
        IEligibilityModule(params.eligibilityModule)
            .batchRegisterHatCreationWithMetadata(
                regHatIds, regParentHatIds, regDefaultEligibles, regDefaultStandings, regNames, regMetadataCIDs
            );

        // Step 5: Collect all eligibility and toggle operations for batch execution
        // Count total eligibility entries needed: 2 per role (executor + deployer) + additional wearers
        uint256 eligibilityCount = 0;
        for (uint256 i = 0; i < len; i++) {
            eligibilityCount += 2; // executor + deployer
            eligibilityCount += params.roles[i].distribution.additionalWearers.length;
        }

        // Build arrays for batch eligibility call
        address[] memory eligWearers = new address[](eligibilityCount);
        uint256[] memory eligHatIds = new uint256[](eligibilityCount);
        uint256 eligIndex = 0;

        // Build arrays for batch toggle call
        uint256[] memory toggleHatIds = new uint256[](len);
        bool[] memory toggleActives = new bool[](len);

        // Build arrays for batch default eligibility call
        uint256[] memory defaultHatIds = new uint256[](len);
        bool[] memory defaultEligibles = new bool[](len);
        bool[] memory defaultStandings = new bool[](len);

        for (uint256 i = 0; i < len; i++) {
            uint256 hatId = result.roleHatIds[i];
            RoleConfigStructs.RoleConfig memory role = params.roles[i];

            // Collect eligibility entries
            eligWearers[eligIndex] = params.executor;
            eligHatIds[eligIndex] = hatId;
            eligIndex++;

            eligWearers[eligIndex] = params.deployerAddress;
            eligHatIds[eligIndex] = hatId;
            eligIndex++;

            // Collect additional wearers
            for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {
                eligWearers[eligIndex] = role.distribution.additionalWearers[j];
                eligHatIds[eligIndex] = hatId;
                eligIndex++;
            }

            // Collect toggle status
            toggleHatIds[i] = hatId;
            toggleActives[i] = true;

            // Collect default eligibility
            defaultHatIds[i] = hatId;
            defaultEligibles[i] = role.defaults.eligible;
            defaultStandings[i] = role.defaults.standing;
        }

        // Execute batch operations (replaces N individual calls with 3 batch calls)
        IEligibilityModule(params.eligibilityModule)
            .batchSetWearerEligibilityMultiHat(eligWearers, eligHatIds, true, true);
        IToggleModule(params.toggleModule).batchSetHatStatus(toggleHatIds, toggleActives);
        IEligibilityModule(params.eligibilityModule)
            .batchSetDefaultEligibility(defaultHatIds, defaultEligibles, defaultStandings);

        // Step 6: Collect all minting operations for batch execution
        uint256 mintCount = 0;
        for (uint256 i = 0; i < len; i++) {
            RoleConfigStructs.RoleConfig memory role = params.roles[i];
            if (!role.canVote) continue;

            if (role.distribution.mintToDeployer) mintCount++;
            if (role.distribution.mintToExecutor) mintCount++;
            mintCount += role.distribution.additionalWearers.length;
        }

        if (mintCount > 0) {
            uint256[] memory hatIdsToMint = new uint256[](mintCount);
            address[] memory wearersToMint = new address[](mintCount);
            uint256 mintIndex = 0;

            // Register deployer username once if needed
            if (params.accountRegistry != address(0) && bytes(params.deployerUsername).length > 0) {
                UniversalAccountRegistry registry = UniversalAccountRegistry(params.accountRegistry);
                if (bytes(registry.getUsername(params.deployerAddress)).length == 0) {
                    registry.registerAccountQuickJoin(params.deployerUsername, params.deployerAddress);
                }
            }

            for (uint256 i = 0; i < len; i++) {
                RoleConfigStructs.RoleConfig memory role = params.roles[i];
                if (!role.canVote) continue;

                uint256 hatId = result.roleHatIds[i];

                if (role.distribution.mintToDeployer) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = params.deployerAddress;
                    mintIndex++;
                }

                if (role.distribution.mintToExecutor) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = params.executor;
                    mintIndex++;
                }

                for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {
                    hatIdsToMint[mintIndex] = hatId;
                    wearersToMint[mintIndex] = role.distribution.additionalWearers[j];
                    mintIndex++;
                }
            }

            // Step 7: Batch mint all hats via single call (replaces N mintHatToAddress calls)
            IEligibilityModule(params.eligibilityModule).batchMintHats(hatIdsToMint, wearersToMint);
        }

        // Transfer top hat to executor
        params.hats.transferHat(result.topHatId, address(this), params.executor);

        // Set default eligibility for top hat
        IEligibilityModule(params.eligibilityModule).setDefaultEligibility(result.topHatId, true, true);

        // Transfer module admin rights to executor
        IEligibilityModule(params.eligibilityModule).transferSuperAdmin(params.executor);
        IToggleModule(params.toggleModule).transferAdmin(params.executor);

        return result;
    }

    /*════════════════  INTERNAL HELPERS  ════════════════*/

    /**
     * @notice Format hat details string - uses CID if provided, otherwise name
     * @param name The role name (fallback if no CID)
     * @param metadataCID The IPFS CID for extended metadata (bytes32(0) if none)
     * @return The formatted details string
     */
    function _formatHatDetails(string memory name, bytes32 metadataCID) internal pure returns (string memory) {
        if (metadataCID == bytes32(0)) {
            return name;
        }
        return _bytes32ToHexString(metadataCID);
    }

    /**
     * @notice Convert bytes32 to hex string with 0x prefix
     * @param value The bytes32 value to convert
     * @return The hex string representation
     */
    function _bytes32ToHexString(bytes32 value) internal pure returns (string memory) {
        bytes memory buffer = new bytes(66); // 2 for "0x" + 64 for hex chars
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            buffer[2 + i * 2] = HEX_DIGITS[uint8(value[i] >> 4)];
            buffer[3 + i * 2] = HEX_DIGITS[uint8(value[i] & 0x0f)];
        }
        return string(buffer);
    }
}

