// SPDX-License-Identifier: MIT
pragma solidity >=0.4.11 >=0.4.16 >=0.8.13 ^0.8.20 ^0.8.21 ^0.8.22 ^0.8.30;

// lib/openzeppelin-contracts/contracts/utils/Errors.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/Errors.sol)

/**
 * @dev Collection of common custom errors used in multiple contracts
 *
 * IMPORTANT: Backwards compatibility is not guaranteed in future versions of the library.
 * It is recommended to avoid relying on the error API for critical functionality.
 *
 * _Available since v5.1._
 */
library Errors {
    /**
     * @dev The ETH balance of the account is not enough to perform the operation.
     */
    error InsufficientBalance(uint256 balance, uint256 needed);

    /**
     * @dev A call to an address target failed. The target may have reverted.
     */
    error FailedCall();

    /**
     * @dev The deployment failed.
     */
    error FailedDeployment();

    /**
     * @dev A necessary precompile is missing.
     */
    error MissingPrecompile(address);
}

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

// lib/openzeppelin-contracts/contracts/proxy/beacon/IBeacon.sol

// OpenZeppelin Contracts (last updated v5.4.0) (proxy/beacon/IBeacon.sol)

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeacon_0 {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {UpgradeableBeacon} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}

// lib/openzeppelin-contracts/contracts/interfaces/IERC1967.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1967.sol)

/**
 * @dev ERC-1967: Proxy Storage Slots. This interface contains the events defined in the ERC.
 */
interface IERC1967 {
    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Emitted when the beacon is changed.
     */
    event BeaconUpgraded(address indexed beacon);
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

// src/libs/ModuleTypes.sol

/**
 * @title ModuleTypes
 * @author POA Team
 * @notice Central registry of module type identifiers (pre-computed keccak256 hashes)
 * @dev These constants represent keccak256(moduleName) pre-computed at compile time
 *      to eliminate runtime hashing and minimize bytecode size.
 *
 *      Design rationale:
 *      - PoaManager internally uses bytes32 typeIds (keccak256 of module names)
 *      - OrgRegistry requires bytes32 typeIds for contract registration
 *      - Pre-computing these hashes eliminates redundant runtime computation
 *      - Using constants instead of functions reduces deployment gas
 *
 *      Migration notes:
 *      - Legacy code using string-based lookups remains compatible via PoaManager.getBeacon(string)
 *      - New code should use typeId-based lookups via PoaManager.getBeaconById(bytes32)
 */
library ModuleTypes {
    // Pre-computed keccak256 hashes of module names
    // These values MUST match exactly with the type names registered in PoaManager

    /// @dev keccak256("Executor")
    bytes32 constant EXECUTOR_ID = 0xeb35d5f9843d4076628c4747d195abdd0312e0b8b8f5812a706f3d25ea0b1074;

    /// @dev keccak256("QuickJoin")
    bytes32 constant QUICK_JOIN_ID = 0x4784d0eb49be96744b28df0ac228d16d518300f3918df72816b3b561765905e2;

    /// @dev keccak256("ParticipationToken")
    bytes32 constant PARTICIPATION_TOKEN_ID = 0x61653188976d6d9ecf5e33b147788ec0830eac3e633a227b8852151b9bc260ff;

    /// @dev keccak256("TaskManager")
    bytes32 constant TASK_MANAGER_ID = 0x32f7a2c64ebedb84c7786a459012ac8953c5a63d5dcc8715f2fa3e32bdb3b434;

    /// @dev keccak256("EducationHub")
    bytes32 constant EDUCATION_HUB_ID = 0xa871f070b566fe185ede7c7d071cb2f92e7c75c6a2912b6f37c86a50cdc6bad3;

    /// @dev keccak256("HybridVoting")
    bytes32 constant HYBRID_VOTING_ID = 0xb8dd67d452899bbfb87b5b09ad416a7e087658a191da37d41f9ea7dee2fa659a;

    /// @dev keccak256("EligibilityModule")
    bytes32 constant ELIGIBILITY_MODULE_ID = 0x4227a68d7c497034bee963ad52ac7718fa79a916edc119c0f7e6589c8b2d4ea7;

    /// @dev keccak256("ToggleModule")
    bytes32 constant TOGGLE_MODULE_ID = 0x75dfb681d193a73a66b628a5adc66bb1ca7bb3feb9a5692cd0a1560ccd9b851a;

    /// @dev keccak256("PaymentManager")
    bytes32 constant PAYMENT_MANAGER_ID = 0x27c0a50afefb382eb18d87e6a049659a778b9a2f11c89b8723c63e6fab6fa323;

    /// @dev keccak256("PaymasterHub")
    bytes32 constant PAYMASTER_HUB_ID = 0x846374a1b9aebfa243bcd01b2b2c7d94ce66a1b22f9ed17ed1d6fd61a8c93891;

    /// @dev keccak256("DirectDemocracyVoting")
    bytes32 constant DIRECT_DEMOCRACY_VOTING_ID = 0xf7339bb8aed66291ac713d0a14749e830b09b2288976ec5d45de7e64df0f2aeb;

    /// @dev keccak256("PasskeyAccount")
    bytes32 constant PASSKEY_ACCOUNT_ID = 0xda41a9794e00ddb18f1b3c615f12a80255bfb0a79706263eee63314d8f817c10;

    /// @dev keccak256("PasskeyAccountFactory")
    bytes32 constant PASSKEY_ACCOUNT_FACTORY_ID = 0x82da23c7ff6e2ce257dee836273bf72af382187589631ce71ae1388c80777930;
}

// lib/openzeppelin-contracts/contracts/proxy/Proxy.sol

// OpenZeppelin Contracts (last updated v5.0.0) (proxy/Proxy.sol)

/**
 * @dev This abstract contract provides a fallback function that delegates all calls to another contract using the EVM
 * instruction `delegatecall`. We refer to the second contract as the _implementation_ behind the proxy, and it has to
 * be specified by overriding the virtual {_implementation} function.
 *
 * Additionally, delegation to the implementation can be triggered manually through the {_fallback} function, or to a
 * different contract through the {_delegate} function.
 *
 * The success and return data of the delegated call will be returned back to the caller of the proxy.
 */
abstract contract Proxy {
    /**
     * @dev Delegates the current call to `implementation`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev This is a virtual function that should be overridden so it returns the address to which the fallback
     * function and {_fallback} should delegate.
     */
    function _implementation() internal view virtual returns (address);

    /**
     * @dev Delegates the current call to the address returned by `_implementation()`.
     *
     * This function does not return to its internal call site, it will return directly to the external caller.
     */
    function _fallback() internal virtual {
        _delegate(_implementation());
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by `_implementation()`. Will run if no other
     * function in the contract matches the call data.
     */
    fallback() external payable virtual {
        _fallback();
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

// lib/openzeppelin-contracts/contracts/utils/StorageSlot.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/StorageSlot.sol)
// This file was procedurally generated from scripts/generate/templates/StorageSlot.js.

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC-1967 implementation slot:
 * ```solidity
 * contract ERC1967 {
 *     // Define the slot. Alternatively, use the SlotDerivation library to derive the slot.
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(newImplementation.code.length > 0);
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * TIP: Consider using this library along with {SlotDerivation}.
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    struct Int256Slot {
        int256 value;
    }

    struct StringSlot {
        string value;
    }

    struct BytesSlot {
        bytes value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `Int256Slot` with member `value` located at `slot`.
     */
    function getInt256Slot(bytes32 slot) internal pure returns (Int256Slot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns a `StringSlot` with member `value` located at `slot`.
     */
    function getStringSlot(bytes32 slot) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `StringSlot` representation of the string storage pointer `store`.
     */
    function getStringSlot(string storage store) internal pure returns (StringSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }

    /**
     * @dev Returns a `BytesSlot` with member `value` located at `slot`.
     */
    function getBytesSlot(bytes32 slot) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BytesSlot` representation of the bytes storage pointer `store`.
     */
    function getBytesSlot(bytes storage store) internal pure returns (BytesSlot storage r) {
        assembly ("memory-safe") {
            r.slot := store.slot
        }
    }
}

// src/SwitchableBeacon.sol

interface IBeacon_1 {
    function implementation() external view returns (address);
}

/**
 * @title SwitchableBeacon
 * @notice A beacon implementation that can switch between mirroring a global beacon and using a static implementation
 * @dev This contract enables organizations to toggle between auto-upgrading (following POA global beacons)
 *      and pinned mode (using a fixed implementation) without redeploying proxies
 * @custom:security-contact security@poa.org
 */
contract SwitchableBeacon is IBeacon_1 {
    enum Mode {
        Mirror, // Follow the global beacon's implementation
        Static // Use a pinned implementation
    }

    /// @notice Current owner of this beacon (typically the Executor or UpgradeAdmin)
    address public owner;

    /// @notice The global POA beacon to mirror when in Mirror mode
    address public mirrorBeacon;

    /// @notice The pinned implementation address when in Static mode
    address public staticImplementation;

    /// @notice Current operational mode of the beacon
    Mode public mode;

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when the beacon mode changes
    /// @param mode The new mode (Mirror or Static)
    event ModeChanged(Mode mode);

    /// @notice Emitted when a new mirror beacon is set
    /// @param mirrorBeacon The address of the new mirror beacon
    event MirrorSet(address indexed mirrorBeacon);

    /// @notice Emitted when an implementation is pinned
    /// @param implementation The address of the pinned implementation
    event Pinned(address indexed implementation);

    /// @notice Thrown when a non-owner attempts a restricted operation
    error NotOwner();

    /// @notice Thrown when a zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when the implementation address cannot be determined
    error ImplNotSet();

    /// @notice Thrown when attempting to set invalid mode transition
    error InvalidModeTransition();

    /// @notice Thrown when an address is not a contract when it should be
    error NotContract();

    /// @notice Restricts function access to the owner only
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /**
     * @notice Constructs a new SwitchableBeacon
     * @param _owner The initial owner of the beacon
     * @param _mirrorBeacon The POA global beacon to mirror when in Mirror mode
     * @param _staticImpl The static implementation to use when in Static mode (can be address(0) if starting in Mirror mode)
     * @param _mode The initial mode of operation
     */
    constructor(address _owner, address _mirrorBeacon, address _staticImpl, Mode _mode) {
        if (_owner == address(0)) revert ZeroAddress();
        if (_mirrorBeacon == address(0)) revert ZeroAddress();

        // Verify mirrorBeacon is a contract
        if (_mirrorBeacon.code.length == 0) revert NotContract();

        // Static implementation can be zero if starting in Mirror mode
        if (_mode == Mode.Static) {
            if (_staticImpl == address(0)) revert ImplNotSet();
            // Verify static implementation is a contract
            if (_staticImpl.code.length == 0) revert NotContract();
        }

        owner = _owner;
        mirrorBeacon = _mirrorBeacon;
        staticImplementation = _staticImpl;
        mode = _mode;

        emit OwnerTransferred(address(0), _owner);
        emit ModeChanged(_mode);
    }

    /**
     * @notice Transfers ownership of the beacon to a new address
     * @param newOwner The address of the new owner
     * @dev Only callable by the current owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = owner;
        owner = newOwner;

        emit OwnerTransferred(previousOwner, newOwner);
    }

    /**
     * @notice Returns the current implementation address based on the beacon's mode
     * @return The address of the implementation contract
     * @dev In Mirror mode, queries the mirror beacon. In Static mode, returns the stored implementation.
     */
    function implementation() external view override returns (address) {
        if (mode == Mode.Mirror) {
            address impl = IBeacon_1(mirrorBeacon).implementation();
            if (impl == address(0)) revert ImplNotSet();
            return impl;
        } else {
            if (staticImplementation == address(0)) revert ImplNotSet();
            return staticImplementation;
        }
    }

    /**
     * @notice Switches to Mirror mode and sets a new mirror beacon
     * @param _mirrorBeacon The address of the POA global beacon to mirror
     * @dev Only callable by the owner. Enables auto-upgrading by following the global beacon.
     */
    function setMirror(address _mirrorBeacon) external onlyOwner {
        if (_mirrorBeacon == address(0)) revert ZeroAddress();

        // Verify the beacon is a contract
        if (_mirrorBeacon.code.length == 0) revert NotContract();

        // Validate that the mirror beacon has a valid implementation
        address impl = IBeacon_1(_mirrorBeacon).implementation();
        if (impl == address(0)) revert ImplNotSet();

        // Verify the implementation is a contract
        if (impl.code.length == 0) revert NotContract();

        mirrorBeacon = _mirrorBeacon;
        mode = Mode.Mirror;

        emit MirrorSet(_mirrorBeacon);
        emit ModeChanged(Mode.Mirror);
    }

    /**
     * @notice Pins the beacon to a specific implementation address
     * @param impl The implementation address to pin
     * @dev Only callable by the owner. Switches to Static mode with the specified implementation.
     */
    function pin(address impl) public onlyOwner {
        if (impl == address(0)) revert ZeroAddress();

        // Verify the implementation is a contract
        if (impl.code.length == 0) revert NotContract();

        staticImplementation = impl;
        mode = Mode.Static;

        emit Pinned(impl);
        emit ModeChanged(Mode.Static);
    }

    /**
     * @notice Pins the beacon to the current implementation of the mirror beacon
     * @dev Only callable by the owner. Convenient way to freeze at the current global version.
     */
    function pinToCurrent() external onlyOwner {
        address impl = IBeacon_1(mirrorBeacon).implementation();
        if (impl == address(0)) revert ImplNotSet();

        // The pin function will validate the implementation is a contract
        pin(impl);
    }

    /**
     * @notice Checks if the beacon is in Mirror mode
     * @return True if in Mirror mode, false otherwise
     */
    function isMirrorMode() external view returns (bool) {
        return mode == Mode.Mirror;
    }

    /**
     * @notice Gets the current implementation without reverting
     * @return success True if implementation could be determined
     * @return impl The implementation address (zero if not determinable)
     */
    function tryGetImplementation() external view returns (bool success, address impl) {
        if (mode == Mode.Mirror) {
            try IBeacon_1(mirrorBeacon).implementation() returns (address mirrorImpl) {
                if (mirrorImpl != address(0)) {
                    return (true, mirrorImpl);
                }
            } catch {
                return (false, address(0));
            }
        } else {
            if (staticImplementation != address(0)) {
                return (true, staticImplementation);
            }
        }
        return (false, address(0));
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

// lib/openzeppelin-contracts/contracts/utils/Address.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/Address.sol)

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev There's no code at `target` (it is not a contract).
     */
    error AddressEmptyCode(address target);

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.8.20/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert Errors.InsufficientBalance(address(this).balance, amount);
        }

        (bool success, bytes memory returndata) = recipient.call{value: amount}("");
        if (!success) {
            _revert(returndata);
        }
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason or custom error, it is bubbled
     * up by this function (like regular Solidity function calls). However, if
     * the call reverted with no returned reason, this function reverts with a
     * {Errors.FailedCall} error.
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert Errors.InsufficientBalance(address(this).balance, value);
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and reverts if the target
     * was not a contract or bubbling up the revert reason (falling back to {Errors.FailedCall}) in case
     * of an unsuccessful call.
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata
    ) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            // only check if target is a contract if the call was successful and the return data is empty
            // otherwise we already know that it was a contract
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and reverts if it wasn't, either by bubbling the
     * revert reason or with a default {Errors.FailedCall} error.
     */
    function verifyCallResult(bool success, bytes memory returndata) internal pure returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            return returndata;
        }
    }

