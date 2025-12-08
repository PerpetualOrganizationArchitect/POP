// SPDX-License-Identifier: MIT
pragma solidity >=0.4.16 >=0.8.13 ^0.8.20 ^0.8.30;

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

// src/libs/VotingErrors.sol

library VotingErrors {
    error Unauthorized();
    error AlreadyVoted();
    error InvalidProposal();
    error VotingExpired();
    error VotingOpen();
    error InvalidIndex();
    error LengthMismatch();
    error DurationOutOfRange();
    error TooManyOptions();
    error TooManyCalls();
    error ZeroAddress();
    error InvalidMetadata();
    error RoleNotAllowed();
    error WeightSumNot100(uint256 sum);
    error InvalidWeight();
    error DuplicateIndex();
    error TargetNotAllowed();
    error TargetSelf();
    error InvalidTarget();
    error EmptyBatch();
    error InvalidQuorum();
    error Paused();
    error Overflow();
    error InvalidClassCount();
    error InvalidSliceSum();
    error TooManyClasses();
    error InvalidStrategy();
}

// src/libs/VotingMath.sol

/**
 * @title VotingMath
 * @notice Unified library for all voting calculations and math utilities
 * @dev Pure library combining all voting math operations used across DirectDemocracy, Participation, and Hybrid voting
 */
