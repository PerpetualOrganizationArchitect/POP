// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../OrgRegistry.sol";
import {ModuleTypes} from "./ModuleTypes.sol";

// Moved interfaces here to break circular dependency
interface IPoaManager {
    function getBeaconById(bytes32 typeId) external view returns (address);
    function getCurrentImplementationById(bytes32 typeId) external view returns (address);
}

interface IHybridVotingInit {
    enum ClassStrategy {
        DIRECT,
        ERC20_BAL
    }

    struct ClassConfig {
        ClassStrategy strategy;
        uint8 slicePct;
        bool quadratic;
        uint256 minBalance;
        address asset;
        uint256[] hatIds;
    }

    function initialize(
        address hats_,
        address executor_,
        uint256[] calldata initialCreatorHats,
        address[] calldata targets,
        uint8 quorumPct,
        ClassConfig[] calldata initialClasses
    ) external;
}

interface IParticipationToken {
    function setTaskManager(address) external;
    function setEducationHub(address) external;
}

// Micro-interfaces for initializer functions (selector optimization)
interface IExecutorInit {
    function initialize(address owner, address hats) external;
}

interface IQuickJoinInit {
    function initialize(
        address executor,
        address hats,
        address registry,
        address master,
        uint256[] calldata memberHats
    ) external;
}

interface IParticipationTokenInit {
    function initialize(
        address executor,
        string calldata name,
        string calldata symbol,
        address hats,
        uint256[] calldata memberHats,
        uint256[] calldata approverHats
    ) external;
}

interface ITaskManagerInit {
    function initialize(address token, address hats, uint256[] calldata creatorHats, address executor) external;
}

interface IEducationHubInit {
    function initialize(
        address token,
        address hats,
        address executor,
        uint256[] calldata creatorHats,
        uint256[] calldata memberHats
    ) external;
}

interface IEligibilityModuleInit {
    function initialize(address deployer, address hats, address toggleModule) external;
}

interface IToggleModuleInit {
    function initialize(address admin) external;
}

interface IPaymentManagerInit {
    function initialize(address _owner, address _revenueShareToken) external;
}

