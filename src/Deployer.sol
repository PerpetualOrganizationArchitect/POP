// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────────  OpenZeppelin  ───────────────────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/*────────────────────────────── Core deps ──────────────────────────────*/
import "./OrgRegistry.sol";

/*──────────────────── External management contracts ────────────────────*/
interface IPoaManager {
    function getBeacon(string calldata) external view returns (address);
    function getCurrentImplementation(string calldata) external view returns (address);
}

/*────────────────────── Module‑specific hooks ──────────────────────────*/
interface IMembership {
    function setQuickJoin(address) external;
}

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
}

/*── init‑selector helpers (reduce bytecode & safety) ────────────────────*/
interface IHybridVotingInit {
    function initialize(
        address membership_,
        address token_,
        address executor_,
        bytes32[] calldata roles,
        address[] calldata targets,
        uint8 quorumPct,
        uint8 ddSplit,
        bool quadratic,
        uint256 minBal
    ) external;
}

interface IParticipationVotingInit {
    function initialize(
        address executor_,
        address membership_,
        address token_,
        bytes32[] calldata roles,
        address[] calldata targets,
        uint8 quorumPct,
        bool quadratic,
        uint256 minBal
    ) external;
}

/*────────────────────────────  Errors  ───────────────────────────────*/
error InvalidAddress();
error EmptyInit();
error UnsupportedType();
error BeaconProbeFail();
error OrgExistsMismatch();

