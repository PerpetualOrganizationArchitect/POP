// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IHub {
    function adminCall(address target, bytes calldata data) external returns (bytes memory);
    function adminCallCrossChain(address target, bytes calldata data) external payable;
}

interface IPM {
    function getRule(bytes32 orgId, address target, bytes4 sel) external view returns (bool allowed, uint32 hint);
}

/**
 * @title SimulateFixRules
 * @notice Simulate adding vouch-claim whitelist rules for Poa governance org on Arbitrum fork.
 *
 * Usage: forge script script/FixVouchClaimRules.s.sol:SimulateFixRules --fork-url arbitrum -vvv
 */
contract SimulateFixRules is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant ARB_PM = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;
    address constant DEPLOYER = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;

    bytes32 constant POA_ORG = 0xa71879ef0e38b15fe7080196c0102f859e0ca8e7b8c0703ec8df03c66befd069;
    address constant POA_QJ = 0x366c605A3064a680fb5c05Bf9EeDa512fdDBF03a;

    bytes4 constant CLAIM_HATS = 0x130906e5;
    bytes4 constant REG_CLAIM_PASSKEY = 0xece090ff;
    bytes4 constant REG_CLAIM_EOA = 0xd58fb6ee;

    function run() public {
        console.log("=== Simulate Fix Vouch-Claim Rules (Arbitrum) ===");

        // Check before
        (bool b1,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, CLAIM_HATS);
        (bool b2,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, REG_CLAIM_PASSKEY);
        (bool b3,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, REG_CLAIM_EOA);
        console.log("Before - claimHatsWithUser:", b1);
        console.log("Before - registerAndClaimHatsWithPasskey:", b2);
        console.log("Before - registerAndClaimHats:", b3);

        // Build calldata
        address[] memory targets = new address[](3);
        bytes4[] memory sels = new bytes4[](3);
        bool[] memory allowed = new bool[](3);
        uint32[] memory hints = new uint32[](3);
        for (uint256 i = 0; i < 3; i++) {
            targets[i] = POA_QJ;
            allowed[i] = true;
        }
        sels[0] = CLAIM_HATS;
        sels[1] = REG_CLAIM_PASSKEY;
        sels[2] = REG_CLAIM_EOA;

        bytes memory innerData = abi.encodeWithSignature(
            "setRulesBatch(bytes32,address[],bytes4[],bool[],uint32[])", POA_ORG, targets, sels, allowed, hints
        );

        // Execute
        vm.prank(DEPLOYER);
        IHub(HUB).adminCall(ARB_PM, innerData);

        // Check after
        (bool a1,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, CLAIM_HATS);
        (bool a2,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, REG_CLAIM_PASSKEY);
        (bool a3,) = IPM(ARB_PM).getRule(POA_ORG, POA_QJ, REG_CLAIM_EOA);
        console.log("After - claimHatsWithUser:", a1);
        console.log("After - registerAndClaimHatsWithPasskey:", a2);
        console.log("After - registerAndClaimHats:", a3);

        require(a1 && a2 && a3, "Rules not set!");
        console.log("PASS: All 3 vouch-claim rules set via Hub.adminCall");
    }
}

/**
 * @title BroadcastFixRulesArbitrum
 * @notice Actually broadcast the fix for Poa governance org on Arbitrum.
 *
 * Usage:
 *   source .env && forge script script/FixVouchClaimRules.s.sol:BroadcastFixRulesArbitrum \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9
 */
contract BroadcastFixRulesArbitrum is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant ARB_PM = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;

    bytes32 constant POA_ORG = 0xa71879ef0e38b15fe7080196c0102f859e0ca8e7b8c0703ec8df03c66befd069;
    address constant POA_QJ = 0x366c605A3064a680fb5c05Bf9EeDa512fdDBF03a;

    function run() public {
        uint256 key = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address[] memory targets = new address[](3);
        bytes4[] memory sels = new bytes4[](3);
        bool[] memory allowed = new bool[](3);
        uint32[] memory hints = new uint32[](3);
        for (uint256 i = 0; i < 3; i++) {
            targets[i] = POA_QJ;
            allowed[i] = true;
        }
        sels[0] = 0x130906e5; // claimHatsWithUser
        sels[1] = 0xece090ff; // registerAndClaimHatsWithPasskey
        sels[2] = 0xd58fb6ee; // registerAndClaimHats

        bytes memory innerData = abi.encodeWithSignature(
            "setRulesBatch(bytes32,address[],bytes4[],bool[],uint32[])", POA_ORG, targets, sels, allowed, hints
        );

        vm.startBroadcast(key);
        IHub(HUB).adminCall(ARB_PM, innerData);
        vm.stopBroadcast();

        console.log("Poa governance org vouch-claim rules set on Arbitrum.");
    }
}

/**
 * @title BroadcastFixRulesKUBI
 * @notice Fix KUBI whitelist rules on Gnosis via adminCallCrossChain.
 *
 * Usage:
 *   source .env && forge script script/FixVouchClaimRules.s.sol:BroadcastFixRulesKUBI \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --sender 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9 --value 0.005ether
 */
contract BroadcastFixRulesKUBI is Script {
    address constant HUB = 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71;
    address constant GNOSIS_PM = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;

    bytes32 constant KUBI_ORG = 0xc0f2765d555e21bfad5c6b05accef86a5758e0dee3e9a5b4ee3c3f3069c2102e;
    address constant KUBI_QJ = 0x5dBda3649B7044C8fDd0E540e86E536dDA7926Cf;

    function run() public {
        uint256 key = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));

        address[] memory targets = new address[](3);
        bytes4[] memory sels = new bytes4[](3);
        bool[] memory allowed = new bool[](3);
        uint32[] memory hints = new uint32[](3);
        for (uint256 i = 0; i < 3; i++) {
            targets[i] = KUBI_QJ;
            allowed[i] = true;
        }
        sels[0] = 0x130906e5; // claimHatsWithUser
        sels[1] = 0xece090ff; // registerAndClaimHatsWithPasskey
        sels[2] = 0xd58fb6ee; // registerAndClaimHats

        bytes memory innerData = abi.encodeWithSignature(
            "setRulesBatch(bytes32,address[],bytes4[],bool[],uint32[])", KUBI_ORG, targets, sels, allowed, hints
        );

        vm.startBroadcast(key);
        IHub(HUB).adminCallCrossChain{value: 0.005 ether}(GNOSIS_PM, innerData);
        vm.stopBroadcast();

        console.log("KUBI vouch-claim rules dispatched to Gnosis. Wait ~5 min for Hyperlane delivery.");
    }
}
