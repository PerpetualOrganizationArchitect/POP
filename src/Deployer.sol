// SPDX‑License‑Identifier: MIT
pragma solidity ^0.8.20;

/*───────────────────────────  OpenZeppelin  ───────────────────────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {EligibilityModule} from "./EligibilityModule.sol";
import {ToggleModule} from "./ToggleModule.sol";

/*────────────────────────────── Core deps ──────────────────────────────*/
import "./OrgRegistry.sol";

/*──────────────────── External management contracts ────────────────────*/
interface IPoaManager {
    function getBeacon(string calldata) external view returns (address);
    function getCurrentImplementation(string calldata) external view returns (address);
}

/*────────────────────── Module‑specific hooks ──────────────────────────*/
interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

interface IExecutorAdmin {
    function setCaller(address) external;
    function setHatMinterAuthorization(address minter, bool authorized) external;
}

/*── init‑selector helpers (reduce bytecode & safety) ────────────────────*/
interface IHybridVotingInit {
    function initialize(
        address hats_,
        address token_,
        address executor_,
        uint256[] calldata initialVotingHats,
        uint256[] calldata initialDemocracyHats,
        uint256[] calldata initialCreatorHats,
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

    IHats public hats;
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

    function initialize(address _poaManager, address _orgRegistry, address _hats) public initializer {
        if (_poaManager == address(0) || _orgRegistry == address(0) || _hats == address(0)) revert InvalidAddress();
        __Ownable_init(msg.sender);

        Layout storage l = _layout();
        l.poaManager = IPoaManager(_poaManager);
        l.orgRegistry = OrgRegistry(_orgRegistry);
        hats = IHats(_hats);
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
    function _deployExecutor(bytes32 orgId, bool autoUp, address customImpl) internal returns (address execProxy) {
        // Initialize with Deployer as owner so we can set up governance
        bytes memory init = abi.encodeWithSignature("initialize(address,address)", address(this), address(hats));
        execProxy = _deploy(orgId, "Executor", address(this), autoUp, customImpl, init, false);
    }

    /*---------  QuickJoin  ---------*/
    function _deployQuickJoin(
        bytes32 orgId,
        address executorAddr,
        address registry,
        address masterDeploy,
        bool autoUp,
        address customImpl
    ) internal returns (address qjProxy) {
        Layout storage l = _layout();

        // Get the DEFAULT role hat ID for new members
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = l.orgRegistry.getRoleHat(orgId, 0); // DEFAULT role hat

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint256[])",
            executorAddr,
            address(hats),
            registry,
            masterDeploy,
            memberHats
        );
        qjProxy = _deploy(orgId, "QuickJoin", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  ParticipationToken  ---------*/
    function _deployPT(
        bytes32 orgId,
        address executorAddr,
        string memory name,
        string memory symbol,
        bool autoUp,
        address customImpl
    ) internal returns (address ptProxy) {
        Layout storage l = _layout();

        // Get the role hat IDs for member and approver permissions
        // DEFAULT role (index 0) = members, EXECUTIVE role (index 1) = approvers
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = l.orgRegistry.getRoleHat(orgId, 0); // DEFAULT role hat

        uint256[] memory approverHats = new uint256[](1);
        approverHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,string,string,address,uint256[],uint256[])",
            executorAddr,
            name,
            symbol,
            address(hats),
            memberHats,
            approverHats
        );
        ptProxy = _deploy(orgId, "ParticipationToken", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  TaskManager  ---------*/
    function _deployTaskManager(bytes32 orgId, address executorAddr, address token, bool autoUp, address customImpl)
        internal
        returns (address tmProxy)
    {
        Layout storage l = _layout();

        // Get the role hat IDs for creator permissions
        // EXECUTIVE role (index 1) = creators
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,uint256[],address)", token, address(hats), creatorHats, executorAddr
        );
        tmProxy = _deploy(orgId, "TaskManager", executorAddr, autoUp, customImpl, init, false);
    }

