// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {UniversalAccountRegistry} from "../../src/UniversalAccountRegistry.sol";
import {NameRegistryHub} from "../../src/crosschain/NameRegistryHub.sol";

/**
 * @title VerifyNameRegistry
 * @notice Read-only verification that cross-chain username + org name claims
 *         were processed on the home chain. Reverts if not yet processed
 *         (shell script checks exit code for polling).
 *
 * Required env vars:
 *   UAR, NAME_HUB, USER
 */
contract VerifyNameRegistry is Script {
    function run() public view {
        address uarAddr = vm.envAddress("UAR");
        address nameHubAddr = vm.envAddress("NAME_HUB");
        address user = vm.envAddress("USER");

        UniversalAccountRegistry uar = UniversalAccountRegistry(uarAddr);
        NameRegistryHub nameHub = NameRegistryHub(payable(nameHubAddr));

        // Check username
        string memory username = uar.getUsername(user);
        bool usernameOk = bytes(username).length > 0;

        // Check org name reservation (manual claim dispatched in Step 4b)
        bytes32 orgNameHash = _hashName("E2EManualClaim");
        bool orgNameOk = nameHub.reservedOrgNames(orgNameHash);

        console.log("=== Verify Name Registry ===");
        console.log("UAR:", uarAddr);
        console.log("NameRegistryHub:", nameHubAddr);
        console.log("User:", user);
        console.log("Username:", username);
        console.log("Username registered:", usernameOk);
        console.log("Org name reserved:", orgNameOk);

        if (usernameOk && orgNameOk) {
            console.log("PASS: Name registry cross-chain verified");
        } else {
            revert("PENDING: Name registry not yet synced");
        }
    }

    function _hashName(string memory name) internal pure returns (bytes32) {
        bytes memory b = bytes(name);
        for (uint256 i; i < b.length; ++i) {
            uint8 c = uint8(b[i]);
            if (c >= 65 && c <= 90) b[i] = bytes1(c + 32);
        }
        return keccak256(b);
    }
}