    /**
     * @dev Reverts with returndata if present. Otherwise reverts with {Errors.FailedCall}.
     */
    function _revert(bytes memory returndata) private pure {
        // Look for revert reason and bubble it up if present
        if (returndata.length > 0) {
            // The easiest way to bubble the revert reason is using memory via assembly
            assembly ("memory-safe") {
                revert(add(returndata, 0x20), mload(returndata))
            }
        } else {
            revert Errors.FailedCall();
        }
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

// lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Utils.sol

// OpenZeppelin Contracts (last updated v5.4.0) (proxy/ERC1967/ERC1967Utils.sol)

/**
 * @dev This library provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] slots.
 */
library ERC1967Utils {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev The `implementation` of the proxy is invalid.
     */
    error ERC1967InvalidImplementation(address implementation);

    /**
     * @dev The `admin` of the proxy is invalid.
     */
    error ERC1967InvalidAdmin(address admin);

    /**
     * @dev The `beacon` of the proxy is invalid.
     */
    error ERC1967InvalidBeacon(address beacon);

    /**
     * @dev An upgrade function sees `msg.value > 0` that may be lost.
     */
    error ERC1967NonPayable();

    /**
     * @dev Returns the current implementation address.
     */
    function getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        if (newImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(newImplementation);
        }
        StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Performs implementation upgrade with additional setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) internal {
        _setImplementation(newImplementation);
        emit IERC1967.Upgraded(newImplementation);

        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     *
     * TIP: To get this value clients can read directly from the storage slot shown below (specified by ERC-1967) using
     * the https://eth.wiki/json-rpc/API#eth_getstorageat[`eth_getStorageAt`] RPC call.
     * `0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103`
     */
    function getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the ERC-1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        if (newAdmin == address(0)) {
            revert ERC1967InvalidAdmin(address(0));
        }
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {IERC1967-AdminChanged} event.
     */
    function changeAdmin(address newAdmin) internal {
        emit IERC1967.AdminChanged(getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is the keccak-256 hash of "eip1967.proxy.beacon" subtracted by 1.
     */
    // solhint-disable-next-line private-vars-leading-underscore
    bytes32 internal constant BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Returns the current beacon.
     */
    function getBeacon() internal view returns (address) {
        return StorageSlot.getAddressSlot(BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the ERC-1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        if (newBeacon.code.length == 0) {
            revert ERC1967InvalidBeacon(newBeacon);
        }

        StorageSlot.getAddressSlot(BEACON_SLOT).value = newBeacon;

        address beaconImplementation = IBeacon_0(newBeacon).implementation();
        if (beaconImplementation.code.length == 0) {
            revert ERC1967InvalidImplementation(beaconImplementation);
        }
    }

    /**
     * @dev Change the beacon and trigger a setup call if data is nonempty.
     * This function is payable only if the setup call is performed, otherwise `msg.value` is rejected
     * to avoid stuck value in the contract.
     *
     * Emits an {IERC1967-BeaconUpgraded} event.
     *
     * CAUTION: Invoking this function has no effect on an instance of {BeaconProxy} since v5, since
     * it uses an immutable beacon without looking at the value of the ERC-1967 beacon slot for
     * efficiency.
     */
    function upgradeBeaconToAndCall(address newBeacon, bytes memory data) internal {
        _setBeacon(newBeacon);
        emit IERC1967.BeaconUpgraded(newBeacon);

        if (data.length > 0) {
            Address.functionDelegateCall(IBeacon_0(newBeacon).implementation(), data);
        } else {
            _checkNonPayable();
        }
    }

    /**
     * @dev Reverts if `msg.value` is not zero. It can be used to avoid `msg.value` stuck in the contract
     * if an upgrade doesn't perform an initialization call.
     */
    function _checkNonPayable() private {
        if (msg.value > 0) {
            revert ERC1967NonPayable();
        }
    }
}

// src/libs/RoleResolver.sol

/**
 * @title RoleResolver
 * @notice Library to reduce code duplication in Deployer by centralizing role-to-hat resolution
 * @dev Saves approximately 3.5KB of bytecode by deduplicating 7 similar loop patterns
 */
library RoleResolver {
    /**
     * @notice Resolves an array of role indices to their corresponding Hat IDs
     * @param orgRegistry The OrgRegistry contract address
     * @param orgId The organization identifier
     * @param roleIndices Array of role indices (0, 1, 2, etc.)
     * @return hatIds Array of corresponding Hat IDs from the Hats Protocol
     */
    function resolveRoleHats(OrgRegistry orgRegistry, bytes32 orgId, uint256[] memory roleIndices)
        internal
        view
        returns (uint256[] memory hatIds)
    {
        uint256 length = roleIndices.length;
        hatIds = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            hatIds[i] = orgRegistry.getRoleHat(orgId, roleIndices[i]);
        }
    }

    /**
     * @notice Validates that all role indices are within bounds
     * @param roleIndices Array of role indices to validate
     * @param maxRoles Maximum number of roles in the organization
     * @return valid True if all indices are valid
     */
    function validateRoleIndices(uint256[] memory roleIndices, uint256 maxRoles) internal pure returns (bool valid) {
        uint256 length = roleIndices.length;
        for (uint256 i = 0; i < length; i++) {
            if (roleIndices[i] >= maxRoles) {
                return false;
            }
        }
        return true;
    }

    /**
     * @notice Ensures array is not empty (for critical roles that must be assigned)
     * @param roleIndices Array to check
     * @return True if array has at least one element
     */
    function requireNonEmpty(uint256[] memory roleIndices) internal pure returns (bool) {
        return roleIndices.length > 0;
    }

    /**
     * @notice Resolves a bitmap of role indices to their corresponding Hat IDs
     * @dev Uses bitmap where bit N represents role index N (supports up to 256 roles)
     * @param orgRegistry The OrgRegistry contract address
     * @param orgId The organization identifier
     * @param rolesBitmap Bitmap where bit N set means role N is assigned
     * @return hatIds Array of corresponding Hat IDs from the Hats Protocol
     */
    function resolveRoleBitmap(OrgRegistry orgRegistry, bytes32 orgId, uint256 rolesBitmap)
        internal
        view
        returns (uint256[] memory hatIds)
    {
        if (rolesBitmap == 0) {
            return new uint256[](0);
        }

        // Count number of set bits (number of roles)
        uint256 count = _countSetBits(rolesBitmap);
        hatIds = new uint256[](count);

        // Extract role indices and resolve to hat IDs
        uint256 index = 0;
        for (uint256 roleIdx = 0; roleIdx < 256; roleIdx++) {
            if ((rolesBitmap & (1 << roleIdx)) != 0) {
                hatIds[index] = orgRegistry.getRoleHat(orgId, roleIdx);
                index++;

                // Early exit when all roles found
                if (index == count) break;
            }
        }
    }

    /**
     * @notice Count number of set bits in bitmap (population count)
     * @dev Uses Brian Kernighan's algorithm for efficiency
     * @param bitmap The bitmap to count
     * @return count Number of set bits
     */
    function _countSetBits(uint256 bitmap) private pure returns (uint256 count) {
        while (bitmap != 0) {
            bitmap &= bitmap - 1; // Clear lowest set bit
            count++;
        }
    }
}

// lib/openzeppelin-contracts/contracts/proxy/beacon/BeaconProxy.sol

// OpenZeppelin Contracts (last updated v5.2.0) (proxy/beacon/BeaconProxy.sol)

/**
 * @dev This contract implements a proxy that gets the implementation address for each call from an {UpgradeableBeacon}.
 *
 * The beacon address can only be set once during construction, and cannot be changed afterwards. It is stored in an
 * immutable variable to avoid unnecessary storage reads, and also in the beacon storage slot specified by
 * https://eips.ethereum.org/EIPS/eip-1967[ERC-1967] so that it can be accessed externally.
 *
 * CAUTION: Since the beacon address can never be changed, you must ensure that you either control the beacon, or trust
 * the beacon to not upgrade the implementation maliciously.
 *
 * IMPORTANT: Do not use the implementation logic to modify the beacon storage slot. Doing so would leave the proxy in
 * an inconsistent state where the beacon storage slot does not match the beacon address.
 */
contract BeaconProxy is Proxy {
    // An immutable address for the beacon to avoid unnecessary SLOADs before each delegate call.
    address private immutable _beacon;

    /**
     * @dev Initializes the proxy with `beacon`.
     *
     * If `data` is nonempty, it's used as data in a delegate call to the implementation returned by the beacon. This
     * will typically be an encoded function call, and allows initializing the storage of the proxy like a Solidity
     * constructor.
     *
     * Requirements:
     *
     * - `beacon` must be a contract with the interface {IBeacon}.
     * - If `data` is empty, `msg.value` must be zero.
     */
    constructor(address beacon, bytes memory data) payable {
        ERC1967Utils.upgradeBeaconToAndCall(beacon, data);
        _beacon = beacon;
    }

    /**
     * @dev Returns the current implementation address of the associated beacon.
     */
    function _implementation() internal view virtual override returns (address) {
        return IBeacon_0(_getBeacon()).implementation();
    }

    /**
     * @dev Returns the beacon.
     */
    function _getBeacon() internal view virtual returns (address) {
        return _beacon;
    }
}

// src/libs/ModuleDeploymentLib.sol

// Moved interfaces here to break circular dependency
interface IPoaManager {
    function getBeaconById(bytes32 typeId) external view returns (address);
    function getCurrentImplementationById(bytes32 typeId) external view returns (address);
}

interface IHybridVotingInit {
    enum ClassStrategy {
        DIRECT,
        ERC20_BAL
    }

    struct ClassConfig {
        ClassStrategy strategy;
        uint8 slicePct;
        bool quadratic;
        uint256 minBalance;
        address asset;
        uint256[] hatIds;
    }

    function initialize(
        address hats_,
        address executor_,
        uint256[] calldata initialCreatorHats,
        address[] calldata targets,
        uint8 quorumPct,
        ClassConfig[] calldata initialClasses
    ) external;
}

interface IParticipationToken_0 {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

// Micro-interfaces for initializer functions (selector optimization)
interface IExecutorInit {
    function initialize(address owner, address hats) external;
}

interface IQuickJoinInit {
    function initialize(address executor, address hats, address registry, address master, uint256[] calldata memberHats)
        external;
}

interface IParticipationTokenInit {
    function initialize(
        address executor,
        string calldata name,
        string calldata symbol,
        address hats,
        uint256[] calldata memberHats,
        uint256[] calldata approverHats
    ) external;
}

interface ITaskManagerInit {
    function initialize(address token, address hats, uint256[] calldata creatorHats, address executor) external;
}

interface IEducationHubInit {
    function initialize(
        address token,
        address hats,
        address executor,
        uint256[] calldata creatorHats,
        uint256[] calldata memberHats
    ) external;
}

interface IEligibilityModuleInit {
    function initialize(address deployer, address hats, address toggleModule) external;
}

interface IToggleModuleInit {
    function initialize(address admin) external;
}

interface IPaymentManagerInit {
    function initialize(address _owner, address _revenueShareToken) external;
}

interface IPasskeyAccountFactoryInit {
    function initialize(address executor, address accountBeacon) external;
}

library ModuleDeploymentLib {
    error InvalidAddress();
    error EmptyInit();
    error UnsupportedType();
    error InitFailed();

    event ModuleDeployed(
        bytes32 indexed orgId, bytes32 indexed typeId, address proxy, address beacon, bool autoUpgrade, address owner
    );

    struct DeployConfig {
        IPoaManager poaManager;
        OrgRegistry orgRegistry;
        address hats;
        bytes32 orgId;
        address moduleOwner;
        bool autoUpgrade;
        address customImpl;
    }

    function deployCore(
        DeployConfig memory config,
        bytes32 typeId, // Pass pre-computed hash instead of string
        bytes memory initData,
        address beacon
    )
        internal
        returns (address proxy)
    {
        if (initData.length == 0) revert EmptyInit();

        // Create proxy using the provided beacon
        proxy = address(new BeaconProxy(beacon, ""));

        // Initialize the proxy (registration happens later via batch registration)
        (bool success, bytes memory returnData) = proxy.call(initData);
        if (!success) {
            // If initialization fails, bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert InitFailed();
            }
        }

        emit ModuleDeployed(config.orgId, typeId, proxy, beacon, config.autoUpgrade, config.moduleOwner);
        return proxy;
    }

    function deployExecutor(DeployConfig memory config, address deployer, address beacon)
        internal
        returns (address execProxy)
    {
        // Initialize with Deployer as owner so we can set up governance
        bytes memory init = abi.encodeWithSelector(IExecutorInit.initialize.selector, deployer, config.hats);

        // Deploy using provided beacon
        execProxy = deployCore(config, ModuleTypes.EXECUTOR_ID, init, beacon);
    }

    function deployQuickJoin(
        DeployConfig memory config,
        address executorAddr,
        address registry,
        address masterDeploy,
        uint256[] memory memberHats,
        address beacon
    ) internal returns (address qjProxy) {
        bytes memory init = abi.encodeWithSelector(
            IQuickJoinInit.initialize.selector, executorAddr, config.hats, registry, masterDeploy, memberHats
        );
        qjProxy = deployCore(config, ModuleTypes.QUICK_JOIN_ID, init, beacon);
    }

    function deployParticipationToken(
        DeployConfig memory config,
        address executorAddr,
        string memory name,
        string memory symbol,
        uint256[] memory memberHats,
        uint256[] memory approverHats,
        address beacon
    ) internal returns (address ptProxy) {
        bytes memory init = abi.encodeWithSelector(
            IParticipationTokenInit.initialize.selector,
            executorAddr,
            name,
            symbol,
            config.hats,
            memberHats,
            approverHats
        );
        ptProxy = deployCore(config, ModuleTypes.PARTICIPATION_TOKEN_ID, init, beacon);
    }

    function deployTaskManager(
        DeployConfig memory config,
        address executorAddr,
        address token,
        uint256[] memory creatorHats,
        address beacon
    ) internal returns (address tmProxy) {
        bytes memory init = abi.encodeWithSelector(
            ITaskManagerInit.initialize.selector, token, config.hats, creatorHats, executorAddr
        );
        tmProxy = deployCore(config, ModuleTypes.TASK_MANAGER_ID, init, beacon);
    }

    function deployEducationHub(
        DeployConfig memory config,
        address executorAddr,
        address token,
        uint256[] memory creatorHats,
        uint256[] memory memberHats,
        address beacon
    ) internal returns (address ehProxy) {
        bytes memory init = abi.encodeWithSelector(
            IEducationHubInit.initialize.selector, token, config.hats, executorAddr, creatorHats, memberHats
        );
        ehProxy = deployCore(config, ModuleTypes.EDUCATION_HUB_ID, init, beacon);
    }

    function deployEligibilityModule(DeployConfig memory config, address deployer, address toggleModule, address beacon)
        internal
        returns (address emProxy)
    {
        bytes memory init =
            abi.encodeWithSelector(IEligibilityModuleInit.initialize.selector, deployer, config.hats, toggleModule);

        emProxy = deployCore(config, ModuleTypes.ELIGIBILITY_MODULE_ID, init, beacon);
    }

    function deployToggleModule(DeployConfig memory config, address adminAddr, address beacon)
        internal
        returns (address tmProxy)
    {
        bytes memory init = abi.encodeWithSelector(IToggleModuleInit.initialize.selector, adminAddr);

        tmProxy = deployCore(config, ModuleTypes.TOGGLE_MODULE_ID, init, beacon);
    }

    function deployHybridVoting(
        DeployConfig memory config,
        address executorAddr,
        uint256[] memory creatorHats,
        uint8 quorumPct,
        IHybridVotingInit.ClassConfig[] memory classes,
        address beacon
    ) internal returns (address hvProxy) {
        address[] memory targets = new address[](1);
        targets[0] = executorAddr;

        bytes memory init = abi.encodeWithSelector(
            IHybridVotingInit.initialize.selector, config.hats, executorAddr, creatorHats, targets, quorumPct, classes
        );
        hvProxy = deployCore(config, ModuleTypes.HYBRID_VOTING_ID, init, beacon);
    }

    function deployPaymentManager(DeployConfig memory config, address owner, address revenueShareToken, address beacon)
        internal
        returns (address pmProxy)
    {
        bytes memory init = abi.encodeWithSelector(IPaymentManagerInit.initialize.selector, owner, revenueShareToken);
        pmProxy = deployCore(config, ModuleTypes.PAYMENT_MANAGER_ID, init, beacon);
    }

    function deployDirectDemocracyVoting(
        DeployConfig memory config,
        address executorAddr,
        uint256[] memory votingHats,
        uint256[] memory creatorHats,
        address[] memory initialTargets,
        uint8 quorumPct,
        address beacon
    ) internal returns (address ddProxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,uint256[],uint256[],address[],uint8)",
            config.hats,
            executorAddr,
            votingHats,
            creatorHats,
            initialTargets,
            quorumPct
        );
        ddProxy = deployCore(config, ModuleTypes.DIRECT_DEMOCRACY_VOTING_ID, init, beacon);
    }

    function deployPasskeyAccountFactory(
        DeployConfig memory config,
        address executorAddr,
        address accountBeacon,
        address factoryBeacon
    ) internal returns (address factoryProxy) {
        bytes memory init = abi.encodeWithSelector(
            IPasskeyAccountFactoryInit.initialize.selector, executorAddr, accountBeacon
        );
        factoryProxy = deployCore(config, ModuleTypes.PASSKEY_ACCOUNT_FACTORY_ID, init, factoryBeacon);
    }
}

// src/libs/BeaconDeploymentLib.sol

/*────────────────────────────  Errors  ───────────────────────────────*/
error UnsupportedType();

/**
 * @title BeaconDeploymentLib
 * @notice Library for creating SwitchableBeacon instances
 * @dev Extracts common beacon creation logic used across factories
 */
library BeaconDeploymentLib {
    /**
     * @notice Creates a SwitchableBeacon for a module type
     * @param typeId Module type identifier from ModuleTypes
     * @param poaManager Address of the PoaManager contract
     * @param moduleOwner Address that will own the beacon
     * @param autoUpgrade Whether the beacon should auto-upgrade with POA beacon
     * @param customImpl Optional custom implementation (address(0) for default)
     * @return beacon Address of the created SwitchableBeacon
     */
    function createBeacon(bytes32 typeId, address poaManager, address moduleOwner, bool autoUpgrade, address customImpl)
        internal
        returns (address beacon)
    {
        IPoaManager poa = IPoaManager(poaManager);

        address poaBeacon = poa.getBeaconById(typeId);
        if (poaBeacon == address(0)) revert UnsupportedType();

        address initImpl = address(0);
        SwitchableBeacon.Mode beaconMode = SwitchableBeacon.Mode.Mirror;

        if (!autoUpgrade) {
            // For static mode, get the current implementation
            initImpl = (customImpl == address(0)) ? poa.getCurrentImplementationById(typeId) : customImpl;
            if (initImpl == address(0)) revert UnsupportedType();
            beaconMode = SwitchableBeacon.Mode.Static;
        }

        // Create SwitchableBeacon with appropriate configuration
        beacon = address(new SwitchableBeacon(moduleOwner, poaBeacon, initImpl, beaconMode));
    }
}

// src/factories/AccessFactory.sol

/*──────────────────── OrgDeployer interface ────────────────────*/
interface IOrgDeployer_0 {
    function batchRegisterContracts(
        bytes32 orgId,
        OrgRegistry.ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external;
}

/*──────────────────── QuickJoin passkey configuration ────────────────────*/
interface IQuickJoinPasskeyConfig {
    function setPasskeyFactory(address factory) external;
    function setOrgId(bytes32 orgId) external;
}

/*──────────────────── PasskeyAccountFactory registration ────────────────────*/
interface IPasskeyAccountFactoryOrg {
    function registerOrg(bytes32 orgId, uint8 maxCredentials, address guardian, uint48 recoveryDelay) external;
}

/*────────────────────────────  Errors  ───────────────────────────────*/

error InvalidAddress();
error UnsupportedType();

/**
 * @title AccessFactory
 * @notice Factory contract for deploying access control and token infrastructure
 * @dev Deploys BeaconProxy instances for QuickJoin and ParticipationToken
 */
contract AccessFactory {
    /*──────────────────── Role Assignments ────────────────────*/
    struct RoleAssignments {
        uint256 quickJoinRolesBitmap; // Bit N set = Role N assigned on join
        uint256 tokenMemberRolesBitmap; // Bit N set = Role N can hold tokens
        uint256 tokenApproverRolesBitmap; // Bit N set = Role N can approve transfers
    }

    /*──────────────────── Passkey Configuration ────────────────────*/
    struct PasskeyConfig {
        bool enabled; // Whether to deploy passkey infrastructure
        uint8 maxCredentialsPerAccount; // Max passkeys per account (0 = default 5)
        address defaultGuardian; // Default recovery guardian
        uint48 recoveryDelay; // Recovery delay in seconds (0 = default 7 days)
    }

    /*──────────────────── Access Deployment Params ────────────────────*/
    struct AccessParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address executor;
        address deployer; // OrgDeployer address for registration callbacks
        address registryAddr; // Universal account registry
        uint256[] roleHatIds;
        bool autoUpgrade;
        RoleAssignments roleAssignments;
        PasskeyConfig passkeyConfig; // Passkey infrastructure configuration
    }

    /*──────────────────── Access Deployment Result ────────────────────*/
    struct AccessResult {
        address quickJoin;
        address participationToken;
        address passkeyAccountFactory; // Optional: only set if passkey enabled
    }

    /*══════════════  MAIN DEPLOYMENT FUNCTION  ═════════════=*/

    /**
     * @notice Deploys complete access control infrastructure for an organization
     * @param params Access deployment parameters
     * @return result Addresses of deployed access components
     */
    function deployAccess(AccessParams memory params) external returns (AccessResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.executor == address(0)
        ) {
            revert InvalidAddress();
        }

        address quickJoinBeacon;
        address participationTokenBeacon;

        /* 1. Deploy QuickJoin (without registration) */
        {
            // Get the role hat IDs for new members
            uint256[] memory memberHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.quickJoinRolesBitmap
            );

            quickJoinBeacon = _createBeacon(
                ModuleTypes.QUICK_JOIN_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.quickJoin = ModuleDeploymentLib.deployQuickJoin(
                config, params.executor, params.registryAddr, address(this), memberHats, quickJoinBeacon
            );
        }

        /* 2. Deploy Participation Token (without registration) */
        {
            string memory tName = string(abi.encodePacked(params.orgName, " Token"));
            string memory tSymbol = "PT";

            // Get the role hat IDs for member and approver permissions
            uint256[] memory memberHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.tokenMemberRolesBitmap
            );

            uint256[] memory approverHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.tokenApproverRolesBitmap
            );

            participationTokenBeacon = _createBeacon(
                ModuleTypes.PARTICIPATION_TOKEN_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.participationToken = ModuleDeploymentLib.deployParticipationToken(
                config, params.executor, tName, tSymbol, memberHats, approverHats, participationTokenBeacon
            );
        }

        address passkeyFactoryBeacon;

        /* 3. Deploy PasskeyAccountFactory if enabled */
        if (params.passkeyConfig.enabled) {
            // Create beacon for PasskeyAccount (the wallet implementation)
            address accountBeacon = _createBeacon(
                ModuleTypes.PASSKEY_ACCOUNT_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            // Create beacon for PasskeyAccountFactory
            passkeyFactoryBeacon = _createBeacon(
                ModuleTypes.PASSKEY_ACCOUNT_FACTORY_ID,
                params.poaManager,
                params.executor,
                params.autoUpgrade,
                address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.passkeyAccountFactory = ModuleDeploymentLib.deployPasskeyAccountFactory(
                config, params.executor, accountBeacon, passkeyFactoryBeacon
            );

            // Register org in the factory
            IPasskeyAccountFactoryOrg(result.passkeyAccountFactory)
                .registerOrg(
                    params.orgId,
                    params.passkeyConfig.maxCredentialsPerAccount,
                    params.passkeyConfig.defaultGuardian,
                    params.passkeyConfig.recoveryDelay
                );

            // Configure QuickJoin with the factory
            IQuickJoinPasskeyConfig(result.quickJoin).setPasskeyFactory(result.passkeyAccountFactory);
            IQuickJoinPasskeyConfig(result.quickJoin).setOrgId(params.orgId);
        }

        /* 4. Batch register all contracts */
        {
            uint256 registrationCount = params.passkeyConfig.enabled ? 3 : 2;
            OrgRegistry.ContractRegistration[] memory registrations =
                new OrgRegistry.ContractRegistration[](registrationCount);

            registrations[0] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.QUICK_JOIN_ID,
                proxy: result.quickJoin,
                beacon: quickJoinBeacon,
                owner: params.executor
            });

            registrations[1] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.PARTICIPATION_TOKEN_ID,
                proxy: result.participationToken,
                beacon: participationTokenBeacon,
                owner: params.executor
            });

