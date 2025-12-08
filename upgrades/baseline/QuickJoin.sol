// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13 ^0.8.20 ^0.8.21;

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

// lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol

// OpenZeppelin Contracts (last updated v5.3.0) (proxy/utils/Initializable.sol)

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
        // - construction: the contract is initialized at version 1 (no reinitialization) and the
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
     * @dev Pointer to storage slot. Allows integrators to override it with a custom storage location.
     *
     * NOTE: Consider following the ERC-7201 formula to derive storage locations.
     */
    function _initializableStorageSlot() internal pure virtual returns (bytes32) {
        return INITIALIZABLE_STORAGE;
    }

    /**
     * @dev Returns a pointer to the storage namespace.
     */
    // solhint-disable-next-line var-name-mixedcase
    function _getInitializableStorage() private pure returns (InitializableStorage storage $) {
        bytes32 slot = _initializableStorageSlot();
        assembly {
            $.slot := slot
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

// lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.1.0) (utils/ReentrancyGuard.sol)

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If EIP-1153 (transient storage) is available on the chain you're deploying at,
 * consider using {ReentrancyGuardTransient} instead.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    /// @custom:storage-location erc7201:openzeppelin.storage.ReentrancyGuard
    struct ReentrancyGuardStorage {
        uint256 _status;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ReentrancyGuard")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ReentrancyGuardStorageLocation = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    function _getReentrancyGuardStorage() private pure returns (ReentrancyGuardStorage storage $) {
        assembly {
            $.slot := ReentrancyGuardStorageLocation
        }
    }

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    function __ReentrancyGuard_init() internal onlyInitializing {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal onlyInitializing {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if ($._status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        $._status = ENTERED;
    }

    function _nonReentrantAfter() private {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        $._status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        ReentrancyGuardStorage storage $ = _getReentrancyGuardStorage();
        return $._status == ENTERED;
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

// src/libs/HatManager.sol

/**
 * @title HatManager
 * @notice Generic library for managing Hats Protocol permissions
 * @dev Storage-agnostic functions that work with any hat array structure
 */
library HatManager {
    /* ─────────── Events ─────────── */
    event HatToggled(uint256 indexed hatId, bool allowed);

    /* ─────────── Core Functions ─────────── */

    /**
     * @notice Add or remove a hat from an array
     * @param hatArray The array of hat IDs to modify
     * @param hatId The hat ID to add/remove
     * @param allowed Whether to add (true) or remove (false) the hat
     * @return modified Whether the array was actually modified
     */
    function setHatInArray(uint256[] storage hatArray, uint256 hatId, bool allowed) internal returns (bool modified) {
        uint256 existingIndex = findHatIndex(hatArray, hatId);
        bool exists = existingIndex != type(uint256).max;

        if (allowed && !exists) {
            // Add new hat
            hatArray.push(hatId);
            emit HatToggled(hatId, true);
            return true;
        } else if (!allowed && exists) {
            // Remove existing hat (swap with last element and pop)
            hatArray[existingIndex] = hatArray[hatArray.length - 1];
            hatArray.pop();
            emit HatToggled(hatId, false);
            return true;
        }

        return false; // No change needed
    }

    /**
     * @notice Check if a user wears any hat from an array
     * @param hats The Hats Protocol contract
     * @param hatArray Array of hat IDs to check
     * @param user The user address to check
     * @return bool True if user wears any hat from the array
     */
    function hasAnyHat(IHats hats, uint256[] storage hatArray, address user) internal view returns (bool) {
        uint256 len = hatArray.length;
        if (len == 0) return false;
        if (len == 1) return hats.isWearerOfHat(user, hatArray[0]);

        // Batch check for efficiency
        return _checkHatsBatch(hats, hatArray, user);
    }

    /**
     * @notice Check if a user wears any hat from a memory array
     * @param hats The Hats Protocol contract
     * @param hatArray Array of hat IDs to check
     * @param user The user address to check
     * @return bool True if user wears any hat from the array
     */
    function hasAnyHatMemory(IHats hats, uint256[] memory hatArray, address user) internal view returns (bool) {
        uint256 len = hatArray.length;
        if (len == 0) return false;
        if (len == 1) return hats.isWearerOfHat(user, hatArray[0]);

        // Build batch check arrays
        address[] memory wearers = new address[](len);
        for (uint256 i; i < len;) {
            wearers[i] = user;
            unchecked {
                ++i;
            }
        }

        uint256[] memory balances = hats.balanceOfBatch(wearers, hatArray);
        for (uint256 i; i < len;) {
            if (balances[i] > 0) return true;
            unchecked {
                ++i;
            }
        }

        return false;
    }

    /**
     * @notice Check if a specific hat is in an array
     * @param hatArray Array of hat IDs to search
     * @param hatId The hat ID to find
     * @return bool True if the hat is in the array
     */
    function isHatInArray(uint256[] storage hatArray, uint256 hatId) internal view returns (bool) {
        return findHatIndex(hatArray, hatId) != type(uint256).max;
    }

    /**
     * @notice Find the index of a hat in an array
     * @param hatArray Array of hat IDs to search
     * @param hatId The hat ID to find
     * @return uint256 Index of the hat, or type(uint256).max if not found
     */
    function findHatIndex(uint256[] storage hatArray, uint256 hatId) internal view returns (uint256) {
        for (uint256 i; i < hatArray.length;) {
            if (hatArray[i] == hatId) return i;
            unchecked {
                ++i;
            }
        }
        return type(uint256).max;
    }

    /**
     * @notice Get a copy of the hat array
     * @param hatArray Array of hat IDs
     * @return uint256[] Memory copy of the array
     */
    function getHatArray(uint256[] storage hatArray) internal view returns (uint256[] memory) {
        return hatArray;
    }

    /**
     * @notice Get the count of hats in an array
     * @param hatArray Array of hat IDs
     * @return uint256 Number of hats in the array
     */
    function getHatCount(uint256[] storage hatArray) internal view returns (uint256) {
        return hatArray.length;
    }

    /**
     * @notice Remove all hats from an array
     * @param hatArray Array of hat IDs to clear
     * @return removedCount Number of hats that were removed
     */
    function clearHatArray(uint256[] storage hatArray) internal returns (uint256 removedCount) {
        removedCount = hatArray.length;
        // Clear the array by setting length to 0
        assembly {
            sstore(hatArray.slot, 0)
        }
        return removedCount;
    }

    /**
     * @notice Efficiently check if user has specific hat without external calls
     * @dev Use this when you already know the specific hat ID to check
     * @param hats The Hats Protocol contract
     * @param user The user address
     * @param hatId The specific hat ID to check
     * @return bool True if user wears the hat
     */
    function hasSpecificHat(IHats hats, address user, uint256 hatId) internal view returns (bool) {
        return hats.isWearerOfHat(user, hatId);
    }

    /**
     * @notice Batch add multiple hats to an array
     * @param hatArray Array to add hats to
     * @param hatIds Array of hat IDs to add
     * @return addedCount Number of hats actually added (excluding duplicates)
     */
    function addHatsBatch(uint256[] storage hatArray, uint256[] calldata hatIds) internal returns (uint256 addedCount) {
        for (uint256 i; i < hatIds.length;) {
            if (setHatInArray(hatArray, hatIds[i], true)) {
                unchecked {
                    ++addedCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        return addedCount;
    }

    /**
     * @notice Batch remove multiple hats from an array
     * @param hatArray Array to remove hats from
     * @param hatIds Array of hat IDs to remove
     * @return removedCount Number of hats actually removed
     */
    function removeHatsBatch(uint256[] storage hatArray, uint256[] calldata hatIds)
        internal
        returns (uint256 removedCount)
    {
        for (uint256 i; i < hatIds.length;) {
            if (setHatInArray(hatArray, hatIds[i], false)) {
                unchecked {
                    ++removedCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        return removedCount;
    }

    /* ─────────── Internal Helpers ─────────── */

    /**
     * @dev Efficient batch checking using Hats Protocol's balanceOfBatch
     */
    function _checkHatsBatch(IHats hats, uint256[] storage hatArray, address user) private view returns (bool) {
        uint256 len = hatArray.length;

        // Build arrays for batch call
        address[] memory wearers = new address[](len);
        uint256[] memory hatIds = new uint256[](len);

        for (uint256 i; i < len;) {
            wearers[i] = user;
            hatIds[i] = hatArray[i];
            unchecked {
                ++i;
            }
        }

        // Single batch call to check all hats
        uint256[] memory balances = hats.balanceOfBatch(wearers, hatIds);

        // Check if any balance > 0
        for (uint256 i; i < len;) {
            if (balances[i] > 0) return true;
            unchecked {
                ++i;
            }
        }

        return false;
    }
}

// src/QuickJoin.sol

/*────────────────────────── OpenZeppelin v5.3 Upgradeables ────────────────────*/

/*───────────────────────── Interface minimal stubs ───────────────────────*/

interface IUniversalAccountRegistry {
    function getUsername(address account) external view returns (string memory);
    function registerAccountQuickJoin(string memory username, address newUser) external;
}

interface IExecutorHatMinter {
    function mintHatsForUser(address user, uint256[] calldata hatIds) external;
}

interface IPasskeyAccountFactory {
    function createAccount(bytes32 orgId, bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        returns (address account);
}

/*──────────────────────────────  Contract  ───────────────────────────────*/
contract QuickJoin is Initializable, ContextUpgradeable, ReentrancyGuardUpgradeable {
    /* ───────── Errors ───────── */
    error InvalidAddress();
    error OnlyMasterDeploy();
    error ZeroUser();
    error UsernameTooLong();
    error NoUsername();
    error Unauthorized();
    error PasskeyFactoryNotSet();
    error AccountAlreadyRegistered();

    /* ───────── Constants ────── */
    uint256 internal constant MAX_USERNAME_LEN = 64;
    bytes4 public constant MODULE_ID = bytes4(keccak256("QuickJoin"));

    /* ───────── ERC-7201 Storage ──────── */
    /// @custom:storage-location erc7201:poa.quickjoin.storage
    struct Layout {
        IHats hats;
        IUniversalAccountRegistry accountRegistry;
        address masterDeployAddress;
        address executor;
        uint256[] memberHatIds; // hat IDs to mint when users join
        IPasskeyAccountFactory passkeyFactory; // Factory for passkey accounts
        bytes32 orgId; // Organization ID for passkey account creation
    }

    /* ───────── Passkey Enrollment Struct ──────── */
    struct PasskeyEnrollment {
        bytes32 credentialId;
        bytes32 publicKeyX;
        bytes32 publicKeyY;
        uint256 salt;
    }

    // keccak256("poa.quickjoin.storage")
    bytes32 private constant _STORAGE_SLOT = 0x566f0545117c69d7a3001f74fa210927792975a5c779e9cbf2876fbc68ef7fa2;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───────── Events ───────── */
    event AddressesUpdated(address hats, address registry, address master);
    event ExecutorUpdated(address newExecutor);
    event MemberHatIdsUpdated(uint256[] hatIds);
    event QuickJoined(address indexed user, bool usernameCreated, uint256[] hatIds);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated, uint256[] hatIds);
    event PasskeyFactoryUpdated(address indexed passkeyFactory);
    event OrgIdUpdated(bytes32 indexed orgId);
    event QuickJoinedWithPasskey(
        address indexed account, string username, bytes32 indexed credentialId, uint256[] hatIds
    );
    event QuickJoinedWithPasskeyByMaster(
        address indexed master, address indexed account, string username, bytes32 indexed credentialId, uint256[] hatIds
    );

    /* ───────── Initialiser ───── */
    function initialize(
        address executor_,
        address hats_,
        address accountRegistry_,
        address masterDeploy_,
        uint256[] calldata memberHatIds_
    ) external initializer {
        if (
            executor_ == address(0) || hats_ == address(0) || accountRegistry_ == address(0)
                || masterDeploy_ == address(0)
        ) revert InvalidAddress();

        __Context_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.executor = executor_;
        l.hats = IHats(hats_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        // Set member hat IDs using HatManager
        for (uint256 i = 0; i < memberHatIds_.length; i++) {
            HatManager.setHatInArray(l.memberHatIds, memberHatIds_[i], true);
        }

        emit AddressesUpdated(hats_, accountRegistry_, masterDeploy_);
        emit ExecutorUpdated(executor_);
        emit MemberHatIdsUpdated(memberHatIds_);
    }

    /* ───────── Modifiers ─────── */
    modifier onlyMasterDeploy() {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && _msgSender() != l.masterDeployAddress) revert OnlyMasterDeploy();
        _;
    }

    modifier onlyExecutor() {
        if (_msgSender() != _layout().executor) revert Unauthorized();
        _;
    }

    /* ─────── Admin / DAO setters (executor-gated) ─────── */
    function updateAddresses(address hats_, address accountRegistry_, address masterDeploy_) external onlyExecutor {
        if (hats_ == address(0) || accountRegistry_ == address(0) || masterDeploy_ == address(0)) {
            revert InvalidAddress();
        }

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.accountRegistry = IUniversalAccountRegistry(accountRegistry_);
        l.masterDeployAddress = masterDeploy_;

        emit AddressesUpdated(hats_, accountRegistry_, masterDeploy_);
    }

    function updateMemberHatIds(uint256[] calldata memberHatIds_) external onlyExecutor {
        Layout storage l = _layout();

        // Clear existing hat IDs using HatManager
        HatManager.clearHatArray(l.memberHatIds);

        // Set new hat IDs using HatManager
        for (uint256 i = 0; i < memberHatIds_.length; i++) {
            HatManager.setHatInArray(l.memberHatIds, memberHatIds_[i], true);
        }

        emit MemberHatIdsUpdated(memberHatIds_);
    }

    function setExecutor(address newExec) external onlyExecutor {
        if (newExec == address(0)) revert InvalidAddress();
        _layout().executor = newExec;
        emit ExecutorUpdated(newExec);
    }

    function setPasskeyFactory(address factory) external onlyExecutor {
        _layout().passkeyFactory = IPasskeyAccountFactory(factory);
        emit PasskeyFactoryUpdated(factory);
    }

    function setOrgId(bytes32 orgId_) external onlyExecutor {
        _layout().orgId = orgId_;
        emit OrgIdUpdated(orgId_);
    }

    /* ───────── Internal helper ─────── */
    function _quickJoin(address user, string memory username) private nonReentrant {
        if (user == address(0)) revert ZeroUser();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        Layout storage l = _layout();
        bool created;

        if (bytes(l.accountRegistry.getUsername(user)).length == 0) {
            if (bytes(username).length == 0) revert NoUsername();
            l.accountRegistry.registerAccountQuickJoin(username, user);
            created = true;
        }

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(user, l.memberHatIds);
        }

        emit QuickJoined(user, created, l.memberHatIds);
    }

    /* ───────── Public user paths ─────── */

    /// 1) caller supplies username if they don't have one yet
    function quickJoinNoUser(string calldata username) external {
        _quickJoin(_msgSender(), username);
    }

    /// 2) caller already registered a username elsewhere
    function quickJoinWithUser() external nonReentrant {
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(_msgSender());
        if (bytes(existing).length == 0) revert NoUsername();

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(_msgSender(), l.memberHatIds);
        }

        emit QuickJoined(_msgSender(), false, l.memberHatIds);
    }

    /* ───────── Passkey join paths ─────── */

    /// @notice Join org with a new passkey account
    /// @param username Username to register
    /// @param passkey Passkey enrollment data
    /// @return account The created passkey account address
    /// @dev Reverts if the passkey already has a registered account with a username
    function quickJoinWithPasskey(string calldata username, PasskeyEnrollment calldata passkey)
        external
        nonReentrant
        returns (address account)
    {
        Layout storage l = _layout();
        if (address(l.passkeyFactory) == address(0)) revert PasskeyFactoryNotSet();
        if (bytes(username).length == 0) revert NoUsername();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        // 1. Create PasskeyAccount via factory (returns existing if already deployed)
        account = l.passkeyFactory
            .createAccount(l.orgId, passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);

        // 2. Register username to the account
        // Revert if account already has a username (prevents duplicate enrollment attempts)
        if (bytes(l.accountRegistry.getUsername(account)).length != 0) {
            revert AccountAlreadyRegistered();
        }
        l.accountRegistry.registerAccountQuickJoin(username, account);

        // 3. Mint member hats to the account
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(account, l.memberHatIds);
        }

        emit QuickJoinedWithPasskey(account, username, passkey.credentialId, l.memberHatIds);
    }

    /// @notice Master-deploy path for passkey onboarding
    /// @param username Username to register
    /// @param passkey Passkey enrollment data
    /// @return account The created passkey account address
    /// @dev Reverts if the passkey already has a registered account with a username
    function quickJoinWithPasskeyMasterDeploy(string calldata username, PasskeyEnrollment calldata passkey)
        external
        onlyMasterDeploy
        nonReentrant
        returns (address account)
    {
        Layout storage l = _layout();
        if (address(l.passkeyFactory) == address(0)) revert PasskeyFactoryNotSet();
        if (bytes(username).length == 0) revert NoUsername();
        if (bytes(username).length > MAX_USERNAME_LEN) revert UsernameTooLong();

        // 1. Create PasskeyAccount via factory (returns existing if already deployed)
        account = l.passkeyFactory
            .createAccount(l.orgId, passkey.credentialId, passkey.publicKeyX, passkey.publicKeyY, passkey.salt);

        // 2. Register username to the account
        // Revert if account already has a username (prevents duplicate enrollment attempts)
        if (bytes(l.accountRegistry.getUsername(account)).length != 0) {
            revert AccountAlreadyRegistered();
        }
        l.accountRegistry.registerAccountQuickJoin(username, account);

        // 3. Mint member hats to the account
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(account, l.memberHatIds);
        }

        emit QuickJoinedWithPasskeyByMaster(_msgSender(), account, username, passkey.credentialId, l.memberHatIds);
    }

    /* ───────── Master-deploy helper paths ─────── */

    function quickJoinNoUserMasterDeploy(string calldata username, address newUser) external onlyMasterDeploy {
        _quickJoin(newUser, username);
        emit QuickJoinedByMaster(_msgSender(), newUser, bytes(username).length > 0, _layout().memberHatIds);
    }

    function quickJoinWithUserMasterDeploy(address newUser) external onlyMasterDeploy nonReentrant {
        if (newUser == address(0)) revert ZeroUser();
        Layout storage l = _layout();
        string memory existing = l.accountRegistry.getUsername(newUser);
        if (bytes(existing).length == 0) revert NoUsername();

        // Request executor to mint all configured member hats to the user
        if (l.memberHatIds.length > 0) {
            IExecutorHatMinter(l.executor).mintHatsForUser(newUser, l.memberHatIds);
        }

        emit QuickJoinedByMaster(_msgSender(), newUser, false, l.memberHatIds);
    }

    /* ───────── Misc view helpers ─────── */
    function memberHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().memberHatIds);
    }

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function accountRegistry() external view returns (IUniversalAccountRegistry) {
        return _layout().accountRegistry;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function masterDeployAddress() external view returns (address) {
        return _layout().masterDeployAddress;
    }

    /* ───────── Hat Management View Functions ─────────── */
    function memberHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().memberHatIds);
    }

    function isMemberHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().memberHatIds, hatId);
    }

    function passkeyFactory() external view returns (IPasskeyAccountFactory) {
        return _layout().passkeyFactory;
    }

    function orgId() external view returns (bytes32) {
        return _layout().orgId;
    }
}

