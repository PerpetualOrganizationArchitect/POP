// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────────  OpenZeppelin  ───────────────────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import { Hats } from "@hats-protocol/src/Hats.sol";
import { EligibilityModule } from "./EligibilityModule.sol";
import { ToggleModule } from "./ToggleModule.sol";

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

    Hats public hats;
    EligibilityModule public eligibilityModule;
    ToggleModule public toggleModule;

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
        hats = Hats(0x3bc1A0Ad72417f2d411118085256fC53CBdDd137);
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
        address customImpl,
        string[] memory roleNames,
        string[] memory roleImages,
        bool[] memory roleCanVote
    ) internal returns (address membershipProxy) {
        bytes32[] memory execRoles = new bytes32[](1);
        execRoles[0] = keccak256("EXECUTIVE");

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,string,string[],string[],bool[],bytes32[])",
            executorAddr,
            orgName,
            roleNames,
            roleImages,
            roleCanVote,
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
        bool lastRegister,
        uint8 quorumPct,
        uint8 ddSplit,
        bool quadratic,
        uint256 minBal
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
            quorumPct,
            ddSplit,
            quadratic,
            minBal
        );
        hvProxy = _deploy(orgId, "HybridVoting", executorAddr, autoUp, customImpl, init, lastRegister);
    }

    function _setupHatsTree(
        bytes32  orgId,            
        address  executorAddr,
        string   memory orgName,
        string[] memory roleNames,
        bool[]   memory roleCanVote
    )
        internal                               
        returns (uint256 topHatId, uint256[] memory roleHatIds)
    {
        require(roleNames.length == roleCanVote.length, "HATS_SETUP: array mismatch");

        // ─────────────────────────────────────────────────────────────
        //  Deploy EligibilityModule
        // ─────────────────────────────────────────────────────────────
        eligibilityModule = new EligibilityModule(executorAddr);
        address eligibilityModuleAddress = address(eligibilityModule);
        
        // ─────────────────────────────────────────────────────────────
        //  Deploy ToggleModule
        // ─────────────────────────────────────────────────────────────
        toggleModule = new ToggleModule(executorAddr);
        address toggleModuleAddress = address(toggleModule);

        // ─────────────────────────────────────────────────────────────
        //  Mint the Top Hat *to this deployer* so we can configure
        // ─────────────────────────────────────────────────────────────
        topHatId = hats.mintTopHat(
            address(this),                        // wearer for now
            string(abi.encodePacked("ipfs://", orgName)),
            ""                                    //image uri
        );

        // ─────────────────────────────────────────────────────────────
        //  Create & (optionally) mint child hats for each role
        // ─────────────────────────────────────────────────────────────
        uint256 len = roleNames.length;
        roleHatIds = new uint256[](len);

        // Create hats one at a time instead of using batchCreateHats
        for (uint256 i; i < len; ++i) {
            roleHatIds[i] = hats.createHat(
                topHatId,                         // admin = parent Top Hat
                roleNames[i],                     // details + placeholder URI
                type(uint32).max,                 // unlimited supply
                eligibilityModuleAddress,         // eligibility module
                toggleModuleAddress,              // toggle module
                true,                             // mutable
                roleNames[i]                      // data blob (optional)
            );

            // Give the role hat to the Executor right away if flagged
            if (roleCanVote[i]) {
                hats.mintHat(roleHatIds[i], executorAddr);
            }
        }

        // ─────────────────────────────────────────────────────────────
        //  Pass Top Hat ownership to the Executor
        hats.transferHat(topHatId, address(this), executorAddr);

        // ─────────────────────────────────────────────────────────────
        //  Book-keep in OrgRegistry so other modules can
        //     fetch the hat IDs later.  Delete if you don't need it.
        // ─────────────────────────────────────────────────────────────
        _layout().orgRegistry.registerOrgContract(
            orgId,
            keccak256("HATS_ROOT"),
            executorAddr,          // pointer; here we store the executor address
            address(0),            // no beacon
            false,
            executorAddr,
            false
        );
    }

    /*════════════════  FULL ORG  DEPLOYMENT  ════════════════*/
    struct DeploymentParams {
        bytes32 orgId;
        address executorEOA;
        string orgName;
        address registryAddr;
        bool autoUpgrade;
        uint8 quorumPct;
        uint8 ddSplit;
        bool quadratic;
        uint256 minBal;
        string[] roleNames;
        string[] roleImages;
        bool[] roleCanVote;
    }

    function deployFullOrg(
        bytes32 orgId,
        address executorEOA,
        string calldata orgName,
        address registryAddr,
        bool autoUpgrade,
        uint8 quorumPct,
        uint8 ddSplit,
        bool quadratic,
        uint256 minBal,
        string[] calldata roleNames,
        string[] calldata roleImages,
        bool[] calldata roleCanVote
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
        DeploymentParams memory params = DeploymentParams({
            orgId: orgId,
            executorEOA: executorEOA,
            orgName: orgName,
            registryAddr: registryAddr,
            autoUpgrade: autoUpgrade,
            quorumPct: quorumPct,
            ddSplit: ddSplit,
            quadratic: quadratic,
            minBal: minBal,
            roleNames: roleNames,
            roleImages: roleImages,
            roleCanVote: roleCanVote
        });

        return _deployFullOrgInternal(params);
    }

    function _deployFullOrgInternal(DeploymentParams memory params)
        internal
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
        if (l.orgRegistry.orgCount() == 0 || !_orgExists(params.orgId)) {
            l.orgRegistry.registerOrg(params.orgId, params.executorEOA, bytes(params.orgName));
        } else {
            (address currentExec,,,) = l.orgRegistry.orgOf(params.orgId);
            if (currentExec != params.executorEOA) revert OrgExistsMismatch();
        }

        /* 1. Executor  */
        executorAddr = _deployExecutor(params.orgId, params.executorEOA, params.autoUpgrade, address(0));

        /* 2. Setup Hats Tree */
        (uint256 topHatId, uint256[] memory roleHatIds) = _setupHatsTree(
            params.orgId,
            executorAddr,
            params.orgName,
            params.roleNames,
            params.roleCanVote
        );

        /* 3. Membership NFT */
        membership = _deployMembership(
            params.orgId,
            executorAddr,
            params.orgName,
            params.autoUpgrade,
            address(0),
            params.roleNames,
            params.roleImages,
            params.roleCanVote
        );

        /* 4. QuickJoin */
        quickJoin = _deployQuickJoin(
            params.orgId,
            executorAddr,
            membership,
            params.registryAddr,
            address(this),
            params.autoUpgrade,
            address(0)
        );

        /* 5. Participation token */
        string memory tName = string(abi.encodePacked(params.orgName, " Token"));
        string memory tSymbol = "PT";
        participationToken = _deployPT(
            params.orgId,
            executorAddr,
            tName,
            tSymbol,
            membership,
            params.autoUpgrade,
            address(0)
        );

        /* 6. TaskManager */
        taskManager = _deployTaskManager(
            params.orgId,
            executorAddr,
            participationToken,
            membership,
            params.autoUpgrade,
            address(0)
        );
        IParticipationToken(participationToken).setTaskManager(taskManager);

        /* 7. EducationHub */
        educationHub = _deployEducationHub(
            params.orgId,
            executorAddr,
            membership,
            participationToken,
            params.autoUpgrade,
            address(0),
            false
        );
        IParticipationToken(participationToken).setEducationHub(educationHub);

        /* 8. HybridVoting governor */
        hybridVoting = _deployHybridVoting(
            params.orgId,
            executorAddr,
            membership,
            participationToken,
            params.autoUpgrade,
            address(0),
            true,
            params.quorumPct,
            params.ddSplit,
            params.quadratic,
            params.minBal
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
        (,,, bool exists) = _layout().orgRegistry.orgOf(id);
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