            if (params.passkeyConfig.enabled) {
                registrations[2] = OrgRegistry.ContractRegistration({
                    typeId: ModuleTypes.PASSKEY_ACCOUNT_FACTORY_ID,
                    proxy: result.passkeyAccountFactory,
                    beacon: passkeyFactoryBeacon,
                    owner: params.executor
                });
            }

            // Call OrgDeployer to batch register (not the last batch)
            IOrgDeployer_0(params.deployer).batchRegisterContracts(params.orgId, registrations, params.autoUpgrade, false);
        }

        return result;
    }

    /*══════════════  INTERNAL HELPERS  ═════════════=*/

    /**
     * @notice Creates a SwitchableBeacon for a module type
     * @dev Returns a beacon address that points to the implementation
     */
    function _createBeacon(
        bytes32 typeId,
        address poaManager,
        address moduleOwner,
        bool autoUpgrade,
        address customImpl
    ) internal returns (address beacon) {
        IPoaManager poa = IPoaManager(poaManager);

        address poaBeacon = poa.getBeaconById(typeId);
        if (poaBeacon == address(0)) revert UnsupportedType();

        address initImpl = address(0);
        SwitchableBeacon.Mode beaconMode = SwitchableBeacon.Mode.Mirror;

        if (!autoUpgrade) {
            // For static mode, get the current implementation
            initImpl = (customImpl == address(0)) ? poa.getCurrentImplementationById(typeId) : customImpl;
            if (initImpl == address(0)) revert UnsupportedType();
            beaconMode = SwitchableBeacon.Mode.Static;
        }

        // Create SwitchableBeacon with appropriate configuration
        beacon = address(new SwitchableBeacon(moduleOwner, poaBeacon, initImpl, beaconMode));
    }
}

