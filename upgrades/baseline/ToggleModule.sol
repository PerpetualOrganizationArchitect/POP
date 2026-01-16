// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19 ^0.8.20;

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

// src/ToggleModule.sol

/**
 * @title ToggleModule
 * @notice A module for toggling Hats active or inactive.
 *
 *         The Hats Protocol calls getHatStatus(uint256) and expects a uint256:
 *         1 indicates "active," and 0 indicates "inactive."
 */
contract ToggleModule is Initializable {
    /*═══════════════════════════════════════════ ERRORS ═══════════════════════════════════════════*/

    error NotToggleAdmin();
    error ZeroAddress();

    /*═════════════════════════════════════ ERC-7201 STORAGE ═════════════════════════════════════*/

    /// @custom:storage-location erc7201:poa.togglemodule.storage
    struct Layout {
        /// @notice The admin who can toggle hat status
        address admin;
        /// @notice The eligibility module address that can also toggle hat status
        address eligibilityModule;
        /// @notice Whether each hat is active or not
        /// @dev hatId => bool (true = active, false = inactive)
        mapping(uint256 => bool) hatActive;
    }

    // keccak256("poa.togglemodule.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x48a7efb8656f02a8591e22e17dff92b9ee0d73547a5595fbb83f382a43ba28cf;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /// @notice Emitted when a hat's status is toggled
    event HatToggled(uint256 indexed hatId, bool newStatus);

    /// @notice Emitted when admin is transferred
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Emitted when the module is initialized
    event ToggleModuleInitialized(address indexed admin);

    /**
     * @notice Initialize the module with admin
     * @param _admin The admin address
     */
    function initialize(address _admin) external initializer {
        if (_admin == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        l.admin = _admin;
        emit ToggleModuleInitialized(_admin);
    }

    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Restricts certain calls so only the admin or eligibility module can perform them
     */
    modifier onlyAdmin() {
        Layout storage l = _layout();
        if (msg.sender != l.admin && msg.sender != l.eligibilityModule) revert NotToggleAdmin();
        _;
    }

    /**
     * @notice Sets an individual hat's active status
     * @param hatId The ID of the hat being toggled
     * @param _active Whether this hat is active (true) or inactive (false)
     */
    function setHatStatus(uint256 hatId, bool _active) external onlyAdmin {
        Layout storage l = _layout();
        l.hatActive[hatId] = _active;
        emit HatToggled(hatId, _active);
    }

    /**
     * @notice Batch set multiple hats' active status
     * @dev Sets status for multiple hats in a single call - gas optimized for HatsTreeSetup
     * @param hatIds Array of hat IDs to toggle
     * @param actives Array of active statuses (must match hatIds length)
     */
    function batchSetHatStatus(uint256[] calldata hatIds, bool[] calldata actives) external onlyAdmin {
        uint256 length = hatIds.length;
        require(length == actives.length, "Array length mismatch");

        Layout storage l = _layout();

        unchecked {
            for (uint256 i; i < length; ++i) {
                l.hatActive[hatIds[i]] = actives[i];
                emit HatToggled(hatIds[i], actives[i]);
            }
        }
    }

    /**
     * @notice The Hats Protocol calls this function to determine if `hatId` is active.
     * @param hatId The ID of the hat being checked
     * @return status 1 if active, 0 if inactive
     */
    function getHatStatus(uint256 hatId) external view returns (uint256 status) {
        // Return 1 for active, 0 for inactive
        return _layout().hatActive[hatId] ? 1 : 0;
    }

    /**
     * @notice Transfer admin rights of this module to a new admin
     * @param newAdmin The new admin address
     */
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        Layout storage l = _layout();
        address oldAdmin = l.admin;
        l.admin = newAdmin;
        emit AdminTransferred(oldAdmin, newAdmin);
    }

    /**
     * @notice Set the eligibility module address that can also toggle hat status
     * @param _eligibilityModule The eligibility module address
     */
    function setEligibilityModule(address _eligibilityModule) external {
        Layout storage l = _layout();
        // Only allow admin to set this, but don't use the modifier since eligibility module might not be set yet
        if (msg.sender != l.admin) revert NotToggleAdmin();
        l.eligibilityModule = _eligibilityModule;
    }

    /**
     * @notice Get the current admin address
     * @return admin The admin address
     */
    function admin() external view returns (address) {
        return _layout().admin;
    }

    /**
     * @notice Check if a hat is active
     * @param hatId The hat ID to check
     * @return active Whether the hat is active
     */
    function hatActive(uint256 hatId) external view returns (bool) {
        return _layout().hatActive[hatId];
    }
}

