// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {IMessageRecipient} from "./interfaces/IHyperlane.sol";
import {PoaManager} from "../PoaManager.sol";

/// @title PoaManagerSatellite
/// @notice Remote-chain receiver that applies beacon upgrades dispatched by the Hub.
/// @dev    Deploy behind a BeaconProxy on each satellite chain. Owns a local PoaManager instance.
///         Only accepts Hyperlane messages from the Hub on the home chain.
contract PoaManagerSatellite is Initializable, OwnableUpgradeable, IMessageRecipient {
    /*──────────── Constants ───────────*/
    uint8 internal constant MSG_UPGRADE_BEACON = 0x01;
    uint8 internal constant MSG_ADD_CONTRACT_TYPE = 0x02;

    /*──────────── ERC-7201 Storage ──────────*/
    /// @custom:storage-location erc7201:poa.poamanagersatellite.storage
    struct Layout {
        PoaManager poaManager;
        address mailbox;
        uint32 hubDomain;
        bytes32 hubAddress;
        bool paused;
    }

    bytes32 private constant _STORAGE_SLOT = keccak256("poa.poamanagersatellite.storage");

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = _STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

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
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*──────────── Initializer ─────────*/
    function initialize(address owner, address _poaManager, address _mailbox, uint32 _hubDomain, address _hubAddress)
        external
        initializer
    {
        if (owner == address(0) || _poaManager == address(0) || _mailbox == address(0) || _hubAddress == address(0)) {
            revert ZeroAddress();
        }
        __Ownable_init(owner);
        Layout storage s = _layout();
        s.poaManager = PoaManager(_poaManager);
        s.mailbox = _mailbox;
        s.hubDomain = _hubDomain;
        s.hubAddress = bytes32(uint256(uint160(_hubAddress)));
    }

    /*══════════════════ Hyperlane Receiver ══════════════════*/

    /// @notice Called by the Hyperlane Mailbox when a message arrives from the Hub.
    /// @dev    Validates origin chain, sender address, and mailbox caller.
    function handle(uint32 _origin, bytes32 _sender, bytes calldata _body) external override {
        Layout storage s = _layout();
        if (msg.sender != s.mailbox) revert UnauthorizedMailbox();
        if (_origin != s.hubDomain) revert UnauthorizedOrigin();
        if (_sender != s.hubAddress) revert UnauthorizedSender();
        if (s.paused) revert IsPaused();

        uint8 msgType = abi.decode(_body[:32], (uint8));

        if (msgType == MSG_UPGRADE_BEACON) {
            (, string memory typeName, address newImpl, string memory version) =
                abi.decode(_body, (uint8, string, address, string));

            s.poaManager.upgradeBeacon(typeName, newImpl, version);

            emit UpgradeReceived(keccak256(bytes(typeName)), newImpl, version, _origin);
        } else if (msgType == MSG_ADD_CONTRACT_TYPE) {
            (, string memory typeName, address impl) = abi.decode(_body, (uint8, string, address));

            s.poaManager.addContractType(typeName, impl);

            emit ContractTypeReceived(keccak256(bytes(typeName)), typeName, impl, _origin);
        } else {
            revert UnknownMessageType();
        }
    }

    /*══════════════════ Public Getters ══════════════════*/

    function poaManager() external view returns (PoaManager) {
        return _layout().poaManager;
    }

    function mailbox() external view returns (address) {
        return _layout().mailbox;
    }

    function hubDomain() external view returns (uint32) {
        return _layout().hubDomain;
    }

    function hubAddress() external view returns (bytes32) {
        return _layout().hubAddress;
    }

    function paused() external view returns (bool) {
        return _layout().paused;
    }

    /*══════════════════ Ownership Safety ══════════════════*/

    /// @dev Ownership cannot be renounced — losing it bricks the satellite permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*══════════════════ Pause ══════════════════*/

    function setPaused(bool _paused) external onlyOwner {
        _layout().paused = _paused;
        emit PauseSet(_paused);
    }

    /*══════════════════ Admin Call Passthrough ══════════════════*/

    /// @notice Execute an arbitrary call through the local PoaManager.
    /// @dev Owner can use this to call admin functions on sub-contracts
    ///      that gate on `msg.sender == poaManager`.
    function adminCall(address target, bytes calldata data) external onlyOwner returns (bytes memory) {
        return _layout().poaManager.adminCall(target, data);
    }

    /*══════════════════ Emergency / Direct Admin ══════════════════*/

    /// @notice Emergency local-only upgrade (bypasses cross-chain path).
    function upgradeBeaconDirect(string calldata typeName, address newImpl, string calldata version)
        external
        onlyOwner
    {
        _layout().poaManager.upgradeBeacon(typeName, newImpl, version);
    }

    /// @notice Register a new contract type locally.
    function addContractType(string calldata typeName, address impl) external onlyOwner {
        _layout().poaManager.addContractType(typeName, impl);
    }

    /// @notice Update the ImplementationRegistry on the local PoaManager.
    function updateImplRegistry(address registryAddr) external onlyOwner {
        _layout().poaManager.updateImplRegistry(registryAddr);
    }

    /// @notice Transfer PoaManager ownership (e.g. to a replacement satellite).
    function transferPoaManagerOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        _layout().poaManager.transferOwnership(newOwner);
    }
}