// src/factories/ModulesFactory.sol

/*──────────────────── OrgDeployer interface ────────────────────*/
interface IOrgDeployer_1 {
    function batchRegisterContracts(
        bytes32 orgId,
        OrgRegistry.ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external;
}

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();

/**
 * @title ModulesFactory
 * @notice Factory contract for deploying functional modules (TaskManager, EducationHub, etc.)
 * @dev Deploys BeaconProxy instances for all module types
 */
contract ModulesFactory {
    /*──────────────────── Role Assignments ────────────────────*/
    struct RoleAssignments {
        uint256 taskCreatorRolesBitmap; // Bit N set = Role N can create tasks
        uint256 educationCreatorRolesBitmap; // Bit N set = Role N can create education
        uint256 educationMemberRolesBitmap; // Bit N set = Role N can access education
    }

    /*──────────────────── EducationHub Configuration ────────────────────*/
    struct EducationHubConfig {
        bool enabled; // Whether to deploy EducationHub
    }

    /*──────────────────── Modules Deployment Params ────────────────────*/
    struct ModulesParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address executor;
        address deployer; // OrgDeployer address for registration callbacks
        address participationToken;
        uint256[] roleHatIds;
        bool autoUpgrade;
        RoleAssignments roleAssignments;
        EducationHubConfig educationHubConfig; // EducationHub deployment configuration
    }

