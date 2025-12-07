// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*───────────────────────  PoaManager v1.0.1  ─────────────────────────*/
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
    mapping(bytes32 => UpgradeableBeacon) public beacons; // typeId to beacon
    bytes32[] public typeIds;
    ImplementationRegistry public registry; // Remove immutable since we need to update it

    /*──────────── Events ───────────*/
    event BeaconCreated(bytes32 indexed typeId, string typeName, address beacon, address implementation);
    event BeaconUpgraded(bytes32 indexed typeId, address newImplementation, string version);
    event RegistryUpdated(address oldRegistry, address newRegistry);
    event InfrastructureDeployed(
        address orgDeployer,
        address orgRegistry,
        address implRegistry,
        address paymasterHub,
        address globalAccountRegistry
    );

    constructor(address registryAddr) {
        // Allow a temporary zero address during initialization
        // This will be updated with updateImplRegistry
        registry = ImplementationRegistry(registryAddr);
    }

    /*──────────── Admin: update registry ───────────*/
    function updateImplRegistry(address registryAddr) external onlyOwner {
        if (registryAddr == address(0)) revert ImplZero();
        address oldRegistry = address(registry);
        registry = ImplementationRegistry(registryAddr);
        emit RegistryUpdated(oldRegistry, registryAddr);
    }

    /*──────────── Admin: register infrastructure ───────────*/
    function registerInfrastructure(
        address _orgDeployer,
        address _orgRegistry,
        address _implRegistry,
        address _paymasterHub,
        address _globalAccountRegistry
    ) external onlyOwner {
        emit InfrastructureDeployed(
            _orgDeployer,
            _orgRegistry,
            _implRegistry,
            _paymasterHub,
            _globalAccountRegistry
        );
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

        // Only try to register in the implementation registry if it exists
        // This allows us to register the ImplementationRegistry itself first
        if (address(registry) != address(0)) {
            registry.registerImplementation(typeName, "v1", impl, true);
        }

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
    function getBeaconById(bytes32 typeId) external view returns (address) {
        address b = address(beacons[typeId]);
        if (b == address(0)) revert TypeUnknown();
        return b;
    }

    function getCurrentImplementationById(bytes32 typeId) external view returns (address) {
        UpgradeableBeacon b = beacons[typeId];
        if (address(b) == address(0)) revert TypeUnknown();
        return b.implementation();
    }

    function contractTypeCount() external view returns (uint256) {
        return typeIds.length;
    }
}