/*───────────────────────────  Deployer  ───────────────────────────────*/
contract Deployer is Initializable, OwnableUpgradeable {
    /*───────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.deployer.storage
    struct Layout {
        /* immutables */
        IPoaManager poaManager;
        OrgRegistry orgRegistry;
    }

    // keccak256("poa.deployer.storage") to get a unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0x4f6cf4b446a382b8bde8d35e8ca59cc30d80d9a326b56d1a5212b27a0198fc7f;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /* Local definition of OrgInfo struct to match OrgRegistry */
    struct OrgInfo {
        address executor;
        uint32 contractCount;
        bool bootstrap;
        bool exists;
        string metaCID;
    }

    /* events */
    event ContractDeployed(
        bytes32 indexed orgId, bytes32 indexed typeId, address proxy, address beacon, bool autoUpgrade, address owner
    );

    /* initializer */
    constructor() initializer {}

    function initialize(address _poaManager, address _orgRegistry) public initializer {
        if (_poaManager == address(0) || _orgRegistry == address(0)) revert InvalidAddress();
        __Ownable_init(msg.sender);

        Layout storage l = _layout();
        l.poaManager = IPoaManager(_poaManager);
        l.orgRegistry = OrgRegistry(_orgRegistry);
    }

    /*──────────────────────── INTERNAL CORE ───────────────────────*/
    function _deploy(
        bytes32 orgId,
        string memory typeName, // human string
        address moduleOwner, // normally the org executor
        bool autoUpgrade,
        address customImpl, // optional bespoke logic
        bytes memory initData,
        bool lastRegister // only TRUE for *final* owner‑side registration
    ) internal returns (address proxy) {
        if (initData.length == 0) revert EmptyInit();

        Layout storage l = _layout();

        /* 1. beacon handling */
        address beacon;
        if (autoUpgrade) {
            if (customImpl != address(0)) revert UnsupportedType();
            beacon = l.poaManager.getBeacon(typeName);
            if (beacon == address(0)) revert UnsupportedType();
            // paranoia‑check – the PoaManager must own the beacon
            (bool ok,) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
            if (!ok || Ownable(beacon).owner() != address(l.poaManager)) revert BeaconProbeFail();
        } else {
            address impl = (customImpl == address(0)) ? l.poaManager.getCurrentImplementation(typeName) : customImpl;
            if (impl == address(0)) revert UnsupportedType();
            beacon = address(new UpgradeableBeacon(impl, moduleOwner));
        }

        /* 2. create proxy */
        proxy = address(new BeaconProxy(beacon, initData));

        /* 3. book‑keeping in OrgRegistry */
        bytes32 typeId = keccak256(bytes(typeName));
        l.orgRegistry.registerOrgContract(orgId, typeId, proxy, beacon, autoUpgrade, moduleOwner, lastRegister);

        emit ContractDeployed(orgId, typeId, proxy, beacon, autoUpgrade, moduleOwner);
    }

    /*══════════════  MODULE‑SPECIFIC DEPLOY HELPERS  ═════════════=*/
    /*---------  Executor  (first, we need its address everywhere) ---------*/
    function _deployExecutor(bytes32 orgId, address executorEOA, bool autoUp, address customImpl)
        internal
        returns (address execProxy)
    {
        bytes memory init = abi.encodeWithSignature("initialize(address)", executorEOA);
        execProxy = _deploy(orgId, "Executor", executorEOA, autoUp, customImpl, init, false);
    }

    /*---------  Membership NFT  ---------*/
    function _deployMembership(
        bytes32 orgId,
        address executorAddr,
        string memory orgName,
        bool autoUp,
        address customImpl
    ) internal returns (address membershipProxy) {
        /* build minimal default role‑set */
        string[] memory names = new string[](2);
        string[] memory images = new string[](2);
        bool[] memory canVote = new bool[](2);

        names[0] = "DEFAULT";
        names[1] = "EXECUTIVE";

        // Set meaningful image URIs for each role
        images[0] = "ipfs://default-role-image"; // Placeholder URI for default role
        images[1] = "ipfs://executive-role-image"; // Placeholder URI for executive role

        canVote[0] = true;
        canVote[1] = true;

        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = keccak256("EXECUTIVE");

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,string,string[],string[],bool[],bytes32[])",
            executorAddr,
            orgName,
            names,
            images,
            canVote,
            execRoles
        );

        membershipProxy = _deploy(orgId, "Membership", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  QuickJoin  ---------*/
    function _deployQuickJoin(
        bytes32 orgId,
        address executorAddr,
        address membership,
        address registry,
        address masterDeploy,
        bool autoUp,
        address customImpl
    ) internal returns (address qjProxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,address,address)", executorAddr, membership, registry, masterDeploy
        );
        qjProxy = _deploy(orgId, "QuickJoin", executorAddr, autoUp, customImpl, init, false);
        IMembership(membership).setQuickJoin(qjProxy);
    }

    /*---------  ParticipationToken  ---------*/
    function _deployPT(
        bytes32 orgId,
        address executorAddr,
        string memory name,
        string memory symbol,
        address membership,
        bool autoUp,
        address customImpl
    ) internal returns (address ptProxy) {
        bytes memory init =
            abi.encodeWithSignature("initialize(address,string,string,address)", executorAddr, name, symbol, membership);
        ptProxy = _deploy(orgId, "ParticipationToken", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  TaskManager  ---------*/
    function _deployTaskManager(
        bytes32 orgId,
        address executorAddr,
        address token,
        address membership,
        bool autoUp,
        address customImpl
    ) internal returns (address tmProxy) {
        bytes32[] memory execOnly = new bytes32[](1);
        execOnly[0] = keccak256("EXECUTIVE");

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,bytes32[],address)", token, membership, execOnly, executorAddr
        );
        tmProxy = _deploy(orgId, "TaskManager", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  EducationHub  ---------*/
    function _deployEducationHub(
        bytes32 orgId,
        address executorAddr,
        address membership,
        address token,
        bool autoUp,
        address customImpl,
        bool lastRegister // <<< flag propagated to registry
    ) internal returns (address ehProxy) {
        bytes32[] memory execOnly = new bytes32[](1);
        execOnly[0] = keccak256("EXECUTIVE");

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,address,bytes32[])", token, membership, executorAddr, execOnly
        );
        ehProxy = _deploy(orgId, "EducationHub", executorAddr, autoUp, customImpl, init, lastRegister);
    }

    /*---------  HybridVoting  ---------*/
    function _deployHybridVoting(
        bytes32 orgId,
        address executorAddr,
        address membership,
        address token,
        bool autoUp,
        address customImpl,
        bool lastRegister
    ) internal returns (address hvProxy) {
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = keccak256("DEFAULT");
        roles[1] = keccak256("EXECUTIVE");
        roles[2] = keccak256("Member");

        address[] memory targets = new address[](2);
        targets[0] = membership;
        targets[1] = executorAddr;

        bytes memory init = abi.encodeWithSelector(
            IHybridVotingInit.initialize.selector,
            membership,
            token,
            executorAddr,
            roles,
            targets,
            50, // quorum %
            50, // DD/PT split %
            false,
            4 ether
        );
        hvProxy = _deploy(orgId, "HybridVoting", executorAddr, autoUp, customImpl, init, lastRegister);
    }

    /*════════════════  FULL ORG  DEPLOYMENT  ════════════════*/
    function deployFullOrg(
        bytes32 orgId,
        address executorEOA, // multisig / DAO address
        string calldata orgName,
        address registryAddr, // external username registry
        bool autoUpgrade
    )
        external
        returns (
            address hybridVoting,
            address executorAddr,
            address membership,
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        Layout storage l = _layout();

        /* 0. ensure Org exists (or create) */
        if (l.orgRegistry.orgCount() == 0 || !_orgExists(orgId)) {
            l.orgRegistry.registerOrg(orgId, executorEOA, orgName);
        } else {
            // Destructure the tuple returned by orgOf
            (address currentExec,,,,) = l.orgRegistry.orgOf(orgId);
            if (currentExec != executorEOA) revert OrgExistsMismatch();
        }

        /* 1. Executor  */
        executorAddr = _deployExecutor(orgId, executorEOA, autoUpgrade, address(0));

        /* 2. Membership NFT */
        membership = _deployMembership(orgId, executorAddr, orgName, autoUpgrade, address(0));

        /* 3. QuickJoin */
        quickJoin =
            _deployQuickJoin(orgId, executorAddr, membership, registryAddr, address(this), autoUpgrade, address(0));

        /* 4. Participation token */
        string memory tName = string(abi.encodePacked(orgName, " Token"));
        string memory tSymbol = "PT";
        participationToken = _deployPT(orgId, executorAddr, tName, tSymbol, membership, autoUpgrade, address(0));

        /* 5. TaskManager */
        taskManager = _deployTaskManager(orgId, executorAddr, participationToken, membership, autoUpgrade, address(0));
        IParticipationToken(participationToken).setTaskManager(taskManager);

        /* 6. EducationHub (no longer the final registration) */
        educationHub = _deployEducationHub(
            orgId,
            executorAddr,
            membership,
            participationToken,
            autoUpgrade,
            address(0),
            false // <--- Changed from true to false
        );
        IParticipationToken(participationToken).setEducationHub(educationHub);

        /* 7. HybridVoting governor (LAST owner-side registration → flips bootstrap) */
        hybridVoting = _deployHybridVoting(
            orgId,
            executorAddr,
            membership,
            participationToken,
            autoUpgrade,
            address(0),
            true // <--- Added lastRegister = true here
        );

        /* link executor to governor */
        IExecutorAdmin(executorAddr).setCaller(hybridVoting);
    }

    /*══════════════  UTILITIES  ═════════════=*/
    function getBeaconImplementation(address beacon) external view returns (address impl) {
        (bool ok, bytes memory ret) = beacon.staticcall(abi.encodeWithSignature("implementation()"));
        if (!ok) revert BeaconProbeFail();
        impl = abi.decode(ret, (address));
    }

    function _orgExists(bytes32 id) internal view returns (bool) {
        // Destructure the tuple to get the exists field (4th element)
        (,,, bool exists,) = _layout().orgRegistry.orgOf(id);
        return exists;
    }

    // Public getter for poaManager
    function poaManager() external view returns (address) {
        return address(_layout().poaManager);
    }

    // Public getter for orgRegistry
    function orgRegistry() external view returns (address) {
        return address(_layout().orgRegistry);
    }

    /* ─────────── Version ─────────── */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
