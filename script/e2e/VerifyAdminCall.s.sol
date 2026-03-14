// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {DeterministicDeployer} from "../../src/crosschain/DeterministicDeployer.sol";

interface IAdminCallTarget {
    function value() external view returns (uint256);
    function callCount() external view returns (uint256);
}

/**
 * @title VerifyAdminCall
 * @notice Read-only verification that the AdminCallTarget was updated by the cross-chain
 *         admin call. Reverts if the value hasn't been set yet (shell script checks exit code
 *         for polling).
 *
 * Required env vars:
 *   DETERMINISTIC_DEPLOYER
 */
contract VerifyAdminCall is Script {
    function run() public view {
        address ddAddr = vm.envAddress("DETERMINISTIC_DEPLOYER");

        DeterministicDeployer dd = DeterministicDeployer(ddAddr);
        bytes32 salt = dd.computeSalt("AdminCallTarget", "v1");
        address target = dd.computeAddress(salt);

        IAdminCallTarget t = IAdminCallTarget(target);

        console.log("=== Verify Admin Call ===");
        console.log("Target:", target);
        console.log("Value:", t.value());
        console.log("Call count:", t.callCount());

        if (t.value() == 42 && t.callCount() == 1) {
            console.log("PASS: Admin call applied (value == 42, callCount == 1)");
        } else if (t.value() == 42 && t.callCount() > 1) {
            revert("FAIL: Admin call applied but callCount > 1 (possible replay)");
        } else {
            revert("PENDING: Admin call not yet applied");
        }
    }
}
