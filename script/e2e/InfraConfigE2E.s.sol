// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManagerHub} from "../../src/crosschain/PoaManagerHub.sol";
import {ImplementationRegistry} from "../../src/ImplementationRegistry.sol";

/**
 * @title TriggerInfraConfig
 * @notice Tests the real admin call chain by calling registerImplementation()
 *         on the ImplementationRegistry (owned by PoaManager) via Hub.adminCall.
 *
 *         Chain of custody:
 *           Hub.adminCall(implRegistry, registerImplementation(...))
 *             → PoaManager.adminCall(implRegistry, data)
 *               → implRegistry.registerImplementation(...)  [checks onlyOwner, owner == PM]
 *
 *         This is the exact same path that real infra config changes follow
 *         (e.g., PaymasterHub config, OrgDeployer wiring, etc.)
 *
 * Required env vars:
 *   PRIVATE_KEY, HUB, IMPL_REGISTRY
 */
contract TriggerInfraConfig is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address hubAddr = vm.envAddress("HUB");
        address regAddr = vm.envAddress("IMPL_REGISTRY");

        console.log("\n=== Trigger Infra Config via Admin Call ===");
        console.log("Hub:", hubAddr);
        console.log("ImplementationRegistry:", regAddr);

        // Use the deployer address itself as the "implementation" — it's just an address
        // that exists on-chain. The point is to prove the admin call reaches the registry.
        address fakeImpl = vm.addr(deployerKey);

        bytes memory data = abi.encodeWithSignature(
            "registerImplementation(string,string,address,bool)", "E2EConfigTest", "v1", fakeImpl, true
        );

        console.log("Registering type 'E2EConfigTest' v1 ->", fakeImpl);

        vm.startBroadcast(deployerKey);
        PoaManagerHub(payable(hubAddr)).adminCall(regAddr, data);
        vm.stopBroadcast();

        console.log("Admin call succeeded - PoaManager is confirmed as msg.sender");
        console.log("(ImplementationRegistry.registerImplementation is onlyOwner, owner == PoaManager)");
    }
}

/**
 * @title TriggerInfraConfigSatellite
 * @notice Same test on the satellite chain. Calls registerImplementation()
 *         on the satellite's ImplementationRegistry via Satellite.adminCall.
 *
 *         Chain of custody:
 *           Satellite.adminCall(implRegistry, registerImplementation(...))
 *             → PoaManager.adminCall(implRegistry, data)
 *               → implRegistry.registerImplementation(...)  [checks onlyOwner, owner == PM]
 *
 * Required env vars:
 *   PRIVATE_KEY, SATELLITE, IMPL_REGISTRY
 */
contract TriggerInfraConfigSatellite is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address satAddr = vm.envAddress("SATELLITE");
        address regAddr = vm.envAddress("IMPL_REGISTRY");

        console.log("\n=== Trigger Infra Config on Satellite ===");
        console.log("Satellite:", satAddr);
        console.log("ImplementationRegistry:", regAddr);

        address fakeImpl = vm.addr(deployerKey);

        bytes memory data = abi.encodeWithSignature(
            "registerImplementation(string,string,address,bool)", "E2EConfigTest", "v1", fakeImpl, true
        );

        console.log("Registering type 'E2EConfigTest' v1 ->", fakeImpl);

        vm.startBroadcast(deployerKey);
        // Satellite.adminCall → PM.adminCall → implRegistry.registerImplementation
        (bool success,) = satAddr.call(abi.encodeWithSignature("adminCall(address,bytes)", regAddr, data));
        require(success, "Satellite adminCall failed");
        vm.stopBroadcast();

        console.log("Admin call succeeded on satellite");
    }
}

/**
 * @title VerifyInfraConfig
 * @notice Verifies that the ImplementationRegistry now has the "E2EConfigTest" type.
 *         This proves the full admin call chain worked: the PoaManager was msg.sender
 *         and the onlyOwner check passed.
 *
 * Required env vars:
 *   IMPL_REGISTRY
 */
contract VerifyInfraConfig is Script {
    function run() public view {
        address regAddr = vm.envAddress("IMPL_REGISTRY");

        ImplementationRegistry reg = ImplementationRegistry(regAddr);

        console.log("=== Verify Infra Config ===");
        console.log("ImplementationRegistry:", regAddr);

        address impl = reg.getLatestImplementation("E2EConfigTest");
        console.log("E2EConfigTest latest impl:", impl);

        if (impl != address(0)) {
            console.log("PASS: ImplementationRegistry configured via admin call");
        } else {
            revert("FAIL: E2EConfigTest not found in registry");
        }
    }
}
