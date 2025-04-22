// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*───────────────────  ImplementationRegistry  ───────────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

contract ImplementationRegistry is Initializable, OwnableUpgradeable {
    /*──────────── Custom errors ───────────*/
    error EmptyString();
    error ImplZero();
    error VersionExists();
    error TypeUnknown();
    error VersionUnknown();

    /*──────────── Storage ────────────────*/
    struct Meta {
        bytes32[] versions; // ordered list of versionIds
        bytes32 latest; // latest versionId
        bool exists; // type exists flag
    }

    //  typeId ⇒ (versionId ⇒ impl)
    mapping(bytes32 => mapping(bytes32 => address)) private _impls;
    //  typeId ⇒ Meta
    mapping(bytes32 => Meta) private _meta;

    // master list of typeIds for off‑chain iteration
    bytes32[] public typeIds;

    /*──────────── Events ────────────────*/
    event ImplementationRegistered(
        bytes32 indexed typeId,
        string typeName,
        bytes32 indexed versionId,
        string version,
        address implementation,
        bool latest
    );

    /*───────── Initializer ─────────────*/
    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    /*───────── Internal utils ───────────*/
    function _id(string calldata s) internal pure returns (bytes32) {
        if (bytes(s).length == 0) revert EmptyString();
        return keccak256(bytes(s));
    }

    /*───────── External API ─────────────*/
    function registerImplementation(string calldata typeName, string calldata version, address impl, bool setLatest)
        external
        onlyOwner
    {
        if (impl == address(0)) revert ImplZero();

        bytes32 tId = _id(typeName);
        bytes32 vId = _id(version);

        if (_impls[tId][vId] != address(0)) revert VersionExists();

        // first time this type?
        if (!_meta[tId].exists) {
            _meta[tId].exists = true;
            typeIds.push(tId);
        }
        // store
        _impls[tId][vId] = impl;
        _meta[tId].versions.push(vId);

        if (setLatest) _meta[tId].latest = vId;

        emit ImplementationRegistered(tId, typeName, vId, version, impl, setLatest);
    }

    function setLatestVersion(string calldata typeName, string calldata version) external onlyOwner {
        bytes32 tId = _id(typeName);
        bytes32 vId = _id(version);

        if (_impls[tId][vId] == address(0)) revert VersionUnknown();
        _meta[tId].latest = vId;
    }

    /*──────── View helpers ────────*/
    function getLatestImplementation(string calldata typeName) external view returns (address) {
        bytes32 tId = _id(typeName);
        bytes32 vId = _meta[tId].latest;
        if (vId == bytes32(0)) revert TypeUnknown();
        return _impls[tId][vId];
    }

    function getImplementation(string calldata typeName, string calldata version) external view returns (address) {
        bytes32 tId = _id(typeName);
        bytes32 vId = _id(version);
        address impl = _impls[tId][vId];
        if (impl == address(0)) revert VersionUnknown();
        return impl;
    }

    function getVersionCount(string calldata typeName) external view returns (uint256) {
        return _meta[_id(typeName)].versions.length;
    }

    function getVersionIdAt(string calldata typeName, uint256 index) external view returns (bytes32) {
        Meta storage m = _meta[_id(typeName)];
        if (index >= m.versions.length) revert VersionUnknown();
        return m.versions[index];
    }

    function typeCount() external view returns (uint256) {
        return typeIds.length;
    }
}
