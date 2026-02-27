// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IMessageRecipient} from "./interfaces/IHyperlane.sol";
import {PoaManager} from "../PoaManager.sol";

/// @title PoaManagerSatellite
/// @notice Remote-chain receiver that applies beacon upgrades dispatched by the Hub.
/// @dev    Deploy on each satellite chain. Owns a local PoaManager instance.
///         Only accepts Hyperlane messages from the Hub on the home chain.
contract PoaManagerSatellite is Ownable(msg.sender), IMessageRecipient {
    /*──────────── Constants ───────────*/
    uint8 internal constant MSG_UPGRADE_BEACON = 0x01;
    uint8 internal constant MSG_ADD_CONTRACT_TYPE = 0x02;

    /*──────────── Immutables ──────────*/
    PoaManager public immutable poaManager;
    address public immutable mailbox;
    uint32 public immutable hubDomain;
    bytes32 public immutable hubAddress;

    /*──────────── Storage ─────────────*/
    bool public paused;

    /*──────────── Errors ──────────────*/
    error UnauthorizedMailbox();
    error UnauthorizedOrigin();
    error UnauthorizedSender();
    error UnknownMessageType();
    error ZeroAddress();
    error IsPaused();
    error CannotRenounce();

    /*──────────── Events ──────────────*/
    event UpgradeReceived(bytes32 indexed typeId, address newImpl, string version, uint32 origin);
    event ContractTypeReceived(bytes32 indexed typeId, string typeName, address impl, uint32 origin);
    event PauseSet(bool paused);

    /*──────────── Constructor ─────────*/
    constructor(address _poaManager, address _mailbox, uint32 _hubDomain, address _hubAddress) {
        if (_poaManager == address(0) || _mailbox == address(0) || _hubAddress == address(0)) {
            revert ZeroAddress();
        }
        poaManager = PoaManager(_poaManager);
        mailbox = _mailbox;
        hubDomain = _hubDomain;
        hubAddress = bytes32(uint256(uint160(_hubAddress)));
    }

    /*══════════════════ Hyperlane Receiver ══════════════════*/

    /// @notice Called by the Hyperlane Mailbox when a message arrives from the Hub.
    /// @dev    Validates origin chain, sender address, and mailbox caller.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external override {
        if (msg.sender != mailbox) revert UnauthorizedMailbox();
        if (_origin != hubDomain) revert UnauthorizedOrigin();
        if (_sender != hubAddress) revert UnauthorizedSender();
        if (paused) revert IsPaused();

        uint8 msgType = abi.decode(_body[:32], (uint8));

        if (msgType == MSG_UPGRADE_BEACON) {
            (, string memory typeName, address newImpl, string memory version) =
                abi.decode(_body, (uint8, string, address, string));

            poaManager.upgradeBeacon(typeName, newImpl, version);

            emit UpgradeReceived(keccak256(bytes(typeName)), newImpl, version, _origin);
        } else if (msgType == MSG_ADD_CONTRACT_TYPE) {
            (, string memory typeName, address impl) = abi.decode(_body, (uint8, string, address));

            poaManager.addContractType(typeName, impl);

            emit ContractTypeReceived(keccak256(bytes(typeName)), typeName, impl, _origin);
        } else {
            revert UnknownMessageType();
        }
    }

    /*══════════════════ Ownership Safety ══════════════════*/

    /// @dev Ownership cannot be renounced — losing it bricks the satellite permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*══════════════════ Pause ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit PauseSet(_paused);
    }

    /*══════════════════ Emergency / Direct Admin ══════════════════*/

    /// @notice Emergency local-only upgrade (bypasses cross-chain path).
    function upgradeBeaconDirect(string calldata typeName, address newImpl, string calldata version)
        external
        onlyOwner
    {
        poaManager.upgradeBeacon(typeName, newImpl, version);
    }

    /// @notice Register a new contract type locally.
    function addContractType(string calldata typeName, address impl) external onlyOwner {
        poaManager.addContractType(typeName, impl);
    }

    /// @notice Update the ImplementationRegistry on the local PoaManager.
    function updateImplRegistry(address registryAddr) external onlyOwner {
        poaManager.updateImplRegistry(registryAddr);
    }

    /// @notice Transfer PoaManager ownership (e.g. to a replacement satellite).
    function transferPoaManagerOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        poaManager.transferOwnership(newOwner);
    }
}
