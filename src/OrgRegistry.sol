// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/* ─────────── Custom errors ─────────── */
error InvalidParam();
error OrgExists();
error OrgUnknown();
error TypeTaken();
error ContractUnknown();
error NotOrgExecutor();
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

    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.orgregistry.storage
    struct Layout {
        /* ───── Storage ───── */
        mapping(bytes32 => OrgInfo) orgOf; // orgId to OrgInfo
        mapping(bytes32 => ContractInfo) contractOf; // contractId to ContractInfo
        mapping(bytes32 => mapping(bytes32 => address)) proxyOf; // (orgId,typeId) to proxy
        bytes32[] orgIds;
        uint256 totalContracts;
    }

    // keccak256("poa.orgregistry.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x3ffb0627b419b7b77c77f589dd229844c112a8c125dceec0d56dda0674b35489;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* ───── Events ───── */
    event OrgRegistered(bytes32 indexed orgId, address indexed executor, bytes metaData);
    event MetaUpdated(bytes32 indexed orgId, bytes newMetaData);
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

    /* ═════════════════ ORG  LOGIC ═════════════════ */
    function registerOrg(bytes32 orgId, address executorAddr, bytes calldata metaData) external onlyOwner {
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
        emit OrgRegistered(orgId, executorAddr, metaData);
    }

    function updateOrgMeta(bytes32 orgId, bytes calldata newMetaData) external {
        Layout storage l = _layout();
        OrgInfo storage o = l.orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        emit MetaUpdated(orgId, newMetaData);
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
        bool callerIsExecutor = (msg.sender == o.executor);

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
        if (callerIsExecutor || (callerIsOwner && lastRegister)) {
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

    /* ─────────── Version ─────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