    /*──────────────────── Modules Deployment Result ────────────────────*/
    struct ModulesResult {
        address taskManager;
        address educationHub;
        address paymentManager;
    }

    /*══════════════  MAIN DEPLOYMENT FUNCTION  ═════════════=*/

    /**
     * @notice Deploys complete functional module infrastructure for an organization
     * @param params Modules deployment parameters
     * @return result Addresses of deployed module components
     */
    function deployModules(ModulesParams memory params) external returns (ModulesResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.executor == address(0) || params.participationToken == address(0)
        ) {
            revert InvalidAddress();
        }

        address taskManagerBeacon;
        address educationHubBeacon;
        address paymentManagerBeacon;

        /* 1. Deploy TaskManager (without registration) */
        {
            // Get the role hat IDs for creator permissions
            uint256[] memory creatorHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.taskCreatorRolesBitmap
            );

            taskManagerBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.TASK_MANAGER_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.taskManager = ModuleDeploymentLib.deployTaskManager(
                config, params.executor, params.participationToken, creatorHats, taskManagerBeacon
            );
        }

        /* 2. Deploy EducationHub if enabled (without registration) */
        if (params.educationHubConfig.enabled) {
            // Get the role hat IDs for creator and member permissions
            uint256[] memory creatorHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.educationCreatorRolesBitmap
            );

            uint256[] memory memberHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.roleAssignments.educationMemberRolesBitmap
            );

            educationHubBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.EDUCATION_HUB_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.educationHub = ModuleDeploymentLib.deployEducationHub(
                config, params.executor, params.participationToken, creatorHats, memberHats, educationHubBeacon
            );
        }

        /* 3. Deploy PaymentManager (without registration) */
        {
            paymentManagerBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.PAYMENT_MANAGER_ID, params.poaManager, params.executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: params.executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.paymentManager = ModuleDeploymentLib.deployPaymentManager(
                config, params.executor, params.participationToken, paymentManagerBeacon
            );
        }

        /* 4. Batch register contracts (2 or 3 depending on EducationHub) */
        {
            uint256 registrationCount = params.educationHubConfig.enabled ? 3 : 2;
            OrgRegistry.ContractRegistration[] memory registrations =
                new OrgRegistry.ContractRegistration[](registrationCount);

            registrations[0] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.TASK_MANAGER_ID,
                proxy: result.taskManager,
                beacon: taskManagerBeacon,
                owner: params.executor
            });

            if (params.educationHubConfig.enabled) {
                registrations[1] = OrgRegistry.ContractRegistration({
                    typeId: ModuleTypes.EDUCATION_HUB_ID,
                    proxy: result.educationHub,
                    beacon: educationHubBeacon,
                    owner: params.executor
                });

                registrations[2] = OrgRegistry.ContractRegistration({
                    typeId: ModuleTypes.PAYMENT_MANAGER_ID,
                    proxy: result.paymentManager,
                    beacon: paymentManagerBeacon,
                    owner: params.executor
                });
            } else {
                registrations[1] = OrgRegistry.ContractRegistration({
                    typeId: ModuleTypes.PAYMENT_MANAGER_ID,
                    proxy: result.paymentManager,
                    beacon: paymentManagerBeacon,
                    owner: params.executor
                });
            }

            // Call OrgDeployer to batch register (not the last batch)
            IOrgDeployer_1(params.deployer).batchRegisterContracts(params.orgId, registrations, params.autoUpgrade, false);
        }

        return result;
    }
}

// src/factories/GovernanceFactory.sol

/*──────────────────── HatsTreeSetup interface ────────────────────*/
interface IHatsTreeSetup {
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
        address deployerAddress;
        address executor;
        address accountRegistry;
        string orgName;
        string deployerUsername;
        RoleConfigStructs.RoleConfig[] roles;
    }

    function setupHatsTree(SetupParams memory params) external returns (SetupResult memory);
}