    /*---------  EducationHub  ---------*/
    function _deployEducationHub(
        bytes32 orgId,
        address executorAddr,
        address token,
        bool autoUp,
        address customImpl,
        bool lastRegister // <<< flag propagated to registry
    ) internal returns (address ehProxy) {
        Layout storage l = _layout();

        // Get the role hat IDs for creator and member permissions
        // EXECUTIVE role (index 1) = creators, DEFAULT role (index 0) = members
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = l.orgRegistry.getRoleHat(orgId, 0); // DEFAULT role hat

        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,address,uint256[],uint256[])",
            token,
            address(hats),
            executorAddr,
            creatorHats,
            memberHats
        );
        ehProxy = _deploy(orgId, "EducationHub", executorAddr, autoUp, customImpl, init, lastRegister);
    }

    /*---------  EligibilityModule  ---------*/
    function _deployEligibilityModule(bytes32 orgId, bool autoUp, address customImpl)
        internal
        returns (address emProxy)
    {
        bytes memory init = abi.encodeWithSignature("initialize(address,address)", address(this), address(hats));
        emProxy = _deploy(orgId, "EligibilityModule", address(this), autoUp, customImpl, init, false);
    }

    /*---------  ToggleModule  ---------*/
    function _deployToggleModule(bytes32 orgId, address adminAddr, bool autoUp, address customImpl)
        internal
        returns (address tmProxy)
    {
        bytes memory init = abi.encodeWithSignature("initialize(address)", adminAddr);
        tmProxy = _deploy(orgId, "ToggleModule", address(this), autoUp, customImpl, init, false);
    }

    /*---------  HybridVoting  ---------*/
    function _deployHybridVoting(
        bytes32 orgId,
        address executorAddr,
        address token,
        bool autoUp,
        address customImpl,
        bool lastRegister,
        uint8 quorumPct,
        uint8 ddSplit,
        bool quadratic,
        uint256 minBal
    ) internal returns (address hvProxy) {
        Layout storage l = _layout();

        // Get the role hat IDs (we know there are at least 2: DEFAULT and EXECUTIVE)
        uint256[] memory votingHats = new uint256[](2);
        votingHats[0] = l.orgRegistry.getRoleHat(orgId, 0); // DEFAULT role hat
        votingHats[1] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        // For democracy hats, use only the EXECUTIVE role hat (gives DD voting power)
        uint256[] memory democracyHats = new uint256[](1);
        democracyHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        // For creator hats, use the EXECUTIVE role hat
        uint256[] memory creatorHats = new uint256[](1);
        creatorHats[0] = l.orgRegistry.getRoleHat(orgId, 1); // EXECUTIVE role hat

        address[] memory targets = new address[](1);
        targets[0] = executorAddr;

        bytes memory init = abi.encodeWithSelector(
            IHybridVotingInit.initialize.selector,
            address(hats),
            token,
            executorAddr,
            votingHats,
            democracyHats,
            creatorHats,
            targets,
            quorumPct,
            ddSplit,
            quadratic,
            minBal
        );
        hvProxy = _deploy(orgId, "HybridVoting", executorAddr, autoUp, customImpl, init, lastRegister);
    }

    function _setupHatsTree(
        bytes32 orgId,
        address executorAddr,
        string memory orgName,
        string[] memory roleNames,
        bool[] memory roleCanVote
    ) internal returns (uint256 topHatId, uint256[] memory roleHatIds) {
        require(roleNames.length == roleCanVote.length, "HATS_SETUP: array mismatch");

        // ─────────────────────────────────────────────────────────────
        //  Deploy EligibilityModule with Deployer as initial super admin
        // ─────────────────────────────────────────────────────────────
        address eligibilityModuleAddress = _deployEligibilityModule(orgId, true, address(0));
        eligibilityModule = EligibilityModule(eligibilityModuleAddress);

        // ─────────────────────────────────────────────────────────────
        //  Deploy ToggleModule with deployer as initial admin
        // ─────────────────────────────────────────────────────────────
        address toggleModuleAddress = _deployToggleModule(orgId, address(this), true, address(0));
        toggleModule = ToggleModule(toggleModuleAddress);

        // ─────────────────────────────────────────────────────────────
        //  Mint the Top Hat *to this deployer* so we can configure
        // ─────────────────────────────────────────────────────────────
        topHatId = hats.mintTopHat(
            address(this), // wearer for now
            string(abi.encodePacked("ipfs://", orgName)),
            "" //image uri
        );

        // Configure Top Hat eligibility and toggle (for the executor initially)
        eligibilityModule.setWearerEligibility(address(this), topHatId, true, true);
        toggleModule.setHatStatus(topHatId, true);

        // ─────────────────────────────────────────────────────────────
        //  Create EligibilityModule Admin Hat
        // ─────────────────────────────────────────────────────────────
        uint256 eligibilityAdminHatId = hats.createHat(
            topHatId, // admin = parent Top Hat
            "ELIGIBILITY_ADMIN", // details
            1, // supply = 1 (only the eligibility module should wear this)
            eligibilityModuleAddress, // eligibility module
            toggleModuleAddress, // toggle module
            true, // mutable
            "ELIGIBILITY_ADMIN" // data blob
        );

        // Configure and mint the eligibility admin hat to the eligibility module itself
        eligibilityModule.setWearerEligibility(eligibilityModuleAddress, eligibilityAdminHatId, true, true);
        toggleModule.setHatStatus(eligibilityAdminHatId, true);
        hats.mintHat(eligibilityAdminHatId, eligibilityModuleAddress);

        // Set the eligibility module's admin hat
        eligibilityModule.setEligibilityModuleAdminHat(eligibilityAdminHatId);

        // ─────────────────────────────────────────────────────────────
        //  Create & (optionally) mint child hats for each role
        //  Now using EligibilityModule admin hat as admin so it can mint them
        // ─────────────────────────────────────────────────────────────
        uint256 len = roleNames.length;
        roleHatIds = new uint256[](len);

        // Create hats one at a time with EligibilityModule admin hat as admin
        for (uint256 i; i < len; ++i) {
            roleHatIds[i] = hats.createHat(
                eligibilityAdminHatId, // admin = EligibilityModule admin hat (not top hat)
                roleNames[i], // details + placeholder URI
                type(uint32).max, // unlimited supply
                eligibilityModuleAddress, // eligibility module
                toggleModuleAddress, // toggle module
                true, // mutable
                roleNames[i] // data blob (optional)
            );

            // Configure role hat eligibility and toggle for the executor
            eligibilityModule.setWearerEligibility(executorAddr, roleHatIds[i], true, true);
            toggleModule.setHatStatus(roleHatIds[i], true);

            // Give the role hat to the Executor right away if flagged
            // Now the EligibilityModule mints the hat since it's the admin
            if (roleCanVote[i]) {
                // Call the EligibilityModule to mint the hat since it's the admin
                // We can do this because the deployer is still the super admin at this point
                eligibilityModule.mintHatToAddress(roleHatIds[i], executorAddr);
            }
        }

        // ─────────────────────────────────────────────────────────────
        //  Pass Top Hat ownership to the Executor
        hats.transferHat(topHatId, address(this), executorAddr);

        // ─────────────────────────────────────────────────────────────
        //  Set default eligibility for all hats so minting works
        // ─────────────────────────────────────────────────────────────
        eligibilityModule.setDefaultEligibility(topHatId, true, true);
        for (uint256 i = 0; i < roleHatIds.length; i++) {
            eligibilityModule.setDefaultEligibility(roleHatIds[i], true, true);
        }

        // ─────────────────────────────────────────────────────────────
        //  Set up admin hat system: EXECUTIVE role can control DEFAULT role
        // ─────────────────────────────────────────────────────────────
        if (roleHatIds.length >= 2) {
            uint256 defaultRoleHat = roleHatIds[0]; // DEFAULT role hat
            uint256 executiveRoleHat = roleHatIds[1]; // EXECUTIVE role hat

            // Set the EXECUTIVE role hat as an admin hat
            eligibilityModule.setAdminHat(executiveRoleHat, true);

            // Give the EXECUTIVE role hat permission to control the DEFAULT role hat
            uint256[] memory targetHats = new uint256[](1);
            targetHats[0] = defaultRoleHat;
            bool[] memory permissions = new bool[](1);
            permissions[0] = true;

            eligibilityModule.setAdminPermissions(executiveRoleHat, targetHats, permissions);

            // Initialize admin rights for the executor who will be wearing the executive hat
            eligibilityModule.updateUserAdminHat(executorAddr, executiveRoleHat);
        }

        // ─────────────────────────────────────────────────────────────
        //  Transfer module admin rights to the Executor
        // ─────────────────────────────────────────────────────────────
        eligibilityModule.transferSuperAdmin(executorAddr);
        toggleModule.transferAdmin(executorAddr);

        // ─────────────────────────────────────────────────────────────
        //  Book-keep in OrgRegistry so other modules can
        //     fetch the hat IDs later.  Delete if you don't need it.
        // ─────────────────────────────────────────────────────────────
        _layout().orgRegistry.registerHatsTree(orgId, topHatId, roleHatIds);
    }

    /*════════════════  FULL ORG  DEPLOYMENT  ════════════════*/
    struct DeploymentParams {
        bytes32 orgId;
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
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        DeploymentParams memory params = DeploymentParams({
            orgId: orgId,
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
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub
        )
    {
        Layout storage l = _layout();

        /* 1. Create Org in bootstrap mode */
        if (!_orgExists(params.orgId)) {
            l.orgRegistry.createOrgBootstrap(params.orgId, bytes(params.orgName));
        } else {
            // Org already exists - this should not happen in normal deployment
            revert OrgExistsMismatch();
        }

        /* 2. Deploy Executor */
        executorAddr = _deployExecutor(params.orgId, params.autoUpgrade, address(0));

        /* 3. Set the executor for the org */
        l.orgRegistry.setOrgExecutor(params.orgId, executorAddr);

        /* 4. Setup Hats Tree */
        (uint256 topHatId, uint256[] memory roleHatIds) =
            _setupHatsTree(params.orgId, executorAddr, params.orgName, params.roleNames, params.roleCanVote);

        /* 5. QuickJoin */
        quickJoin = _deployQuickJoin(
            params.orgId, executorAddr, params.registryAddr, address(this), params.autoUpgrade, address(0)
        );

        /* 6. Participation token */
        string memory tName = string(abi.encodePacked(params.orgName, " Token"));
        string memory tSymbol = "PT";
        participationToken = _deployPT(params.orgId, executorAddr, tName, tSymbol, params.autoUpgrade, address(0));

        /* 7. TaskManager */
        taskManager = _deployTaskManager(params.orgId, executorAddr, participationToken, params.autoUpgrade, address(0));
        IParticipationToken(participationToken).setTaskManager(taskManager);

        /* 8. EducationHub */
        educationHub =
            _deployEducationHub(params.orgId, executorAddr, participationToken, params.autoUpgrade, address(0), false);
        IParticipationToken(participationToken).setEducationHub(educationHub);

        /* 9. HybridVoting governor */
        hybridVoting = _deployHybridVoting(
            params.orgId,
            executorAddr,
            participationToken,
            params.autoUpgrade,
            address(0),
            true,
            params.quorumPct,
            params.ddSplit,
            params.quadratic,
            params.minBal
        );

        /* authorize QuickJoin to mint hats (before setting voting contract as caller) */
        IExecutorAdmin(executorAddr).setHatMinterAuthorization(quickJoin, true);

        /* link executor to governor */
        IExecutorAdmin(executorAddr).setCaller(hybridVoting);

        /* renounce executor ownership - now only governed by voting */
        OwnableUpgradeable(executorAddr).renounceOwnership();
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
