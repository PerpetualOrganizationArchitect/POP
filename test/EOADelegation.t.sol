// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {EOADelegation} from "../src/EOADelegation.sol";
import {PackedUserOperation} from "../src/interfaces/PackedUserOperation.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @dev Mock EntryPoint that can call validateUserOp and execute
contract MockEntryPoint {
    function callValidate(
        address account,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingFunds
    ) external returns (uint256) {
        return EOADelegation(payable(account)).validateUserOp(userOp, userOpHash, missingFunds);
    }

    function callExecute(address account, address target, uint256 value, bytes calldata data)
        external
        returns (bytes memory)
    {
        return EOADelegation(payable(account)).execute(target, value, data);
    }

    function callExecuteBatch(
        address account,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata datas
    ) external {
        EOADelegation(payable(account)).executeBatch(targets, values, datas);
    }

    receive() external payable {}
}

/// @dev Simple target contract for testing execute calls
contract Counter {
    uint256 public count;

    function increment() external {
        count++;
    }

    function incrementBy(uint256 n) external {
        count += n;
    }

    function getCount() external view returns (uint256) {
        return count;
    }
}

contract EOADelegationTest is Test {
    EOADelegation delegation;
    MockEntryPoint entryPoint;
    Counter counter;

    uint256 constant EOA_PK = 0xA11CE;
    address eoaAddr;

    function setUp() public {
        delegation = new EOADelegation();
        entryPoint = new MockEntryPoint();
        counter = new Counter();
        eoaAddr = vm.addr(EOA_PK);

        // Fund the EOA
        vm.deal(eoaAddr, 10 ether);

        // Override the ENTRY_POINT check by deploying delegation code at a known address
        // and calling from the mock entry point. We use vm.etch to put delegation code
        // at the EOA address (simulating 7702 delegation).
        vm.etch(address(entryPoint), address(delegation).code);

        // For tests, deploy fresh delegation and entry point
        delegation = new EOADelegation();
        entryPoint = new MockEntryPoint();
    }

    /*──────────────── Helpers ────────────────*/

    function _buildUserOp(bytes memory callData, bytes memory signature)
        internal
        view
        returns (PackedUserOperation memory)
    {
        return PackedUserOperation({
            sender: eoaAddr,
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: signature
        });
    }

    function _signUserOpHash(uint256 pk, bytes32 userOpHash) internal pure returns (bytes memory) {
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethSignedHash);
        return abi.encodePacked(r, s, v);
    }

    /*──────────────── validateUserOp Tests ────────────────*/

    function testValidateUserOp_ValidSignature() public {
        bytes32 userOpHash = keccak256("test-user-op");
        bytes memory sig = _signUserOpHash(EOA_PK, userOpHash);

        PackedUserOperation memory userOp = _buildUserOp("", sig);

        // Deploy delegation code at EOA address (simulate 7702)
        vm.etch(eoaAddr, address(delegation).code);

        // Call from ENTRY_POINT address
        vm.prank(delegation.ENTRY_POINT());
        uint256 result = EOADelegation(payable(eoaAddr)).validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 0, "Valid signature should return 0");
    }

    function testValidateUserOp_InvalidSignature() public {
        bytes32 userOpHash = keccak256("test-user-op");

        // Sign with wrong key
        uint256 wrongPk = 0xB0B;
        bytes memory sig = _signUserOpHash(wrongPk, userOpHash);

        PackedUserOperation memory userOp = _buildUserOp("", sig);

        vm.etch(eoaAddr, address(delegation).code);
        vm.prank(delegation.ENTRY_POINT());
        uint256 result = EOADelegation(payable(eoaAddr)).validateUserOp(userOp, userOpHash, 0);

        assertEq(result, 1, "Invalid signature should return 1");
    }

    function testValidateUserOp_OnlyEntryPoint() public {
        bytes32 userOpHash = keccak256("test");
        bytes memory sig = _signUserOpHash(EOA_PK, userOpHash);
        PackedUserOperation memory userOp = _buildUserOp("", sig);

        vm.etch(eoaAddr, address(delegation).code);

        // Call from non-EntryPoint should revert
        vm.prank(address(0xDEAD));
        vm.expectRevert(EOADelegation.OnlyEntryPoint.selector);
        EOADelegation(payable(eoaAddr)).validateUserOp(userOp, userOpHash, 0);
    }

    function testValidateUserOp_PaysPrefund() public {
        bytes32 userOpHash = keccak256("test");
        bytes memory sig = _signUserOpHash(EOA_PK, userOpHash);
        PackedUserOperation memory userOp = _buildUserOp("", sig);

        vm.etch(eoaAddr, address(delegation).code);

        address ep = delegation.ENTRY_POINT();
        uint256 epBalanceBefore = ep.balance;

        vm.prank(ep);
        EOADelegation(payable(eoaAddr)).validateUserOp(userOp, userOpHash, 0.1 ether);

        assertEq(ep.balance - epBalanceBefore, 0.1 ether, "Should pay prefund to EntryPoint");
    }

    /*──────────────── execute Tests ────────────────*/

    function testExecute_FromEntryPoint() public {
        vm.etch(eoaAddr, address(delegation).code);

        bytes memory callData = abi.encodeWithSignature("increment()");

        vm.prank(delegation.ENTRY_POINT());
        EOADelegation(payable(eoaAddr)).execute(address(counter), 0, callData);

        assertEq(counter.count(), 1);
    }

    function testExecute_FromSelf() public {
        vm.etch(eoaAddr, address(delegation).code);

        bytes memory callData = abi.encodeWithSignature("increment()");

        vm.prank(eoaAddr);
        EOADelegation(payable(eoaAddr)).execute(address(counter), 0, callData);

        assertEq(counter.count(), 1);
    }

    function testExecute_RejectsUnauthorized() public {
        vm.etch(eoaAddr, address(delegation).code);

        bytes memory callData = abi.encodeWithSignature("increment()");

        vm.prank(address(0xBEEF));
        vm.expectRevert(EOADelegation.OnlySelf.selector);
        EOADelegation(payable(eoaAddr)).execute(address(counter), 0, callData);
    }

    function testExecute_BubblesRevert() public {
        vm.etch(eoaAddr, address(delegation).code);

        // Call a non-existent function — will revert
        bytes memory callData = abi.encodeWithSignature("nonExistent()");

        vm.prank(delegation.ENTRY_POINT());
        vm.expectRevert();
        EOADelegation(payable(eoaAddr)).execute(address(counter), 0, callData);
    }

    function testExecute_WithValue() public {
        vm.etch(eoaAddr, address(delegation).code);

        address recipient = address(0x1234);
        uint256 sendAmount = 1 ether;

        vm.prank(delegation.ENTRY_POINT());
        EOADelegation(payable(eoaAddr)).execute(recipient, sendAmount, "");

        assertEq(recipient.balance, sendAmount);
    }

    /*──────────────── executeBatch Tests ────────────────*/

    function testExecuteBatch() public {
        vm.etch(eoaAddr, address(delegation).code);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        targets[0] = address(counter);
        targets[1] = address(counter);
        values[0] = 0;
        values[1] = 0;
        datas[0] = abi.encodeWithSignature("increment()");
        datas[1] = abi.encodeWithSignature("incrementBy(uint256)", 5);

        vm.prank(delegation.ENTRY_POINT());
        EOADelegation(payable(eoaAddr)).executeBatch(targets, values, datas);

        assertEq(counter.count(), 6); // 1 + 5
    }

    function testExecuteBatch_ArrayLengthMismatch() public {
        vm.etch(eoaAddr, address(delegation).code);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // mismatch
        bytes[] memory datas = new bytes[](2);

        vm.prank(delegation.ENTRY_POINT());
        vm.expectRevert(EOADelegation.ArrayLengthMismatch.selector);
        EOADelegation(payable(eoaAddr)).executeBatch(targets, values, datas);
    }

    function testExecuteBatch_RejectsUnauthorized() public {
        vm.etch(eoaAddr, address(delegation).code);

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory datas = new bytes[](0);

        vm.prank(address(0xBEEF));
        vm.expectRevert(EOADelegation.OnlySelf.selector);
        EOADelegation(payable(eoaAddr)).executeBatch(targets, values, datas);
    }

    /*──────────────── execute selector Tests ────────────────*/

    function testExecuteSelector() public pure {
        // Verify execute has the same selector as PasskeyAccount (0xb61d27f6)
        bytes4 selector = bytes4(keccak256("execute(address,uint256,bytes)"));
        assertEq(selector, bytes4(0xb61d27f6));
    }

    function testExecuteBatchSelector() public pure {
        bytes4 selector = bytes4(keccak256("executeBatch(address[],uint256[],bytes[])"));
        assertEq(selector, bytes4(0x47e1da2a));
    }

    /*──────────────── receive Tests ────────────────*/

    function testReceiveETH() public {
        vm.etch(eoaAddr, address(delegation).code);

        uint256 balBefore = eoaAddr.balance;
        vm.deal(address(this), 1 ether);
        payable(eoaAddr).transfer(0.5 ether);

        assertEq(eoaAddr.balance, balBefore + 0.5 ether);
    }
}
