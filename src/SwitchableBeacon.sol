// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBeacon {
    function implementation() external view returns (address);
}

/**
 * @title SwitchableBeacon
 * @notice A beacon implementation that can switch between mirroring a global beacon and using a static implementation
 * @dev This contract enables organizations to toggle between auto-upgrading (following POA global beacons)
 *      and pinned mode (using a fixed implementation) without redeploying proxies
 * @custom:security-contact security@poa.org
 */
contract SwitchableBeacon is IBeacon {
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
            address impl = IBeacon(mirrorBeacon).implementation();
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
        address impl = IBeacon(_mirrorBeacon).implementation();
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
        address impl = IBeacon(mirrorBeacon).implementation();
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
            try IBeacon(mirrorBeacon).implementation() returns (address mirrorImpl) {
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
