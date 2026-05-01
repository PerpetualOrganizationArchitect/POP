// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CashOutRelay, IEscrowV2Minimal} from "../src/cashout/CashOutRelay.sol";

/// @dev Mock EscrowV2 that records depositTo calls
contract MockEscrow {
    struct DepositRecord {
        address depositor;
        uint256 amount;
        bytes32 paymentMethod;
        bytes32 payeeDetails;
    }

    DepositRecord[] public deposits;
    bool public shouldRevert;
    string public revertReason;

    function setRevert(bool _shouldRevert, string memory _reason) external {
        shouldRevert = _shouldRevert;
        revertReason = _reason;
    }

    function depositTo(address _depositor, CashOutRelay.CreateDepositParams calldata _params) external {
        if (shouldRevert) revert(revertReason);

        // Pull USDC from caller (same as real escrow)
        _params.token.transferFrom(msg.sender, address(this), _params.amount);

        deposits.push(
            DepositRecord({
                depositor: _depositor,
                amount: _params.amount,
                paymentMethod: _params.paymentMethods[0],
                payeeDetails: _params.paymentMethodData[0].payeeDetails
            })
        );
    }

    function depositCount() external view returns (uint256) {
        return deposits.length;
    }
}

/// @dev Mock USDC token
contract MockUSDC {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient balance");
        require(allowance[from][msg.sender] >= amount, "insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev Mock CCTP MessageTransmitter — mints USDC to the relay on receiveMessage
contract MockMessageTransmitter {
    MockUSDC public usdc;
    address public relay;
    bool public shouldRevert;
    mapping(bytes32 => bool) public used; // replay protection

    constructor(MockUSDC _usdc) {
        usdc = _usdc;
    }

    function setRelay(address _relay) external {
        relay = _relay;
    }

    function setRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function receiveMessage(bytes calldata message, bytes calldata) external returns (bool) {
        if (shouldRevert) revert("CCTP: invalid attestation");
        bytes32 msgHash = keccak256(message);
        require(!used[msgHash], "CCTP: already received");
        used[msgHash] = true;

        // Decode amount from the message (we encode it simply for testing)
        uint256 amount = abi.decode(message, (uint256));
        usdc.mint(relay, amount);
        return true;
    }
}

contract CashOutRelayTest is Test {
    CashOutRelay public relay;
    MockEscrow public escrow;
    MockUSDC public usdc;
    MockMessageTransmitter public mockTransmitter;

    address constant BUNGEE = address(0xB009EE);
    address constant USER = address(0xCAFE);
    address constant OWNER = address(0x0A0E);

    bytes32 constant VENMO_METHOD = keccak256("venmo");
    bytes32 constant USD_CURRENCY = keccak256("USD");
    bytes32 constant PAYEE_HASH = keccak256("venmouser123");
    uint256 constant CONVERSION_RATE = 1e18; // 1:1

    function setUp() public {
        escrow = new MockEscrow();
        usdc = new MockUSDC();
        mockTransmitter = new MockMessageTransmitter(usdc);

        // Deploy relay behind UUPS proxy
        CashOutRelay impl = new CashOutRelay();
        bytes memory initData = abi.encodeWithSelector(
            CashOutRelay.initialize.selector, address(escrow), address(usdc), address(mockTransmitter), OWNER
        );
        relay = CashOutRelay(payable(address(new ERC1967Proxy(address(impl), initData))));

        // Tell mock transmitter where the relay is (so it mints USDC there)
        mockTransmitter.setRelay(address(relay));
    }

    /*═══════════════════════ HELPERS ═══════════════════════*/

    function _encodeCashOutParams(address depositor, uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(
            CashOutRelay.CashOutParams({
                depositor: depositor,
                paymentMethod: VENMO_METHOD,
                payeeDetailsHash: PAYEE_HASH,
                fiatCurrency: USD_CURRENCY,
                conversionRate: CONVERSION_RATE,
                minIntentAmount: 1e6, // $1 min
                maxIntentAmount: amount // max = full amount
            })
        );
    }

    function _mintAndDeliver(uint256 amount) internal {
        // Simulate Bungee delivering USDC to the relay
        usdc.mint(address(relay), amount);
    }

    function _callExecuteData(bytes32 requestHash, uint256 amount, bytes memory callData) internal {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(BUNGEE);
        relay.executeData(requestHash, amounts, tokens, callData);
    }

    /*═══════════════════════ HAPPY PATH ═══════════════════════*/

    function testHappyPath_DepositCreatedAndOwnedByUser() public {
        uint256 amount = 50e6; // $50 USDC
        _mintAndDeliver(amount);

        bytes memory callData = _encodeCashOutParams(USER, amount);
        _callExecuteData(keccak256("req1"), amount, callData);

        // Verify: escrow received the deposit
        assertEq(escrow.depositCount(), 1, "Should have 1 deposit");
        (address depositor, uint256 depAmount, bytes32 method, bytes32 payee) = escrow.deposits(0);
        assertEq(depositor, USER, "Deposit should be owned by user");
        assertEq(depAmount, amount, "Deposit amount should match");
        assertEq(method, VENMO_METHOD, "Payment method should be venmo");
        assertEq(payee, PAYEE_HASH, "Payee hash should match");

        // Verify: relay has no remaining USDC
        assertEq(usdc.balanceOf(address(relay)), 0, "Relay should have 0 USDC after deposit");
    }

    function testHappyPath_EmitsEvent() public {
        uint256 amount = 25e6;
        _mintAndDeliver(amount);

        bytes memory callData = _encodeCashOutParams(USER, amount);

        vm.expectEmit(true, true, false, true);
        emit CashOutRelay.CashOutDeposited(USER, keccak256("req1"), amount, VENMO_METHOD);

        _callExecuteData(keccak256("req1"), amount, callData);
    }

    function testHappyPath_MultipleConcurrentUsers() public {
        address user2 = address(0xBEEF);
        uint256 amount1 = 50e6;
        uint256 amount2 = 100e6;

        // User 1
        _mintAndDeliver(amount1);
        _callExecuteData(keccak256("req1"), amount1, _encodeCashOutParams(USER, amount1));

        // User 2
        _mintAndDeliver(amount2);
        _callExecuteData(keccak256("req2"), amount2, _encodeCashOutParams(user2, amount2));

        assertEq(escrow.depositCount(), 2, "Should have 2 deposits");
        assertEq(usdc.balanceOf(address(relay)), 0, "Relay should be empty");
    }

    /*═══════════════════════ FAILURE & RECOVERY ═══════════════════════*/

    function testEscrowReverts_HoldsUSDCForRecovery() public {
        uint256 amount = 50e6;
        _mintAndDeliver(amount);

        // Make escrow revert
        escrow.setRevert(true, "ZKP2P paused");

        bytes32 reqHash = keccak256("req_fail");
        bytes memory callData = _encodeCashOutParams(USER, amount);

        // Should NOT revert — relay catches it
        _callExecuteData(reqHash, amount, callData);

        // USDC should be held in relay
        assertEq(usdc.balanceOf(address(relay)), amount, "Relay should hold USDC after failure");
        assertEq(relay.failedDepositor(reqHash), USER, "Failed depositor should be tracked");
        assertEq(relay.failedAmount(reqHash), amount, "Failed amount should be tracked");

        // Escrow should have 0 deposits
        assertEq(escrow.depositCount(), 0, "Escrow should have no deposits");
    }

    function testRecovery_UserCanRecoverFailedDeposit() public {
        uint256 amount = 50e6;
        _mintAndDeliver(amount);

        escrow.setRevert(true, "paused");
        bytes32 reqHash = keccak256("req_recover");
        _callExecuteData(reqHash, amount, _encodeCashOutParams(USER, amount));

        // User recovers
        vm.prank(USER);
        relay.recoverFailed(reqHash);

        assertEq(usdc.balanceOf(USER), amount, "User should receive USDC back");
        assertEq(usdc.balanceOf(address(relay)), 0, "Relay should be empty");
        assertEq(relay.failedDepositor(reqHash), address(0), "Failed record should be cleared");
    }

    function testRecovery_NonDepositorCannotRecover() public {
        uint256 amount = 50e6;
        _mintAndDeliver(amount);

        escrow.setRevert(true, "paused");
        bytes32 reqHash = keccak256("req_steal");
        _callExecuteData(reqHash, amount, _encodeCashOutParams(USER, amount));

        // Attacker tries to recover
        vm.prank(address(0xA77AC6));
        vm.expectRevert(CashOutRelay.NotOwner.selector);
        relay.recoverFailed(reqHash);
    }

    function testRecovery_DoubleRecoverReverts() public {
        uint256 amount = 50e6;
        _mintAndDeliver(amount);

        escrow.setRevert(true, "paused");
        bytes32 reqHash = keccak256("req_double");
        _callExecuteData(reqHash, amount, _encodeCashOutParams(USER, amount));

        vm.prank(USER);
        relay.recoverFailed(reqHash);

        vm.prank(USER);
        vm.expectRevert(CashOutRelay.NoPendingRecovery.selector);
        relay.recoverFailed(reqHash);
    }

    /*═══════════════════════ EDGE CASES ═══════════════════════*/

    function testEdge_WrongToken_Reverts() public {
        address wrongToken = address(0xBAD);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e6;
        address[] memory tokens = new address[](1);
        tokens[0] = wrongToken;

        bytes memory callData = _encodeCashOutParams(USER, 50e6);

        vm.prank(BUNGEE);
        vm.expectRevert(abi.encodeWithSelector(CashOutRelay.WrongToken.selector, wrongToken, address(usdc)));
        relay.executeData(keccak256("req_wrong"), amounts, tokens, callData);
    }

    function testEdge_ZeroAmount_Reverts() public {
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(BUNGEE);
        vm.expectRevert(CashOutRelay.ZeroAmount.selector);
        relay.executeData(keccak256("req_zero"), amounts, tokens, _encodeCashOutParams(USER, 0));
    }

    function testEdge_ZeroDepositor_Reverts() public {
        uint256 amount = 50e6;
        _mintAndDeliver(amount);

        bytes memory callData = _encodeCashOutParams(address(0), amount);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(BUNGEE);
        vm.expectRevert(CashOutRelay.ZeroDepositor.selector);
        relay.executeData(keccak256("req_zero_dep"), amounts, tokens, callData);
    }

    function testEdge_EmptyAmounts_Reverts() public {
        vm.prank(BUNGEE);
        vm.expectRevert(CashOutRelay.ZeroAmount.selector);
        relay.executeData(keccak256("req_empty"), new uint256[](0), new address[](0), _encodeCashOutParams(USER, 50e6));
    }

    /*═══════════════════════ ADMIN ═══════════════════════*/

    function testAdmin_EmergencyRecover() public {
        usdc.mint(address(relay), 100e6);

        vm.prank(OWNER);
        relay.emergencyRecover(address(usdc), OWNER, 100e6);

        assertEq(usdc.balanceOf(OWNER), 100e6, "Owner should receive tokens");
    }

    function testAdmin_NonOwnerCannotEmergencyRecover() public {
        usdc.mint(address(relay), 100e6);

        vm.prank(address(0xA77AC6));
        vm.expectRevert(CashOutRelay.NotOwner.selector);
        relay.emergencyRecover(address(usdc), address(0xA77AC6), 100e6);
    }

    function testAdmin_NonOwnerCannotUpgrade() public {
        CashOutRelay newImpl = new CashOutRelay();

        vm.prank(address(0xA77AC6));
        vm.expectRevert();
        relay.upgradeToAndCall(address(newImpl), "");
    }

    function testAdmin_OwnerCanUpgrade() public {
        CashOutRelay newImpl = new CashOutRelay();

        vm.prank(OWNER);
        relay.upgradeToAndCall(address(newImpl), "");

        // Still works after upgrade
        assertEq(relay.escrow(), address(escrow), "Config preserved after upgrade");
    }

    /*═══════════════════════ INITIALIZATION ═══════════════════════*/

    function testInit_ConfigSetCorrectly() public view {
        assertEq(relay.escrow(), address(escrow), "Escrow should be set");
        assertEq(relay.usdc(), address(usdc), "USDC should be set");
        assertEq(relay.owner(), OWNER, "Owner should be set");
    }

    function testInit_CannotReinitialize() public {
        vm.expectRevert();
        relay.initialize(address(0), address(0), address(0), address(0));
    }

    /*═══════════════════════ SECURITY: FUND THEFT PREVENTION ═══════════════════════*/

    function testSecurity_AttackerCannotStealFailedDeposits() public {
        // User's deposit fails — 50 USDC held in relay
        uint256 amount = 50e6;
        _mintAndDeliver(amount);
        escrow.setRevert(true, "paused");
        _callExecuteData(keccak256("req_victim"), amount, _encodeCashOutParams(USER, amount));

        assertEq(usdc.balanceOf(address(relay)), amount, "Relay holds user's USDC");

        // Attacker calls executeData directly (no bridge, no USDC delivered)
        // with amounts[0] = 50e6 claiming the held USDC
        escrow.setRevert(false, "");
        address attacker = address(0xBAD1);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(attacker);
        // Should revert — available USDC (balance - totalFailedAmount) is 0
        vm.expectRevert(abi.encodeWithSelector(CashOutRelay.InsufficientDelivery.selector, amount, 0));
        relay.executeData(keccak256("req_attack"), amounts, tokens, _encodeCashOutParams(attacker, amount));

        // User's recovery is still intact
        vm.prank(USER);
        relay.recoverFailed(keccak256("req_victim"));
        assertEq(usdc.balanceOf(USER), amount, "User recovered their USDC");
    }

    function testSecurity_EmergencyRecoverCannotDrainUserFunds() public {
        // User's deposit fails — 50 USDC held
        uint256 amount = 50e6;
        _mintAndDeliver(amount);
        escrow.setRevert(true, "paused");
        _callExecuteData(keccak256("req_held"), amount, _encodeCashOutParams(USER, amount));

        // Extra 20 USDC accidentally sent to relay
        usdc.mint(address(relay), 20e6);

        // Owner can recover the extra 20, but NOT the held 50
        vm.prank(OWNER);
        relay.emergencyRecover(address(usdc), OWNER, 20e6);
        assertEq(usdc.balanceOf(OWNER), 20e6, "Owner recovers surplus");

        // Owner tries to drain held funds — should fail
        vm.prank(OWNER);
        vm.expectRevert("would drain recovery funds");
        relay.emergencyRecover(address(usdc), OWNER, 1);

        // User can still recover
        vm.prank(USER);
        relay.recoverFailed(keccak256("req_held"));
        assertEq(usdc.balanceOf(USER), amount, "User still recovers");
    }

    function testSecurity_RequestHashCollisionBlocked() public {
        // Two deposits fail with the same requestHash
        _mintAndDeliver(50e6);
        escrow.setRevert(true, "paused");
        _callExecuteData(keccak256("collision"), 50e6, _encodeCashOutParams(USER, 50e6));

        // Second call with same hash — should revert
        _mintAndDeliver(30e6);
        vm.expectRevert(CashOutRelay.RequestHashAlreadyFailed.selector);
        _callExecuteData(keccak256("collision"), 30e6, _encodeCashOutParams(address(0xBEEF), 30e6));

        // First user's recovery is intact
        assertEq(relay.failedAmount(keccak256("collision")), 50e6, "First user amount preserved");
        assertEq(relay.failedDepositor(keccak256("collision")), USER, "First user address preserved");
    }

    function testSecurity_CreateZkp2pDepositCannotBeCalledExternally() public {
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: 50e6
        });

        vm.prank(address(0xBAD1));
        vm.expectRevert("only self");
        relay.createZkp2pDeposit(params, 50e6);
    }

    /*═══════════════════════ BALANCE VERIFICATION ═══════════════════════*/

    function testBalance_InsufficientDeliveryReverts() public {
        // Don't deliver any USDC — just call executeData
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e6;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(BUNGEE);
        vm.expectRevert(abi.encodeWithSelector(CashOutRelay.InsufficientDelivery.selector, 50e6, 0));
        relay.executeData(keccak256("no_delivery"), amounts, tokens, _encodeCashOutParams(USER, 50e6));
    }

    function testBalance_PartialDeliveryReverts() public {
        // Deliver less than claimed
        usdc.mint(address(relay), 30e6);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 50e6;
        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);

        vm.prank(BUNGEE);
        vm.expectRevert(abi.encodeWithSelector(CashOutRelay.InsufficientDelivery.selector, 50e6, 30e6));
        relay.executeData(keccak256("partial"), amounts, tokens, _encodeCashOutParams(USER, 50e6));
    }

    function testBalance_SuccessiveCallsOnlyUseFreshFunds() public {
        // First call: deliver and deposit 50 USDC
        _mintAndDeliver(50e6);
        _callExecuteData(keccak256("req1"), 50e6, _encodeCashOutParams(USER, 50e6));

        // Relay should be empty
        assertEq(usdc.balanceOf(address(relay)), 0, "Empty after first deposit");

        // Second call: deliver fresh 30 USDC
        _mintAndDeliver(30e6);
        _callExecuteData(keccak256("req2"), 30e6, _encodeCashOutParams(address(0xBEEF), 30e6));

        assertEq(escrow.depositCount(), 2, "Two deposits created");
    }

    /*═══════════════════════ TRACKING ═══════════════════════*/

    function testTracking_TotalFailedAmountAccurate() public {
        escrow.setRevert(true, "paused");

        // Two failures
        _mintAndDeliver(50e6);
        _callExecuteData(keccak256("f1"), 50e6, _encodeCashOutParams(USER, 50e6));
        _mintAndDeliver(30e6);
        _callExecuteData(keccak256("f2"), 30e6, _encodeCashOutParams(address(0xBEEF), 30e6));

        assertEq(relay.totalFailedAmount(), 80e6, "Total failed = 80 USDC");

        // User recovers one
        vm.prank(USER);
        relay.recoverFailed(keccak256("f1"));
        assertEq(relay.totalFailedAmount(), 30e6, "Total failed = 30 after recovery");

        // Second user recovers
        vm.prank(address(0xBEEF));
        relay.recoverFailed(keccak256("f2"));
        assertEq(relay.totalFailedAmount(), 0, "Total failed = 0 after all recovered");
    }

    /*═══════════════════════ ETH HANDLING ═══════════════════════*/

    function testETH_AcceptsAndOwnerCanWithdraw() public {
        // Send ETH to relay
        vm.deal(BUNGEE, 1 ether);
        vm.prank(BUNGEE);
        (bool ok,) = address(relay).call{value: 0.01 ether}("");
        assertTrue(ok, "Should accept ETH");

        assertEq(address(relay).balance, 0.01 ether, "Relay holds ETH");

        // Owner withdraws
        vm.prank(OWNER);
        relay.withdrawETH(OWNER);
        assertEq(OWNER.balance, 0.01 ether, "Owner received ETH");
    }

    function testETH_NonOwnerCannotWithdraw() public {
        vm.deal(address(relay), 0.01 ether);

        vm.prank(address(0xA77AC6));
        vm.expectRevert(CashOutRelay.NotOwner.selector);
        relay.withdrawETH(address(0xA77AC6));
    }

    /*═══════════════════════ CCTP completeCashOut TESTS ═══════════════════════*/

    function _buildCctpMessage(uint256 amount) internal pure returns (bytes memory) {
        return abi.encode(amount);
    }

    function testCCTP_HappyPath_DepositCreated() public {
        uint256 amount = 50e6;
        bytes memory message = _buildCctpMessage(amount);
        bytes memory attestation = hex"CAFE";

        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: amount
        });

        vm.prank(OWNER);
        relay.completeCashOut(message, attestation, params);

        // Escrow should have the deposit, owned by USER
        assertEq(escrow.depositCount(), 1, "Deposit created");
        (address depositor, uint256 depAmount,,) = escrow.deposits(0);
        assertEq(depositor, USER, "Owned by user");
        assertEq(depAmount, amount, "Correct amount");
    }

    function testCCTP_NonOwnerReverts() public {
        bytes memory message = _buildCctpMessage(10e6);
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: 10e6
        });

        vm.prank(address(0xBAD1));
        vm.expectRevert(CashOutRelay.NotOwner.selector);
        relay.completeCashOut(message, hex"CAFE", params);
    }

    function testCCTP_TransmitterReverts_FailsCleanly() public {
        mockTransmitter.setRevert(true);
        bytes memory message = _buildCctpMessage(10e6);
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: 10e6
        });

        vm.prank(OWNER);
        vm.expectRevert("CCTP: invalid attestation");
        relay.completeCashOut(message, hex"CAFE", params);
    }

    function testCCTP_ReplayBlocked() public {
        uint256 amount = 10e6;
        bytes memory message = _buildCctpMessage(amount);
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: amount
        });

        // First call succeeds
        vm.prank(OWNER);
        relay.completeCashOut(message, hex"CAFE", params);

        // Replay reverts (mock has nonce tracking)
        vm.prank(OWNER);
        vm.expectRevert("CCTP: already received");
        relay.completeCashOut(message, hex"CAFE", params);
    }

    function testCCTP_EscrowFails_RecoveryWorks() public {
        escrow.setRevert(true, "ZKP2P paused");
        uint256 amount = 25e6;
        bytes memory message = _buildCctpMessage(amount);
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: amount
        });

        vm.prank(OWNER);
        relay.completeCashOut(message, hex"CAFE", params);

        // USDC held in relay, tracked for recovery
        bytes32 reqHash = keccak256(message);
        assertEq(relay.failedAmount(reqHash), amount, "Failed amount tracked");
        assertEq(relay.failedDepositor(reqHash), USER, "Failed depositor tracked");
        assertEq(relay.totalFailedAmount(), amount, "Total failed updated");

        // User recovers
        vm.prank(USER);
        relay.recoverFailed(reqHash);
        assertEq(usdc.balanceOf(USER), amount, "User recovered USDC");
        assertEq(relay.totalFailedAmount(), 0, "Total failed zeroed");
    }

    function testCCTP_BalanceMathCorrectWithExistingFailedDeposits() public {
        // First: create a failed deposit via Bungee path (50 USDC held)
        _mintAndDeliver(50e6);
        escrow.setRevert(true, "paused");
        _callExecuteData(keccak256("bungee_fail"), 50e6, _encodeCashOutParams(address(0xBEEF), 50e6));
        assertEq(relay.totalFailedAmount(), 50e6);

        // Now: CCTP cashout should succeed independently (no interference from held funds)
        escrow.setRevert(false, "");
        uint256 cctpAmount = 10e6;
        bytes memory message = _buildCctpMessage(cctpAmount);
        CashOutRelay.CashOutParams memory params = CashOutRelay.CashOutParams({
            depositor: USER,
            paymentMethod: VENMO_METHOD,
            payeeDetailsHash: PAYEE_HASH,
            fiatCurrency: USD_CURRENCY,
            conversionRate: CONVERSION_RATE,
            minIntentAmount: 1e6,
            maxIntentAmount: cctpAmount
        });

        vm.prank(OWNER);
        relay.completeCashOut(message, hex"CAFE", params);

        // CCTP deposit should work, Bungee recovery still intact
        assertEq(escrow.depositCount(), 1, "CCTP deposit created");
        assertEq(relay.totalFailedAmount(), 50e6, "Bungee failed amount unchanged");
        assertEq(relay.failedDepositor(keccak256("bungee_fail")), address(0xBEEF), "Bungee recovery intact");
    }
}
