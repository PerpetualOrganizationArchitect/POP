// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*────────────── OpenZeppelin ─────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./OrgRegistry.sol";

/*──────────── External manager ───────────*/
interface IPoaManager {
    function getBeacon(string calldata) external view returns (address);
    function getCurrentImplementation(string calldata) external view returns (address);
}

/*──────────── Module hooks ───────────────*/
interface IDirectDemocracyVoting {
    function setElectionsContract(address) external;
}

interface INFTMembership {
    function setQuickJoin(address) external;
    function setElectionContract(address) external;
}

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IOwnable {
    function owner() external view returns (address);
}

/*──────────────────── Deployer ───────────────────*/
contract Deployer is Ownable(msg.sender) {
    /*──────── Custom errors ────────*/
    error InvalidAddress();
    error EmptyInit();
    error UnsupportedType();
    error BeaconProbeFail();
    error OrgExistsMismatch();

    /*──────── Immutables ───────────*/
    IPoaManager public immutable poaManager;
    OrgRegistry public immutable orgRegistry;

    event ContractDeployed(
        bytes32 indexed orgId, string contractType, address proxy, address beacon, bool autoUpgrade, address orgOwner
    );

    constructor(address _poaManager, address _orgRegistry) {
        if (_poaManager == address(0) || _orgRegistry == address(0)) revert InvalidAddress();
        poaManager = IPoaManager(_poaManager);
        orgRegistry = OrgRegistry(_orgRegistry);
    }

    /*──────────────── Core factory ───────────────*/
    function _deployContract(
        bytes32 orgId,
        string memory contractType,
        address orgOwner,
        bool autoUpgrade,
        address customImpl,
        bytes memory initData
    ) internal returns (address proxy) {
        if (bytes(contractType).length == 0) revert UnsupportedType();
        if (orgOwner == address(0)) revert InvalidAddress();
        if (initData.length == 0) revert EmptyInit();

        /*── 1. Beacon ──*/
        address beacon;
        if (autoUpgrade) {
            if (customImpl != address(0)) revert UnsupportedType();
            beacon = poaManager.getBeacon(contractType);
            if (beacon == address(0)) revert UnsupportedType();

            (bool ok,) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
            if (!ok || IOwnable(beacon).owner() != address(poaManager)) revert BeaconProbeFail();
        } else {
            address impl = customImpl == address(0) ? poaManager.getCurrentImplementation(contractType) : customImpl;
            if (impl == address(0)) revert UnsupportedType();

            UpgradeableBeacon newBeacon = new UpgradeableBeacon(impl, orgOwner);
            beacon = address(newBeacon);
        }

        /*── 2. Proxy ──*/
        proxy = address(new BeaconProxy(beacon, initData));

        /*── 3. Registry ──*/
        orgRegistry.registerOrgContract(orgId, contractType, proxy, beacon, autoUpgrade, orgOwner);
        emit ContractDeployed(orgId, contractType, proxy, beacon, autoUpgrade, orgOwner);
    }

    /*──────────── Membership ─────────────*/
    function deployMembership(
        bytes32 orgId,
        address orgOwner,
        string calldata orgName,
        bool autoUpgrade,
        address customImpl,
        bool isNFT
    ) public returns (address proxy) {
        if (bytes(orgName).length == 0) revert UnsupportedType();

        bytes memory init = isNFT
            ? _membershipInit(orgOwner, orgName)
            : abi.encodeWithSignature("initialize(address,string)", orgOwner, orgName);

        proxy = _deployContract(orgId, "Membership", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    function _membershipInit(address owner_, string calldata name_) private pure returns (bytes memory) {
        string[] memory roleNames = new string[](2);
        string[] memory roleImages = new string[](2);
        bool[] memory roleVote = new bool[](2);

        roleNames[0] = "DEFAULT";
        roleNames[1] = "EXECUTIVE";
        roleImages[0] = "https://example.com/default.png";
        roleImages[1] = "https://example.com/executive.png";
        roleVote[0] = true;
        roleVote[1] = true;

        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = keccak256("EXECUTIVE");

        return abi.encodeWithSignature(
            "initialize(address,string,string[],string[],bool[],bytes32[])",
            owner_,
            name_,
            roleNames,
            roleImages,
            roleVote,
            execRoles
        );
    }

    /*──────────── QuickJoin ─────────────*/
    function deployQuickJoin(
        bytes32 orgId,
        address orgOwner,
        address membership,
        address registry,
        address master,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,address,address)", orgOwner, membership, registry, master
        );
        proxy = _deployContract(orgId, "QuickJoin", orgOwner, autoUpgrade, customImpl, init);
        INFTMembership(membership).setQuickJoin(proxy);
        return proxy;
    }

    /*──────────── Voting ─────────────*/
    function deployDirectDemocracyVoting(
        bytes32 orgId,
        address orgOwner,
        address membership,
        address treasury,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        string[] memory roles = new string[](3);
        roles[0] = "DEFAULT";
        roles[1] = "EXECUTIVE";
        roles[2] = "Member";

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,string[],address,uint256)", orgOwner, membership, roles, treasury, 50
        );
        proxy = _deployContract(orgId, "DirectDemocracyVoting", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── Election ─────────────*/
    function deployElectionContract(
        bytes32 orgId,
        address orgOwner,
        address membership,
        address voting,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init = abi.encodeWithSignature("initialize(address,address,address)", orgOwner, membership, voting);
        proxy = _deployContract(orgId, "ElectionContract", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── ParticipationToken ─────────────*/
    function deployParticipationToken(
        bytes32 orgId,
        address orgOwner,
        string memory tokenName,
        string memory tokenSymbol,
        address membership,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(string,string,address)", tokenName, tokenSymbol, membership
        );
        proxy = _deployContract(orgId, "ParticipationToken", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── TaskManager ─────────────*/
    function deployTaskManager(
        bytes32 orgId,
        address orgOwner,
        address token,
        address membership,
        bytes32[] memory creatorRoleIds,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,bytes32[])", token, membership, creatorRoleIds
        );
        proxy = _deployContract(orgId, "TaskManager", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── Bundle helper ─────────────*/
    function deployFullOrg(
        bytes32 orgId,
        address orgOwner,
        string calldata orgName,
        address registry,
        address treasury,
        bool autoUpgrade
    ) external returns (
        address voting,
        address election,
        address membership,
        address quickjoin,
        address participationToken,
        address taskManager
    ) {
        if (_orgExists(orgId)) {
            (address recordedOwner,,,) = orgRegistry.orgOf(orgId);
            if (recordedOwner != orgOwner) revert OrgExistsMismatch();
        } else {
            orgRegistry.registerOrg(orgId, orgOwner, orgName);
        }

        membership = deployMembership(orgId, orgOwner, orgName, autoUpgrade, address(0), true);
        voting = deployDirectDemocracyVoting(orgId, orgOwner, membership, treasury, autoUpgrade, address(0));
        election = deployElectionContract(orgId, orgOwner, membership, voting, autoUpgrade, address(0));

        IDirectDemocracyVoting(voting).setElectionsContract(election);
        INFTMembership(membership).setElectionContract(election);

        quickjoin = deployQuickJoin(orgId, orgOwner, membership, registry, address(this), autoUpgrade, address(0));
        
        // Deploy participation token
        string memory tokenName = string(abi.encodePacked(orgName, " Token"));
        string memory tokenSymbol = "TKN";
        participationToken = deployParticipationToken(
            orgId, orgOwner, tokenName, tokenSymbol, membership, autoUpgrade, address(0)
        );
        
        // Deploy task manager
        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = keccak256("EXECUTIVE");
        taskManager = deployTaskManager(
            orgId, orgOwner, participationToken, membership, execRoles, autoUpgrade, address(0)
        );
        
        // Link token with task manager
        IParticipationToken(participationToken).setTaskManager(taskManager);
    }

    /*──────────── Utilities ────────────*/
    function getBeaconImplementation(address beacon) external view returns (address impl) {
        (bool ok, bytes memory ret) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
        if (!ok) revert BeaconProbeFail();
        impl = abi.decode(ret, (address));
    }

    function _orgExists(bytes32 id) internal view returns (bool) {
        (,,,bool exists) = orgRegistry.orgOf(id);
        return exists;
    }
}