library VotingMath {
    /* ─────────── Errors ─────────── */
    error InvalidQuorum();
    error InvalidSplit();
    error InvalidMinBalance();
    error MinBalanceNotMet(uint256 required);
    error RoleNotAllowed();
    error DuplicateIndex();
    error InvalidIndex();
    error InvalidWeight();
    error WeightSumNot100(uint256 sum);
    error Overflow();
    error TargetSelf();
    error TargetNotAllowed();
    error LengthMismatch();

    /* ─────────── Constants ─────────── */
    uint256 private constant MAX_UINT256 = type(uint256).max;

    /* ─────────── Structs ─────────── */
    struct Weights {
        uint8[] idxs;
        uint8[] weights;
        uint256 optionsLen;
    }

    /* ─────────── Validation Functions ─────────── */

    /**
     * @notice Validate quorum percentage
     * @param quorum Quorum percentage (1-100)
     */
    function validateQuorum(uint8 quorum) internal pure {
        if (quorum == 0 || quorum > 100) revert InvalidQuorum();
    }

    /**
     * @notice Validate split percentage
     * @param split Split percentage (0-100)
     */
    function validateSplit(uint8 split) internal pure {
        if (split > 100) revert InvalidSplit();
    }

    /**
     * @notice Validate minimum balance
     * @param minBalance Minimum balance required
     */
    function validateMinBalance(uint256 minBalance) internal pure {
        if (minBalance == 0) revert InvalidMinBalance();
    }

    /**
     * @notice Check if balance meets minimum requirement
     * @param balance Current balance
     * @param minBalance Minimum required balance
     */
    function checkMinBalance(uint256 balance, uint256 minBalance) internal pure {
        if (balance < minBalance) revert MinBalanceNotMet(minBalance);
    }

    /* ─────────── Weight Validation (New Struct Version) ─────────── */

    /**
     * @notice Validates weight distribution across options (struct version)
     * @param w Weight struct containing indices, weights, and option count
     * @dev Reverts on: length mismatch, invalid index, duplicate index, weight>100, sum!=100
     */
    function validateWeights(Weights memory w) internal pure {
        uint256 len = w.idxs.length;
        if (len == 0 || len != w.weights.length) revert LengthMismatch();

        uint256 seen;
        uint256 sum;

        unchecked {
            for (uint256 i; i < len; ++i) {
                uint256 ix = w.idxs[i];
                if (ix >= w.optionsLen) revert InvalidIndex();

                uint8 wt = w.weights[i];
                if (wt > 100) revert InvalidWeight();

                if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
                seen |= 1 << ix;

                sum += wt;
            }
        }

        if (sum != 100) revert WeightSumNot100(sum);
    }

    /**
     * @notice Validate weight distribution (legacy version for backward compatibility)
     * @param weights Array of weights
     * @param indices Array of indices
     * @param numOptions Number of options
     * @return sum Total weight sum
     */
    function validateWeights(uint8[] calldata weights, uint8[] calldata indices, uint256 numOptions)
        internal
        pure
        returns (uint256 sum)
    {
        uint256 seen;
        sum = 0;

        for (uint256 i; i < weights.length;) {
            uint8 ix = indices[i];
            if (ix >= numOptions) revert InvalidIndex();
            if ((seen >> ix) & 1 == 1) revert DuplicateIndex();
            seen |= 1 << ix;
            if (weights[i] > 100) revert InvalidWeight();
            sum += weights[i];
            unchecked {
                ++i;
            }
        }

        if (sum != 100) revert WeightSumNot100(sum);
    }

    /* ─────────── Power Calculation Functions ─────────── */

    /**
     * @notice Calculate voting power based on balance and quadratic setting (legacy)
     * @param balance Token balance
     * @param quadratic Whether to use quadratic voting
     * @return power The calculated voting power
     */
    function calculateVotingPower(uint256 balance, bool quadratic) internal pure returns (uint256 power) {
        if (balance == 0) return 0;
        return quadratic ? sqrt(balance) : balance;
    }

    /**
     * @notice Calculate voting power for participation token holders
     * @param bal Token balance
     * @param minBal Minimum balance required
     * @param quadratic Whether to use quadratic voting
     * @return power The calculated voting power
     */
    function powerPT(uint256 bal, uint256 minBal, bool quadratic) internal pure returns (uint256 power) {
        if (bal < minBal) return 0;
        if (!quadratic) return bal;
        return sqrt(bal);
    }

    /**
     * @notice Calculate voting powers for hybrid voting
     * @param hasDemocracyHat Whether voter has democracy hat
     * @param bal Token balance
     * @param minBal Minimum balance required
     * @param quadratic Whether to use quadratic voting
     * @return ddRaw Direct democracy raw power
     * @return ptRaw Participation token raw power
     */
    function powersHybrid(bool hasDemocracyHat, uint256 bal, uint256 minBal, bool quadratic)
        internal
        pure
        returns (uint256 ddRaw, uint256 ptRaw)
    {
        if (hasDemocracyHat) ddRaw = 100; // one unit per eligible voter

        uint256 p = powerPT(bal, minBal, quadratic);
        if (p > 0) ptRaw = p * 100; // match existing scaling
    }

    /**
     * @notice Calculate raw voting power for a voter (legacy)
     * @param hasDemocracyHat Whether voter has democracy hat
     * @param tokenBalance Token balance
     * @param minBalance Minimum required balance
     * @param quadratic Whether to use quadratic voting
     * @return ddRaw Direct democracy raw power
     * @return ptRaw Participation token raw power
     */
    function calculateRawPowers(bool hasDemocracyHat, uint256 tokenBalance, uint256 minBalance, bool quadratic)
        internal
        pure
        returns (uint256 ddRaw, uint256 ptRaw)
    {
        // Direct democracy power (only if has democracy hat)
        ddRaw = hasDemocracyHat ? 100 : 0;

        // Participation token power
        if (tokenBalance < minBalance) {
            ptRaw = 0;
        } else {
            uint256 power = calculateVotingPower(tokenBalance, quadratic);
            ptRaw = power * 100; // raw numerator
        }
    }

    /* ─────────── Accumulation Helpers ─────────── */

    /**
     * @notice Calculate vote deltas for participation token voting
     * @param power Voter's voting power
     * @param idxs Option indices
     * @param weights Vote weights per option
     * @return adds Vote increments per option
     */
    function deltasPT(uint256 power, uint8[] memory idxs, uint8[] memory weights)
        internal
        pure
        returns (uint256[] memory adds)
    {
        uint256 len = idxs.length;
        adds = new uint256[](len);

        unchecked {
            for (uint256 i; i < len; ++i) {
                adds[i] = power * uint256(weights[i]);
            }
        }
    }

    /**
     * @notice Calculate vote deltas for hybrid voting
     * @param ddRaw Direct democracy raw power
     * @param ptRaw Participation token raw power
     * @param idxs Option indices
     * @param weights Vote weights per option
     * @return ddAdds DD vote increments per option
     * @return ptAdds PT vote increments per option
     */
    function deltasHybrid(uint256 ddRaw, uint256 ptRaw, uint8[] memory idxs, uint8[] memory weights)
        internal
        pure
        returns (uint256[] memory ddAdds, uint256[] memory ptAdds)
    {
        uint256 len = idxs.length;
        ddAdds = new uint256[](len);
        ptAdds = new uint256[](len);

        unchecked {
            for (uint256 i; i < len; ++i) {
                ddAdds[i] = (ddRaw * weights[i]) / 100;
                ptAdds[i] = (ptRaw * weights[i]) / 100;
            }
        }
    }

    /* ─────────── Winner & Quorum Functions ─────────── */

    /**
     * @notice Check if a proposal meets quorum requirements (legacy)
     * @param highestVote Highest vote count
     * @param secondHighest Second highest vote count
     * @param totalWeight Total voting weight
     * @param quorumPercentage Required quorum percentage
     * @return valid Whether the proposal meets quorum
     */
    function meetsQuorum(uint256 highestVote, uint256 secondHighest, uint256 totalWeight, uint8 quorumPercentage)
        internal
        pure
        returns (bool valid)
    {
        return (highestVote * 100 >= totalWeight * quorumPercentage) && (highestVote > secondHighest);
    }

    /**
     * @notice Determine winner using majority rules
     * @param optionScores Per-option vote totals
     * @param totalWeight Total voting weight (e.g., sum power or voters*100)
     * @param quorumPct Required quorum percentage (1-100)
     * @param requireStrictMajority Whether winner must strictly exceed second place
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest score
     * @return second Second highest score
     */
    function pickWinnerMajority(
        uint256[] memory optionScores,
        uint256 totalWeight,
        uint8 quorumPct,
        bool requireStrictMajority
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        uint256 len = optionScores.length;

        for (uint256 i; i < len; ++i) {
            uint256 v = optionScores[i];
            if (v > hi) {
                second = hi;
                hi = v;
                win = i;
            } else if (v > second) {
                second = v;
            }
        }

        if (hi == 0) return (win, false, hi, second);

        // Quorum check: hi * 100 > totalWeight * quorumPct
        bool quorumMet = (hi * 100 > totalWeight * quorumPct);
        bool meetsMargin = requireStrictMajority ? (hi > second) : (hi >= second);

        ok = quorumMet && meetsMargin;
    }

    /**
     * @notice Determine winner for hybrid two-slice voting
     * @param ddRaw Per-option direct democracy raw votes
     * @param ptRaw Per-option participation token raw votes
     * @param ddTotalRaw Total DD raw votes
     * @param ptTotalRaw Total PT raw votes
     * @param ddSharePct DD share percentage (e.g., 50 = 50%)
     * @param quorumPct Required quorum percentage (1-100)
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest combined score
     * @return second Second highest combined score
     */
    function pickWinnerTwoSlice(
        uint256[] memory ddRaw,
        uint256[] memory ptRaw,
        uint256 ddTotalRaw,
        uint256 ptTotalRaw,
        uint8 ddSharePct,
        uint8 quorumPct
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        if (ddTotalRaw == 0 && ptTotalRaw == 0) return (0, false, 0, 0);

        uint256 len = ddRaw.length;
        uint256 sliceDD = ddSharePct; // out of 100
        uint256 slicePT = 100 - ddSharePct;

        for (uint256 i; i < len; ++i) {
            uint256 sDD = (ddTotalRaw == 0) ? 0 : (ddRaw[i] * sliceDD) / ddTotalRaw;
            uint256 sPT = (ptTotalRaw == 0) ? 0 : (ptRaw[i] * slicePT) / ptTotalRaw;
            uint256 tot = sDD + sPT; // both scaled to [0..100]

            if (tot > hi) {
                second = hi;
                hi = tot;
                win = i;
            } else if (tot > second) {
                second = tot;
            }
        }

        // Quorum interpreted on the final scaled total (max 100)
        // Requires strict margin for hybrid voting
        ok = (hi > second) && (hi >= quorumPct);
    }

    /**
     * @notice Determine winner for N-class voting
     * @param perOptionPerClassRaw [option][class] raw vote matrix
     * @param totalsRaw [class] total raw votes per class
     * @param slices [class] slice percentages (must sum to 100)
     * @param quorumPct Required quorum percentage (1-100)
     * @param strict Whether to require strict majority (winner > second)
     * @return win Winning option index
     * @return ok Whether quorum is met and winner is valid
     * @return hi Highest combined score
     * @return second Second highest combined score
     */
    function pickWinnerNSlices(
        uint256[][] memory perOptionPerClassRaw,
        uint256[] memory totalsRaw,
        uint8[] memory slices,
        uint8 quorumPct,
        bool strict
    ) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
        uint256 numOptions = perOptionPerClassRaw.length;
        if (numOptions == 0) return (0, false, 0, 0);

        uint256 numClasses = slices.length;

        // Calculate combined scores for each option
        for (uint256 opt; opt < numOptions; ++opt) {
            uint256 score;

            for (uint256 cls; cls < numClasses; ++cls) {
                if (totalsRaw[cls] > 0) {
                    // Calculate this class's contribution to the option's score
                    uint256 classContribution = (perOptionPerClassRaw[opt][cls] * slices[cls]) / totalsRaw[cls];
                    score += classContribution;
                }
            }

            // Track winner and second place
            if (score > hi) {
                second = hi;
                hi = score;
                win = opt;
            } else if (score > second) {
                second = score;
            }
        }

        // Check quorum and margin requirements
        bool quorumMet = hi >= quorumPct;
        bool meetsMargin = strict ? (hi > second) : (hi >= second);
        ok = quorumMet && meetsMargin;
    }

    /**
     * @notice Validate class slices sum to 100
     * @param slices Array of slice percentages
     */
    function validateClassSlices(uint8[] memory slices) internal pure {
        if (slices.length == 0) revert InvalidQuorum();
        uint256 sum;
        for (uint256 i; i < slices.length; ++i) {
            if (slices[i] == 0 || slices[i] > 100) revert InvalidSplit();
            sum += slices[i];
        }
        if (sum != 100) revert InvalidSplit();
    }

    /* ─────────── Math Utilities ─────────── */

    /**
     * @notice Calculate square root using optimized assembly
     * @param x Input value
     * @return y Square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        if (x <= 3) return 1;

        // Calculate the square root using the Babylonian method
        // with overflow protection
        unchecked {
            y = x;
            uint256 z = (x + 1) / 2;
            while (z < y) {
                y = z;
                z = (x / z + z) / 2;
            }
        }
    }

    /**
     * @notice Check for overflow in uint128
     * @param value Value to check
     */
    function checkOverflow(uint256 value) internal pure {
        if (value > type(uint128).max) revert Overflow();
    }

    /**
     * @notice Check if value fits in uint128
     * @param value Value to check
     * @return Whether value fits in uint128
     */
    function fitsUint128(uint256 value) internal pure returns (bool) {
        return value <= type(uint128).max;
    }

    /**
     * @notice Check if value fits in uint96
     * @param value Value to check
     * @return Whether value fits in uint96
     */
    function fitsUint96(uint256 value) internal pure returns (bool) {
        return value <= type(uint96).max;
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

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

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

// lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /// @custom:storage-location erc7201:openzeppelin.storage.Pausable
    struct PausableStorage {
        bool _paused;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.Pausable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PausableStorageLocation = 0xcd5ed15c6e187e77e9aee88184c21f4f2182ab5827cb3b7e07fbedcd63f03300;

    function _getPausableStorage() private pure returns (PausableStorage storage $) {
        assembly {
            $.slot := PausableStorageLocation
        }
    }

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal onlyInitializing {
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal onlyInitializing {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        PausableStorage storage $ = _getPausableStorage();
        return $._paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        PausableStorage storage $ = _getPausableStorage();
        $._paused = false;
        emit Unpaused(_msgSender());
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

// src/Executor.sol
// SPDX‑License‑Identifier: MIT

/* OpenZeppelin v5.3 Upgradeables */

interface IExecutor {
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    function execute(uint256 proposalId, Call[] calldata batch) external;
}

/**
 * @title Executor
 * @notice Batch‑executor behind an UpgradeableBeacon.
 *         Exactly **one** governor address is authorised to trigger `execute`.
 */
contract Executor is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IExecutor {
    /* ─────────── Errors ─────────── */
    error UnauthorizedCaller();
    error CallFailed(uint256 index, bytes lowLevelData);
    error EmptyBatch();
    error TooManyCalls();
    error TargetSelf();
    error ZeroAddress();

    /* ─────────── Constants ─────────── */
    uint8 public constant MAX_CALLS_PER_BATCH = 20;

    /* ─────────── ERC-7201 Storage ─────────── */
    /// @custom:storage-location erc7201:poa.executor.storage
    struct Layout {
        address allowedCaller; // sole authorised governor
        IHats hats; // Hats Protocol interface
        mapping(address => bool) authorizedHatMinters; // contracts authorized to request hat minting
    }

    // keccak256("poa.executor.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x4a2328a3c3b056def98e04ebb0cc7ccc084886f7998dd0a6d16fd24be55ffa5d;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────────── Events ─────────── */
    event CallerSet(address indexed caller);
    event BatchExecuted(uint256 indexed proposalId, uint256 calls);
    event CallExecuted(uint256 indexed proposalId, uint256 indexed index, address target, uint256 value);
    event Swept(address indexed to, uint256 amount);
    event HatsSet(address indexed hats);
    event HatMinterAuthorized(address indexed minter, bool authorized);
    event HatsMinted(address indexed user, uint256[] hatIds);

    /* ─────────── Initialiser ─────────── */
    function initialize(address owner_, address hats_) external initializer {
        if (owner_ == address(0) || hats_ == address(0)) revert ZeroAddress();
        __Ownable_init(owner_);
        __Pausable_init();
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        emit HatsSet(hats_);
    }

    /* ─────────── Governor management ─────────── */
    function setCaller(address newCaller) external {
        if (newCaller == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        if (l.allowedCaller != address(0)) {
            // After first set, only current caller or owner can change
            if (msg.sender != l.allowedCaller && msg.sender != owner()) revert UnauthorizedCaller();
        }
        l.allowedCaller = newCaller;
        emit CallerSet(newCaller);
    }

    /* ─────────── Hat minting management ─────────── */
    function setHatMinterAuthorization(address minter, bool authorized) external {
        if (minter == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        // Only owner or allowed caller can set authorizations
        if (msg.sender != owner() && msg.sender != l.allowedCaller) revert UnauthorizedCaller();
        l.authorizedHatMinters[minter] = authorized;
        emit HatMinterAuthorized(minter, authorized);
    }

    function mintHatsForUser(address user, uint256[] calldata hatIds) external {
        Layout storage l = _layout();
        if (!l.authorizedHatMinters[msg.sender]) revert UnauthorizedCaller();
        if (user == address(0)) revert ZeroAddress();

        // Mint each hat to the user
        for (uint256 i = 0; i < hatIds.length; i++) {
            l.hats.mintHat(hatIds[i], user);
        }

        emit HatsMinted(user, hatIds);
    }

    /* ─────────── Batch execution ─────────── */
    function execute(uint256 proposalId, Call[] calldata batch) external override whenNotPaused nonReentrant {
        if (msg.sender != _layout().allowedCaller) revert UnauthorizedCaller();
        uint256 len = batch.length;
        if (len == 0) revert EmptyBatch();
        if (len > MAX_CALLS_PER_BATCH) revert TooManyCalls();

        for (uint256 i; i < len;) {
            if (batch[i].target == address(this)) revert TargetSelf();

            (bool ok, bytes memory ret) = batch[i].target.call{value: batch[i].value}(batch[i].data);
            if (!ok) revert CallFailed(i, ret);

            emit CallExecuted(proposalId, i, batch[i].target, batch[i].value);
            unchecked {
                ++i;
            }
        }
        emit BatchExecuted(proposalId, len);
    }

    /* ─────────── Guardian helpers ─────────── */
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ─────────── ETH recovery ─────────── */
    function sweep(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = address(this).balance;
        to.transfer(bal);
        emit Swept(to, bal);
    }

    /* ─────────── Module Configuration ─────────── */
    /**
     * @notice Configure vouching on EligibilityModule during initial setup
     * @dev Only callable by owner before renouncing ownership
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatId Hat ID to configure vouching for
     * @param quorum Number of vouches required
     * @param membershipHatId Hat ID whose wearers can vouch
     * @param combineWithHierarchy Whether to combine with parent hat eligibility
     */
    function configureVouching(
        address eligibilityModule,
        uint256 hatId,
        uint32 quorum,
        uint256 membershipHatId,
        bool combineWithHierarchy
    ) external onlyOwner {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature(
                "configureVouching(uint256,uint32,uint256,bool)", hatId, quorum, membershipHatId, combineWithHierarchy
            )
        );
        require(success, "configureVouching failed");
    }

    /**
     * @notice Batch configure vouching for multiple hats during initial setup
     * @dev Only callable by owner before renouncing ownership - gas optimized for org deployment
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatIds Array of hat IDs to configure
     * @param quorums Array of quorum values
     * @param membershipHatIds Array of membership hat IDs
     * @param combineWithHierarchyFlags Array of combine flags
     */
    function batchConfigureVouching(
        address eligibilityModule,
        uint256[] calldata hatIds,
        uint32[] calldata quorums,
        uint256[] calldata membershipHatIds,
        bool[] calldata combineWithHierarchyFlags
    ) external onlyOwner {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature(
                "batchConfigureVouching(uint256[],uint32[],uint256[],bool[])",
                hatIds,
                quorums,
                membershipHatIds,
                combineWithHierarchyFlags
            )
        );
        require(success, "batchConfigureVouching failed");
    }

    /**
     * @notice Set default eligibility for a hat during initial setup
     * @dev Only callable by owner before renouncing ownership
     * @param eligibilityModule Address of the EligibilityModule
     * @param hatId Hat ID to set default eligibility for
     * @param eligible Whether wearers are eligible by default
     * @param standing Whether wearers have good standing by default
     */
    function setDefaultEligibility(address eligibilityModule, uint256 hatId, bool eligible, bool standing)
        external
        onlyOwner
    {
        if (eligibilityModule == address(0)) revert ZeroAddress();
        (bool success,) = eligibilityModule.call(
            abi.encodeWithSignature("setDefaultEligibility(uint256,bool,bool)", hatId, eligible, standing)
        );
        require(success, "setDefaultEligibility failed");
    }

    /* ─────────── View Helpers ─────────── */
    function allowedCaller() external view returns (address) {
        return _layout().allowedCaller;
    }

    /* accept ETH for payable calls within a batch */
    receive() external payable {}
}

// src/libs/HybridVotingConfig.sol

library HybridVotingConfig {
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    uint8 public constant MAX_CLASSES = 8;

    event ClassesReplaced(
        uint256 indexed version, bytes32 indexed classesHash, HybridVoting.ClassConfig[] classes, uint64 timestamp
    );

    function _layout() private pure returns (HybridVoting.Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    function setClasses(HybridVoting.ClassConfig[] calldata newClasses) external {
        if (newClasses.length == 0) revert VotingErrors.InvalidClassCount();
        if (newClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();

        uint256 totalSlice;
        for (uint256 i; i < newClasses.length;) {
            HybridVoting.ClassConfig calldata c = newClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;

            if (c.strategy == HybridVoting.ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }
            unchecked {
                ++i;
            }
        }

        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();

        HybridVoting.Layout storage l = _layout();
        delete l.classes;
        for (uint256 i; i < newClasses.length;) {
            l.classes.push(newClasses[i]);
            unchecked {
                ++i;
            }
        }

        bytes32 classesHash = keccak256(abi.encode(newClasses));
        emit ClassesReplaced(block.number, classesHash, l.classes, uint64(block.timestamp));
    }

    function validateAndInitClasses(HybridVoting.ClassConfig[] calldata initialClasses) external {
        if (initialClasses.length == 0) revert VotingErrors.InvalidClassCount();
        if (initialClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();

        uint256 totalSlice;
        for (uint256 i; i < initialClasses.length;) {
            HybridVoting.ClassConfig calldata c = initialClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;

            if (c.strategy == HybridVoting.ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }

            _layout().classes.push(initialClasses[i]);
            unchecked {
                ++i;
            }
        }

        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();

        HybridVoting.Layout storage l = _layout();
        bytes32 classesHash = keccak256(abi.encode(l.classes));
        emit ClassesReplaced(block.number, classesHash, l.classes, uint64(block.timestamp));
    }
}

// src/libs/HybridVotingCore.sol

library HybridVotingCore {
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    event VoteCast(
        uint256 indexed id,
        address indexed voter,
        uint8[] idxs,
        uint8[] weights,
        uint256[] classRawPowers,
        uint64 timestamp
    );
    event Winner(uint256 indexed id, uint256 indexed winningIdx, bool valid, bool executed, uint64 timestamp);
    event ProposalExecuted(uint256 indexed id, uint256 indexed winningIdx, uint256 numCalls);

    function _layout() private pure returns (HybridVoting.Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights) external {
        if (idxs.length != weights.length) revert VotingErrors.LengthMismatch();
        if (block.timestamp > _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingExpired();

        HybridVoting.Layout storage l = _layout();
        HybridVoting.Proposal storage p = l._proposals[id];
        address voter = msg.sender;

        // Check poll-level restrictions
        if (p.restricted) {
            bool hasAllowedHat = false;
            uint256 len = p.pollHatIds.length;
            for (uint256 i = 0; i < len;) {
                if (l.hats.isWearerOfHat(voter, p.pollHatIds[i])) {
                    hasAllowedHat = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
            if (!hasAllowedHat) revert VotingErrors.RoleNotAllowed();
        }

        if (p.hasVoted[voter]) revert VotingErrors.AlreadyVoted();

        // Validate weights
        VotingMath.validateWeights(VotingMath.Weights({idxs: idxs, weights: weights, optionsLen: p.options.length}));

        // Calculate raw power for each class
        uint256 classCount = p.classesSnapshot.length;
        uint256[] memory classRawPowers = new uint256[](classCount);

        for (uint256 c; c < classCount;) {
            HybridVoting.ClassConfig memory cls = p.classesSnapshot[c];
            uint256 rawPower = _calculateClassPower(voter, cls, l);
            classRawPowers[c] = rawPower;
            p.classTotalsRaw[c] += rawPower;
            unchecked {
                ++c;
            }
        }

        // Accumulate deltas for each option
        uint256 len2 = weights.length;
        for (uint256 i; i < len2;) {
            uint8 ix = idxs[i];
            uint8 weight = weights[i];

            for (uint256 c; c < classCount;) {
                if (classRawPowers[c] > 0) {
                    uint256 delta = (classRawPowers[c] * weight) / 100;
                    if (delta > 0) {
                        uint256 newVal = p.options[ix].classRaw[c] + delta;
                        require(VotingMath.fitsUint128(newVal), "Class raw overflow");
                        p.options[ix].classRaw[c] = uint128(newVal);
                    }
                }
                unchecked {
                    ++c;
                }
            }
            unchecked {
                ++i;
            }
        }

        p.hasVoted[voter] = true;
        emit VoteCast(id, voter, idxs, weights, classRawPowers, uint64(block.timestamp));
    }

    function _calculateClassPower(address voter, HybridVoting.ClassConfig memory cls, HybridVoting.Layout storage l)
        internal
        view
        returns (uint256)
    {
        // Check hat gating for this class
        bool hasClassHat = (voter == address(l.executor)) || (cls.hatIds.length == 0);

        // Check if voter has any of the class hats
        if (!hasClassHat && cls.hatIds.length > 0) {
            for (uint256 i; i < cls.hatIds.length;) {
                if (l.hats.isWearerOfHat(voter, cls.hatIds[i])) {
                    hasClassHat = true;
                    break;
                }
                unchecked {
                    ++i;
                }
            }
        }

        if (!hasClassHat) return 0;

        if (cls.strategy == HybridVoting.ClassStrategy.DIRECT) {
            return 100; // Direct democracy: 1 person = 100 raw points
        } else if (cls.strategy == HybridVoting.ClassStrategy.ERC20_BAL) {
            uint256 balance = IERC20(cls.asset).balanceOf(voter);
            if (balance < cls.minBalance) return 0;
            uint256 power = cls.quadratic ? VotingMath.sqrt(balance) : balance;
            return power * 100; // Scale to match existing system
        }

        return 0;
    }

    function announceWinner(uint256 id) external returns (uint256 winner, bool valid) {
        HybridVoting.Layout storage l = _layout();
        HybridVoting.Proposal storage p = l._proposals[id];

        // Check if any votes were cast
        bool hasVotes = false;
        for (uint256 i; i < p.classTotalsRaw.length;) {
            if (p.classTotalsRaw[i] > 0) {
                hasVotes = true;
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (!hasVotes) {
            emit Winner(id, 0, false, false, uint64(block.timestamp));
            return (0, false);
        }

        // Build matrix for N-class winner calculation
        uint256 numOptions = p.options.length;
        uint256 numClasses = p.classesSnapshot.length;
        uint256[][] memory perOptionPerClassRaw = new uint256[][](numOptions);
        uint8[] memory slices = new uint8[](numClasses);

        for (uint256 opt; opt < numOptions;) {
            perOptionPerClassRaw[opt] = new uint256[](numClasses);
            for (uint256 cls; cls < numClasses;) {
                perOptionPerClassRaw[opt][cls] = p.options[opt].classRaw[cls];
                unchecked {
                    ++cls;
                }
            }
            unchecked {
                ++opt;
            }
        }

        for (uint256 cls; cls < numClasses;) {
            slices[cls] = p.classesSnapshot[cls].slicePct;
            unchecked {
                ++cls;
            }
        }

        // Use VotingMath to pick winner with N-class logic
        (winner, valid,,) = VotingMath.pickWinnerNSlices(
            perOptionPerClassRaw,
            p.classTotalsRaw,
            slices,
            l.quorumPct,
            true // strict majority required
        );

        IExecutor.Call[] storage batch = p.batches[winner];
        bool executed = false;
        if (valid && batch.length > 0) {
            uint256 batchLen = batch.length;
            for (uint256 i; i < batchLen;) {
                if (!l.allowedTarget[batch[i].target]) revert VotingErrors.InvalidTarget();
                unchecked {
                    ++i;
                }
            }
            l.executor.execute(id, batch);
            executed = true;
            emit ProposalExecuted(id, winner, batchLen);
        }
        emit Winner(id, winner, valid, executed, uint64(block.timestamp));
    }
}

// src/libs/HybridVotingProposals.sol

library HybridVotingProposals {
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint32 public constant MAX_DURATION = 43_200;
    uint32 public constant MIN_DURATION = 10;

    event NewProposal(uint256 id, bytes title, bytes32 descriptionHash, uint8 numOptions, uint64 endTs, uint64 created);
    event NewHatProposal(
        uint256 id,
        bytes title,
        bytes32 descriptionHash,
        uint8 numOptions,
        uint64 endTs,
        uint64 created,
        uint256[] hatIds
    );

    function _layout() private pure returns (HybridVoting.Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    function createProposal(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) external {
        uint256 id = _initProposal(title, descriptionHash, minutesDuration, numOptions, batches, hatIds);

        uint64 endTs = _layout()._proposals[id].endTimestamp;

        if (hatIds.length > 0) {
            emit NewHatProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp), hatIds);
        } else {
            emit NewProposal(id, title, descriptionHash, numOptions, endTs, uint64(block.timestamp));
        }
    }

    function _initProposal(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) internal returns (uint256) {
        ValidationLib.requireValidTitle(title);
        if (numOptions == 0) revert VotingErrors.LengthMismatch();
        if (numOptions > MAX_OPTIONS) revert VotingErrors.TooManyOptions();
        _validateDuration(minutesDuration);

        HybridVoting.Layout storage l = _layout();
        if (l.classes.length == 0) revert VotingErrors.InvalidClassCount();

        bool isExecuting = false;
        if (batches.length > 0) {
            if (numOptions != batches.length) revert VotingErrors.LengthMismatch();
            for (uint256 i; i < numOptions;) {
                if (batches[i].length > 0) {
                    isExecuting = true;
                    _validateTargets(batches[i], l);
                }
                unchecked {
                    ++i;
                }
            }
        }

        uint64 endTs = uint64(block.timestamp + minutesDuration * 60);
        HybridVoting.Proposal storage p = l._proposals.push();
        p.endTimestamp = endTs;
        p.restricted = hatIds.length > 0;

        _snapshotClasses(p, l);
        uint256 classCount = l.classes.length;
        _initOptions(p, numOptions, classCount);

        uint256 id = l._proposals.length - 1;

        if (isExecuting) {
            for (uint256 i; i < numOptions;) {
                p.batches.push(batches[i]);
                unchecked {
                    ++i;
                }
            }
        } else {
            for (uint256 i; i < numOptions;) {
                p.batches.push();
                unchecked {
                    ++i;
                }
            }
        }

        if (hatIds.length > 0) {
            uint256 len = hatIds.length;
            for (uint256 i; i < len;) {
                p.pollHatIds.push(hatIds[i]);
                p.pollHatAllowed[hatIds[i]] = true;
                unchecked {
                    ++i;
                }
            }
        }

        return id;
    }

    function _validateDuration(uint32 minutesDuration) internal pure {
        if (minutesDuration < MIN_DURATION || minutesDuration > MAX_DURATION) {
            revert VotingErrors.DurationOutOfRange();
        }
    }

    function _validateTargets(IExecutor.Call[] calldata batch, HybridVoting.Layout storage l) internal view {
        uint256 batchLen = batch.length;
        if (batchLen > MAX_CALLS) revert VotingErrors.TooManyCalls();
        for (uint256 j; j < batchLen;) {
            if (!l.allowedTarget[batch[j].target]) revert VotingErrors.InvalidTarget();
            if (batch[j].target == address(this)) revert VotingErrors.InvalidTarget();
            unchecked {
                ++j;
            }
        }
    }

    function _snapshotClasses(HybridVoting.Proposal storage p, HybridVoting.Layout storage l) internal {
        uint256 classCount = l.classes.length;
        for (uint256 i; i < classCount;) {
            p.classesSnapshot.push(l.classes[i]);
            unchecked {
                ++i;
            }
        }
        p.classTotalsRaw = new uint256[](classCount);
    }

    function _initOptions(HybridVoting.Proposal storage p, uint8 numOptions, uint256 classCount) internal {
        for (uint256 i; i < numOptions;) {
            HybridVoting.PollOption storage opt = p.options.push();
            opt.classRaw = new uint128[](classCount);
            unchecked {
                ++i;
            }
        }
    }
}

// src/HybridVoting.sol

/*  OpenZeppelin v5.3 Upgradeables  */

/* ─────────────────── HybridVoting ─────────────────── */
contract HybridVoting is Initializable {
    /* ─────── Constants ─────── */
    uint8 public constant MAX_OPTIONS = 50;
    uint8 public constant MAX_CALLS = 20;
    uint8 public constant MAX_CLASSES = 8;
    uint32 public constant MAX_DURATION = 43_200; /* 30 days */
    uint32 public constant MIN_DURATION = 1; /* 1 min for testing */

    /* ─────── Data Structures ─────── */

    enum ClassStrategy {
        DIRECT, // 1 person → 100 raw points
        ERC20_BAL // balance (or sqrt) scaled
    }

    struct ClassConfig {
        ClassStrategy strategy; // DIRECT / ERC20_BAL
        uint8 slicePct; // 1..100; all classes must sum to 100
        bool quadratic; // only for token strategies
        uint256 minBalance; // sybil floor for token strategies
        address asset; // ERC20 token (if required)
        uint256[] hatIds; // voter must wear ≥1 (union)
    }

    struct PollOption {
        uint128[] classRaw; // length = classesSnapshot.length
    }

    struct Proposal {
        uint64 endTimestamp;
        uint256[] classTotalsRaw; // Σ raw from each class (len = classesSnapshot.length)
        PollOption[] options; // each option has classRaw[i]
        mapping(address => bool) hasVoted;
        IExecutor.Call[][] batches;
        uint256[] pollHatIds; // array of specific hat IDs for this poll
        bool restricted; // if true only pollHatIds can vote
        mapping(uint256 => bool) pollHatAllowed; // O(1) lookup for poll hat permission
        ClassConfig[] classesSnapshot; // Snapshot the class config to freeze semantics for this proposal
    }

    /* ─────── ERC-7201 Storage ─────── */
    /// @custom:storage-location erc7201:poa.hybridvoting.v2.storage
    struct Layout {
        /* Config / Storage */
        IHats hats;
        IExecutor executor;
        mapping(address => bool) allowedTarget; // execution allow‑list
        uint256[] creatorHatIds; // enumeration array for creator hats
        uint8 quorumPct; // 1‑100
        ClassConfig[] classes; // global N-class configuration
        /* Vote Bookkeeping */
        Proposal[] _proposals;
        /* Inline State */
        bool _paused; // Inline pausable state
        uint256 _lock; // Inline reentrancy guard state
    }

    // keccak256("poa.hybridvoting.v2.storage") → unique, collision-free slot for v2
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ─────────── Inline Context Implementation ─────────── */
    function _msgSender() internal view returns (address addr) {
        assembly {
            addr := caller()
        }
    }

    /* ─────────── Inline Pausable Implementation ─────────── */
    modifier whenNotPaused() {
        _checkNotPaused();
        _;
    }

    function _checkNotPaused() private view {
        if (_layout()._paused) revert VotingErrors.Paused();
    }

    function paused() external view returns (bool) {
        return _layout()._paused;
    }

    function _pause() internal {
        _layout()._paused = true;
    }

    function _unpause() internal {
        _layout()._paused = false;
    }

    /* ─────── Events ─────── */
    event HatSet(HatType hatType, uint256 hat, bool allowed);
    event TargetAllowed(address target, bool allowed);
    event ExecutorUpdated(address newExec);
    event QuorumSet(uint8 pct);

    /* ─────── Initialiser ─────── */
    constructor() initializer {}

    function initialize(
        address hats_,
        address executor_,
        uint256[] calldata initialCreatorHats,
        address[] calldata initialTargets,
        uint8 quorum_,
        ClassConfig[] calldata initialClasses
    ) external initializer {
        if (hats_ == address(0) || executor_ == address(0)) {
            revert VotingErrors.ZeroAddress();
        }

        VotingMath.validateQuorum(quorum_);

        Layout storage l = _layout();
        l.hats = IHats(hats_);
        l.executor = IExecutor(executor_);
        l._paused = false; // Initialize paused state
        l._lock = 0; // Initialize reentrancy guard state

        l.quorumPct = quorum_;
        emit QuorumSet(quorum_);

        // Initialize creator hats and targets
        _initializeCreatorHats(initialCreatorHats);
        _initializeTargets(initialTargets);

        // Use library for class initialization
        HybridVotingConfig.validateAndInitClasses(initialClasses);
    }

    function _initializeCreatorHats(uint256[] calldata creatorHats) internal {
        Layout storage l = _layout();
        uint256 len = creatorHats.length;
        for (uint256 i; i < len;) {
            HatManager.setHatInArray(l.creatorHatIds, creatorHats[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /* ─────── Internal Initialization Helpers ─────── */
    function _initializeTargets(address[] calldata targets) internal {
        Layout storage l = _layout();
        uint256 len = targets.length;
        for (uint256 i; i < len;) {
            l.allowedTarget[targets[i]] = true;
            emit TargetAllowed(targets[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /* ─────── Governance setters (executor‑gated) ─────── */
    modifier onlyExecutor() {
        _checkExecutor();
        _;
    }

    function _checkExecutor() private view {
        if (_msgSender() != address(_layout().executor)) revert VotingErrors.Unauthorized();
    }

    function pause() external onlyExecutor {
        _pause();
    }

    function unpause() external onlyExecutor {
        _unpause();
    }

    /* ─────── Hat Management ─────── */
    function setCreatorHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.creatorHatIds, h, ok);
        emit HatSet(HatType.CREATOR, h, ok);
    }

    enum HatType {
        CREATOR
    }

    /* ─────── N-Class Configuration ─────── */
    function setClasses(ClassConfig[] calldata newClasses) external onlyExecutor {
        HybridVotingConfig.setClasses(newClasses);
    }

    function getClasses() external view returns (ClassConfig[] memory) {
        return _layout().classes;
    }

    function getProposalClasses(uint256 id) external view exists(id) returns (ClassConfig[] memory) {
        return _layout()._proposals[id].classesSnapshot;
    }

    /* ─────── Configuration Setters ─────── */
    enum ConfigKey {
        QUORUM,
        TARGET_ALLOWED,
        EXECUTOR
    }

    function setConfig(ConfigKey key, bytes calldata value) external onlyExecutor {
        Layout storage l = _layout();

        if (key == ConfigKey.QUORUM) {
            uint8 q = abi.decode(value, (uint8));
            VotingMath.validateQuorum(q);
            l.quorumPct = q;
            emit QuorumSet(q);
        } else if (key == ConfigKey.TARGET_ALLOWED) {
            (address target, bool allowed) = abi.decode(value, (address, bool));
            l.allowedTarget[target] = allowed;
            emit TargetAllowed(target, allowed);
        } else if (key == ConfigKey.EXECUTOR) {
            address newExecutor = abi.decode(value, (address));
            if (newExecutor == address(0)) revert VotingErrors.ZeroAddress();
            l.executor = IExecutor(newExecutor);
            emit ExecutorUpdated(newExecutor);
        }
    }

    /* ─────── Helpers & modifiers ─────── */
    modifier onlyCreator() {
        _checkCreator();
        _;
    }

    modifier exists(uint256 id) {
        _checkExists(id);
        _;
    }

    modifier isExpired(uint256 id) {
        _checkExpired(id);
        _;
    }

    function _checkCreator() private view {
        Layout storage l = _layout();
        if (_msgSender() != address(l.executor)) {
            bool canCreate = HatManager.hasAnyHat(l.hats, l.creatorHatIds, _msgSender());
            if (!canCreate) revert VotingErrors.Unauthorized();
        }
    }

    function _checkExists(uint256 id) private view {
        if (id >= _layout()._proposals.length) revert VotingErrors.InvalidProposal();
    }

    function _checkExpired(uint256 id) private view {
        if (block.timestamp <= _layout()._proposals[id].endTimestamp) revert VotingErrors.VotingOpen();
    }

    /* ─────── Proposal creation ─────── */
    function createProposal(
        bytes calldata title,
        bytes32 descriptionHash,
        uint32 minutesDuration,
        uint8 numOptions,
        IExecutor.Call[][] calldata batches,
        uint256[] calldata hatIds
    ) external onlyCreator whenNotPaused {
        HybridVotingProposals.createProposal(title, descriptionHash, minutesDuration, numOptions, batches, hatIds);
    }

    /* ─────── Voting ─────── */
    function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights) external exists(id) whenNotPaused {
        HybridVotingCore.vote(id, idxs, weights);
    }

    /* ─────── Winner & execution ─────── */
    function announceWinner(uint256 id)
        external
        exists(id)
        isExpired(id)
        whenNotPaused
        returns (uint256 winner, bool valid)
    {
        return HybridVotingCore.announceWinner(id);
    }

    /* ─────── Targeted View Functions ─────── */
    function proposalsCount() external view returns (uint256) {
        return _layout()._proposals.length;
    }

    function quorumPct() external view returns (uint8) {
        return _layout().quorumPct;
    }

    function isTargetAllowed(address target) external view returns (bool) {
        return _layout().allowedTarget[target];
    }

    function creatorHats() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().creatorHatIds);
    }

    function pollRestricted(uint256 id) external view exists(id) returns (bool) {
        return _layout()._proposals[id].restricted;
    }

    function pollHatAllowed(uint256 id, uint256 hat) external view exists(id) returns (bool) {
        return _layout()._proposals[id].pollHatAllowed[hat];
    }

    function executor() external view returns (address) {
        return address(_layout().executor);
    }

    function hats() external view returns (address) {
        return address(_layout().hats);
    }
}

