// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.17;

/*────────────── OpenZeppelin ─────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/*────────────── Local deps ───────────────*/
import "./OrgRegistry.sol";

/*──────────── External manager ───────────*/
interface IPoaManager {
    function getBeacon(string calldata) external view returns (address);
    function getCurrentImplementation(string calldata) external view returns (address);
}

/*──────────── Module hooks ───────────────*/
interface INFTMembership {
    function setQuickJoin(address) external;
}

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

/*── Executor admin interface (setCaller) ─*/
interface IExecutorAdmin {
    function setCaller(address) external;
}

/*── HybridVoting initializer selector ────*/
interface IHybridVotingInit {
    function initialize(
        address owner_, // multisig / DAO owner
        address membership_, // NFT membership address
        address token_, // participation token
        address executor_, // batch‑executor
        bytes32[] calldata roleHashes,
        address[] calldata initialTargets,
        uint8 quorumPct,
        uint8 ddSharePct,
        bool quadratic,
        uint256 minBalance
    ) external;
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
            if (!ok || Ownable(beacon).owner() != address(poaManager)) revert BeaconProbeFail();
        } else {
            address impl = customImpl == address(0) ? poaManager.getCurrentImplementation(contractType) : customImpl;
            if (impl == address(0)) revert UnsupportedType();

            beacon = address(new UpgradeableBeacon(impl, orgOwner));
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
        /* default & executive roles with voting rights */
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
        bytes memory init =
            abi.encodeWithSignature("initialize(string,string,address)", tokenName, tokenSymbol, membership);
        proxy = _deployContract(orgId, "ParticipationToken", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── TaskManager ─────────────*/
    function deployTaskManager(
        bytes32 orgId,
        address orgOwner,
        address token,
        address membership,
        bytes32[] memory creatorRoles,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init =
            abi.encodeWithSignature("initialize(address,address,bytes32[])", token, membership, creatorRoles);
        proxy = _deployContract(orgId, "TaskManager", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── EducationHub ─────────────*/
    function deployEducationHub(
        bytes32 orgId,
        address orgOwner,
        address membership,
        address token,
        bytes32[] memory creatorRoles,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes memory init =
            abi.encodeWithSignature("initialize(address,address,bytes32[])", token, membership, creatorRoles);
        proxy = _deployContract(orgId, "EducationHub", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── Executor (batch caller) ─────────────*/
    function deployExecutor(bytes32 orgId, address orgOwner, bool autoUpgrade, address customImpl)
        public
        returns (address proxy)
    {
        bytes memory init = abi.encodeWithSignature("initialize(address)", orgOwner);
        proxy = _deployContract(orgId, "Executor", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── HybridVoting ─────────────*/
    function deployHybridVoting(
        bytes32 orgId,
        address orgOwner,
        address membership,
        address token,
        address executorAddr,
        bool autoUpgrade,
        address customImpl
    ) public returns (address proxy) {
        bytes32[] memory roleHashes = new bytes32[](3);
        roleHashes[0] = keccak256("DEFAULT");
        roleHashes[1] = keccak256("EXECUTIVE");
        roleHashes[2] = keccak256("Member");

        address[] memory emptyTargets = new address[](0);

        bytes memory init = abi.encodeWithSelector(
            IHybridVotingInit.initialize.selector,
            orgOwner,
            membership,
            token,
            executorAddr,
            roleHashes,
            emptyTargets,
            50, // quorum %
            50, // 50‑50 split DD vs participation
            false, // quadratic disabled by default
            4 ether // min balance
        );
        proxy = _deployContract(orgId, "HybridVoting", orgOwner, autoUpgrade, customImpl, init);
        return proxy;
    }

    /*──────────── Full‑org bundle (updated) ─────────────*/
    function deployFullOrg(
        bytes32 orgId,
        address orgOwner,
        string calldata orgName,
        address registry,
        address treasury, // retained for possible future modules
        bool autoUpgrade
    )
        external
        returns (
            address hybridVoting,
            address executorAddr,
            address membership,
            address quickjoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        /* ─── 0. ensure org record ─── */
        if (_orgExists(orgId)) {
            (address recordedOwner,,,) = orgRegistry.orgOf(orgId);
            if (recordedOwner != orgOwner) revert OrgExistsMismatch();
        } else {
            orgRegistry.registerOrg(orgId, orgOwner, orgName);
        }

        /* ─── 1. Membership NFT ─── */
        membership = deployMembership(orgId, orgOwner, orgName, autoUpgrade, address(0), true);

        /* ─── 2. QuickJoin helper ─── */
        quickjoin = deployQuickJoin(orgId, orgOwner, membership, registry, address(this), autoUpgrade, address(0));

        /* ─── 3. Participation token ─── */
        string memory tokenName = string(abi.encodePacked(orgName, " Token"));
        string memory tokenSymbol = "TKN";
        participationToken =
            deployParticipationToken(orgId, orgOwner, tokenName, tokenSymbol, membership, autoUpgrade, address(0));

        /* ─── 4. Executor (temp caller = orgOwner) ─── */
        executorAddr = deployExecutor(orgId, orgOwner, autoUpgrade, address(0));

        /* ─── 5. Hybrid governor ─── */
        hybridVoting =
            deployHybridVoting(orgId, orgOwner, membership, participationToken, executorAddr, autoUpgrade, address(0));

        /*   tie executor to governor   */
        IExecutorAdmin(executorAddr).setCaller(hybridVoting);

        /* ─── 6. Task manager & Education hub ─── */
        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = keccak256("EXECUTIVE");
        taskManager =
            deployTaskManager(orgId, orgOwner, participationToken, membership, execRoles, autoUpgrade, address(0));
        IParticipationToken(participationToken).setTaskManager(taskManager);

        bytes32[] memory creatorRoles = new bytes32[](1);
        creatorRoles[0] = keccak256("EXECUTIVE");
        educationHub =
            deployEducationHub(orgId, orgOwner, membership, participationToken, creatorRoles, autoUpgrade, address(0));
        IParticipationToken(participationToken).setEducationHub(educationHub);
    }

    /*──────────── Utilities ────────────*/
    function getBeaconImplementation(address beacon) external view returns (address impl) {
        (bool ok, bytes memory ret) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
        if (!ok) revert BeaconProbeFail();
        impl = abi.decode(ret, (address));
    }

    function _orgExists(bytes32 id) internal view returns (bool) {
        (,,, bool exists) = orgRegistry.orgOf(id);
        return exists;
    }
}