/*──────────────────── OrgDeployer interface ────────────────────*/
interface IOrgDeployer_2 {
    function batchRegisterContracts(
        bytes32 orgId,
        OrgRegistry.ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external;
}

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error UnsupportedType();

/**
 * @title GovernanceFactory
 * @notice Factory contract for deploying governance infrastructure (Executor, Hats modules)
 * @dev Deploys BeaconProxy instances, NOT implementation contracts
 */
contract GovernanceFactory {
    /*──────────────────── Governance Deployment Params ────────────────────*/
    struct GovernanceParams {
        bytes32 orgId;
        string orgName;
        address poaManager;
        address orgRegistry;
        address hats;
        address hatsTreeSetup;
        address deployer; // OrgDeployer address for registration callbacks
        address deployerAddress; // Address to receive ADMIN hat
        address accountRegistry; // UniversalAccountRegistry for username registration
        address participationToken; // Token for HybridVoting
        string deployerUsername; // Optional username for deployer (empty string = skip registration)
        bool autoUpgrade;
        uint8 hybridQuorumPct; // Quorum for HybridVoting
        uint8 ddQuorumPct; // Quorum for DirectDemocracyVoting
        IHybridVotingInit.ClassConfig[] hybridClasses; // Voting class configuration
        uint256 hybridProposalCreatorRolesBitmap; // Bit N set = Role N can create proposals
        uint256 ddVotingRolesBitmap; // Bit N set = Role N can vote in polls
        uint256 ddCreatorRolesBitmap; // Bit N set = Role N can create polls
        address[] ddInitialTargets; // Allowed execution targets for DirectDemocracyVoting
        RoleConfigStructs.RoleConfig[] roles; // Complete role configuration
    }

    /*──────────────────── Governance Deployment Result ────────────────────*/
    struct GovernanceResult {
        address executor;
        address eligibilityModule;
        address toggleModule;
        address hybridVoting; // Governance mechanism
        address directDemocracyVoting; // Polling mechanism
        uint256 topHatId;
        uint256[] roleHatIds;
    }

    /*══════════════  INFRASTRUCTURE DEPLOYMENT  ═════════════=*/

    /**
     * @notice Deploys governance infrastructure (Executor, Hats modules, Hats tree)
     * @dev Called BEFORE AccessFactory. Voting mechanisms deployed separately after token exists.
     * @param params Governance deployment parameters
     * @return result Addresses and IDs of deployed governance components (voting addresses will be zero)
     */
    function deployInfrastructure(GovernanceParams memory params) external returns (GovernanceResult memory result) {
        if (
            params.poaManager == address(0) || params.orgRegistry == address(0) || params.hats == address(0)
                || params.hatsTreeSetup == address(0)
        ) {
            revert InvalidAddress();
        }

        /* 1. Deploy Executor with temporary ownership (without registration) */
        address execBeacon;
        address eligibilityBeacon;
        address toggleBeacon;
        {
            execBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.EXECUTOR_ID,
                params.poaManager,
                address(this), // temporary owner
                params.autoUpgrade,
                address(0) // no custom impl
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: address(this),
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            result.executor = ModuleDeploymentLib.deployExecutor(config, params.deployer, execBeacon);
        }

        /* 2. Deploy and configure modules for Hats tree (without registration) */
        (result.eligibilityModule, eligibilityBeacon) = _deployEligibilityModule(
            params.orgId, params.poaManager, params.orgRegistry, params.hats, params.autoUpgrade, params.deployer
        );

        (result.toggleModule, toggleBeacon) = _deployToggleModule(
            params.orgId, params.poaManager, params.orgRegistry, params.hats, params.autoUpgrade, params.deployer
        );

        /* 3. Setup Hats Tree */
        {
            // Transfer superAdmin rights to HatsTreeSetup contract
            IEligibilityModule(result.eligibilityModule).transferSuperAdmin(params.hatsTreeSetup);
            IToggleModule(result.toggleModule).transferAdmin(params.hatsTreeSetup);

            // Call HatsTreeSetup to do all the Hats configuration
            IHatsTreeSetup.SetupParams memory setupParams = IHatsTreeSetup.SetupParams({
                hats: IHats(params.hats),
                orgRegistry: OrgRegistry(params.orgRegistry),
                orgId: params.orgId,
                eligibilityModule: result.eligibilityModule,
                toggleModule: result.toggleModule,
                deployer: address(this),
                deployerAddress: params.deployerAddress,
                executor: result.executor,
                accountRegistry: params.accountRegistry,
                orgName: params.orgName,
                deployerUsername: params.deployerUsername,
                roles: params.roles
            });

            IHatsTreeSetup.SetupResult memory setupResult =
                IHatsTreeSetup(params.hatsTreeSetup).setupHatsTree(setupParams);

            result.topHatId = setupResult.topHatId;
            result.roleHatIds = setupResult.roleHatIds;
        }

        /* 4. Batch register all 3 deployed contracts */
        {
            OrgRegistry.ContractRegistration[] memory registrations = new OrgRegistry.ContractRegistration[](3);

            registrations[0] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.EXECUTOR_ID, proxy: result.executor, beacon: execBeacon, owner: address(this)
            });

            registrations[1] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.ELIGIBILITY_MODULE_ID,
                proxy: result.eligibilityModule,
                beacon: eligibilityBeacon,
                owner: address(this)
            });

            registrations[2] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.TOGGLE_MODULE_ID,
                proxy: result.toggleModule,
                beacon: toggleBeacon,
                owner: address(this)
            });

            // Call OrgDeployer to batch register (not the last batch)
            IOrgDeployer_2(params.deployer).batchRegisterContracts(params.orgId, registrations, params.autoUpgrade, false);
        }

        /* 5. Transfer executor beacon ownership back to executor itself */
        SwitchableBeacon(execBeacon).transferOwnership(result.executor);

        return result;
    }

    /*══════════════  VOTING DEPLOYMENT  ═════════════=*/

    /**
     * @notice Deploys voting mechanisms for an organization
     * @dev Called AFTER AccessFactory to ensure participationToken exists
     * @param params Governance deployment parameters (must include participationToken address)
     * @param executor Address of the executor (from deployInfrastructure)
     * @param roleHatIds Hat IDs for roles (from deployInfrastructure)
     * @return hybridVoting Address of deployed HybridVoting contract
     * @return directDemocracyVoting Address of deployed DirectDemocracyVoting contract
     */
    function deployVoting(GovernanceParams memory params, address executor, uint256[] memory roleHatIds)
        external
        returns (address hybridVoting, address directDemocracyVoting)
    {
        if (executor == address(0) || params.participationToken == address(0)) {
            revert InvalidAddress();
        }

        address hybridBeacon;
        address ddBeacon;

        /* 1. Deploy HybridVoting (Governance Mechanism) - without registration */
        {
            // Resolve proposal creator roles to hat IDs
            uint256[] memory creatorHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.hybridProposalCreatorRolesBitmap
            );

            // Update voting classes with token addresses and role hat IDs
            IHybridVotingInit.ClassConfig[] memory finalClasses =
                _updateClassesWithTokenAndHats(params.hybridClasses, params.participationToken, roleHatIds);

            hybridBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.HYBRID_VOTING_ID, params.poaManager, executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            hybridVoting = ModuleDeploymentLib.deployHybridVoting(
                config, executor, creatorHats, params.hybridQuorumPct, finalClasses, hybridBeacon
            );
        }

        /* 2. Deploy DirectDemocracyVoting (Polling Mechanism) - without registration */
        {
            // Resolve voting and creator roles to hat IDs
            uint256[] memory votingHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.ddVotingRolesBitmap
            );

            uint256[] memory creatorHats = RoleResolver.resolveRoleBitmap(
                OrgRegistry(params.orgRegistry), params.orgId, params.ddCreatorRolesBitmap
            );

            ddBeacon = BeaconDeploymentLib.createBeacon(
                ModuleTypes.DIRECT_DEMOCRACY_VOTING_ID, params.poaManager, executor, params.autoUpgrade, address(0)
            );

            ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
                poaManager: IPoaManager(params.poaManager),
                orgRegistry: OrgRegistry(params.orgRegistry),
                hats: params.hats,
                orgId: params.orgId,
                moduleOwner: executor,
                autoUpgrade: params.autoUpgrade,
                customImpl: address(0)
            });

            directDemocracyVoting = ModuleDeploymentLib.deployDirectDemocracyVoting(
                config, executor, votingHats, creatorHats, params.ddInitialTargets, params.ddQuorumPct, ddBeacon
            );
        }

        /* 3. Batch register both voting contracts */
        {
            OrgRegistry.ContractRegistration[] memory registrations = new OrgRegistry.ContractRegistration[](2);

            registrations[0] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.HYBRID_VOTING_ID, proxy: hybridVoting, beacon: hybridBeacon, owner: executor
            });

            registrations[1] = OrgRegistry.ContractRegistration({
                typeId: ModuleTypes.DIRECT_DEMOCRACY_VOTING_ID,
                proxy: directDemocracyVoting,
                beacon: ddBeacon,
                owner: executor
            });

            // Call OrgDeployer to batch register (this is the LAST batch - finalizes bootstrap)
            IOrgDeployer_2(params.deployer).batchRegisterContracts(params.orgId, registrations, params.autoUpgrade, true);
        }

        return (hybridVoting, directDemocracyVoting);
    }

    /*══════════════  INTERNAL HELPERS  ═════════════=*/

    /**
     * @notice Updates voting classes with token addresses and role hat IDs
     * @dev Fills in missing token addresses for ERC20_BAL classes
     */
    function _updateClassesWithTokenAndHats(
        IHybridVotingInit.ClassConfig[] memory classes,
        address token,
        uint256[] memory roleHatIds
    ) internal pure returns (IHybridVotingInit.ClassConfig[] memory) {
        for (uint256 i = 0; i < classes.length; i++) {
            if (classes[i].strategy == IHybridVotingInit.ClassStrategy.ERC20_BAL) {
                // Fill in token address if not provided
                if (classes[i].asset == address(0)) {
                    classes[i].asset = token;
                }
            }
            // For both DIRECT and ERC20_BAL, use all role hats if hatIds not specified
            if (classes[i].hatIds.length == 0) {
                classes[i].hatIds = roleHatIds;
            }
        }
        return classes;
    }

    /*══════════════  INTERNAL DEPLOYMENT HELPERS  ═════════════=*/

    /**
     * @notice Deploys EligibilityModule BeaconProxy (without registration)
     * @dev Registration handled via batch in deployInfrastructure
     * @return emProxy The deployed eligibility module proxy address
     * @return beacon The beacon address for this module
     */
    function _deployEligibilityModule(
        bytes32 orgId,
        address poaManager,
        address orgRegistry,
        address hats,
        bool autoUpgrade,
        address deployer
    ) internal returns (address emProxy, address beacon) {
        beacon = BeaconDeploymentLib.createBeacon(
            ModuleTypes.ELIGIBILITY_MODULE_ID, poaManager, address(this), autoUpgrade, address(0)
        );

        ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
            poaManager: IPoaManager(poaManager),
            orgRegistry: OrgRegistry(orgRegistry),
            hats: hats,
            orgId: orgId,
            moduleOwner: address(this),
            autoUpgrade: autoUpgrade,
            customImpl: address(0)
        });

        emProxy = ModuleDeploymentLib.deployEligibilityModule(config, address(this), address(0), beacon);
    }

    /**
     * @notice Deploys ToggleModule BeaconProxy (without registration)
     * @dev Registration handled via batch in deployInfrastructure
     * @return tmProxy The deployed toggle module proxy address
     * @return beacon The beacon address for this module
     */
    function _deployToggleModule(
        bytes32 orgId,
        address poaManager,
        address orgRegistry,
        address hats,
        bool autoUpgrade,
        address deployer
    ) internal returns (address tmProxy, address beacon) {
        beacon = BeaconDeploymentLib.createBeacon(
            ModuleTypes.TOGGLE_MODULE_ID, poaManager, address(this), autoUpgrade, address(0)
        );

        ModuleDeploymentLib.DeployConfig memory config = ModuleDeploymentLib.DeployConfig({
            poaManager: IPoaManager(poaManager),
            orgRegistry: OrgRegistry(orgRegistry),
            hats: hats,
            orgId: orgId,
            moduleOwner: address(this),
            autoUpgrade: autoUpgrade,
            customImpl: address(0)
        });

        tmProxy = ModuleDeploymentLib.deployToggleModule(config, address(this), beacon);
    }
}

// src/OrgDeployer.sol

