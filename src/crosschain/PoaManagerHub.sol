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
    function upgradeBeaconCrossChain(string calldata typeName, address newImpl, string calldata version)
        external
        payable
        onlyOwner
    {
        if (paused) revert IsPaused();

        // 1. Upgrade locally (validates impl, updates registry, upgrades beacon)
        poaManager.upgradeBeacon(typeName, newImpl, version);

        // 2. Dispatch to all active satellites
        bytes memory payload = abi.encode(MSG_UPGRADE_BEACON, typeName, newImpl, version);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = satellites[i];
            if (sat.active) {
                bytes32 msgId = mailbox.dispatch(sat.domain, sat.satellite, payload);
                emit CrossChainUpgradeDispatched(typeId, newImpl, version, sat.domain, msgId);
            }
            unchecked {
                ++i;
            }
        }
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
    function addContractTypeCrossChain(string calldata typeName, address impl) external payable onlyOwner {
        if (paused) revert IsPaused();

        poaManager.addContractType(typeName, impl);

        bytes memory payload = abi.encode(MSG_ADD_CONTRACT_TYPE, typeName, impl);
        bytes32 typeId = keccak256(bytes(typeName));
        uint256 len = satellites.length;
        for (uint256 i; i < len;) {
            SatelliteConfig storage sat = satellites[i];
            if (sat.active) {
                bytes32 msgId = mailbox.dispatch(sat.domain, sat.satellite, payload);
                emit CrossChainAddTypeDispatched(typeId, typeName, sat.domain, msgId);
            }
            unchecked {
                ++i;
            }
        }
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

    /*══════════════════ Emergency ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseSet(_paused);
    }

    /// @notice Rescue ETH accidentally sent to this contract.
    /// @dev    dispatch() calls are made without value (fees handled via Hyperlane IGP).
    ///         This function recovers any ETH stuck in the contract.
    function withdrawETH(address payable to) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        uint256 balance = address(this).balance;
        (bool ok,) = to.call{value: balance}("");
        require(ok);
    }
}
