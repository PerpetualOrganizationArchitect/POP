// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBungeeInbox {
    struct BasicRequest {
        uint256 originChainId;
        uint256 destinationChainId;
        uint256 deadline;
        uint256 nonce;
        address sender;
        address receiver;
        address delegate;
        address bungeeGateway;
        uint32 switchboardId;
        address inputToken;
        uint256 inputAmount;
        address outputToken;
        uint256 minOutputAmount;
        uint256 refuelAmount;
    }

    struct Request {
        BasicRequest basicReq;
        address swapOutputToken;
        uint256 minSwapOutput;
        bytes32 metadata;
        bytes affiliateFees;
        uint256 minDestGas;
        bytes destinationPayload;
        address exclusiveTransmitter;
    }

    function createRequest(Request calldata singleOutputRequest, address refundAddress) external payable;
}

/// @title CashOutPasskeyFlow
/// @notice Forks Arbitrum mainnet and verifies the on-chain BungeeInbox.createRequest path
///         a passkey smart account would take. This is the route that avoids Permit2 EIP-712
///         signing — required for ERC-4337 accounts that cannot produce off-chain sigs.
/// @dev Run with: forge test --match-path test/CashOutPasskeyFlow.t.sol --fork-url arbitrum -vvv
contract CashOutPasskeyFlowTest is Test {
    /*════════════════════════════════ ADDRESSES ════════════════════════════════*/

    address constant BUNGEE_INBOX_ARB = 0x5E0f8E7337C8955D2124b8e85Ca74aF884b3E124;
    address constant BUNGEE_GATEWAY_ARB = 0xCdEa28Ee7BD5bf7710B294d9391e1b6A318d809a;
    address constant USDC_ARB = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;

    address constant BUNGEE_GATEWAY_BASE = 0x84F06fBaCc4b64CA2f72a4B26191DAD97f2b52BA;
    address constant USDC_BASE = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant CASHOUT_RELAY_BASE = 0xA65414A21dc114199cAfD7c6c3ed99488Eb9eFE5;

    uint32 constant DEFAULT_SWITCHBOARD = 1;

    /// @dev Same encoding the relay decodes on Base
    struct CashOutParams {
        address depositor;
        bytes32 paymentMethod;
        bytes32 payeeDetailsHash;
        bytes32 fiatCurrency;
        uint256 conversionRate;
        uint256 minIntentAmount;
        uint256 maxIntentAmount;
    }

    /// @dev Simulated passkey smart account
    address smartAccount;

    function setUp() public {
        vm.createSelectFork("arbitrum");
        smartAccount = makeAddr("passkey-smart-account");
    }

    /*════════════════════════════════ TESTS ════════════════════════════════*/

    function test_PasskeyBatch_CreatesRequestSuccessfully() public {
        uint256 amount = 10 * 1e6;
        deal(USDC_ARB, smartAccount, amount);

        IBungeeInbox.Request memory req = _buildRequest(smartAccount, amount);

        vm.startPrank(smartAccount, smartAccount);
        IERC20(USDC_ARB).approve(BUNGEE_INBOX_ARB, amount);

        vm.recordLogs();
        IBungeeInbox(BUNGEE_INBOX_ARB).createRequest(req, smartAccount);
        vm.stopPrank();

        assertEq(IERC20(USDC_ARB).balanceOf(smartAccount), 0, "USDC should be pulled");

        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertTrue(_findRequestCreatedLog(logs), "SingleOutputRequestCreated must fire");
    }

    function test_DestinationPayload_RoundTripsThroughInbox() public {
        uint256 amount = 25 * 1e6;
        deal(USDC_ARB, smartAccount, amount);

        bytes32 expectedPayeeHash = keccak256("venmo:hudsonhrh");
        IBungeeInbox.Request memory req = _buildRequest(smartAccount, amount);
        req.destinationPayload = abi.encode(_buildCashOutParams(smartAccount, expectedPayeeHash, amount));

        vm.startPrank(smartAccount, smartAccount);
        IERC20(USDC_ARB).approve(BUNGEE_INBOX_ARB, amount);
        vm.recordLogs();
        IBungeeInbox(BUNGEE_INBOX_ARB).createRequest(req, smartAccount);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory emittedRequest = _extractRequestBytes(logs);
        assertGt(emittedRequest.length, 0, "request bytes must be emitted");

        IBungeeInbox.Request memory decoded = abi.decode(emittedRequest, (IBungeeInbox.Request));
        assertEq(decoded.destinationPayload, req.destinationPayload, "destinationPayload must round-trip");

        CashOutParams memory params = abi.decode(decoded.destinationPayload, (CashOutParams));
        assertEq(params.depositor, smartAccount);
        assertEq(params.payeeDetailsHash, expectedPayeeHash);
        assertEq(params.maxIntentAmount, amount);
    }

    function test_PasskeyBatch_FailsWithoutApproval() public {
        uint256 amount = 10 * 1e6;
        deal(USDC_ARB, smartAccount, amount);

        IBungeeInbox.Request memory req = _buildRequest(smartAccount, amount);

        vm.prank(smartAccount);
        vm.expectRevert();
        IBungeeInbox(BUNGEE_INBOX_ARB).createRequest(req, smartAccount);
    }

    function test_RequestEncodesRelayAsReceiver() public {
        uint256 amount = 10 * 1e6;
        deal(USDC_ARB, smartAccount, amount);

        IBungeeInbox.Request memory req = _buildRequest(smartAccount, amount);

        vm.startPrank(smartAccount, smartAccount);
        IERC20(USDC_ARB).approve(BUNGEE_INBOX_ARB, amount);
        vm.recordLogs();
        IBungeeInbox(BUNGEE_INBOX_ARB).createRequest(req, smartAccount);
        vm.stopPrank();

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes memory emittedRequest = _extractRequestBytes(logs);
        IBungeeInbox.Request memory decoded = abi.decode(emittedRequest, (IBungeeInbox.Request));
        assertEq(decoded.basicReq.receiver, CASHOUT_RELAY_BASE, "receiver must be relay");
        assertEq(decoded.basicReq.destinationChainId, 8453, "destination must be Base");
        assertEq(decoded.basicReq.outputToken, USDC_BASE, "output must be Base USDC");
    }

    /*════════════════════════════════ HELPERS ════════════════════════════════*/

    /// @dev The Bungee delegate is a fixed operator address that the protocol authorizes
    ///      to fulfill requests. Discovered from the live /quote API response.
    address constant BUNGEE_DELEGATE = 0x86C950FE91D96Fa113A96eE23EDc7C517b94BFDC;
    address constant AFFILIATE_FEE_TAKER = 0xe3D091bcb9406Ddb9a121e37f4eb1345336AFBBf;

    /// @dev Per BungeeInbox._checkRequestValidity, basicReq.sender MUST equal address(this).
    ///      The inbox proxies for the user via Permit2's EIP-1271 path. The actual user
    ///      identity travels in the `delegate` field and via msg.sender.
    function _buildRequest(address user, uint256 amount) internal view returns (IBungeeInbox.Request memory) {
        return IBungeeInbox.Request({
            basicReq: IBungeeInbox.BasicRequest({
                originChainId: block.chainid,
                destinationChainId: 8453,
                deadline: block.timestamp + 10 minutes,
                nonce: block.timestamp + uint160(user), // unique per (user, time)
                sender: BUNGEE_INBOX_ARB, // ← must be the inbox itself
                receiver: CASHOUT_RELAY_BASE,
                delegate: BUNGEE_DELEGATE,
                bungeeGateway: BUNGEE_GATEWAY_ARB,
                switchboardId: DEFAULT_SWITCHBOARD,
                inputToken: USDC_ARB,
                inputAmount: amount,
                outputToken: USDC_BASE,
                minOutputAmount: amount * 99 / 100,
                refuelAmount: 0
            }),
            swapOutputToken: address(0),
            minSwapOutput: 0,
            metadata: bytes32(0),
            affiliateFees: abi.encode(AFFILIATE_FEE_TAKER, amount / 1000), // 0.1%
            minDestGas: 250_000,
            destinationPayload: abi.encode(_buildCashOutParams(user, keccak256("test-payee"), amount)),
            exclusiveTransmitter: address(0)
        });
    }

    function _buildCashOutParams(address depositor, bytes32 payeeHash, uint256 maxAmount)
        internal
        pure
        returns (CashOutParams memory)
    {
        return CashOutParams({
            depositor: depositor,
            paymentMethod: keccak256("venmo"),
            payeeDetailsHash: payeeHash,
            fiatCurrency: keccak256("USD"),
            conversionRate: 0.98e18,
            minIntentAmount: 1e6,
            maxIntentAmount: maxAmount
        });
    }

    function _findRequestCreatedLog(Vm.Log[] memory logs) internal pure returns (bool) {
        bytes32 sig = keccak256("SingleOutputRequestCreated(bytes32,address,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) return true;
        }
        return false;
    }

    function _extractRequestBytes(Vm.Log[] memory logs) internal pure returns (bytes memory) {
        bytes32 sig = keccak256("SingleOutputRequestCreated(bytes32,address,bytes)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == sig) {
                (, bytes memory request) = abi.decode(logs[i].data, (address, bytes));
                return request;
            }
        }
        return "";
    }
}
