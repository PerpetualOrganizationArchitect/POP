// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ValidationLib} from "./libs/ValidationLib.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";

/* ─────────── Custom errors ─────────── */
error InvalidParam();
error OrgExists();
error OrgUnknown();
error TypeTaken();
error ContractUnknown();
error NotOrgExecutor();
error NotOrgAdmin();
error OwnerOnlyDuringBootstrap(); // deployer tried after bootstrap
error AutoUpgradeRequired(); // deployer must set autoUpgrade=true

/* ────────────────── Org Registry ────────────────── */
contract OrgRegistry is Initializable, OwnableUpgradeable {
    /* ───── Data structs ───── */
    struct ContractInfo {
        address proxy; // BeaconProxy address
        address beacon; // Beacon address
        bool autoUpgrade; // true ⇒ proxy follows beacon
        address owner; // module owner (immutable metadata)
    }

    struct OrgInfo {
        address executor; // DAO / governor / timelock that controls the org
        uint32 contractCount;
        bool bootstrap; // TRUE until the executor (or deployer via `lastRegister`)
        // finishes initial deployment. Afterwards the registry
        // owner can no longer add contracts.
        bool exists;
    }

    /**
     * @dev Struct for batch contract registration
     * @param typeId The module type identifier (keccak256 of module name)
     * @param proxy The BeaconProxy address
     * @param beacon The Beacon address
     * @param owner The module owner address
     */
    struct ContractRegistration {
        bytes32 typeId;
        address proxy;
        address beacon;
        address owner;
    }

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgregistry.storage
    struct Layout {
        /* ───── Storage ───── */
        mapping(bytes32 => OrgInfo) orgOf; // orgId to OrgInfo
        mapping(bytes32 => ContractInfo) contractOf; // contractId to ContractInfo
        mapping(bytes32 => mapping(bytes32 => address)) proxyOf; // (orgId,typeId) to proxy
        mapping(bytes32 => uint256) topHatOf; // orgId to topHatId
        mapping(bytes32 => mapping(uint256 => uint256)) roleHatOf; // orgId => roleIndex => hatId
        bytes32[] orgIds;
        uint256 totalContracts;
        // New storage for admin hat feature
        mapping(bytes32 => uint256) adminHatOf; // orgId => admin hatId for direct metadata editing
        address hatsProtocol; // Hats Protocol contract address
    }

    // keccak256("poa.orgregistry.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x3ffb0627b419b7b77c77f589dd229844c112a8c125dceec0d56dda0674b35489;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───── Events ───── */
    event OrgRegistered(bytes32 indexed orgId, address indexed executor, bytes name, bytes32 metadataHash);
    event MetaUpdated(bytes32 indexed orgId, bytes newName, bytes32 newMetadataHash);
    event ContractRegistered(
        bytes32 indexed contractId,
        bytes32 indexed orgId,
        bytes32 indexed typeId,
        address proxy,
        address beacon,
        bool autoUpgrade,
        address owner
    );
    event AutoUpgradeSet(bytes32 indexed contractId, bool enabled);
    event HatsTreeRegistered(bytes32 indexed orgId, uint256 topHatId, uint256[] roleHatIds);
    event OrgAdminHatSet(bytes32 indexed orgId, uint256 hatId);
    event HatsProtocolSet(address hatsProtocol);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    /**
     * @dev Initializes the contract, replacing the constructor for upgradeable pattern
     * @param initialOwner The address that will own this registry
     */
    function initialize(address initialOwner) external initializer {
        if (initialOwner == address(0)) revert InvalidParam();
        __Ownable_init(initialOwner);
    }

    /**
     * @dev Sets the Hats Protocol contract address
     * @param _hats The Hats Protocol contract address
     */
    function setHatsProtocol(address _hats) external onlyOwner {
        if (_hats == address(0)) revert InvalidParam();
        _layout().hatsProtocol = _hats;
        emit HatsProtocolSet(_hats);
    }

    /**
     * @dev Gets the Hats Protocol contract address
     */
    function getHatsProtocol() external view returns (address) {
        return _layout().hatsProtocol;
    }

    /* ═════════════════ ORG  LOGIC ═════════════════ */
    function registerOrg(bytes32 orgId, address executorAddr, bytes calldata name, bytes32 metadataHash)
        external
        onlyOwner
    {
        ValidationLib.requireValidTitle(name);
        if (orgId == bytes32(0) || executorAddr == address(0)) revert InvalidParam();

        Layout storage l = _layout();
        if (l.orgOf[orgId].exists) revert OrgExists();

        l.orgOf[orgId] = OrgInfo({
            executor: executorAddr,
            contractCount: 0,
            bootstrap: true, // owner can add modules while true
            exists: true
        });
        l.orgIds.push(orgId);
        emit OrgRegistered(orgId, executorAddr, name, metadataHash);
    }

    /**
     * @dev Creates an org in bootstrap mode without an executor (for deployment scenarios)
     * @param orgId The org identifier
     * @param name Name of the org (required, raw UTF-8)
     * @param metadataHash IPFS CID sha256 digest (optional, bytes32(0) is valid)
     */
    function createOrgBootstrap(bytes32 orgId, bytes calldata name, bytes32 metadataHash) external onlyOwner {
        ValidationLib.requireValidTitle(name);
        if (orgId == bytes32(0)) revert InvalidParam();

        Layout storage l = _layout();
        if (l.orgOf[orgId].exists) revert OrgExists();

        l.orgOf[orgId] = OrgInfo({
            executor: address(0), // no executor yet
            contractCount: 0,
            bootstrap: true, // in bootstrap mode
            exists: true
        });
        l.orgIds.push(orgId);
        emit OrgRegistered(orgId, address(0), name, metadataHash);
    }

    /**
     * @dev Sets the executor for an org (only during bootstrap)
     * @param orgId The org identifier
     * @param executorAddr The executor address
     */
    function setOrgExecutor(bytes32 orgId, address executorAddr) external onlyOwner {
        if (orgId == bytes32(0) || executorAddr == address(0)) revert InvalidParam();

        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();

        o.executor = executorAddr;
    }

    /**
     * @dev Updates org metadata (governance path - only executor)
     * @param orgId The organization ID
     * @param newName New organization name (bytes, validated by ValidationLib)
     * @param newMetadataHash New IPFS metadata hash (bytes32)
     */
    function updateOrgMeta(bytes32 orgId, bytes calldata newName, bytes32 newMetadataHash) external {
        ValidationLib.requireValidTitle(newName);
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        emit MetaUpdated(orgId, newName, newMetadataHash);
    }

    /**
     * @dev Allows an admin hat wearer to update org metadata directly (no governance)
     * @param orgId The organization ID
     * @param newName New organization name (bytes, validated by ValidationLib)
     * @param newMetadataHash New IPFS metadata hash (bytes32)
     */
    function updateOrgMetaAsAdmin(bytes32 orgId, bytes calldata newName, bytes32 newMetadataHash) external {
        ValidationLib.requireValidTitle(newName);
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();

        // Check if caller wears the org's admin hat
        uint256 adminHat = l.adminHatOf[orgId];
        if (adminHat == 0) {
            // No admin hat configured, fall back to topHat
            adminHat = l.topHatOf[orgId];
        }
        if (adminHat == 0) revert NotOrgAdmin();

        address hats = l.hatsProtocol;
        if (hats == address(0)) revert InvalidParam();
        if (!IHats(hats).isWearerOfHat(msg.sender, adminHat)) revert NotOrgAdmin();

        emit MetaUpdated(orgId, newName, newMetadataHash);
    }

    /**
     * @dev Set the admin hat for an org (only executor can do this)
     * @param orgId The organization ID
     * @param hatId The hat ID that can edit metadata directly (0 to use topHat)
     */
    function setOrgAdminHat(bytes32 orgId, uint256 hatId) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        l.adminHatOf[orgId] = hatId;
        emit OrgAdminHatSet(orgId, hatId);
    }

    /**
     * @dev Get the admin hat for an org
     */
    function getOrgAdminHat(bytes32 orgId) external view returns (uint256) {
        return _layout().adminHatOf[orgId];
    }

    /* ══════════ CONTRACT  REGISTRATION  ══════════ */
    /**
     *  ‑ During **bootstrap** (`o.bootstrap == true`) the registry owner _may_
     *    register contracts **if and only if `autoUpgrade == true`.**
     *  ‑ Pass `lastRegister = true` on the deployer's final call, or let the
     *    executor register at least once, to end the bootstrap phase.
     *
     *  @param lastRegister  set TRUE when this is the deployer's last module;
     *                       it flips `bootstrap` to false.
     */
    function registerOrgContract(
        bytes32 orgId,
        bytes32 typeId,
        address proxy,
        address beacon,
        bool autoUp,
        address moduleOwner,
        bool lastRegister
    ) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();

        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap, _and_ must opt‑in to auto‑upgrade
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
            if (!autoUp) revert AutoUpgradeRequired();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        if (typeId == bytes32(0) || proxy == address(0) || beacon == address(0) || moduleOwner == address(0)) {
            revert InvalidParam();
        }
        if (l.proxyOf[orgId][typeId] != address(0)) revert TypeTaken();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));

        l.contractOf[contractId] = ContractInfo({proxy: proxy, beacon: beacon, autoUpgrade: autoUp, owner: moduleOwner});
        l.proxyOf[orgId][typeId] = proxy;

        unchecked {
            ++o.contractCount;
            ++l.totalContracts;
        }
        emit ContractRegistered(contractId, orgId, typeId, proxy, beacon, autoUp, moduleOwner);

        // Finish bootstrap if executor registered OR deployer signalled completion
        if ((o.executor != address(0) && callerIsExecutor) || (callerIsOwner && lastRegister)) {
            o.bootstrap = false;
        }
    }

    /**
     * @notice Register multiple contracts in a single transaction (batch operation)
     * @dev Optimized for standard 10-contract deployments. Reduces gas by ~60-80k vs individual calls.
     * @param orgId The organization identifier
     * @param registrations Array of contracts to register
     * @param autoUpgrade Whether contracts auto-upgrade with their beacons
     * @param lastRegister Set true when this is the final batch; finalizes bootstrap phase
     */
    function batchRegisterOrgContracts(
        bytes32 orgId,
        ContractRegistration[] calldata registrations,
        bool autoUpgrade,
        bool lastRegister
    ) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];

        // Validation
        if (!o.exists) revert OrgUnknown();
        if (registrations.length == 0) revert InvalidParam();

        // Check caller permissions (same logic as single registration)
        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap, and must opt-in to auto-upgrade
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
            if (!autoUpgrade) revert AutoUpgradeRequired();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        // Batch register all contracts
        uint256 len = registrations.length;
        for (uint256 i = 0; i < len; i++) {
            ContractRegistration calldata reg = registrations[i];

            // Validate parameters
            if (
                reg.typeId == bytes32(0) || reg.proxy == address(0) || reg.beacon == address(0)
                    || reg.owner == address(0)
            ) {
                revert InvalidParam();
            }

            // Check not already registered
            if (l.proxyOf[orgId][reg.typeId] != address(0)) {
                revert TypeTaken();
            }

            // Store contract info
            bytes32 contractId = keccak256(abi.encodePacked(orgId, reg.typeId));
            l.contractOf[contractId] =
                ContractInfo({proxy: reg.proxy, beacon: reg.beacon, autoUpgrade: autoUpgrade, owner: reg.owner});
            l.proxyOf[orgId][reg.typeId] = reg.proxy;

            // Emit event for each contract
            emit ContractRegistered(contractId, orgId, reg.typeId, reg.proxy, reg.beacon, autoUpgrade, reg.owner);
        }

        // Update counts once at the end
        unchecked {
            o.contractCount += uint32(len);
            l.totalContracts += len;
        }

        // Finalize bootstrap if executor registered OR deployer signalled completion
        if ((o.executor != address(0) && callerIsExecutor) || (callerIsOwner && lastRegister)) {
            o.bootstrap = false;
        }
    }

    function setAutoUpgrade(bytes32 orgId, bytes32 typeId, bool enabled) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        address proxy = l.proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));
        l.contractOf[contractId].autoUpgrade = enabled;

        emit AutoUpgradeSet(contractId, enabled);
    }

    /* ═════════════════  VIEW HELPERS  ═════════════════ */
    function getOrgContract(bytes32 orgId, bytes32 typeId) external view returns (address proxy) {
        Layout storage l = _layout();
        if (!l.orgOf[orgId].exists) revert OrgUnknown();
        proxy = l.proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();
    }

    function getContractBeacon(bytes32 contractId) external view returns (address beacon) {
        Layout storage l = _layout();
        beacon = l.contractOf[contractId].beacon;
        if (beacon == address(0)) revert ContractUnknown();
    }

    function isAutoUpgrade(bytes32 contractId) external view returns (bool) {
        Layout storage l = _layout();
        ContractInfo storage c = l.contractOf[contractId];
        if (c.proxy == address(0)) revert ContractUnknown();
        return c.autoUpgrade;
    }

    /* enumeration helpers */
    function orgCount() external view returns (uint256) {
        return _layout().orgIds.length;
    }

    function getOrgIds() external view returns (bytes32[] memory) {
        return _layout().orgIds;
    }

    /* Public getters for storage variables */
    function orgOf(bytes32 orgId)
        external
        view
        returns (address executor, uint32 contractCount, bool bootstrap, bool exists)
    {
        OrgInfo storage o = _layout().orgOf[orgId];
        return (o.executor, o.contractCount, o.bootstrap, o.exists);
    }

    function contractOf(bytes32 contractId)
        external
        view
        returns (address proxy, address beacon, bool autoUpgrade, address owner)
    {
        ContractInfo storage c = _layout().contractOf[contractId];
        return (c.proxy, c.beacon, c.autoUpgrade, c.owner);
    }

    function proxyOf(bytes32 orgId, bytes32 typeId) external view returns (address) {
        return _layout().proxyOf[orgId][typeId];
    }

    function totalContracts() external view returns (uint256) {
        return _layout().totalContracts;
    }

    function orgIds(uint256 index) external view returns (bytes32) {
        return _layout().orgIds[index];
    }

    /* ══════════ HATS TREE REGISTRATION ══════════ */
    function registerHatsTree(bytes32 orgId, uint256 topHatId, uint256[] calldata roleHatIds) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();

        bool callerIsOwner = (msg.sender == owner());
        bool callerIsExecutor = (o.executor != address(0) && msg.sender == o.executor);

        if (callerIsOwner) {
            // owner path allowed only during bootstrap
            if (!o.bootstrap) revert OwnerOnlyDuringBootstrap();
        } else if (!callerIsExecutor) {
            revert NotOrgExecutor();
        }

        l.topHatOf[orgId] = topHatId;
        for (uint256 i = 0; i < roleHatIds.length; i++) {
            l.roleHatOf[orgId][i] = roleHatIds[i];
        }

        emit HatsTreeRegistered(orgId, topHatId, roleHatIds);
    }

    function getTopHat(bytes32 orgId) external view returns (uint256) {
        return _layout().topHatOf[orgId];
    }

    function getRoleHat(bytes32 orgId, uint256 roleIndex) external view returns (uint256) {
        return _layout().roleHatOf[orgId][roleIndex];
    }
}
