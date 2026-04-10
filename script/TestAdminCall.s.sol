// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PoaManagerHub} from "../src/crosschain/PoaManagerHub.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {PoaManager} from "../src/PoaManager.sol";

/// Full E2E: upgrade beacon to v16, set Poa rules on Arbitrum, read back, verify.
///
/// Usage: FOUNDRY_PROFILE=production forge script script/TestAdminCall.s.sol:E2ESimArbitrum \
///   --fork-url arbitrum --optimizer-runs 100 -vvv
contract E2ESimArbitrum is Script {
    function run() public {
        address deployer = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;
        address hub = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
        address arbPM = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;
        address poaManagerAddr = 0xFF585Fae4A944cD173B19158C6FC5E08980b0815;

        bytes32 poaOrg = 0xa71879ef0e38b15fe7080196c0102f859e0ca8e7b8c0703ec8df03c66befd069;
        address poaQJ = 0x366c605A3064a680fb5c05Bf9EeDa512fdDBF03a;

        console.log("=== E2E Arbitrum Simulation ===");

        // Deploy new impl
        PaymasterHub newImpl = new PaymasterHub();
        console.log("New impl size:", address(newImpl).code.length);
        require(address(newImpl).code.length <= 24576, "OVER EIP-170");

        // Upgrade beacon (Hub owns PoaManager)
        vm.prank(PoaManager(poaManagerAddr).owner());
        PoaManager(poaManagerAddr).upgradeBeacon("PaymasterHub", address(newImpl), "v16-test");
        console.log("Beacon upgraded");

        // Read BEFORE
        PaymasterHub pm = PaymasterHub(payable(arbPM));
        console.log("BEFORE claimHatsWithUser:", pm.getRule(poaOrg, poaQJ, bytes4(0x130906e5)).allowed);
        console.log("BEFORE regClaimPasskey:", pm.getRule(poaOrg, poaQJ, bytes4(0xece090ff)).allowed);
        console.log("BEFORE regClaimEOA:", pm.getRule(poaOrg, poaQJ, bytes4(0xd58fb6ee)).allowed);

        // Call adminBatchAddRules via Hub.adminCall
        bytes32[] memory orgIds = new bytes32[](3);
        address[] memory targets = new address[](3);
        bytes4[] memory sels = new bytes4[](3);
        for (uint256 i; i < 3; i++) {
            orgIds[i] = poaOrg;
            targets[i] = poaQJ;
        }
        sels[0] = bytes4(0x130906e5);
        sels[1] = bytes4(0xece090ff);
        sels[2] = bytes4(0xd58fb6ee);

        bytes memory ruleData =
            abi.encodeWithSignature("adminBatchAddRules(bytes32[],address[],bytes4[])", orgIds, targets, sels);

        vm.prank(deployer);
        PoaManagerHub(payable(hub)).adminCall(arbPM, ruleData);
        console.log("adminBatchAddRules called");

        // Read AFTER
        bool a1 = pm.getRule(poaOrg, poaQJ, bytes4(0x130906e5)).allowed;
        bool a2 = pm.getRule(poaOrg, poaQJ, bytes4(0xece090ff)).allowed;
        bool a3 = pm.getRule(poaOrg, poaQJ, bytes4(0xd58fb6ee)).allowed;
        console.log("AFTER claimHatsWithUser:", a1);
        console.log("AFTER regClaimPasskey:", a2);
        console.log("AFTER regClaimEOA:", a3);

        require(a1 && a2 && a3, "RULES NOT SET");
        console.log("=== ALL CHECKS PASSED ===");
    }
}
