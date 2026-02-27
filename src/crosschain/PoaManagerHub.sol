// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMailbox} from "./interfaces/IHyperlane.sol";
import {PoaManager} from "../PoaManager.sol";

/// @title PoaManagerHub
/// @notice Home-chain wrapper around PoaManager that propagates beacon upgrades
///         to satellite chains via Hyperlane.
/// @dev    Deploy on the home chain, then transfer PoaManager ownership to this contract.
///         All admin calls (addContractType, upgradeBeacon) go through the Hub.
contract PoaManagerHub is Ownable(msg.sender) {
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

    /*──────────── Immutables ──────────*/
    PoaManager public immutable poaManager;
    IMailbox public immutable mailbox;

    /*──────────── Storage ─────────────*/
    SatelliteConfig[] public satellites;
    bool public paused;

    /*──────────── Errors ──────────────*/
    error IsPaused();
    error ZeroAddress();
    error NoActiveSatellites();
    error CannotRenounce();
    error TransferFailed();

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
    constructor(address _poaManager, address _mailbox) {
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

        // 1. Upgrade locally (validates impl, updates registry, upgrades beacon)
        poaManager.upgradeBeacon(typeName, newImpl, version);

        // 2. Dispatch to all active satellites
        bytes memory payload = abi.encode(MSG_UPGRADE_BEACON, typeName, newImpl, version);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 feePerSatellite = _feePerActiveSatellite();
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = satellites[i];
            if (sat.active) {
                bytes32 msgId = mailbox.dispatch{value: feePerSatellite}(sat.domain, sat.satellite, payload);
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

        bytes memory payload = abi.encode(MSG_ADD_CONTRACT_TYPE, typeName, impl);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 feePerSatellite = _feePerActiveSatellite();
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = satellites[i];
            if (sat.active) {
                bytes32 msgId = mailbox.dispatch{value: feePerSatellite}(sat.domain, sat.satellite, payload);
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
        return poaManager.adminCall(target, data);
    }

    /*══════════════════ Registry Passthrough ══════════════════*/

    /// @notice Update the ImplementationRegistry on the local PoaManager.
    function updateImplRegistry(address registryAddr) external onlyOwner {
        poaManager.updateImplRegistry(registryAddr);
    }

    /*══════════════════ Satellite Management ══════════════════*/

    function registerSatellite(uint32 domain, address satellite) external onlyOwner {
        if (satellite == address(0)) revert ZeroAddress();
        satellites.push(
            SatelliteConfig({domain: domain, satellite: bytes32(uint256(uint160(satellite))), active: true})
        );
        emit SatelliteRegistered(domain, satellite);
    }

    function removeSatellite(uint256 index) external onlyOwner {
        uint32 domain = satellites[index].domain;
        satellites[index].active = false;
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

    /// @dev Computes the fee to send per active satellite by dividing msg.value evenly.
    ///      Reverts if ETH is sent but there are no active satellites (would be lost).
    function _feePerActiveSatellite() internal view returns (uint256) {
        uint256 len = satellites.length;
        uint256 activeCount;
        for (uint256 i; i < len;) {
            if (satellites[i].active) {
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
