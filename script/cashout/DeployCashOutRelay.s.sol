// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CashOutRelay} from "../../src/cashout/CashOutRelay.sol";

// Deploy CashOutRelay on Base + initiate CCTP cashout from Arbitrum.
//
// Addresses:
//   USDC (Arbitrum):        0xaf88d065e77c8cC2239327C5EDb3A432268e5831
//   USDC (Base):            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913
//   CCTP TokenMessenger:    0x19330d10D9Cc8751218eaf51E8885D058642E08A (Arbitrum)
//   CCTP MessageTransmitter:0x1682Ae6375C4E4A97e4B583BC394c861A46D8962 (Base)
//   ZKP2P EscrowV2:         0x777777779d229cdF3110e9de47943791c26300Ef (Base)
//   CCTP Base domain:       6

/**
 * @title Step1_DeployRelayOnBase
 * @notice Deploy CashOutRelay behind UUPS proxy on Base.
 *
 *   FOUNDRY_PROFILE=production forge script \
 *     script/DeployCashOutRelay.s.sol:Step1_DeployRelayOnBase \
 *     --rpc-url base --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 */
contract Step1_DeployRelayOnBase is Script {
    address constant ESCROW = 0x777777779d229cdF3110e9de47943791c26300Ef;
    address constant BASE_USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant BASE_CCTP_TRANSMITTER = 0x1682Ae6375C4E4A97e4B583BC394c861A46D8962;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n=== Deploy CashOutRelay on Base ===");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        CashOutRelay impl = new CashOutRelay();
        bytes memory initData = abi.encodeWithSelector(
            CashOutRelay.initialize.selector, ESCROW, BASE_USDC, BASE_CCTP_TRANSMITTER, deployer
        );
        address proxy = address(new ERC1967Proxy(address(impl), initData));

        vm.stopBroadcast();

        console.log("Implementation:", address(impl));
        console.log("Proxy:", proxy);
        console.log("\nNext: Run Step2 on Arbitrum with RELAY_ADDRESS=%s", proxy);
    }
}

/**
 * @title Step2_InitiateCashOut
 * @notice Burn USDC on Arbitrum via CCTP. Mints to the CashOutRelay on Base.
 *
 *   RELAY_ADDRESS=0x... FOUNDRY_PROFILE=production forge script \
 *     script/DeployCashOutRelay.s.sol:Step2_InitiateCashOut \
 *     --rpc-url arbitrum --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 */
contract Step2_InitiateCashOut is Script {
    address constant ARB_USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address constant ARB_TOKEN_MESSENGER = 0x19330d10D9Cc8751218eaf51E8885D058642E08A;
    uint32 constant BASE_DOMAIN = 6;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address relayOnBase = vm.envAddress("RELAY_ADDRESS");
        uint256 amount = vm.envOr("CASHOUT_AMOUNT", uint256(10_000000)); // default 10 USDC

        console.log("\n=== Initiate CCTP Burn (Arbitrum -> Base) ===");
        console.log("Amount:", amount);
        console.log("Relay on Base:", relayOnBase);
        console.log("Mint recipient (bytes32):", vm.toString(bytes32(uint256(uint160(relayOnBase)))));

        vm.startBroadcast(deployerKey);

        // Approve USDC to TokenMessenger
        IERC20(ARB_USDC).approve(ARB_TOKEN_MESSENGER, amount);

        // Burn USDC — will mint to relay on Base
        // depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        (bool ok, bytes memory ret) = ARB_TOKEN_MESSENGER.call(
            abi.encodeWithSignature(
                "depositForBurn(uint256,uint32,bytes32,address)",
                amount,
                BASE_DOMAIN,
                bytes32(uint256(uint160(relayOnBase))),
                ARB_USDC
            )
        );
        require(ok, "depositForBurn failed");

        // The return value is the nonce
        uint64 nonce = abi.decode(ret, (uint64));

        vm.stopBroadcast();

        console.log("CCTP burn nonce:", nonce);
        console.log("\nWait ~2 min for Circle attestation, then run:");
        console.log("  curl -s 'https://iris-api-sandbox.circle.com/v1/attestations/%s' | jq", nonce);
        console.log("(Use https://iris-api.circle.com for mainnet)");
        console.log("\nThen run Step3 on Base with the attestation.");
    }
}

/**
 * @title Step3_CompleteCashOut
 * @notice Submit CCTP attestation + Venmo details to the relay on Base.
 *
 *   RELAY_ADDRESS=0x... \
 *   CCTP_MESSAGE=0x... \
 *   CCTP_ATTESTATION=0x... \
 *   VENMO_USERNAME=hudsonhrh \
 *   FOUNDRY_PROFILE=production forge script \
 *     script/DeployCashOutRelay.s.sol:Step3_CompleteCashOut \
 *     --rpc-url base --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 */
contract Step3_CompleteCashOut is Script {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);
        address relayAddress = vm.envAddress("RELAY_ADDRESS");
        bytes memory cctpMessage = vm.envBytes("CCTP_MESSAGE");
        bytes memory attestation = vm.envBytes("CCTP_ATTESTATION");

        // Venmo details — these need to come from ZKP2P curator registration
        // For now, encode directly (the payeeDetailsHash would come from the curator API)
        string memory venmoUsername = vm.envOr("VENMO_USERNAME", string("hudsonhrh"));

        console.log("\n=== Complete CashOut on Base ===");
        console.log("Relay:", relayAddress);
        console.log("Depositor (you):", deployer);
        console.log("Venmo:", venmoUsername);

        // Build CashOutParams
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: deployer,
            paymentMethod: keccak256(bytes("venmo")),
            payeeDetailsHash: keccak256(bytes(venmoUsername)), // NOTE: real hash comes from ZKP2P curator
            fiatCurrency: keccak256(bytes("USD")),
            conversionRate: 1e18, // 1:1 (you'd get this from ZKP2P getQuote)
            minIntentAmount: 1_000000, // $1 min
            maxIntentAmount: 10_000000 // $10 max
        });

        vm.startBroadcast(deployerKey);
        CashOutRelay(payable(relayAddress)).completeCashOut(cctpMessage, attestation, params);
        vm.stopBroadcast();

        console.log("CashOut deposit created! Check peer.xyz to monitor.");
    }
}
