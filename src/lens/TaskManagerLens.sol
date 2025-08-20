// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {TaskManager} from "../TaskManager.sol";
import {HatManager} from "../libs/HatManager.sol";
import {BudgetLib} from "../libs/BudgetLib.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";

/**
 * @title TaskManagerLens
 * @notice External view functions for TaskManager, primarily for testing and debugging
 * @dev Separated from main contract to reduce bytecode size
 */
contract TaskManagerLens {
    
    /*──────── Enums ────────*/
    enum StorageKey {
        HATS,
        EXECUTOR,
        CREATOR_HATS,
        CREATOR_HAT_COUNT,
        PERMISSION_HATS,
        PERMISSION_HAT_COUNT,
        VERSION,
        TASK_INFO,
        TASK_FULL_INFO,
        PROJECT_INFO,
        TASK_APPLICANTS,
        TASK_APPLICATION,
        TASK_APPLICANT_COUNT,
        HAS_APPLIED_FOR_TASK,
        BOUNTY_BUDGET
    }
    
    enum Status {
        UNCLAIMED,
        CLAIMED,
        SUBMITTED,
        COMPLETED,
        CANCELLED
    }
    
    /*──────── Storage Access ───────*/
    // Copy the storage layout types needed
    struct Task {
        bytes32 projectId;
        uint96 payout;
        address claimer;
        uint96 bountyPayout;
        bool requiresApplication;
        Status status;
        address bountyToken;
    }
    
    struct Project {
        mapping(address => bool) managers;
        uint128 cap;
        uint128 spent;
        bool exists;
        mapping(address => BudgetLib.Budget) bountyBudgets;
    }
    
    struct Layout {
        mapping(bytes32 => Project) _projects;
        mapping(uint256 => Task) _tasks;
        IHats hats;
        address token;
        uint256[] creatorHatIds;
        uint48 nextTaskId;
        uint48 nextProjectId;
        address executor;
        mapping(uint256 => uint8) rolePermGlobal;
        mapping(bytes32 => mapping(uint256 => uint8)) rolePermProj;
        uint256[] permissionHatIds;
        mapping(uint256 => address[]) taskApplicants;
        mapping(uint256 => mapping(address => bytes32)) taskApplications;
    }
    
    bytes32 private constant _STORAGE_SLOT = 0x30bc214cbc65463577eb5b42c88d60986e26fc81ad89a2eb74550fb255f1e712;
    
    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }
    
    /*──────── Unified Storage Getter ─────── */
    function getStorage(StorageKey key, bytes calldata params) external view returns (bytes memory) {
        Layout storage l = _layout();
        
        if (key == StorageKey.HATS) {
            return abi.encode(l.hats);
        } else if (key == StorageKey.EXECUTOR) {
            return abi.encode(l.executor);
        } else if (key == StorageKey.CREATOR_HATS) {
            return abi.encode(HatManager.getHatArray(l.creatorHatIds));
        } else if (key == StorageKey.CREATOR_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.creatorHatIds));
        } else if (key == StorageKey.PERMISSION_HATS) {
            return abi.encode(HatManager.getHatArray(l.permissionHatIds));
        } else if (key == StorageKey.PERMISSION_HAT_COUNT) {
            return abi.encode(HatManager.getHatCount(l.permissionHatIds));
        } else if (key == StorageKey.VERSION) {
            return abi.encode("v1");
        } else if (key == StorageKey.TASK_INFO) {
            uint256 id = abi.decode(params, (uint256));
            require(id < l.nextTaskId, "Unknown task");
            Task storage t = l._tasks[id];
            return abi.encode(t.payout, t.status, t.claimer, t.projectId, t.requiresApplication);
        } else if (key == StorageKey.TASK_FULL_INFO) {
            uint256 id = abi.decode(params, (uint256));
            require(id < l.nextTaskId, "Unknown task");
            Task storage t = l._tasks[id];
            return abi.encode(
                t.payout, t.bountyPayout, t.bountyToken, t.status, t.claimer, t.projectId, t.requiresApplication
            );
        } else if (key == StorageKey.PROJECT_INFO) {
            bytes32 pid = abi.decode(params, (bytes32));
            Project storage p = l._projects[pid];
            require(p.exists, "Unknown project");
            return abi.encode(p.cap, p.spent, p.managers[msg.sender]);
        } else if (key == StorageKey.TASK_APPLICANTS) {
            uint256 id = abi.decode(params, (uint256));
            return abi.encode(l.taskApplicants[id]);
        } else if (key == StorageKey.TASK_APPLICATION) {
            (uint256 id, address applicant) = abi.decode(params, (uint256, address));
            return abi.encode(l.taskApplications[id][applicant]);
        } else if (key == StorageKey.TASK_APPLICANT_COUNT) {
            uint256 id = abi.decode(params, (uint256));
            return abi.encode(l.taskApplicants[id].length);
        } else if (key == StorageKey.HAS_APPLIED_FOR_TASK) {
            (uint256 id, address applicant) = abi.decode(params, (uint256, address));
            return abi.encode(l.taskApplications[id][applicant]);
        } else if (key == StorageKey.BOUNTY_BUDGET) {
            (bytes32 pid, address token) = abi.decode(params, (bytes32, address));
            require(token != address(0), "Invalid token");
            Project storage p = l._projects[pid];
            require(p.exists, "Unknown project");
            BudgetLib.Budget storage b = p.bountyBudgets[token];
            return abi.encode(b.cap, b.spent);
        }
        
        revert("Invalid index");
    }
    
    /*──────── Additional View Helpers ─────── */
    function getTask(uint256 id) external view returns (
        bytes32 projectId,
        uint96 payout,
        address claimer,
        uint96 bountyPayout,
        bool requiresApplication,
        Status status,
        address bountyToken
    ) {
        Layout storage l = _layout();
        require(id < l.nextTaskId, "Unknown task");
        Task storage t = l._tasks[id];
        return (t.projectId, t.payout, t.claimer, t.bountyPayout, t.requiresApplication, t.status, t.bountyToken);
    }
    
    function getProject(bytes32 pid) external view returns (
        uint128 cap,
        uint128 spent,
        bool exists,
        bool isManager
    ) {
        Layout storage l = _layout();
        Project storage p = l._projects[pid];
        return (p.cap, p.spent, p.exists, p.managers[msg.sender]);
    }
    
    function getNextIds() external view returns (uint48 nextTaskId, uint48 nextProjectId) {
        Layout storage l = _layout();
        return (l.nextTaskId, l.nextProjectId);
    }
}