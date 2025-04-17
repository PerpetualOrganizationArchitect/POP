// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*───────────────────────  PoaManager  ─────────────────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ImplementationRegistry.sol";

contract PoaManager is Ownable(msg.sender) {
    /*──────────── Errors ───────────*/
    error TypeExists();
    error TypeUnknown();
    error ImplZero();
    error SameImplementation();

    /*──────────── Storage ──────────*/
    mapping(bytes32 => UpgradeableBeacon) public beacons; // typeId ⇒ beacon
    bytes32[] public typeIds;
    ImplementationRegistry public immutable registry;

    /*──────────── Events ───────────*/
    event BeaconCreated(bytes32 indexed typeId, string typeName, address beacon, address implementation);
    event BeaconUpgraded(bytes32 indexed typeId, address newImplementation, string version);

    constructor(address registryAddr) {
        if (registryAddr == address(0)) revert ImplZero();
        registry = ImplementationRegistry(registryAddr);
    }

    /*──────────── Internal utils ───────────*/
    function _id(string calldata s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    /*──────────── Admin: add & bootstrap ───────────*/
    function addContractType(string calldata typeName, address impl) external onlyOwner {
        if (impl == address(0)) revert ImplZero();
        bytes32 tId = _id(typeName);
        if (address(beacons[tId]) != address(0)) revert TypeExists();

        UpgradeableBeacon beacon = new UpgradeableBeacon(impl, address(this));
        beacons[tId] = beacon;
        typeIds.push(tId);

        // auto‑register as v1 & mark latest
        registry.registerImplementation(typeName, "v1", impl, true);

        emit BeaconCreated(tId, typeName, address(beacon), impl);
    }

    /*──────────── Admin: upgrade ───────────*/
    function upgradeBeacon(string calldata typeName, address newImpl, string calldata version) external onlyOwner {
        if (newImpl == address(0)) revert ImplZero();
        bytes32 tId = _id(typeName);
        UpgradeableBeacon beacon = beacons[tId];
        if (address(beacon) == address(0)) revert TypeUnknown();
        if (beacon.implementation() == newImpl) revert SameImplementation();

        // register & upgrade
        registry.registerImplementation(typeName, version, newImpl, true);
        beacon.upgradeTo(newImpl);

        emit BeaconUpgraded(tId, newImpl, version);
    }

    /*──────────── Views ───────────*/
    function getBeacon(string calldata typeName) external view returns (address) {
        address b = address(beacons[_id(typeName)]);
        if (b == address(0)) revert TypeUnknown();
        return b;
    }

    function getCurrentImplementation(string calldata typeName) external view returns (address) {
        UpgradeableBeacon b = beacons[_id(typeName)];
        if (address(b) == address(0)) revert TypeUnknown();
        return b.implementation();
    }

    function contractTypeCount() external view returns (uint256) {
        return typeIds.length;
    }
}