/*────────────────────── Module‑specific hooks ──────────────────────────*/
interface IParticipationToken_1 {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
    function setHatMinterAuthorization(address minter, bool authorized) external;
    function configureVouching(
        address eligibilityModule,
        uint256 hatId,
        uint32 quorum,
        uint256 membershipHatId,
        bool combineWithHierarchy
    ) external;
    function batchConfigureVouching(
        address eligibilityModule,
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external;
    function setDefaultEligibility(address eligibilityModule, uint256 hatId, bool eligible, bool standing) external;
}

interface IPaymasterHub {
    function registerOrg(bytes32 orgId, uint256 adminHatId, uint256 operatorHatId) external;
}

/**
 * @title OrgDeployer
 * @notice Thin orchestrator for deploying complete organizations using factory pattern
 * @dev Coordinates GovernanceFactory, AccessFactory, and ModulesFactory
 */
contract OrgDeployer is Initializable {
    /// @notice Contract version for tracking deployments
    string public constant VERSION = "1.0.1";

    /*────────────────────────────  Errors  ───────────────────────────────*/
    error InvalidAddress();
    error OrgExistsMismatch();
    error Reentrant();
    error InvalidRoleConfiguration();

    /*────────────────────────────  Events  ───────────────────────────────*/
    event OrgDeployed(
        bytes32 indexed orgId,
        address indexed executor,
        address hybridVoting,
        address directDemocracyVoting,
        address quickJoin,
        address participationToken,
        address taskManager,
        address educationHub,
        address paymentManager,
        address eligibilityModule,
        address toggleModule,
        uint256 topHatId,
        uint256[] roleHatIds
    );

    event RolesCreated(
        bytes32 indexed orgId, uint256[] hatIds, string[] names, string[] images, bytes32[] metadataCIDs, bool[] canVote
    );

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgdeployer.storage
    struct Layout {
        GovernanceFactory governanceFactory;
        AccessFactory accessFactory;
        ModulesFactory modulesFactory;
        OrgRegistry orgRegistry;
        address poaManager;
        address hatsTreeSetup;
        address paymasterHub; // Shared PaymasterHub for all orgs
        uint256 _status; // manual reentrancy guard
    }

    IHats public hats;

    bytes32 private constant _STORAGE_SLOT = 0x9f1e8f9f8d4c3b2a1e7f6d5c4b3a2e1f0d9c8b7a6e5f4d3c2b1a0e9f8d7c6b5a;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*════════════════  INITIALIZATION  ════════════════*/

    constructor() initializer {}

    function initialize(
        address _governanceFactory,
        address _accessFactory,
        address _modulesFactory,
        address _poaManager,
        address _orgRegistry,
        address _hats,
        address _hatsTreeSetup,
        address _paymasterHub
    ) public initializer {
        if (
            _governanceFactory == address(0) || _accessFactory == address(0) || _modulesFactory == address(0)
                || _poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0)
                || _hatsTreeSetup == address(0) || _paymasterHub == address(0)
        ) {
            revert InvalidAddress();
        }

        Layout storage l = _layout();
        l.governanceFactory = GovernanceFactory(_governanceFactory);
        l.accessFactory = AccessFactory(_accessFactory);
        l.modulesFactory = ModulesFactory(_modulesFactory);
        l.orgRegistry = OrgRegistry(_orgRegistry);
        l.poaManager = _poaManager;
        l.hatsTreeSetup = _hatsTreeSetup;
        l.paymasterHub = _paymasterHub;
        l._status = 1; // Initialize manual reentrancy guard
        hats = IHats(_hats);
    }

    /*════════════════  DEPLOYMENT STRUCTS  ════════════════*/

    struct DeploymentResult {
        address hybridVoting;
        address directDemocracyVoting;
        address executor;
        address quickJoin;
        address participationToken;
        address taskManager;
        address educationHub;
        address paymentManager;
        address passkeyAccountFactory; // Optional: only set if passkey enabled
    }

    struct RoleAssignments {
        uint256 quickJoinRolesBitmap; // Bit N set = Role N assigned on join
        uint256 tokenMemberRolesBitmap; // Bit N set = Role N can hold tokens
        uint256 tokenApproverRolesBitmap; // Bit N set = Role N can approve transfers
        uint256 taskCreatorRolesBitmap; // Bit N set = Role N can create tasks
        uint256 educationCreatorRolesBitmap; // Bit N set = Role N can create education
        uint256 educationMemberRolesBitmap; // Bit N set = Role N can access education
        uint256 hybridProposalCreatorRolesBitmap; // Bit N set = Role N can create proposals
        uint256 ddVotingRolesBitmap; // Bit N set = Role N can vote in polls
        uint256 ddCreatorRolesBitmap; // Bit N set = Role N can create polls
    }

    struct DeploymentParams {
        bytes32 orgId;
        string orgName;
        bytes32 metadataHash; // IPFS CID sha256 digest (optional, bytes32(0) is valid)
        address registryAddr;
        address deployerAddress; // Address to receive ADMIN hat
        string deployerUsername; // Optional username for deployer (empty string = skip registration)
        bool autoUpgrade;
        uint8 hybridQuorumPct;
        uint8 ddQuorumPct;
        IHybridVotingInit.ClassConfig[] hybridClasses;
        address[] ddInitialTargets;
        RoleConfigStructs.RoleConfig[] roles; // Complete role configuration (replaces roleNames, roleImages, roleCanVote)
        RoleAssignments roleAssignments;
        AccessFactory.PasskeyConfig passkeyConfig; // Passkey infrastructure configuration
        ModulesFactory.EducationHubConfig educationHubConfig; // EducationHub deployment configuration
    }

    /*════════════════  VALIDATION  ════════════════*/

    /// @notice Validates role configurations for correctness
    /// @dev Checks indices, prevents cycles, validates vouching configs
    /// @param roles Array of role configurations to validate
    function _validateRoleConfigs(RoleConfigStructs.RoleConfig[] calldata roles) internal pure {
        uint256 len = roles.length;

        // Must have at least one role
        if (len == 0) revert InvalidRoleConfiguration();

        // Practical limit to prevent gas issues
        if (len > 32) revert InvalidRoleConfiguration();

        for (uint256 i = 0; i < len; i++) {
            RoleConfigStructs.RoleConfig calldata role = roles[i];

            // Validate vouching configuration
            if (role.vouching.enabled) {
                // Quorum must be positive
                if (role.vouching.quorum == 0) revert InvalidRoleConfiguration();

                // Voucher role index must be valid
                if (role.vouching.voucherRoleIndex >= len) {
                    revert InvalidRoleConfiguration();
                }
            }

            // Validate hierarchy configuration
            if (role.hierarchy.adminRoleIndex != type(uint256).max) {
                // Admin role index must be valid
                if (role.hierarchy.adminRoleIndex >= len) {
                    revert InvalidRoleConfiguration();
                }

                // Prevent simple self-referential cycles
                if (role.hierarchy.adminRoleIndex == i) {
                    revert InvalidRoleConfiguration();
                }
            }

            // Validate name is not empty
            if (bytes(role.name).length == 0) revert InvalidRoleConfiguration();
        }

        // Note: Full cycle detection would require graph traversal
        // The Hats contract itself will revert if actual cycles exist during tree creation
    }

    /*════════════════  MAIN DEPLOYMENT FUNCTION  ════════════════*/

    function deployFullOrg(DeploymentParams calldata params) external returns (DeploymentResult memory result) {
        // Manual reentrancy guard
        Layout storage l = _layout();
        if (l._status == 2) revert Reentrant();
        l._status = 2;

        result = _deployFullOrgInternal(params);

        // Reset reentrancy guard
        l._status = 1;

        return result;
    }

    /*════════════════  INTERNAL ORCHESTRATION  ════════════════*/

