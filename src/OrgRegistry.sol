// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";

/*──────────────────────────── Errors ───────────────────────────*/
error InvalidParam();
error OrgExists();
error OrgUnknown();
error TypeTaken();
error ContractUnknown();
error NotRegistryOrOrg();
error NotOrgOwner();

/*─────────────────────────── Registry ──────────────────────────*/
contract OrgRegistry is Ownable(msg.sender) {
    /*──────────── Data structs ───────────*/
    struct ContractInfo {
        address proxy; // BeaconProxy address
        address beacon; // Beacon address
        bool autoUpgrade; // true = follows PoaManager beacon
        address owner; // module owner
    }

    struct OrgInfo {
        address owner;
        string name;
        uint32 contractCount;
        bool exists;
    }

    /*──────────── Storage ───────────*/
    mapping(bytes32 => OrgInfo) public orgOf; // orgId to OrgInfo
    mapping(bytes32 => ContractInfo) public contractOf; // contractId to ContractInfo
    mapping(bytes32 => mapping(bytes32 => address)) public proxyOf; // orgId to typeId to proxy

    bytes32[] public orgIds; // all orgIds for enumeration
    uint256 public totalContracts; // running total of registered contracts

    /*──────────── Events ───────────*/
    event OrgRegistered(bytes32 indexed orgId, address owner, string name);
    event ContractRegistered(
        bytes32 indexed contractId,
        bytes32 indexed orgId,
        bytes32 indexed typeId,
        address proxy,
        address beacon,
        bool autoUpgrade,
        address owner
    );

    /*──────────── Modifiers ─────────*/
    modifier onlyRegistryOrOrg(bytes32 orgId) {
        if (msg.sender != owner() && msg.sender != orgOf[orgId].owner) {
            revert NotRegistryOrOrg();
        }
        _;
    }

    /*────────────────── Org logic ─────────────────*/
    function registerOrg(bytes32 orgId, address orgOwner, string calldata name) external onlyOwner {
        if (orgId == bytes32(0) || orgOwner == address(0)) revert InvalidParam();
        if (orgOf[orgId].exists) revert OrgExists();

        orgOf[orgId] = OrgInfo({owner: orgOwner, name: name, contractCount: 0, exists: true});
        orgIds.push(orgId);

        emit OrgRegistered(orgId, orgOwner, name);
    }

    /*──────────────── Contract logic ──────────────*/
    function registerOrgContract(
        bytes32 orgId,
        string calldata typeName,
        address proxy,
        address beacon,
        bool autoUp,
        address moduleOwner
    ) external onlyRegistryOrOrg(orgId) {
        if (!orgOf[orgId].exists) revert OrgUnknown();
        if (bytes(typeName).length == 0 || proxy == address(0) || beacon == address(0) || moduleOwner == address(0)) {
            revert InvalidParam();
        }

        bytes32 typeId = keccak256(bytes(typeName));
        if (proxyOf[orgId][typeId] != address(0)) revert TypeTaken();

        // Build deterministic contractId = keccak256(orgId, typeId)
        bytes32 contractId = keccak256(abi.encodePacked(orgId, typeId));

        contractOf[contractId] = ContractInfo({proxy: proxy, beacon: beacon, autoUpgrade: autoUp, owner: moduleOwner});
        proxyOf[orgId][typeId] = proxy;

        unchecked {
            orgOf[orgId].contractCount++;
            totalContracts++;
        }

        emit ContractRegistered(contractId, orgId, typeId, proxy, beacon, autoUp, moduleOwner);
    }

    /*────────────── View helpers ─────────────*/
    function getOrgContract(bytes32 orgId, string calldata typeName) external view returns (address) {
        if (!orgOf[orgId].exists) revert OrgUnknown();
        address proxy = proxyOf[orgId][keccak256(bytes(typeName))];
        if (proxy == address(0)) revert ContractUnknown();
        return proxy;
    }

    function getContractBeacon(bytes32 contractId) external view returns (address) {
        address beacon = contractOf[contractId].beacon;
        if (beacon == address(0)) revert ContractUnknown();
        return beacon;
    }

    function isAutoUpgrade(bytes32 contractId) external view returns (bool) {
        if (contractOf[contractId].proxy == address(0)) revert ContractUnknown();
        return contractOf[contractId].autoUpgrade;
    }

    /// @notice Number of registered orgs
    function orgCount() external view returns (uint256) {
        return orgIds.length;
    }

    /*──────────── Storage gap ────────────*/
    uint256[46] private __gap;
}
