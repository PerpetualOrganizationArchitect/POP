// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 >=0.6.2 >=0.8.13 ^0.8.20 ^0.8.30;

// src/libs/BudgetLib.sol

/**
 * @title BudgetLib
 * @notice Library for budget management operations
 * @dev Reduces bytecode by extracting common budget logic into reusable functions
 */
library BudgetLib {
    /* ─────────── Errors ─────────── */
    error BudgetExceeded();
    error SpentUnderflow();
    error CapBelowCommitted();

    /* ─────────── Data Types ─────────── */
    struct Budget {
        uint128 cap; // 16 bytes
        uint128 spent; // 16 bytes (total 32 bytes)
    }

    /* ─────────── Core Functions ─────────── */

    /**
     * @notice Add spent amount to budget with cap checking
     * @param budget The budget struct to modify
     * @param delta Amount to add to spent
     * @param cap The budget cap (0 means unlimited)
     */
    function addSpent(Budget storage budget, uint256 delta, uint256 cap) internal {
        uint256 newSpent = budget.spent + delta;
        if (newSpent > type(uint128).max) revert BudgetExceeded();
        if (cap != 0 && newSpent > cap) revert BudgetExceeded();
        budget.spent = uint128(newSpent);
    }

    /**
     * @notice Add spent amount to budget using budget's own cap
     * @param budget The budget struct to modify
     * @param delta Amount to add to spent
     */
    function addSpent(Budget storage budget, uint256 delta) internal {
        addSpent(budget, delta, budget.cap);
    }

    /**
     * @notice Subtract spent amount from budget with underflow protection
     * @param budget The budget struct to modify
     * @param delta Amount to subtract from spent
     */
    function subtractSpent(Budget storage budget, uint256 delta) internal {
        if (budget.spent < delta) revert SpentUnderflow();
        unchecked {
            budget.spent -= uint128(delta);
        }
    }

    /**
     * @notice Update budget spent amount (can increase or decrease)
     * @param budget The budget struct to modify
     * @param oldAmount Previous amount to rollback
     * @param newAmount New amount to apply
     * @param cap The budget cap (0 means unlimited)
     */
    function updateSpent(Budget storage budget, uint256 oldAmount, uint256 newAmount, uint256 cap) internal {
        // Rollback old amount
        if (oldAmount > 0) {
            subtractSpent(budget, oldAmount);
        }

        // Apply new amount
        if (newAmount > 0) {
            addSpent(budget, newAmount, cap);
        }
    }

    /**
     * @notice Update budget spent amount using budget's own cap
     * @param budget The budget struct to modify
     * @param oldAmount Previous amount to rollback
     * @param newAmount New amount to apply
     */
    function updateSpent(Budget storage budget, uint256 oldAmount, uint256 newAmount) internal {
        updateSpent(budget, oldAmount, newAmount, budget.cap);
    }

    /**
     * @notice Check if an amount can be added without exceeding cap
     * @param budget The budget struct to check
     * @param delta Amount to potentially add
     * @return bool True if the addition would not exceed cap
     */
    function canAddSpent(Budget storage budget, uint256 delta) internal view returns (bool) {
        if (budget.cap == 0) return true; // Unlimited
        return budget.spent + delta <= budget.cap;
    }

    /**
     * @notice Get remaining budget capacity
     * @param budget The budget struct to check
     * @return uint256 Remaining capacity (returns max uint256 if unlimited)
     */
    function remainingCapacity(Budget storage budget) internal view returns (uint256) {
        if (budget.cap == 0) return type(uint256).max; // Unlimited
        if (budget.spent >= budget.cap) return 0;
        return budget.cap - budget.spent;
    }

    /**
     * @notice Check if a new cap is valid (not below current spent)
     * @param budget The budget struct to check
     * @param newCap The proposed new cap
     * @return bool True if the new cap is valid
     */
    function isValidCap(Budget storage budget, uint256 newCap) internal view returns (bool) {
        return newCap == 0 || newCap >= budget.spent;
    }

    /**
     * @notice Set budget cap with validation
     * @param budget The budget struct to modify
     * @param newCap The new cap to set
     */
    function setCap(Budget storage budget, uint256 newCap) internal {
        if (!isValidCap(budget, newCap)) revert CapBelowCommitted();
        budget.cap = uint128(newCap);
    }
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

// lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (utils/introspection/IERC165.sol)

/**
 * @dev Interface of the ERC-165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[ERC].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[ERC section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC-20 standard as defined in the ERC.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
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

// src/libs/TaskPerm.sol

/**
 * @dev Bit-mask helpers for granular task permissions.
 * Flags may be OR-combined (e.g. CREATE | ASSIGN).
 */
library TaskPerm {
    uint8 internal constant CREATE = 1 << 0;
    uint8 internal constant CLAIM = 1 << 1;
    uint8 internal constant REVIEW = 1 << 2;
    uint8 internal constant ASSIGN = 1 << 3;

    function has(uint8 mask, uint8 flag) internal pure returns (bool) {
        return mask & flag != 0;
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

// lib/openzeppelin-contracts/contracts/interfaces/IERC165.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC165.sol)

// lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC20.sol)

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

// lib/openzeppelin-contracts/contracts/interfaces/IERC1363.sol

// OpenZeppelin Contracts (last updated v5.4.0) (interfaces/IERC1363.sol)

/**
 * @title IERC1363
 * @dev Interface of the ERC-1363 standard as defined in the https://eips.ethereum.org/EIPS/eip-1363[ERC-1363].
 *
 * Defines an extension interface for ERC-20 tokens that supports executing code on a recipient contract
 * after `transfer` or `transferFrom`, or code on a spender contract after `approve`, in a single transaction.
 */
interface IERC1363 is IERC20, IERC165 {
    /*
     * Note: the ERC-165 identifier for this interface is 0xb0202a11.
     * 0xb0202a11 ===
     *   bytes4(keccak256('transferAndCall(address,uint256)')) ^
     *   bytes4(keccak256('transferAndCall(address,uint256,bytes)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256)')) ^
     *   bytes4(keccak256('transferFromAndCall(address,address,uint256,bytes)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256)')) ^
     *   bytes4(keccak256('approveAndCall(address,uint256,bytes)'))
     */

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the allowance mechanism
     * and then calls {IERC1363Receiver-onTransferReceived} on `to`.
     * @param from The address which you want to send tokens from.
     * @param to The address which you want to transfer to.
     * @param value The amount of tokens to be transferred.
     * @param data Additional data with no specified format, sent in call to `to`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function transferFromAndCall(address from, address to, uint256 value, bytes calldata data) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value) external returns (bool);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens and then calls {IERC1363Spender-onApprovalReceived} on `spender`.
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     * @param data Additional data with no specified format, sent in call to `spender`.
     * @return A boolean value indicating whether the operation succeeded unless throwing.
     */
    function approveAndCall(address spender, uint256 value, bytes calldata data) external returns (bool);
}

// lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol

// OpenZeppelin Contracts (last updated v5.3.0) (token/ERC20/utils/SafeERC20.sol)

/**
 * @title SafeERC20
 * @dev Wrappers around ERC-20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    /**
     * @dev An operation with an ERC-20 token failed.
     */
    error SafeERC20FailedOperation(address token);

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error SafeERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    /**
     * @dev Transfer `value` amount of `token` from the calling contract to `to`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Transfer `value` amount of `token` from `from` to `to`, spending the approval given by `from` to the
     * calling contract. If `token` returns no value, non-reverting calls are assumed to be successful.
     */
    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Variant of {safeTransfer} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransfer(IERC20 token, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @dev Variant of {safeTransferFrom} that returns a bool instead of reverting if the operation is not successful.
     */
    function trySafeTransferFrom(IERC20 token, address from, address to, uint256 value) internal returns (bool) {
        return _callOptionalReturnBool(token, abi.encodeCall(token.transferFrom, (from, to, value)));
    }

    /**
     * @dev Increase the calling contract's allowance toward `spender` by `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 oldAllowance = token.allowance(address(this), spender);
        forceApprove(token, spender, oldAllowance + value);
    }

    /**
     * @dev Decrease the calling contract's allowance toward `spender` by `requestedDecrease`. If `token` returns no
     * value, non-reverting calls are assumed to be successful.
     *
     * IMPORTANT: If the token implements ERC-7674 (ERC-20 with temporary allowance), and if the "client"
     * smart contract uses ERC-7674 to set temporary allowances, then the "client" smart contract should avoid using
     * this function. Performing a {safeIncreaseAllowance} or {safeDecreaseAllowance} operation on a token contract
     * that has a non-zero temporary allowance (for that particular owner-spender) will result in unexpected behavior.
     */
    function safeDecreaseAllowance(IERC20 token, address spender, uint256 requestedDecrease) internal {
        unchecked {
            uint256 currentAllowance = token.allowance(address(this), spender);
            if (currentAllowance < requestedDecrease) {
                revert SafeERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
            }
            forceApprove(token, spender, currentAllowance - requestedDecrease);
        }
    }

    /**
     * @dev Set the calling contract's allowance toward `spender` to `value`. If `token` returns no value,
     * non-reverting calls are assumed to be successful. Meant to be used with tokens that require the approval
     * to be set to zero before setting it to a non-zero value, such as USDT.
     *
     * NOTE: If the token implements ERC-7674, this function will not modify any temporary allowance. This function
     * only sets the "standard" allowance. Any temporary allowance will remain active, in addition to the value being
     * set here.
     */
    function forceApprove(IERC20 token, address spender, uint256 value) internal {
        bytes memory approvalCall = abi.encodeCall(token.approve, (spender, value));

        if (!_callOptionalReturnBool(token, approvalCall)) {
            _callOptionalReturn(token, abi.encodeCall(token.approve, (spender, 0)));
            _callOptionalReturn(token, approvalCall);
        }
    }

    /**
     * @dev Performs an {ERC1363} transferAndCall, with a fallback to the simple {ERC20} transfer if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            safeTransfer(token, to, value);
        } else if (!token.transferAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} transferFromAndCall, with a fallback to the simple {ERC20} transferFrom if the target
     * has no code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * Reverts if the returned value is other than `true`.
     */
    function transferFromAndCallRelaxed(
        IERC1363 token,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) {
            safeTransferFrom(token, from, to, value);
        } else if (!token.transferFromAndCall(from, to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Performs an {ERC1363} approveAndCall, with a fallback to the simple {ERC20} approve if the target has no
     * code. This can be used to implement an {ERC721}-like safe transfer that rely on {ERC1363} checks when
     * targeting contracts.
     *
     * NOTE: When the recipient address (`to`) has no code (i.e. is an EOA), this function behaves as {forceApprove}.
     * Opposedly, when the recipient address (`to`) has code, this function only attempts to call {ERC1363-approveAndCall}
     * once without retrying, and relies on the returned value to be true.
     *
     * Reverts if the returned value is other than `true`.
     */
    function approveAndCallRelaxed(IERC1363 token, address to, uint256 value, bytes memory data) internal {
        if (to.code.length == 0) {
            forceApprove(token, to, value);
        } else if (!token.approveAndCall(to, value, data)) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturnBool} that reverts if call fails to meet the requirements.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            let success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            // bubble errors
            if iszero(success) {
                let ptr := mload(0x40)
                returndatacopy(ptr, 0, returndatasize())
                revert(ptr, returndatasize())
            }
            returnSize := returndatasize()
            returnValue := mload(0)
        }

        if (returnSize == 0 ? address(token).code.length == 0 : returnValue != 1) {
            revert SafeERC20FailedOperation(address(token));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     *
     * This is a variant of {_callOptionalReturn} that silently catches all reverts and returns a bool instead.
     */
    function _callOptionalReturnBool(IERC20 token, bytes memory data) private returns (bool) {
        bool success;
        uint256 returnSize;
        uint256 returnValue;
        assembly ("memory-safe") {
            success := call(gas(), token, 0, add(data, 0x20), mload(data), 0, 0x20)
            returnSize := returndatasize()
            returnValue := mload(0)
        }
        return success && (returnSize == 0 ? address(token).code.length > 0 : returnValue == 1);
    }
}

// src/TaskManager.sol

/*──────── OpenZeppelin v5.3 Upgradeables ────────*/

/*────────── Internal Libraries ──────────*/

/*────────── External Hats interface ──────────*/

/*────────── External Interfaces ──────────*/
interface IParticipationToken is IERC20 {
    function mint(address, uint256) external;
}

/*────────────────────── Contract ───────────────────────*/
contract TaskManager is Initializable, ContextUpgradeable {
    using SafeERC20 for IERC20;
    using BudgetLib for BudgetLib.Budget;
    using ValidationLib for address;
    using ValidationLib for bytes;

    /*──────── Errors ───────*/
    error NotFound();
    error BadStatus();
    error NotCreator();
    error NotClaimer();
    error NotExecutor();
    error Unauthorized();
    error NotApplicant();
    error AlreadyApplied();
    error RequiresApplication();
    error NoApplicationRequired();
    error InvalidIndex();

    /*──────── Constants ─────*/
    bytes4 public constant MODULE_ID = 0x54534b32; // "TSK2"

    /*──────── Enums ─────*/
    enum HatType {
        CREATOR
    }

    enum ConfigKey {
        EXECUTOR,
        CREATOR_HAT_ALLOWED,
        ROLE_PERM,
        PROJECT_ROLE_PERM,
        BOUNTY_CAP,
        PROJECT_MANAGER,
        PROJECT_CAP
    }

    /*──────── Data Types ────*/
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }

    struct Task {
        bytes32 projectId; // slot 1: full 32 bytes
        uint96 payout; // slot 2: 12 bytes (supports up to 7e28, well over 1e24 cap), voting token payout
        address claimer; // slot 2: 20 bytes (total 32 bytes in slot 2)
        uint96 bountyPayout; // slot 3: 12 bytes, additional payout in bounty currency
        bool requiresApplication; // slot 3: 1 byte
        Status status; // slot 3: 1 byte (enum fits in 1 byte)
        address bountyToken; // slot 4: 20 bytes (optimized packing: small fields grouped together)
    }

    struct Project {
        mapping(address => bool) managers; // slot 0: mapping (full slot)
        uint128 cap; // slot 1: 16 bytes (participation token cap)
        uint128 spent; // slot 1: 16 bytes (participation token spent)
        bool exists; // slot 2: 1 byte (separate slot for cleaner access)
        mapping(address => BudgetLib.Budget) bountyBudgets; // slot 2: rest of slot & beyond
    }

    /*──────── Storage (ERC-7201) ───────*/
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IHats hats;
        IParticipationToken token;
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint48 nextTaskId;
        uint48 nextProjectId;
        address executor; // 20 bytes + 2*6 bytes = 32 bytes (one slot)
        mapping(uint256 => uint8) rolePermGlobal; // hat ID => permission mask
        mapping(bytes32 => mapping(uint256 => uint8)) rolePermProj; // project => hat ID => permission mask
        uint256[] permissionHatIds; // enumeration array for hats with permissions
        mapping(uint256 => address[]) taskApplicants; // task ID => array of applicants
        mapping(uint256 => mapping(address => bytes32)) taskApplications; // task ID => applicant => application hash
    }

    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────── Events ───────*/
    event HatSet(HatType hatType, uint256 hat, bool allowed);
    event ProjectCreated(bytes32 indexed id, bytes title, bytes32 metadataHash, uint256 cap);
    event ProjectCapUpdated(bytes32 indexed id, uint256 oldCap, uint256 newCap);
    event ProjectManagerUpdated(bytes32 indexed id, address indexed manager, bool isManager);
    event ProjectDeleted(bytes32 indexed id);
    event ProjectRolePermSet(bytes32 indexed id, uint256 indexed hatId, uint8 mask);
    event BountyCapSet(bytes32 indexed projectId, address indexed token, uint256 oldCap, uint256 newCap);

    event TaskCreated(
        uint256 indexed id,
        bytes32 indexed project,
        uint256 payout,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication,
        bytes title,
        bytes32 metadataHash
    );
    event TaskUpdated(
        uint256 indexed id, uint256 payout, address bountyToken, uint256 bountyPayout, bytes title, bytes32 metadataHash
    );
    event TaskSubmitted(uint256 indexed id, bytes32 submissionHash);
    event TaskClaimed(uint256 indexed id, address indexed claimer);
    event TaskAssigned(uint256 indexed id, address indexed assignee, address indexed assigner);
    event TaskCompleted(uint256 indexed id, address indexed completer);
    event TaskCancelled(uint256 indexed id, address indexed canceller);
    event TaskApplicationSubmitted(uint256 indexed id, address indexed applicant, bytes32 applicationHash);
    event TaskApplicationApproved(uint256 indexed id, address indexed applicant, address indexed approver);
    event ExecutorUpdated(address newExecutor);

    /*──────── Initialiser ───────*/
    function initialize(
        address tokenAddress,
        address hatsAddress,
        uint256[] calldata creatorHats,
        address executorAddress
    ) external initializer {
        tokenAddress.requireNonZeroAddress();
        hatsAddress.requireNonZeroAddress();
        executorAddress.requireNonZeroAddress();

        __Context_init();

        Layout storage l = _layout();
        l.token = IParticipationToken(tokenAddress);
        l.hats = IHats(hatsAddress);
        l.executor = executorAddress;

        // Initialize creator hat arrays using HatManager
        for (uint256 i; i < creatorHats.length;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHats[i], true);
            emit HatSet(HatType.CREATOR, creatorHats[i], true);
            unchecked {
                ++i;
            }
        }

        emit ExecutorUpdated(executorAddress);
    }

    /*──────── Internal Check Functions ─────*/
    function _requireCreator() internal view {
        Layout storage l = _layout();
        address s = _msgSender();
        if (!_hasCreatorHat(s) && s != l.executor) revert NotCreator();
    }

    function _requireProjectExists(bytes32 pid) internal view {
        if (!_layout()._projects[pid].exists) revert NotFound();
    }

    function _requireExecutor() internal view {
        if (_msgSender() != _layout().executor) revert NotExecutor();
    }

    function _requireCanCreate(bytes32 pid) internal view {
        _checkPerm(pid, TaskPerm.CREATE);
    }

    function _requireCanClaim(uint256 tid) internal view {
        _checkPerm(_layout()._tasks[tid].projectId, TaskPerm.CLAIM);
    }

    function _requireCanAssign(bytes32 pid) internal view {
        _checkPerm(pid, TaskPerm.ASSIGN);
    }

    /*──────── Project Logic ─────*/
    /**
     * @param title           Project title (required, raw UTF-8)
     * @param metadataHash    IPFS CID sha256 digest (optional, bytes32(0) valid)
     * @param managers        initial manager addresses (auto-adds msg.sender)
     * @param createHats      hat IDs allowed to CREATE tasks in this project
     * @param claimHats       hat IDs allowed to CLAIM
     * @param reviewHats      hat IDs allowed to REVIEW / COMPLETE / UPDATE
     * @param assignHats      hat IDs allowed to ASSIGN tasks
     */
    function createProject(
        bytes calldata title,
        bytes32 metadataHash,
        uint256 cap,
        address[] calldata managers,
        uint256[] calldata createHats,
        uint256[] calldata claimHats,
        uint256[] calldata reviewHats,
        uint256[] calldata assignHats
    ) external returns (bytes32 projectId) {
        _requireCreator();
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidCapAmount(cap);

        Layout storage l = _layout();
        projectId = bytes32(uint256(l.nextProjectId++));
        Project storage p = l._projects[projectId];
        p.cap = uint128(cap);
        p.exists = true;

        /* managers */
        p.managers[_msgSender()] = true;
        emit ProjectManagerUpdated(projectId, _msgSender(), true);
        for (uint256 i; i < managers.length;) {
            managers[i].requireNonZeroAddress();
            p.managers[managers[i]] = true;
            emit ProjectManagerUpdated(projectId, managers[i], true);
            unchecked {
                ++i;
            }
        }

        /* hat-permission matrix */
        _setBatchHatPerm(projectId, createHats, TaskPerm.CREATE);
        _setBatchHatPerm(projectId, claimHats, TaskPerm.CLAIM);
        _setBatchHatPerm(projectId, reviewHats, TaskPerm.REVIEW);
        _setBatchHatPerm(projectId, assignHats, TaskPerm.ASSIGN);

        emit ProjectCreated(projectId, title, metadataHash, cap);
    }

    function deleteProject(bytes32 pid) external {
        _requireCreator();
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        delete l._projects[pid];
        emit ProjectDeleted(pid);
    }

    /*──────── Task Logic ───────*/
    function createTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication
    ) external {
        _requireCanCreate(pid);
        _createTask(payout, title, metadataHash, pid, requiresApplication, bountyToken, bountyPayout);
    }

    function _createTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal {
        Layout storage l = _layout();
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidPayout96(payout);
        ValidationLib.requireValidBountyConfig(bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        // Update participation token budget
        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check and update bounty budget if applicable
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        uint48 id = l.nextTaskId++;
        l._tasks[id] = Task(
            pid, uint96(payout), address(0), uint96(bountyPayout), requiresApplication, Status.UNCLAIMED, bountyToken
        );
        emit TaskCreated(id, pid, payout, bountyToken, bountyPayout, requiresApplication, title, metadataHash);
    }

    function updateTask(
        uint256 id,
        uint256 newPayout,
        bytes calldata newTitle,
        bytes32 newMetadataHash,
        address newBountyToken,
        uint256 newBountyPayout
    ) external {
        _requireCanCreate(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        ValidationLib.requireValidTitle(newTitle);
        ValidationLib.requireValidPayout96(newPayout);
        ValidationLib.requireValidBountyConfig(newBountyToken, newBountyPayout);

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        Project storage p = l._projects[t.projectId];

        // Update participation token budget
        uint256 tentative = p.spent - t.payout + newPayout;
        if (p.cap != 0 && tentative > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(tentative);

        // Update bounty budgets
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            BudgetLib.Budget storage oldB = p.bountyBudgets[t.bountyToken];
            oldB.subtractSpent(t.bountyPayout);
        }

        if (newBountyToken != address(0) && newBountyPayout > 0) {
            BudgetLib.Budget storage newB = p.bountyBudgets[newBountyToken];
            newB.addSpent(newBountyPayout);
        }

        // Update task
        t.payout = uint96(newPayout);
        t.bountyToken = newBountyToken;
        t.bountyPayout = uint96(newBountyPayout);

        emit TaskUpdated(id, newPayout, newBountyToken, newBountyPayout, newTitle, newMetadataHash);
    }

    function claimTask(uint256 id) external {
        _requireCanClaim(id);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        if (t.requiresApplication) revert RequiresApplication();

        t.status = Status.CLAIMED;
        t.claimer = _msgSender();
        emit TaskClaimed(id, _msgSender());
    }

    function assignTask(uint256 id, address assignee) external {
        _requireCanAssign(_layout()._tasks[id].projectId);
        assignee.requireNonZeroAddress();
        Layout storage l = _layout();

        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        t.status = Status.CLAIMED;
        t.claimer = assignee;
        emit TaskAssigned(id, assignee, _msgSender());
    }

    function submitTask(uint256 id, bytes32 submissionHash) external {
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.CLAIMED) revert BadStatus();
        if (t.claimer != _msgSender()) revert NotClaimer();
        if (submissionHash == bytes32(0)) revert ValidationLib.InvalidString();

        t.status = Status.SUBMITTED;
        emit TaskSubmitted(id, submissionHash);
    }

    function completeTask(uint256 id) external {
        Layout storage l = _layout();
        _checkPerm(l._tasks[id].projectId, TaskPerm.REVIEW);
        Task storage t = _task(l, id);
        if (t.status != Status.SUBMITTED) revert BadStatus();

        t.status = Status.COMPLETED;
        l.token.mint(t.claimer, uint256(t.payout));

        // Transfer bounty token if set
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            IERC20(t.bountyToken).safeTransfer(t.claimer, uint256(t.bountyPayout));
        }

        emit TaskCompleted(id, _msgSender());
    }

    function cancelTask(uint256 id) external {
        _requireCanCreate(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();

        Project storage p = l._projects[t.projectId];
        if (p.spent < t.payout) revert BudgetLib.SpentUnderflow();
        unchecked {
            p.spent -= t.payout;
        }

        // Roll back bounty budget if applicable
        if (t.bountyToken != address(0) && t.bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[t.bountyToken];
            bb.subtractSpent(t.bountyPayout);
        }

        t.status = Status.CANCELLED;
        t.claimer = address(0);

        // Clear all applications - zero out the mapping and delete applicants array
        delete l.taskApplicants[id];

        emit TaskCancelled(id, _msgSender());
    }

    /*──────── Application System ─────*/
    /**
     * @dev Submit application for a task with IPFS hash containing submission
     * @param id Task ID to apply for
     * @param applicationHash IPFS hash of the application/submission
     */
    function applyForTask(uint256 id, bytes32 applicationHash) external {
        _requireCanClaim(id);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        ValidationLib.requireValidApplicationHash(applicationHash);
        if (!t.requiresApplication) revert NoApplicationRequired();

        address applicant = _msgSender();

        // Check if user has already applied
        if (l.taskApplications[id][applicant] != bytes32(0)) revert AlreadyApplied();

        // Add applicant to the list
        l.taskApplicants[id].push(applicant);
        l.taskApplications[id][applicant] = applicationHash;

        emit TaskApplicationSubmitted(id, applicant, applicationHash);
    }

    /**
     * @dev Approve an application, moving task to CLAIMED status
     * @param id Task ID
     * @param applicant Address of the applicant to approve
     */
    function approveApplication(uint256 id, address applicant) external {
        _requireCanAssign(_layout()._tasks[id].projectId);
        Layout storage l = _layout();
        Task storage t = _task(l, id);
        if (t.status != Status.UNCLAIMED) revert BadStatus();
        if (l.taskApplications[id][applicant] == bytes32(0)) revert NotApplicant();

        t.status = Status.CLAIMED;
        t.claimer = applicant;
        delete l.taskApplicants[id];
        emit TaskApplicationApproved(id, applicant, _msgSender());
    }

    /**
     * @dev Creates a task and immediately assigns it to the specified assignee in a single transaction.
     * @param payout The payout amount for the task
     * @param title Task title (required, raw UTF-8)
     * @param metadataHash IPFS CID sha256 digest (optional, bytes32(0) valid)
     * @param pid Project ID
     * @param assignee Address to assign the task to
     * @return taskId The ID of the created task
     */
    function createAndAssignTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address assignee,
        address bountyToken,
        uint256 bountyPayout,
        bool requiresApplication
    ) external returns (uint256 taskId) {
        return _createAndAssignTask(
            payout, title, metadataHash, pid, assignee, requiresApplication, bountyToken, bountyPayout
        );
    }

    function _createAndAssignTask(
        uint256 payout,
        bytes calldata title,
        bytes32 metadataHash,
        bytes32 pid,
        address assignee,
        bool requiresApplication,
        address bountyToken,
        uint256 bountyPayout
    ) internal returns (uint256 taskId) {
        assignee.requireNonZeroAddress();

        Layout storage l = _layout();
        address sender = _msgSender();

        // Check permissions - user must have both CREATE and ASSIGN permissions, or be a project manager
        uint8 userPerms = _permMask(sender, pid);
        bool hasCreateAndAssign = TaskPerm.has(userPerms, TaskPerm.CREATE) && TaskPerm.has(userPerms, TaskPerm.ASSIGN);
        if (!hasCreateAndAssign && !_isPM(pid, sender)) {
            revert Unauthorized();
        }

        // Validation
        ValidationLib.requireValidTitle(title);
        ValidationLib.requireValidPayout96(payout);
        ValidationLib.requireValidBountyConfig(bountyToken, bountyPayout);

        Project storage p = l._projects[pid];
        if (!p.exists) revert NotFound();

        uint256 newSpent = p.spent + payout;
        if (p.cap != 0 && newSpent > p.cap) revert BudgetLib.BudgetExceeded();
        p.spent = uint128(newSpent);

        // Check and update bounty budget if applicable
        if (bountyToken != address(0) && bountyPayout > 0) {
            BudgetLib.Budget storage bb = p.bountyBudgets[bountyToken];
            bb.addSpent(bountyPayout);
        }

        // Create and assign task in one go
        taskId = l.nextTaskId++;
        l._tasks[taskId] =
            Task(pid, uint96(payout), assignee, uint96(bountyPayout), requiresApplication, Status.CLAIMED, bountyToken);

        // Emit events
        emit TaskCreated(taskId, pid, payout, bountyToken, bountyPayout, requiresApplication, title, metadataHash);
        emit TaskAssigned(taskId, assignee, sender);
    }

    /*──────── Config Setter (Optimized) ─────── */
    function setConfig(ConfigKey key, bytes calldata value) external {
        _requireExecutor();
        Layout storage l = _layout();

        if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            newExecutor.requireNonZeroAddress();
            l.executor = newExecutor;
            emit ExecutorUpdated(newExecutor);
            return;
        }

        if (key == ConfigKey.CREATOR_HAT_ALLOWED) {
            (uint256 hat, bool allowed) = abi.decode(value, (uint256, bool));
            HatManager.setHatInArray(l.creatorHatIds, hat, allowed);
            emit HatSet(HatType.CREATOR, hat, allowed);
            return;
        }

        if (key == ConfigKey.ROLE_PERM) {
            (uint256 hatId, uint8 mask) = abi.decode(value, (uint256, uint8));
            l.rolePermGlobal[hatId] = mask;
            HatManager.setHatInArray(l.permissionHatIds, hatId, mask != 0);
            return;
        }

        // Project-related configs - consolidate common logic
        bytes32 pid;
        if (key >= ConfigKey.BOUNTY_CAP) {
            pid = abi.decode(value, (bytes32));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();

            if (key == ConfigKey.BOUNTY_CAP) {
                (, address token, uint256 newCap) = abi.decode(value, (bytes32, address, uint256));
                token.requireNonZeroAddress();
                ValidationLib.requireValidCapAmount(newCap);
                BudgetLib.Budget storage b = p.bountyBudgets[token];
                ValidationLib.requireValidCap(newCap, b.spent);
                uint256 oldCap = b.cap;
                b.cap = uint128(newCap);
                emit BountyCapSet(pid, token, oldCap, newCap);
            } else if (key == ConfigKey.PROJECT_MANAGER) {
                (, address mgr, bool isManager) = abi.decode(value, (bytes32, address, bool));
                mgr.requireNonZeroAddress();
                p.managers[mgr] = isManager;
                emit ProjectManagerUpdated(pid, mgr, isManager);
            } else if (key == ConfigKey.PROJECT_CAP) {
                (, uint256 newCap) = abi.decode(value, (bytes32, uint256));
                ValidationLib.requireValidCapAmount(newCap);
                ValidationLib.requireValidCap(newCap, p.spent);
                uint256 old = p.cap;
                p.cap = uint128(newCap);
                emit ProjectCapUpdated(pid, old, newCap);
            }
        }
    }

    function setProjectRolePerm(bytes32 pid, uint256 hatId, uint8 mask) external {
        _requireCreator();
        _requireProjectExists(pid);
        Layout storage l = _layout();
        l.rolePermProj[pid][hatId] = mask;

        // Track that this hat has permissions (project-specific permissions count too)
        if (mask != 0) {
            HatManager.setHatInArray(l.permissionHatIds, hatId, true);
        } else {
            HatManager.setHatInArray(l.permissionHatIds, hatId, false);
        }

        emit ProjectRolePermSet(pid, hatId, mask);
    }
    /*──────── Internal Perm helpers ─────*/

    function _permMask(address user, bytes32 pid) internal view returns (uint8 m) {
        Layout storage l = _layout();
        uint256 len = l.permissionHatIds.length;
        if (len == 0) return 0;

        // one call instead of N
        address[] memory wearers = new address[](len);
        uint256[] memory hats_ = new uint256[](len);
        for (uint256 i; i < len;) {
            wearers[i] = user;
            hats_[i] = l.permissionHatIds[i];
            unchecked {
                ++i;
            }
        }
        uint256[] memory bal = l.hats.balanceOfBatch(wearers, hats_);

        for (uint256 i; i < len;) {
            if (bal[i] == 0) {
                unchecked {
                    ++i;
                }
                continue; // user doesn't wear it
            }
            uint256 h = hats_[i];
            uint8 mask = l.rolePermProj[pid][h];
            m |= mask == 0 ? l.rolePermGlobal[h] : mask; // project overrides global
            unchecked {
                ++i;
            }
        }
    }

    function _isPM(bytes32 pid, address who) internal view returns (bool) {
        Layout storage l = _layout();
        return (who == l.executor) || l._projects[pid].managers[who];
    }

    function _checkPerm(bytes32 pid, uint8 flag) internal view {
        address s = _msgSender();
        if (!TaskPerm.has(_permMask(s, pid), flag) && !_isPM(pid, s)) revert Unauthorized();
    }

    function _setBatchHatPerm(bytes32 pid, uint256[] calldata hatIds, uint8 flag) internal {
        Layout storage l = _layout();
        for (uint256 i; i < hatIds.length;) {
            uint256 hatId = hatIds[i];
            uint8 newMask = l.rolePermProj[pid][hatId] | flag;
            l.rolePermProj[pid][hatId] = newMask;

            // Track that this hat has permissions
            HatManager.setHatInArray(l.permissionHatIds, hatId, true);

            emit ProjectRolePermSet(pid, hatId, newMask);
            unchecked {
                ++i;
            }
        }
    }

    /*──────── Internal Helper Functions ─────────── */
    /// @dev Returns true if `user` wears *any* creator hat.
    function _hasCreatorHat(address user) internal view returns (bool) {
        Layout storage l = _layout();
        return HatManager.hasAnyHat(l.hats, l.creatorHatIds, user);
    }

    /*──────── Utils / View ────*/
    function _task(Layout storage l, uint256 id) private view returns (Task storage t) {
        if (id >= l.nextTaskId) revert NotFound();
        t = l._tasks[id];
    }

    /*──────── Minimal External Getters for Lens ─────── */
    function getLensData(uint8 t, bytes calldata d) external view returns (bytes memory) {
        Layout storage l = _layout();
        if (t == 1) {
            // Task
            uint256 id = abi.decode(d, (uint256));
            if (id >= l.nextTaskId) revert NotFound();
            Task storage task = l._tasks[id];
            return abi.encode(
                task.projectId,
                task.payout,
                task.claimer,
                task.bountyPayout,
                task.requiresApplication,
                task.status,
                task.bountyToken
            );
        } else if (t == 2) {
            // Project
            bytes32 pid = abi.decode(d, (bytes32));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();
            return abi.encode(p.cap, p.spent, p.exists);
        } else if (t == 3) {
            // Hats
            return abi.encode(address(l.hats));
        } else if (t == 4) {
            // Executor
            return abi.encode(l.executor);
        } else if (t == 5) {
            // CreatorHats
            return abi.encode(HatManager.getHatArray(l.creatorHatIds));
        } else if (t == 6) {
            // PermissionHats
            return abi.encode(HatManager.getHatArray(l.permissionHatIds));
        } else if (t == 7) {
            // TaskApplicants
            uint256 id = abi.decode(d, (uint256));
            return abi.encode(l.taskApplicants[id]);
        } else if (t == 8) {
            // TaskApplication
            (uint256 id, address applicant) = abi.decode(d, (uint256, address));
            return abi.encode(l.taskApplications[id][applicant]);
        } else if (t == 9) {
            // BountyBudget
            (bytes32 pid, address token) = abi.decode(d, (bytes32, address));
            Project storage p = l._projects[pid];
            if (!p.exists) revert NotFound();
            BudgetLib.Budget storage b = p.bountyBudgets[token];
            return abi.encode(b.cap, b.spent);
        }
        revert NotFound();
    }
}