    function _deployFullOrgInternal(DeploymentParams calldata params)
        internal
        returns (DeploymentResult memory result)
    {
        Layout storage l = _layout();

        /* 1. Validate role configurations */
        _validateRoleConfigs(params.roles);

        /* 2. Validate deployer address */
        if (params.deployerAddress == address(0)) {
            revert InvalidAddress();
        }

        /* 3. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName), params.metadataHash);
        } else {
            revert OrgExistsMismatch();
        }

        /* 2. Deploy Governance Infrastructure (Executor, Hats modules, Hats tree) */
        GovernanceFactory.GovernanceResult memory gov = _deployGovernanceInfrastructure(params);
        result.executor = gov.executor;

        /* 3. Set the executor for the org */
        l.orgRegistry.setOrgExecutor(params.orgId, result.executor);

        /* 4. Register Hats tree in OrgRegistry */
        l.orgRegistry.registerHatsTree(params.orgId, gov.topHatId, gov.roleHatIds);

        /* 5. Register org with shared PaymasterHub */
        IPaymasterHub(l.paymasterHub).registerOrg(params.orgId, gov.topHatId, 0);

        /* 6. Deploy Access Infrastructure (QuickJoin, Token) */
        AccessFactory.AccessResult memory access;
        {
            AccessFactory.RoleAssignments memory accessRoles = AccessFactory.RoleAssignments({
                quickJoinRolesBitmap: params.roleAssignments.quickJoinRolesBitmap,
                tokenMemberRolesBitmap: params.roleAssignments.tokenMemberRolesBitmap,
                tokenApproverRolesBitmap: params.roleAssignments.tokenApproverRolesBitmap
            });

            AccessFactory.AccessParams memory accessParams = AccessFactory.AccessParams({
                orgId: params.orgId,
                orgName: params.orgName,
                poaManager: l.poaManager,
                orgRegistry: address(l.orgRegistry),
                hats: address(hats),
                executor: result.executor,
                deployer: address(this), // For registration callbacks
                registryAddr: params.registryAddr,
                roleHatIds: gov.roleHatIds,
                autoUpgrade: params.autoUpgrade,
                roleAssignments: accessRoles,
                passkeyConfig: params.passkeyConfig
            });

            access = l.accessFactory.deployAccess(accessParams);
            result.quickJoin = access.quickJoin;
            result.participationToken = access.participationToken;
            result.passkeyAccountFactory = access.passkeyAccountFactory;
        }

        /* 6. Deploy Functional Modules (TaskManager, Education, Payment) */
        ModulesFactory.ModulesResult memory modules;
        {
            ModulesFactory.RoleAssignments memory moduleRoles = ModulesFactory.RoleAssignments({
                taskCreatorRolesBitmap: params.roleAssignments.taskCreatorRolesBitmap,
                educationCreatorRolesBitmap: params.roleAssignments.educationCreatorRolesBitmap,
                educationMemberRolesBitmap: params.roleAssignments.educationMemberRolesBitmap
            });

            ModulesFactory.ModulesParams memory moduleParams = ModulesFactory.ModulesParams({
                orgId: params.orgId,
                orgName: params.orgName,
                poaManager: l.poaManager,
                orgRegistry: address(l.orgRegistry),
                hats: address(hats),
                executor: result.executor,
                deployer: address(this), // For registration callbacks
                participationToken: result.participationToken,
                roleHatIds: gov.roleHatIds,
                autoUpgrade: params.autoUpgrade,
                roleAssignments: moduleRoles,
                educationHubConfig: params.educationHubConfig
            });

            modules = l.modulesFactory.deployModules(moduleParams);
            result.taskManager = modules.taskManager;
            result.educationHub = modules.educationHub;
            result.paymentManager = modules.paymentManager;
        }

        /* 7. Deploy Voting Mechanisms (HybridVoting, DirectDemocracyVoting) */
        (result.hybridVoting, result.directDemocracyVoting) =
            _deployVotingMechanisms(params, result.executor, result.participationToken, gov.roleHatIds);

        /* 8. Wire up cross-module connections */
        IParticipationToken_1(result.participationToken).setTaskManager(result.taskManager);
        if (params.educationHubConfig.enabled) {
            IParticipationToken_1(result.participationToken).setEducationHub(result.educationHub);
        }

        /* 9. Authorize QuickJoin to mint hats */
        IExecutorAdmin(result.executor).setHatMinterAuthorization(result.quickJoin, true);

        /* 10. Link executor to governor */
        IExecutorAdmin(result.executor).setCaller(result.hybridVoting);

        /* 10.5. Configure vouching system from role configurations (batch optimized) */
        {
            // Count roles with vouching enabled
            uint256 vouchCount = 0;
            for (uint256 i = 0; i < params.roles.length; i++) {
                if (params.roles[i].vouching.enabled) vouchCount++;
            }

            if (vouchCount > 0) {
                uint256[] memory hatIds = new uint256[](vouchCount);
                uint32[] memory quorums = new uint32[](vouchCount);
                uint256[] memory membershipHatIds = new uint256[](vouchCount);
                bool[] memory combineFlags = new bool[](vouchCount);
                uint256 vouchIndex = 0;

                for (uint256 i = 0; i < params.roles.length; i++) {
                    RoleConfigStructs.RoleConfig calldata role = params.roles[i];
                    if (role.vouching.enabled) {
                        hatIds[vouchIndex] = gov.roleHatIds[i];
                        quorums[vouchIndex] = role.vouching.quorum;
                        membershipHatIds[vouchIndex] = gov.roleHatIds[role.vouching.voucherRoleIndex];
                        combineFlags[vouchIndex] = role.vouching.combineWithHierarchy;
                        vouchIndex++;
                    }
                }

                IExecutorAdmin(result.executor)
                    .batchConfigureVouching(gov.eligibilityModule, hatIds, quorums, membershipHatIds, combineFlags);
            }
        }

        /* 11. Renounce executor ownership - now only governed by voting */
        OwnableUpgradeable(result.executor).renounceOwnership();

        /* 12. Emit event for subgraph indexing */
        emit OrgDeployed(
            params.orgId,
            result.executor,
            result.hybridVoting,
            result.directDemocracyVoting,
            result.quickJoin,
            result.participationToken,
            result.taskManager,
            result.educationHub,
            result.paymentManager,
            gov.eligibilityModule,
            gov.toggleModule,
            gov.topHatId,
            gov.roleHatIds
        );

        /* 13. Emit role metadata for subgraph indexing */
        {
            uint256 roleCount = params.roles.length;
            string[] memory names = new string[](roleCount);
            string[] memory images = new string[](roleCount);
            bytes32[] memory metadataCIDs = new bytes32[](roleCount);
            bool[] memory canVoteFlags = new bool[](roleCount);

            for (uint256 i = 0; i < roleCount; i++) {
                names[i] = params.roles[i].name;
                images[i] = params.roles[i].image;
                metadataCIDs[i] = params.roles[i].metadataCID;
                canVoteFlags[i] = params.roles[i].canVote;
            }

            emit RolesCreated(params.orgId, gov.roleHatIds, names, images, metadataCIDs, canVoteFlags);
        }

        return result;
    }

    /*══════════════  UTILITIES  ═════════════=*/

    function _orgExists(bytes32 id) internal view returns (bool) {
        (,,, bool exists) = _layout().orgRegistry.orgOf(id);
        return exists;
    }

    /**
     * @notice Internal helper to deploy governance infrastructure
     * @dev Extracted to reduce stack depth in main deployment function
     */
    function _deployGovernanceInfrastructure(DeploymentParams calldata params)
        internal
        returns (GovernanceFactory.GovernanceResult memory)
    {
        Layout storage l = _layout();

        GovernanceFactory.GovernanceParams memory govParams;
        govParams.orgId = params.orgId;
        govParams.orgName = params.orgName;
        govParams.poaManager = l.poaManager;
        govParams.orgRegistry = address(l.orgRegistry);
        govParams.hats = address(hats);
        govParams.hatsTreeSetup = l.hatsTreeSetup;
        govParams.deployer = address(this);
        govParams.deployerAddress = params.deployerAddress; // Pass deployer address for ADMIN hat
        govParams.accountRegistry = params.registryAddr; // UniversalAccountRegistry for username registration
        govParams.participationToken = address(0);
        govParams.deployerUsername = params.deployerUsername; // Optional username (empty = skip)
        govParams.autoUpgrade = params.autoUpgrade;
        govParams.hybridQuorumPct = params.hybridQuorumPct;
        govParams.ddQuorumPct = params.ddQuorumPct;
        govParams.hybridClasses = params.hybridClasses;
        govParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        govParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        govParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        govParams.ddInitialTargets = params.ddInitialTargets;
        govParams.roles = params.roles;

        return l.governanceFactory.deployInfrastructure(govParams);
    }

    /**
     * @notice Internal helper to deploy voting mechanisms after token is available
     * @dev Extracted to reduce stack depth in main deployment function
     */
    function _deployVotingMechanisms(
        DeploymentParams calldata params,
        address executor,
        address participationToken,
        uint256[] memory roleHatIds
    ) internal returns (address hybridVoting, address directDemocracyVoting) {
        Layout storage l = _layout();

        GovernanceFactory.GovernanceParams memory votingParams;
        votingParams.orgId = params.orgId;
        votingParams.orgName = params.orgName;
        votingParams.poaManager = l.poaManager;
        votingParams.orgRegistry = address(l.orgRegistry);
        votingParams.hats = address(hats);
        votingParams.hatsTreeSetup = l.hatsTreeSetup;
        votingParams.deployer = address(this);
        votingParams.deployerAddress = params.deployerAddress;
        votingParams.participationToken = participationToken;
        votingParams.autoUpgrade = params.autoUpgrade;
        votingParams.hybridQuorumPct = params.hybridQuorumPct;
        votingParams.ddQuorumPct = params.ddQuorumPct;
        votingParams.hybridClasses = params.hybridClasses;
        votingParams.hybridProposalCreatorRolesBitmap = params.roleAssignments.hybridProposalCreatorRolesBitmap;
        votingParams.ddVotingRolesBitmap = params.roleAssignments.ddVotingRolesBitmap;
        votingParams.ddCreatorRolesBitmap = params.roleAssignments.ddCreatorRolesBitmap;
        votingParams.ddInitialTargets = params.ddInitialTargets;
        votingParams.roles = params.roles;

        return l.governanceFactory.deployVoting(votingParams, executor, roleHatIds);
    }

    /**
     * @notice Allows factories to register contracts via OrgDeployer's ownership
     * @dev Only callable by approved factory contracts during deployment
     */
    function registerContract(
        bytes32 orgId,
        bytes32 typeId,
        address proxy,
        address beacon,
        bool autoUpgrade,
        address moduleOwner,
        bool lastRegister
    ) external {
        Layout storage l = _layout();

        // Only allow factory contracts to call this
        if (
            msg.sender != address(l.governanceFactory) && msg.sender != address(l.accessFactory)
                && msg.sender != address(l.modulesFactory)
        ) {
            revert InvalidAddress();
        }

        // Only allow during bootstrap (deployment phase)
        (,, bool bootstrap,) = l.orgRegistry.orgOf(orgId);
        if (!bootstrap) revert("Deployment complete");

        // Forward registration to OrgRegistry (we are the owner)
        l.orgRegistry.registerOrgContract(orgId, typeId, proxy, beacon, autoUpgrade, moduleOwner, lastRegister);
    }

    /**
     * @notice Batch register multiple contracts from factories
     * @dev Only callable by approved factory contracts. Reduces gas overhead by batching registrations.
     * @param orgId The organization identifier
     * @param registrations Array of contracts to register
     * @param autoUpgrade Whether contracts auto-upgrade with their beacons
     */
    function batchRegisterContracts(
        bytes32 orgId,
        OrgRegistry.ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external {
        Layout storage l = _layout();

        // Only allow factory contracts to call this
        if (
            msg.sender != address(l.governanceFactory) && msg.sender != address(l.accessFactory)
                && msg.sender != address(l.modulesFactory)
        ) {
            revert InvalidAddress();
        }

        // Only allow during bootstrap (deployment phase)
        (,, bool bootstrap,) = l.orgRegistry.orgOf(orgId);
        if (!bootstrap) revert("Deployment complete");

        // Forward batch registration to OrgRegistry (we are the owner)
        l.orgRegistry.batchRegisterOrgContracts(orgId, registrations, autoUpgrade, lastRegister);
    }
}

