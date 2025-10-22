// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────── External Hats interface ──────────*/
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

interface IUniversalAccountRegistry {
    function recoverAccount(address from, address to) external;
}

/**
 * @title DeviceWrapRegistry
 * @notice Manages encrypted device wraps with guardian-gated approval system
 * @dev Uses Hats Protocol for guardian role management
 *
 * Key Features:
 * - Instant wrap approval up to maxInstantWraps
 * - Guardian quorum required for over-cap wraps
 * - Guardian quorum required for account recovery
 * - POA Manager controls guardian hat and threshold
 */
contract DeviceWrapRegistry is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    /*──────── Errors ────────*/
    error IndexOOB();
    error NotPending();
    error AlreadyActive();
    error AlreadyRevoked();
    error NotGuardian();
    error InvalidThreshold();
    error AlreadyVoted();
    error TransferAlreadyExecuted();
    error InvalidGuardianHat();

    /*──────── Events ────────*/
    event MaxInstantWrapsChanged(uint256 oldVal, uint256 newVal);
    event GuardianHatChanged(uint256 oldHat, uint256 newHat);
    event GuardianThresholdChanged(uint256 oldVal, uint256 newVal);

    event WrapAdded(address indexed owner, uint256 indexed idx, Wrap w);
    event WrapGuardianApproved(
        address indexed owner, uint256 indexed idx, address indexed guardian, uint256 approvals, uint256 threshold
    );
    event WrapFinalized(address indexed owner, uint256 indexed idx);
    event WrapRevoked(address indexed owner, uint256 indexed idx);

    event TransferProposed(bytes32 indexed id, address indexed from, address indexed to);
    event TransferGuardianApproved(bytes32 indexed id, address indexed guardian, uint256 approvals, uint256 threshold);
    event TransferExecuted(bytes32 indexed id, address indexed from, address indexed to);

    /*──────── Types ────────*/
    enum WrapStatus {
        Active,
        Pending,
        Revoked
    }

    struct Wrap {
        bytes32 credentialHint; // keccak256(credentialId)
        bytes32 salt; // HKDF salt
        bytes12 iv; // AES-GCM IV
        bytes32 aadHash; // keccak256(rpIdHash || credentialHint || owner)
        string cid; // pointer to ciphertext JSON/blob (IPFS/Arweave)
        WrapStatus status;
        uint64 createdAt;
    }

    struct TransferState {
        address from;
        address to;
        bool executed;
        uint64 createdAt;
        uint32 approvals;
        // per-id guardian vote map
        mapping(address => bool) voted;
    }

    /*──────── Storage (ERC-7201) ────────*/
    /// @custom:storage-location erc7201:poa.devicewrapregistry.v2
    struct Layout {
        mapping(address => Wrap[]) wrapsOf;
        mapping(address => mapping(uint256 => uint256)) approvalsWrap; // count approvals for Pending wrap
        mapping(address => mapping(uint256 => mapping(address => bool))) votedWrap; // guardian voted?
        uint256 maxInstantWraps;
        // guardians - using Hats Protocol
        IHats hats;
        uint256 guardianHatId; // Single hat ID for guardian role
        uint256 guardianThreshold;
        // recovery
        mapping(bytes32 => TransferState) transfer; // id => state
        IUniversalAccountRegistry uar;
    }

    // keccak256("poa.devicewrapregistry.v2.storage")
    bytes32 private constant _SLOT = 0x6743e67f10aa0ef86480ca36274fa9f13e8f36deea208a7c47d39f0000853a97;

    function _l() private pure returns (Layout storage s) {
        assembly {
            s.slot := _SLOT
        }
    }

    /*──────── Modifiers ────────*/
    modifier onlyGuardian() {
        Layout storage l = _l();
        if (l.guardianHatId == 0 || !l.hats.isWearerOfHat(msg.sender, l.guardianHatId)) {
            revert NotGuardian();
        }
        _;
    }

    /*──────── Init ────────*/
    /**
     * @notice Initialize the DeviceWrapRegistry
     * @param poaManager Address that will own this contract (typically PoaManager)
     * @param uar_ UniversalAccountRegistry address
     * @param hats_ Hats Protocol address
     */
    function initialize(address poaManager, address uar_, address hats_) external initializer {
        __Ownable_init(poaManager);
        __ReentrancyGuard_init();
        Layout storage L = _l();
        L.maxInstantWraps = 3; // default; Poa Manager can change
        L.guardianThreshold = 1; // default minimal quorum
        L.uar = IUniversalAccountRegistry(uar_);
        L.hats = IHats(hats_);
        L.guardianHatId = 0; // Must be set by owner
        emit MaxInstantWrapsChanged(0, 3);
        emit GuardianThresholdChanged(0, 1);
    }

    /*──────── Admin (Poa Manager) ────────*/
    function setMaxInstantWraps(uint256 n) external onlyOwner {
        uint256 old = _l().maxInstantWraps;
        _l().maxInstantWraps = n;
        emit MaxInstantWrapsChanged(old, n);
    }

    /**
     * @notice Set the guardian hat ID
     * @dev Only POA Manager can call this
     * @param hatId The hat ID that grants guardian permissions
     */
    function setGuardianHat(uint256 hatId) external onlyOwner {
        if (hatId == 0) revert InvalidGuardianHat();
        Layout storage L = _l();
        uint256 old = L.guardianHatId;
        L.guardianHatId = hatId;
        emit GuardianHatChanged(old, hatId);
    }

    function setGuardianThreshold(uint256 t) external onlyOwner {
        if (t == 0) revert InvalidThreshold();
        Layout storage L = _l();
        uint256 old = L.guardianThreshold;
        L.guardianThreshold = t;
        emit GuardianThresholdChanged(old, t);
    }

    function setRegistry(address uar_) external onlyOwner {
        _l().uar = IUniversalAccountRegistry(uar_);
    }

    /*──────── Wrap lifecycle ────────*/
    function addWrap(Wrap calldata w) external nonReentrant returns (uint256 idx) {
        address ownerAddr = msg.sender;
        Wrap memory nw = w;
        nw.createdAt = uint64(block.timestamp);

        if (_activeCount(ownerAddr) < _l().maxInstantWraps) {
            nw.status = WrapStatus.Active;
        } else {
            nw.status = WrapStatus.Pending;
        }

        idx = _l().wrapsOf[ownerAddr].length;
        _l().wrapsOf[ownerAddr].push(nw);
        emit WrapAdded(ownerAddr, idx, nw);

        if (nw.status == WrapStatus.Active) {
            emit WrapFinalized(ownerAddr, idx);
        }
    }

    /// Guardians approve a specific owner's Pending wrap (the 4th, 5th, …).
    function guardianApproveWrap(address ownerAddr, uint256 idx) external onlyGuardian {
        Wrap storage w = _get(ownerAddr, idx);
        if (w.status != WrapStatus.Pending) revert NotPending();
        Layout storage L = _l();
        if (L.votedWrap[ownerAddr][idx][msg.sender]) revert AlreadyVoted();
        L.votedWrap[ownerAddr][idx][msg.sender] = true;

        uint256 approvals = ++L.approvalsWrap[ownerAddr][idx];
        emit WrapGuardianApproved(ownerAddr, idx, msg.sender, approvals, L.guardianThreshold);
        // Optional convenience: auto-finalize when quorum reached, owner not required to call finalize
        if (approvals >= L.guardianThreshold) {
            w.status = WrapStatus.Active;
            emit WrapFinalized(ownerAddr, idx);
        }
    }

    /// Owner can always revoke their own wrap
    function revokeWrap(uint256 idx) external {
        address ownerAddr = msg.sender;
        Wrap storage w = _get(ownerAddr, idx);
        if (w.status == WrapStatus.Revoked) revert AlreadyRevoked();
        w.status = WrapStatus.Revoked;
        emit WrapRevoked(ownerAddr, idx);
    }

    /*──────── Account transfer (recovery) ────────*/
    /// Deterministic id for (from,to). Anyone can propose; only guardians can approve/execute.
    function transferId(address from, address to) public view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), block.chainid, from, to));
    }

    function proposeAccountTransfer(address from, address to) external {
        bytes32 id = transferId(from, to);
        TransferState storage T = _l().transfer[id];
        if (T.createdAt == 0) {
            T.from = from;
            T.to = to;
            T.createdAt = uint64(block.timestamp);
            emit TransferProposed(id, from, to);
        }
        // no else: re-propose is no-op
    }

    function guardianApproveTransfer(address from, address to) external onlyGuardian nonReentrant {
        bytes32 id = transferId(from, to);
        TransferState storage T = _l().transfer[id];
        if (T.createdAt == 0) {
            // implicit proposal if not proposed yet
            T.from = from;
            T.to = to;
            T.createdAt = uint64(block.timestamp);
            emit TransferProposed(id, from, to);
        }
        if (T.executed) revert TransferAlreadyExecuted();
        if (T.voted[msg.sender]) revert AlreadyVoted();

        T.voted[msg.sender] = true;
        uint32 approvals = ++T.approvals;
        emit TransferGuardianApproved(id, msg.sender, approvals, uint32(_l().guardianThreshold));

        if (approvals >= _l().guardianThreshold) {
            _executeTransfer(id);
        }
    }

    function executeTransfer(address from, address to) external nonReentrant {
        bytes32 id = transferId(from, to);
        _executeTransfer(id);
    }

    function _executeTransfer(bytes32 id) internal {
        Layout storage L = _l();
        TransferState storage T = L.transfer[id];
        if (T.executed) revert TransferAlreadyExecuted();
        require(T.approvals >= L.guardianThreshold && T.createdAt != 0, "not-approved");
        T.executed = true;

        // call into UAR (we pre-authorized this DWR as recoveryCaller)
        L.uar.recoverAccount(T.from, T.to);
        emit TransferExecuted(id, T.from, T.to);
    }

    /*──────── Views ────────*/
    function wrapsOf(address ownerAddr) external view returns (Wrap[] memory) {
        return _l().wrapsOf[ownerAddr];
    }

    function activeCount(address ownerAddr) public view returns (uint256) {
        return _activeCount(ownerAddr);
    }

    function guardianThreshold() external view returns (uint256) {
        return _l().guardianThreshold;
    }

    function guardianHatId() external view returns (uint256) {
        return _l().guardianHatId;
    }

    function isGuardian(address g) external view returns (bool) {
        Layout storage l = _l();
        if (l.guardianHatId == 0) return false;
        return l.hats.isWearerOfHat(g, l.guardianHatId);
    }

    function maxInstantWraps() external view returns (uint256) {
        return _l().maxInstantWraps;
    }

    function getTransferState(address from, address to)
        external
        view
        returns (address, address, bool executed, uint64 createdAt, uint32 approvals)
    {
        bytes32 id = transferId(from, to);
        TransferState storage T = _l().transfer[id];
        return (T.from, T.to, T.executed, T.createdAt, T.approvals);
    }

    function hasGuardianVotedOnWrap(address ownerAddr, uint256 idx, address guardian)
        external
        view
        returns (bool)
    {
        return _l().votedWrap[ownerAddr][idx][guardian];
    }

    function hasGuardianVotedOnTransfer(address from, address to, address guardian) external view returns (bool) {
        bytes32 id = transferId(from, to);
        return _l().transfer[id].voted[guardian];
    }

    /*──────── Internals ────────*/
    function _get(address ownerAddr, uint256 idx) internal view returns (Wrap storage) {
        Wrap[] storage arr = _l().wrapsOf[ownerAddr];
        if (idx >= arr.length) revert IndexOOB();
        return arr[idx];
    }

    function _activeCount(address ownerAddr) internal view returns (uint256 n) {
        Wrap[] storage arr = _l().wrapsOf[ownerAddr];
        for (uint256 i; i < arr.length; ++i) {
            if (arr[i].status == WrapStatus.Active) ++n;
        }
    }
}
