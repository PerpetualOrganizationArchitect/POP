// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IMailbox} from "./interfaces/IHyperlane.sol";
import {PoaManager} from "../PoaManager.sol";

/// @title PoaManagerHub
/// @notice Home-chain wrapper around PoaManager that propagates beacon upgrades
///         to satellite chains via Hyperlane.
/// @dev    Deploy behind a BeaconProxy on the home chain, then transfer PoaManager
///         ownership to this proxy. All admin calls (addContractType, upgradeBeacon)
///         go through the Hub.
contract PoaManagerHub is Initializable, OwnableUpgradeable {
    /*──────────── Types ───────────*/
    struct SatelliteConfig {
        uint32 domain; // Hyperlane domain ID
        bytes32 satellite; // Satellite contract address as bytes32
        bool active;
    }

    /*──────────── Constants ───────────*/
    /// @dev Message type tags for the satellite to distinguish upgrade vs addType
    uint8 internal constant MSG_UPGRADE_BEACON = 0x01;
    uint8 internal constant MSG_ADD_CONTRACT_TYPE = 0x02;

    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.poamanagerhub.storage
    struct Layout {
        PoaManager poaManager;
        IMailbox mailbox;
        SatelliteConfig[] satellites;
        bool paused;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.poamanagerhub.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*──────────── Errors ──────────────*/
    error IsPaused();
    error ZeroAddress();
    error NoActiveSatellites();
    error CannotRenounce();
    error TransferFailed();
    error DuplicateDomain(uint32 domain);

    /*──────────── Events ──────────────*/
    event CrossChainUpgradeDispatched(
        bytes32 indexed typeId, address newImpl, string version, uint32 indexed domain, bytes32 messageId
    );
    event CrossChainAddTypeDispatched(
        bytes32 indexed typeId, string typeName, uint32 indexed domain, bytes32 messageId
    );
    event SatelliteRegistered(uint32 indexed domain, address satellite);
    event SatelliteRemoved(uint32 indexed domain);
    event PauseSet(bool paused);

    /*──────────── Constructor ─────────*/
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _poaManager, address _mailbox) external initializer {
        if (owner == address(0) || _poaManager == address(0) || _mailbox == address(0)) revert ZeroAddress();
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.poaManager = PoaManager(_poaManager);
        s.mailbox = IMailbox(_mailbox);
    }

    /*══════════════════ Upgrade Functions ══════════════════*/

    /// @notice Upgrade a beacon on the home chain AND propagate to all active satellites.
    /// @dev    Send enough ETH to cover Hyperlane protocol fees for all active satellites.
    function upgradeBeaconCrossChain(string calldata typeName, address newImpl, string calldata version)
        external
        payable
        onlyOwner
    {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        uint256 preBalance = address(this).balance - msg.value;

        // 1. Upgrade locally (validates impl, updates registry, upgrades beacon)
        s.poaManager.upgradeBeacon(typeName, newImpl, version);

        // 2. Dispatch to all active satellites
        bytes memory payload = abi.encode(MSG_UPGRADE_BEACON, typeName, newImpl, version);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 feePerSatellite = _feePerActiveSatellite(s);
        uint256 len = s.satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = s.satellites[i];
            if (sat.active) {
                bytes32 msgId = s.mailbox.dispatch{value: feePerSatellite}(sat.domain, sat.satellite, payload);
                emit CrossChainUpgradeDispatched(typeId, newImpl, version, sat.domain, msgId);
            }
            unchecked {
                ++i;
            }
        }

        _refundExcess(preBalance);
    }

    /// @notice Upgrade a beacon on the home chain only (no cross-chain propagation).
    function upgradeBeaconLocal(string calldata typeName, address newImpl, string calldata version) external onlyOwner {
        _layout().poaManager.upgradeBeacon(typeName, newImpl, version);
    }

    /*══════════════════ Contract Type Functions ══════════════════*/

    /// @notice Register a new contract type on the home chain only.
    function addContractType(string calldata typeName, address impl) external onlyOwner {
        _layout().poaManager.addContractType(typeName, impl);
    }

    /// @notice Register a new contract type on the home chain AND propagate to satellites.
    /// @dev    Satellites must have the implementation already deployed at `impl`.
    ///         Send enough ETH to cover Hyperlane protocol fees for all active satellites.
    function addContractTypeCrossChain(string calldata typeName, address impl) external payable onlyOwner {
        Layout storage s = _layout();
        if (s.paused) revert IsPaused();
        uint256 preBalance = address(this).balance - msg.value;

        s.poaManager.addContractType(typeName, impl);

        bytes memory payload = abi.encode(MSG_ADD_CONTRACT_TYPE, typeName, impl);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 feePerSatellite = _feePerActiveSatellite(s);
        uint256 len = s.satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = s.satellites[i];
            if (sat.active) {
                bytes32 msgId = s.mailbox.dispatch{value: feePerSatellite}(sat.domain, sat.satellite, payload);
                emit CrossChainAddTypeDispatched(typeId, typeName, sat.domain, msgId);
            }
            unchecked {
                ++i;
            }
        }

        _refundExcess(preBalance);
    }

    /*══════════════════ Admin Call Passthrough ══════════════════*/

    /// @notice Execute an arbitrary call through the local PoaManager.
    /// @dev Governance (Executor → Hub → PM) can use this to call admin functions
    ///      on sub-contracts that gate on `msg.sender == poaManager`.
    function adminCall(address target, bytes calldata data) external onlyOwner returns (bytes memory) {
        return _layout().poaManager.adminCall(target, data);
    }

    /*══════════════════ Registry Passthrough ══════════════════*/

    /// @notice Update the ImplementationRegistry on the local PoaManager.
    function updateImplRegistry(address registryAddr) external onlyOwner {
        _layout().poaManager.updateImplRegistry(registryAddr);
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function registerSatellite(uint32 domain, address satellite) external onlyOwner {
        if (satellite == address(0)) revert ZeroAddress();
        Layout storage s = _layout();

        // Reject duplicate active domains — prevents double-dispatch and fee burn
        uint256 len = s.satellites.length;
        for (uint256 i; i < len;) {
            if (s.satellites[i].domain == domain && s.satellites[i].active) {
                revert DuplicateDomain(domain);
            }
            unchecked {
                ++i;
            }
        }

        s.satellites
            .push(SatelliteConfig({domain: domain, satellite: bytes32(uint256(uint160(satellite))), active: true}));
        emit SatelliteRegistered(domain, satellite);
    }

    function removeSatellite(uint256 index) external onlyOwner {
        Layout storage s = _layout();
        uint32 domain = s.satellites[index].domain;
        s.satellites[index].active = false;
        emit SatelliteRemoved(domain);
    }

    /*══════════════════ Public Getters ══════════════════*/

    function poaManager() external view returns (PoaManager) {
        return _layout().poaManager;
    }

    function mailbox() external view returns (IMailbox) {
        return _layout().mailbox;
    }

    function satellites(uint256 index) external view returns (uint32 domain, bytes32 satellite, bool active) {
        Layout storage s = _layout();
        SatelliteConfig storage sat = s.satellites[index];
        return (sat.domain, sat.satellite, sat.active);
    }

    function paused() external view returns (bool) {
        return _layout().paused;
    }

    function satelliteCount() external view returns (uint256) {
        return _layout().satellites.length;
    }

    /*══════════════════ Ownership Safety ══════════════════*/

    /// @dev Ownership cannot be renounced — losing it bricks the Hub permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /// @notice Transfer PoaManager ownership (e.g. to a replacement Hub).
    function transferPoaManagerOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        _layout().poaManager.transferOwnership(newOwner);
    }

    /*══════════════════ Emergency ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        _layout().paused = _paused;
        emit PauseSet(_paused);
    }

    /// @notice Rescue ETH stuck in this contract (e.g. excess fees from dispatch calls).
    function withdrawETH(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = to.call{value: balance}("");
        if (!ok) revert TransferFailed();
    }

    /*══════════════════ Internal ══════════════════*/

    /// @dev Computes the fee to send per active satellite by dividing msg.value evenly.
    ///      Reverts if ETH is sent but there are no active satellites (would be lost).
    function _feePerActiveSatellite(Layout storage s) internal view returns (uint256) {
        uint256 len = s.satellites.length;
        uint256 activeCount;
        for (uint256 i; i < len;) {
            if (s.satellites[i].active) {
                unchecked {
                    ++activeCount;
                }
            }
            unchecked {
                ++i;
            }
        }
        if (activeCount == 0 && msg.value > 0) revert NoActiveSatellites();
        return activeCount > 0 ? msg.value / activeCount : 0;
    }

    /// @dev Refunds only the caller's overpayment (integer division remainder).
    ///      Pre-existing contract balance (e.g. Hyperlane refunds) is preserved.
    function _refundExcess(uint256 preBalance) internal {
        uint256 excess = address(this).balance - preBalance;
        if (excess > 0) {
            (bool ok,) = msg.sender.call{value: excess}("");
            if (!ok) revert TransferFailed();
        }
    }

    /// @dev Accept ETH (e.g. Hyperlane fee refunds).
    receive() external payable {}
}
