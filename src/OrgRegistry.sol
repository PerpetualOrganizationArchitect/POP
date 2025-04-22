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
        string metaCID; // IPFS / Arweave metadata for the org
    }

    /* ───── Storage ───── */
    mapping(bytes32 => OrgInfo) public orgOf; // orgId to OrgInfo
    mapping(bytes32 => ContractInfo) public contractOf; // contractId to ContractInfo
    mapping(bytes32 => mapping(bytes32 => address)) public proxyOf; // (orgId,typeId) to proxy

    bytes32[] public orgIds;
    uint256 public totalContracts;

    /* ───── Events ───── */
    event OrgRegistered(bytes32 indexed orgId, address indexed executor, string metaCID);
    event MetaUpdated(bytes32 indexed orgId, string newCID);
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
    function registerOrg(bytes32 orgId, address executorAddr, string calldata metaCID) external onlyOwner {
        if (orgId == bytes32(0) || executorAddr == address(0)) revert InvalidParam();
        if (orgOf[orgId].exists) revert OrgExists();

        orgOf[orgId] = OrgInfo({
            executor: executorAddr,
            contractCount: 0,
            bootstrap: true, // owner can add modules while true
            exists: true,
            metaCID: metaCID
        });
        orgIds.push(orgId);
        emit OrgRegistered(orgId, executorAddr, metaCID);
    }

    function updateOrgMeta(bytes32 orgId, string calldata newCID) external {
        OrgInfo storage o = orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        o.metaCID = newCID;
        emit MetaUpdated(orgId, newCID);
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
        OrgInfo storage o = orgOf[orgId];
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
        if (proxyOf[orgId][typeId] != address(0)) revert TypeTaken();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));

        contractOf[contractId] = ContractInfo({proxy: proxy, beacon: beacon, autoUpgrade: autoUp, owner: moduleOwner});
        proxyOf[orgId][typeId] = proxy;

        unchecked {
            ++o.contractCount;
            ++totalContracts;
        }
        emit ContractRegistered(contractId, orgId, typeId, proxy, beacon, autoUp, moduleOwner);

        // Finish bootstrap if executor registered OR deployer signalled completion
        if (callerIsExecutor || (callerIsOwner && lastRegister)) {
            o.bootstrap = false;
        }
    }

    function setAutoUpgrade(bytes32 orgId, bytes32 typeId, bool enabled) external {
        OrgInfo storage o = orgOf[orgId];
        if (!o.exists) revert OrgUnknown();
        if (msg.sender != o.executor) revert NotOrgExecutor();

        address proxy = proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();

        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));
        contractOf[contractId].autoUpgrade = enabled;

        emit AutoUpgradeSet(contractId, enabled);
    }

    /* ═════════════════  VIEW HELPERS  ═════════════════ */
    function getOrgContract(bytes32 orgId, bytes32 typeId) external view returns (address proxy) {
        if (!orgOf[orgId].exists) revert OrgUnknown();
        proxy = proxyOf[orgId][typeId];
        if (proxy == address(0)) revert ContractUnknown();
    }

    function getContractBeacon(bytes32 contractId) external view returns (address beacon) {
        beacon = contractOf[contractId].beacon;
        if (beacon == address(0)) revert ContractUnknown();
    }

    function isAutoUpgrade(bytes32 contractId) external view returns (bool) {
        ContractInfo storage c = contractOf[contractId];
        if (c.proxy == address(0)) revert ContractUnknown();
        return c.autoUpgrade;
    }

    /* enumeration helpers */
    function orgCount() external view returns (uint256) {
        return orgIds.length;
    }

    function getOrgMeta(bytes32 orgId) external view returns (string memory) {
        return orgOf[orgId].metaCID;
    }

    function getOrgIds() external view returns (bytes32[] memory) {
        return orgIds;
    }

    /* ─────────── Version ─────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }

    /* ─────────── Storage gap ─────────── */
    uint256[50] private __gap;
}
