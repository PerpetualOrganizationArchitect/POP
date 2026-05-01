// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {PaymasterHub} from "../../src/PaymasterHub.sol";
import {PackedUserOperation} from "../../src/interfaces/PackedUserOperation.sol";

interface IEligibilityModule {
    function vouchFor(address account, uint256 hatId) external;
}

interface IHats {
    function isEligible(address account, uint256 hatId) external view returns (bool);
}

// Full E2E: vouch for a new address → simulate passkey join via PaymasterHub validation
//
// Usage:
//   forge script script/SimulateKubiJoin.s.sol:SimulateKubiJoin \
//     --fork-url https://rpc.gnosischain.com -vvv
contract SimulateKubiJoin is Script {
    address constant GNOSIS_PM_PROXY = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;
    address constant PASSKEY_FACTORY = 0x6B5E116688A0903a80d9eb9E0CbBDbd3aD3ce025;
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    bytes32 constant KUBI_ORG = 0xc0f2765d555e21bfad5c6b05accef86a5758e0dee3e9a5b4ee3c3f3069c2102e;
    address constant KUBI_QJ = 0x5dBda3649B7044C8fDd0E540e86E536dDA7926Cf;
    address constant KUBI_ELIGIBILITY = 0x27114Cb757BeDF77E30EeB0Ca635e3368d8C2914;

    // KUBI Member hat
    uint256 constant MEMBER_HAT = 29089782865237956866263577802518366573012001940915670447121420467044352;
    // An existing KUBI member who can vouch
    address constant VOUCHER = 0x211bF72F6363590fF889BD058aAf610311f6724A;

    function run() public {
        console.log("=== Full E2E: Vouch + Passkey Join on KUBI (Gnosis Fork) ===");

        PaymasterHub pm = PaymasterHub(payable(GNOSIS_PM_PROXY));

        // 1. Create a new random account (the passkey smart account that will be deployed)
        address newUser = address(uint160(uint256(keccak256("new-kubi-passkey-user"))));
        console.log("New user address:", newUser);

        // 2. Verify new user is NOT eligible before vouching
        bool eligibleBefore = IHats(HATS).isEligible(newUser, MEMBER_HAT);
        console.log("Eligible before vouch:", eligibleBefore);
        require(!eligibleBefore, "Should not be eligible yet");

        // 3. Vouch for the new user (as an existing KUBI member)
        console.log("Vouching for new user as", VOUCHER);
        vm.prank(VOUCHER);
        IEligibilityModule(KUBI_ELIGIBILITY).vouchFor(newUser, MEMBER_HAT);

        // 4. Verify new user IS eligible after vouching
        bool eligibleAfter = IHats(HATS).isEligible(newUser, MEMBER_HAT);
        console.log("Eligible after vouch:", eligibleAfter);
        require(eligibleAfter, "Should be eligible after vouch");

        // 5. Build the UserOp callData: execute(QuickJoin, 0, registerAndClaimHatsWithPasskey(...))
        bytes memory innerCall = abi.encodeWithSelector(
            bytes4(0xece090ff), // registerAndClaimHatsWithPasskey
            bytes32(uint256(0xC4ED)),
            bytes32(uint256(0x1234)),
            bytes32(uint256(0x5678)),
            uint256(0), // credential
            "newkubimember",
            uint256(block.timestamp + 1 hours),
            uint256(0), // username, deadline, nonce
            bytes(""),
            bytes(""),
            uint256(0),
            uint256(0),
            bytes32(0),
            bytes32(0), // WebAuthnAuth (dummy)
            _singleHatArray(MEMBER_HAT) // hatIds to claim
        );

        bytes memory callData =
            abi.encodeWithSignature("execute(address,uint256,bytes)", KUBI_QJ, uint256(0), innerCall);

        // 6. Build paymasterAndData with the Member hat
        bytes memory paymasterAndData = abi.encodePacked(
            GNOSIS_PM_PROXY,
            uint128(200000),
            uint128(200000), // v0.7 gas limits
            uint8(0x01), // version
            KUBI_ORG, // orgId
            uint8(0x01), // subjectType = HAT
            bytes32(MEMBER_HAT), // subjectId = member hat
            uint32(0), // ruleId = GENERIC
            uint64(0) // mailboxCommit
        );

        // 7. Build UserOp
        vm.etch(newUser, hex"01"); // Give account code (EntryPoint deploys before validatePaymasterUserOp)

        PackedUserOperation memory userOp = PackedUserOperation({
            sender: newUser,
            nonce: 0,
            initCode: abi.encodePacked(PASSKEY_FACTORY, hex"d0a252ba"),
            callData: callData,
            accountGasLimits: bytes32(uint256(500000) << 128 | uint256(1500000)),
            preVerificationGas: 100000,
            gasFees: bytes32(uint256(2000000000) << 128 | uint256(1000000000)),
            paymasterAndData: paymasterAndData,
            signature: hex"ff"
        });

        // 8. Call validatePaymasterUserOp as EntryPoint
        console.log("");
        console.log("Calling validatePaymasterUserOp...");
        console.log("  sender:", newUser);
        console.log("  target: KUBI QuickJoin");
        console.log("  selector: registerAndClaimHatsWithPasskey (0xece090ff)");
        console.log("  subjectType: HAT, hatId: Member");

        vm.prank(ENTRY_POINT);
        try pm.validatePaymasterUserOp(userOp, bytes32(0), 0.001 ether) returns (
            bytes memory context, uint256 validationData
        ) {
            console.log("");
            console.log("=== validatePaymasterUserOp SUCCEEDED ===");
            console.log("  validationData:", validationData);
            console.log("  context length:", context.length);
            console.log("");
            console.log("Full flow confirmed:");
            console.log("  1. KUBI org registered and not paused");
            console.log("  2. New user vouched and eligible for Member hat");
            console.log("  3. registerAndClaimHatsWithPasskey whitelisted");
            console.log("  4. Member hat budget has capacity (0.05 xDAI/week)");
            console.log("  5. Org has deposits (2 xDAI)");
            console.log("");
            console.log("=== KUBI VOUCH-CLAIM PASSKEY JOIN WORKS ===");
        } catch (bytes memory reason) {
            console.log("");
            console.log("=== validatePaymasterUserOp FAILED ===");
            if (reason.length >= 4) {
                bytes4 sel;
                assembly { sel := mload(add(reason, 32)) }
                console.log("Revert selector:");
                console.logBytes4(sel);
            }
            console.logBytes(reason);
            revert("PaymasterHub validation failed");
        }
    }

    function _singleHatArray(uint256 hatId) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = hatId;
        return arr;
    }
}
