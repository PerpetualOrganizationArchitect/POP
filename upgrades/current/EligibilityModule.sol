// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.13 ^0.8.19 ^0.8.20;

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

// lib/hats-protocol/src/Interfaces/IHatsEligibility.sol

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

interface IHatsEligibility {
    /// @notice Returns the status of a wearer for a given hat
    /// @dev If standing is false, eligibility MUST also be false
    /// @param _wearer The address of the current or prospective Hat wearer
    /// @param _hatId The id of the hat in question
    /// @return eligible Whether the _wearer is eligible to wear the hat
    /// @return standing Whether the _wearer is in goog standing
    function getWearerStatus(address _wearer, uint256 _hatId) external view returns (bool eligible, bool standing);
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

// src/EligibilityModule.sol

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

    /*═══════════════════════════════════ METADATA CONSTANTS ═══════════════════════════════════════*/

    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

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
    event HatClaimed(address indexed wearer, uint256 indexed hatId);
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
    event HatMetadataUpdated(uint256 indexed hatId, string name, bytes32 metadataCID);

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

    /**
     * @notice Batch set wearer eligibility across multiple hats - optimized for HatsTreeSetup
     * @dev Sets eligibility for multiple (wearer, hatId) pairs in a single call
     * @param wearers Array of wearer addresses
     * @param hatIds Array of hat IDs (must match wearers length)
     * @param eligible Eligibility status to set for all pairs
     * @param standing Standing status to set for all pairs
     */
    function batchSetWearerEligibilityMultiHat(
        address[] calldata wearers,
        uint256[] calldata hatIds,
        bool eligible,
        bool standing
    ) external onlySuperAdmin whenNotPaused {
        uint256 length = wearers.length;
        if (length != hatIds.length) revert ArrayLengthMismatch();

        Layout storage l = _layout();
        uint8 packedFlags = _packWearerFlags(eligible, standing);

        unchecked {
            for (uint256 i; i < length; ++i) {
                address wearer = wearers[i];
                uint256 hatId = hatIds[i];
                l.wearerRules[wearer][hatId] = WearerRules(packedFlags);
                l.hasSpecificWearerRules[wearer][hatId] = true;
                emit WearerEligibilityUpdated(wearer, hatId, eligible, standing, msg.sender);
            }
        }
    }

    /**
     * @notice Batch set default eligibility for multiple hats
     * @dev Sets default eligibility rules for multiple hats in a single call
     * @param hatIds Array of hat IDs
     * @param eligibles Array of eligibility flags
     * @param standings Array of standing flags
     */
    function batchSetDefaultEligibility(uint256[] calldata hatIds, bool[] calldata eligibles, bool[] calldata standings)
        external
        onlySuperAdmin
        whenNotPaused
    {
        uint256 length = hatIds.length;
        if (length != eligibles.length || length != standings.length) {
            revert ArrayLengthMismatch();
        }

        Layout storage l = _layout();

        unchecked {
            for (uint256 i; i < length; ++i) {
                uint256 hatId = hatIds[i];
                l.defaultRules[hatId] = WearerRules(_packWearerFlags(eligibles[i], standings[i]));
                emit DefaultEligibilityUpdated(hatId, eligibles[i], standings[i], msg.sender);
            }
        }
    }

    /**
     * @notice Batch mint hats to multiple wearers
     * @dev Mints multiple hats in a single call - optimized for HatsTreeSetup
     * @param hatIds Array of hat IDs to mint
     * @param wearers Array of addresses to receive hats
     */
    function batchMintHats(uint256[] calldata hatIds, address[] calldata wearers) external onlySuperAdmin {
        uint256 length = hatIds.length;
        if (length != wearers.length) revert ArrayLengthMismatch();

        Layout storage l = _layout();

        unchecked {
            for (uint256 i; i < length; ++i) {
                bool success = l.hats.mintHat(hatIds[i], wearers[i]);
                require(success, "Hat minting failed");
            }
        }
    }

