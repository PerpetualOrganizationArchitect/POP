// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title SwitchableBeacon
 * @notice A beacon that can switch between mirroring a global beacon and using a static implementation.
 * @dev Enables organizations to toggle between auto-upgrading (following POA global beacons)
 *      and pinned mode (using a fixed implementation) without redeploying proxies.
 *
 *      Three sovereignty tiers:
 *        1. Mirror mode  – org auto-follows the POA global beacon (latest version).
 *        2. Static mode   – org pins to a specific implementation and votes to upgrade.
 *        3. Custom beacon – org calls setMirror() with their own beacon for full custody.
 */
contract SwitchableBeacon is IBeacon, Ownable2Step {
    enum Mode {
        Mirror, // Follow the global beacon's implementation
        Static // Use a pinned implementation
    }

    /*──────────── Storage ─────────────*/

    /// @notice The global POA beacon to mirror when in Mirror mode
    address public mirrorBeacon;

    /// @notice The pinned implementation address when in Static mode
    address public staticImplementation;

    /// @notice Current operational mode of the beacon
    Mode public mode;

    /*──────────── Events ──────────────*/

    event ModeChanged(Mode mode);
    event MirrorSet(address indexed mirrorBeacon);
    event Pinned(address indexed implementation);

    /*──────────── Errors ──────────────*/

    error ImplNotSet();
    error NotContract();
    error CannotRenounce();

    /*──────────── Constructor ─────────*/

    /**
     * @notice Constructs a new SwitchableBeacon.
     * @param _owner The initial owner of the beacon (typically the Executor).
     * @param _mirrorBeacon The POA global beacon to mirror when in Mirror mode.
     * @param _staticImpl The static implementation when in Static mode (can be address(0) if starting in Mirror mode).
     * @param _mode The initial mode of operation.
     */
    constructor(address _owner, address _mirrorBeacon, address _staticImpl, Mode _mode) Ownable(_owner) {
        if (_mirrorBeacon == address(0) || _mirrorBeacon.code.length == 0) revert NotContract();

        if (_mode == Mode.Static) {
            if (_staticImpl == address(0)) revert ImplNotSet();
            if (_staticImpl.code.length == 0) revert NotContract();
        }

        mirrorBeacon = _mirrorBeacon;
        staticImplementation = _staticImpl;
        mode = _mode;

        emit ModeChanged(_mode);
    }

    /*══════════════════ Ownership Safety ══════════════════*/

    /// @dev Ownership cannot be renounced — losing it bricks the beacon permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*══════════════════ IBeacon ══════════════════*/

    /// @notice Returns the current implementation address based on the beacon's mode.
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

    /*══════════════════ Mode Switching ══════════════════*/

    /// @notice Switch to Mirror mode, following the given beacon.
    /// @param _mirrorBeacon The beacon to mirror (can be the POA global beacon or a custom one).
    function setMirror(address _mirrorBeacon) external onlyOwner {
        if (_mirrorBeacon == address(0) || _mirrorBeacon.code.length == 0) revert NotContract();

        address impl = IBeacon(_mirrorBeacon).implementation();
        if (impl == address(0)) revert ImplNotSet();
        if (impl.code.length == 0) revert NotContract();

        mirrorBeacon = _mirrorBeacon;
        mode = Mode.Mirror;

        emit MirrorSet(_mirrorBeacon);
        emit ModeChanged(Mode.Mirror);
    }

    /// @notice Pin the beacon to a specific implementation address.
    function pin(address impl) public onlyOwner {
        if (impl == address(0) || impl.code.length == 0) revert NotContract();

        staticImplementation = impl;
        mode = Mode.Static;

        emit Pinned(impl);
        emit ModeChanged(Mode.Static);
    }

    /// @notice Pin the beacon to the current implementation of the mirror beacon.
    function pinToCurrent() external onlyOwner {
        address impl = IBeacon(mirrorBeacon).implementation();
        if (impl == address(0)) revert ImplNotSet();
        pin(impl);
    }

    /*══════════════════ Views ══════════════════*/

    /// @notice Gets the current implementation without reverting.
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