library ModuleDeploymentLib {
    error InvalidAddress();
    error EmptyInit();
    error UnsupportedType();
    error InitFailed();

    event ModuleDeployed(
        bytes32 indexed orgId, bytes32 indexed typeId, address proxy, address beacon, bool autoUpgrade, address owner
    );

    struct DeployConfig {
        IPoaManager poaManager;
        OrgRegistry orgRegistry;
        address hats;
        bytes32 orgId;
        address moduleOwner;
        bool autoUpgrade;
        address customImpl;
        address registrar; // Optional: if set, use this for registration instead of orgRegistry owner
    }

    function deployCore(
        DeployConfig memory config,
        bytes32 typeId, // Pass pre-computed hash instead of string
        bytes memory initData,
        bool lastRegister,
        address beacon
    ) internal returns (address proxy) {
        if (initData.length == 0) revert EmptyInit();

        // Create proxy using the provided beacon
        proxy = address(new BeaconProxy(beacon, ""));

        // Register in OrgRegistry BEFORE initialization
        // Use registrar if provided (for factory pattern), otherwise direct registration
        if (config.registrar != address(0)) {
            // Call registrar's registerContract function (used by factories)
            (bool success, bytes memory returnData) = config.registrar
                .call(
                    abi.encodeWithSignature(
                        "registerContract(bytes32,bytes32,address,address,bool,address,bool)",
                        config.orgId,
                        typeId,
                        proxy,
                        beacon,
                        config.autoUpgrade,
                        config.moduleOwner,
                        lastRegister
                    )
                );
            if (!success) {
                // Bubble up the revert reason
                if (returnData.length > 0) {
                    assembly {
                        revert(add(32, returnData), mload(returnData))
                    }
                } else {
                    revert("Registration failed");
                }
            }
        } else {
            // Direct registration (backwards compatible)
            config.orgRegistry
                .registerOrgContract(
                    config.orgId, typeId, proxy, beacon, config.autoUpgrade, config.moduleOwner, lastRegister
                );
        }

        // Now safely initialize the proxy after registration is complete
        (bool success, bytes memory returnData) = proxy.call(initData);
        if (!success) {
            // If initialization fails, bubble up the revert reason
            if (returnData.length > 0) {
                assembly {
                    revert(add(32, returnData), mload(returnData))
                }
            } else {
                revert InitFailed();
            }
        }

        emit ModuleDeployed(config.orgId, typeId, proxy, beacon, config.autoUpgrade, config.moduleOwner);
        return proxy;
    }

    function deployExecutor(DeployConfig memory config, address deployer, address beacon)
        internal
        returns (address execProxy)
    {
        // Initialize with Deployer as owner so we can set up governance
        bytes memory init = abi.encodeWithSelector(IExecutorInit.initialize.selector, deployer, config.hats);

        // Deploy using provided beacon
        execProxy = deployCore(config, ModuleTypes.EXECUTOR_ID, init, false, beacon);
    }

    function deployQuickJoin(
        DeployConfig memory config,
        address executorAddr,
        address registry,
        address masterDeploy,
        uint256[] memory memberHats,
        address beacon
    ) internal returns (address qjProxy) {
        bytes memory init = abi.encodeWithSelector(
            IQuickJoinInit.initialize.selector, executorAddr, config.hats, registry, masterDeploy, memberHats
        );
        qjProxy = deployCore(config, ModuleTypes.QUICK_JOIN_ID, init, false, beacon);
    }

    function deployParticipationToken(
        DeployConfig memory config,
        address executorAddr,
        string memory name,
        string memory symbol,
        uint256[] memory memberHats,
        uint256[] memory approverHats,
        address beacon
    ) internal returns (address ptProxy) {
        bytes memory init = abi.encodeWithSelector(
            IParticipationTokenInit.initialize.selector,
            executorAddr,
            name,
            symbol,
            config.hats,
            memberHats,
            approverHats
        );
        ptProxy = deployCore(config, ModuleTypes.PARTICIPATION_TOKEN_ID, init, false, beacon);
    }

    function deployTaskManager(
        DeployConfig memory config,
        address executorAddr,
        address token,
        uint256[] memory creatorHats,
        address beacon
    ) internal returns (address tmProxy) {
        bytes memory init = abi.encodeWithSelector(
            ITaskManagerInit.initialize.selector, token, config.hats, creatorHats, executorAddr
        );
        tmProxy = deployCore(config, ModuleTypes.TASK_MANAGER_ID, init, false, beacon);
    }

    function deployEducationHub(
        DeployConfig memory config,
        address executorAddr,
        address token,
        uint256[] memory creatorHats,
        uint256[] memory memberHats,
        bool lastRegister,
        address beacon
    ) internal returns (address ehProxy) {
        bytes memory init = abi.encodeWithSelector(
            IEducationHubInit.initialize.selector, token, config.hats, executorAddr, creatorHats, memberHats
        );
        ehProxy = deployCore(config, ModuleTypes.EDUCATION_HUB_ID, init, lastRegister, beacon);
    }

    function deployEligibilityModule(
        DeployConfig memory config,
        address deployer,
        address toggleModule,
        address beacon
    ) internal returns (address emProxy) {
        bytes memory init = abi.encodeWithSelector(
            IEligibilityModuleInit.initialize.selector, deployer, config.hats, toggleModule
        );

        emProxy = deployCore(config, ModuleTypes.ELIGIBILITY_MODULE_ID, init, false, beacon);
    }

    function deployToggleModule(DeployConfig memory config, address adminAddr, address beacon)
        internal
        returns (address tmProxy)
    {
        bytes memory init = abi.encodeWithSelector(IToggleModuleInit.initialize.selector, adminAddr);

        tmProxy = deployCore(config, ModuleTypes.TOGGLE_MODULE_ID, init, false, beacon);
    }

    function deployHybridVoting(
        DeployConfig memory config,
        address executorAddr,
        uint256[] memory creatorHats,
        uint8 quorumPct,
        IHybridVotingInit.ClassConfig[] memory classes,
        bool lastRegister,
        address beacon
    ) internal returns (address hvProxy) {
        address[] memory targets = new address[](1);
        targets[0] = executorAddr;

        bytes memory init = abi.encodeWithSelector(
            IHybridVotingInit.initialize.selector, config.hats, executorAddr, creatorHats, targets, quorumPct, classes
        );
        hvProxy = deployCore(config, ModuleTypes.HYBRID_VOTING_ID, init, lastRegister, beacon);
    }

    function deployPaymentManager(
        DeployConfig memory config,
        address owner,
        address revenueShareToken,
        address beacon,
        bool lastRegister
    ) internal returns (address pmProxy) {
        bytes memory init = abi.encodeWithSelector(IPaymentManagerInit.initialize.selector, owner, revenueShareToken);
        pmProxy = deployCore(config, ModuleTypes.PAYMENT_MANAGER_ID, init, lastRegister, beacon);
    }

    function deployDirectDemocracyVoting(
        DeployConfig memory config,
        address executorAddr,
        uint256[] memory votingHats,
        uint256[] memory creatorHats,
        address[] memory initialTargets,
        uint8 quorumPct,
        address beacon,
        bool lastRegister
    ) internal returns (address ddProxy) {
        bytes memory init = abi.encodeWithSignature(
            "initialize(address,address,uint256[],uint256[],address[],uint8)",
            config.hats,
            executorAddr,
            votingHats,
            creatorHats,
            initialTargets,
            quorumPct
        );
        ddProxy = deployCore(config, ModuleTypes.DIRECT_DEMOCRACY_VOTING_ID, init, lastRegister, beacon);
    }
}