    /**
     * @notice Batch register hat creations for subgraph indexing
     * @dev Registers multiple hats in a single call - optimized for HatsTreeSetup
     * @param hatIds Array of hat IDs that were created
     * @param parentHatIds Array of parent hat IDs
     * @param defaultEligibles Array of default eligibility flags
     * @param defaultStandings Array of default standing flags
     */
    function batchRegisterHatCreation(
        uint256[] calldata hatIds,
        uint256[] calldata parentHatIds,
        bool[] calldata defaultEligibles,
        bool[] calldata defaultStandings
    ) external onlySuperAdmin {
        uint256 length = hatIds.length;
        if (length != parentHatIds.length || length != defaultEligibles.length || length != defaultStandings.length) {
            revert ArrayLengthMismatch();
        }

        Layout storage l = _layout();

        unchecked {
            for (uint256 i; i < length; ++i) {
                uint256 hatId = hatIds[i];
                l.defaultRules[hatId] = WearerRules(_packWearerFlags(defaultEligibles[i], defaultStandings[i]));
                emit DefaultEligibilityUpdated(hatId, defaultEligibles[i], defaultStandings[i], msg.sender);
                emit HatCreatedWithEligibility(
                    msg.sender, parentHatIds[i], hatId, defaultEligibles[i], defaultStandings[i], 0
                );
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

    /*═══════════════════════════════════ METADATA MANAGEMENT ═══════════════════════════════════════*/

    /**
     * @notice Update hat metadata CID (uses native Hats Protocol changeHatDetails)
     * @dev Emits HatDetailsChanged event from Hats Protocol (subgraph indexable)
     * @param hatId The ID of the hat to update
     * @param name The role name
     * @param metadataCID The IPFS CID for extended metadata (bytes32(0) to clear)
     */
    function updateHatMetadata(uint256 hatId, string memory name, bytes32 metadataCID)
        external
        onlyHatAdmin(hatId)
        whenNotPaused
    {
        string memory details = _formatHatDetails(name, metadataCID);
        _layout().hats.changeHatDetails(hatId, details);
        // Native HatDetailsChanged event is emitted by Hats Protocol
        emit HatMetadataUpdated(hatId, name, metadataCID);
    }

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

    /**
     * @notice Batch configure vouching for multiple hats
     * @dev Sets vouching configuration for multiple hats in a single call - gas optimized for org deployment
     * @param hatIds Array of hat IDs to configure
     * @param quorums Array of quorum values (number of vouches required)
     * @param membershipHatIds Array of hat IDs whose wearers can vouch
     * @param combineWithHierarchyFlags Array of flags for combining with hierarchy eligibility
     */
    function batchConfigureVouching(
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external onlySuperAdmin {
        uint256 length = hatIds.length;
        if (length != quorums.length || length != membershipHatIds.length || length != combineWithHierarchyFlags.length)
        {
            revert ArrayLengthMismatch();
        }

        Layout storage l = _layout();

        unchecked {
            for (uint256 i; i < length; ++i) {
                uint256 hatId = hatIds[i];
                bool enabled = quorums[i] > 0;
                l.vouchConfigs[hatId] = VouchConfig({
                    quorum: quorums[i],
                    membershipHatId: membershipHatIds[i],
                    flags: _packVouchFlags(enabled, combineWithHierarchyFlags[i])
                });

                emit VouchConfigSet(hatId, quorums[i], membershipHatIds[i], enabled, combineWithHierarchyFlags[i]);
            }
        }
    }

    function vouchFor(address wearer, uint256 hatId) external whenNotPaused {
        if (wearer == address(0)) revert ZeroAddress();
        if (wearer == msg.sender) revert CannotVouchForSelf();

        Layout storage l = _layout();
        VouchConfig memory config = l.vouchConfigs[hatId];
        if (!_isVouchingEnabled(config.flags)) revert VouchingNotEnabled();

        // Check vouching authorization
        bool isAuthorized = l.hats.isWearerOfHat(msg.sender, config.membershipHatId);

        // If combineWithHierarchy is enabled, also check if voucher has admin privileges for this hat
        if (!isAuthorized && _shouldCombineWithHierarchy(config.flags)) {
            isAuthorized = l.hats.isAdminOfHat(msg.sender, hatId);
        }

        if (!isAuthorized) revert NotAuthorizedToVouch();
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

    /**
     * @notice Allows a user to claim a hat they are eligible for after being vouched
     * @dev User must have sufficient vouches to be eligible. This is the claim-based pattern
     *      where users explicitly accept their role rather than having it auto-minted.
     *      The EligibilityModule contract mints the hat using its ELIGIBILITY_ADMIN permissions.
     * @param hatId The ID of the hat to claim
     */
    function claimVouchedHat(uint256 hatId) external whenNotPaused {
        Layout storage l = _layout();

        // Check if caller is eligible to claim this hat
        (bool eligible, bool standing) = this.getWearerStatus(msg.sender, hatId);
        require(eligible && standing, "Not eligible to claim hat");

        // Check if already wearing the hat
        require(!l.hats.isWearerOfHat(msg.sender, hatId), "Already wearing hat");

        // Mint the hat to the caller using EligibilityModule's admin powers
        bool success = l.hats.mintHat(hatId, msg.sender);
        require(success, "Hat minting failed");

        emit HatClaimed(msg.sender, hatId);
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

