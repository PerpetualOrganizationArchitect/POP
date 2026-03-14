// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IMailbox} from "./interfaces/IHyperlane.sol";
import {PoaManager} from "../PoaManager.sol";

/// @title PoaManagerHub
/// @notice Home-chain wrapper around PoaManager that propagates beacon upgrades
///         to satellite chains via Hyperlane.
/// @dev    Deploy on the home chain, then transfer PoaManager ownership to this contract.
///         All admin calls (addContractType, upgradeBeacon) go through the Hub.
contract PoaManagerHub is Ownable2Step {
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
    uint8 internal constant MSG_ADMIN_CALL = 0x03;

    /*──────────── Immutables ──────────*/
    PoaManager public immutable poaManager;
    IMailbox public immutable mailbox;

    /*──────────── Storage ─────────────*/
    SatelliteConfig[] public satellites;
    uint256 public activeSatelliteCount;
    bool public paused;

    /*──────────── Errors ──────────────*/
    error IsPaused();
    error ZeroAddress();
    error NoActiveSatellites();
    error CannotRenounce();
    error TransferFailed();
    error DuplicateDomain(uint32 domain);
    error SatelliteNotActive();

    /*──────────── Events ──────────────*/
    event CrossChainUpgradeDispatched(bytes32 indexed typeId, address newImpl, string version);
    event CrossChainAddTypeDispatched(bytes32 indexed typeId, string typeName, address impl);
    event CrossChainAdminCallDispatched(address indexed target, bytes data);
    event SatelliteRegistered(uint32 indexed domain, address satellite);
    event SatelliteRemoved(uint32 indexed domain);
    event PauseSet(bool paused);

    /*──────────── Constructor ─────────*/
    constructor(address _poaManager, address _mailbox) Ownable(msg.sender) {
        if (_poaManager == address(0) || _mailbox == address(0)) revert ZeroAddress();
        poaManager = PoaManager(_poaManager);
        mailbox = IMailbox(_mailbox);
    }

    /*══════════════════ Upgrade Functions ══════════════════*/

    /// @notice Upgrade a beacon on the home chain AND propagate to all active satellites.
    /// @dev    Send enough ETH to cover Hyperlane protocol fees for all active satellites.
    function upgradeBeaconCrossChain(string calldata typeName, address newImpl, string calldata version)
        external
        payable
        onlyOwner
    {
        if (paused) revert IsPaused();
        uint256 preBalance = address(this).balance - msg.value;
        poaManager.upgradeBeacon(typeName, newImpl, version);
        emit CrossChainUpgradeDispatched(keccak256(bytes(typeName)), newImpl, version);
        _broadcast(abi.encode(MSG_UPGRADE_BEACON, typeName, newImpl, version), preBalance);
    }

    /// @notice Upgrade a beacon on the home chain only (no cross-chain propagation).
    function upgradeBeaconLocal(string calldata typeName, address newImpl, string calldata version) external onlyOwner {
        poaManager.upgradeBeacon(typeName, newImpl, version);
    }

    /*══════════════════ Contract Type Functions ══════════════════*/

    /// @notice Register a new contract type on the home chain only.
    function addContractType(string calldata typeName, address impl) external onlyOwner {
        poaManager.addContractType(typeName, impl);
    }

    /// @notice Register a new contract type on the home chain AND propagate to satellites.
    /// @dev    Satellites must have the implementation already deployed at `impl`.
    ///         Send enough ETH to cover Hyperlane protocol fees for all active satellites.
    function addContractTypeCrossChain(string calldata typeName, address impl) external payable onlyOwner {
        if (paused) revert IsPaused();
        uint256 preBalance = address(this).balance - msg.value;
        poaManager.addContractType(typeName, impl);
        emit CrossChainAddTypeDispatched(keccak256(bytes(typeName)), typeName, impl);
        _broadcast(abi.encode(MSG_ADD_CONTRACT_TYPE, typeName, impl), preBalance);
    }

    /*══════════════════ Admin Call Passthrough ══════════════════*/

    /// @notice Execute an arbitrary call through the local PoaManager.
    /// @dev Governance (Executor → Hub → PM) can use this to call admin functions
    ///      on sub-contracts that gate on `msg.sender == poaManager`.
    function adminCall(address target, bytes calldata data) external onlyOwner returns (bytes memory) {
        return poaManager.adminCall(target, data);
    }

    /// @notice Execute an admin call on the home chain AND propagate to all active satellites.
    /// @dev    Send enough ETH to cover Hyperlane protocol fees for all active satellites.
    ///         The satellite's PoaManager will call `adminCall(target, data)` on receipt.
    ///         NOTE: `target` must exist at the same address on all satellite chains.
    function adminCallCrossChain(address target, bytes calldata data) external payable onlyOwner {
        if (paused) revert IsPaused();
        uint256 preBalance = address(this).balance - msg.value;
        poaManager.adminCall(target, data);
        emit CrossChainAdminCallDispatched(target, data);
        _broadcast(abi.encode(MSG_ADMIN_CALL, target, data), preBalance);
    }

    /*══════════════════ Registry Passthrough ══════════════════*/

    /// @notice Update the ImplementationRegistry on the local PoaManager.
    function updateImplRegistry(address registryAddr) external onlyOwner {
        poaManager.updateImplRegistry(registryAddr);
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function registerSatellite(uint32 domain, address satellite) external onlyOwner {
        if (satellite == address(0)) revert ZeroAddress();

        // Reject duplicate active domains — prevents double-dispatch and fee burn
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            if (satellites[i].domain == domain && satellites[i].active) {
                revert DuplicateDomain(domain);
            }
            unchecked {
                ++i;
            }
        }

        satellites.push(
            SatelliteConfig({domain: domain, satellite: bytes32(uint256(uint160(satellite))), active: true})
        );
        ++activeSatelliteCount;
        emit SatelliteRegistered(domain, satellite);
    }

    function removeSatellite(uint256 index) external onlyOwner {
        if (!satellites[index].active) revert SatelliteNotActive();
        uint32 domain = satellites[index].domain;
        satellites[index].active = false;
        --activeSatelliteCount;
        emit SatelliteRemoved(domain);
    }

    function satelliteCount() external view returns (uint256) {
        return satellites.length;
    }

    /*══════════════════ Ownership Safety ══════════════════*/

    /// @dev Ownership cannot be renounced — losing it bricks the Hub permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /// @notice Transfer PoaManager ownership (e.g. to a replacement Hub).
    function transferPoaManagerOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        poaManager.transferOwnership(newOwner);
    }

    /*══════════════════ Emergency ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
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

    /// @dev Dispatches payload to every active satellite via Hyperlane. Handles fee split + refund.
    function _broadcast(bytes memory payload, uint256 preBalance) internal {
        uint256 count = activeSatelliteCount;
        if (count == 0) revert NoActiveSatellites();
        uint256 fee = msg.value / count;
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = satellites[i];
            if (sat.active) {
                mailbox.dispatch{value: fee}(sat.domain, sat.satellite, payload);
            }
            unchecked {
                ++i;
            }
        }
        _refundExcess(preBalance);
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
