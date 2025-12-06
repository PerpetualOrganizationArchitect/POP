// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PackedUserOperation} from "./PackedUserOperation.sol";

/**
 * @title IAccount
 * @notice ERC-4337 Account interface
 * @dev Required interface for smart contract wallets in the ERC-4337 account abstraction system
 *
 *      The account's validateUserOp function is called by the EntryPoint to validate
 *      a UserOperation before execution. The account must verify the signature and
 *      may perform additional authorization checks.
 *
 *      Return Values for validationData:
 *      - 0: Signature is valid
 *      - 1: Signature validation failed (SIG_VALIDATION_FAILED)
 *      - Packed value: (authorizer address, validUntil, validAfter)
 *        - authorizer: Address to call for additional validation (0 for none)
 *        - validUntil: Timestamp until which the signature is valid (0 for infinite)
 *        - validAfter: Timestamp from which the signature is valid (0 for immediate)
 */
interface IAccount {
    /**
     * @notice Validate a UserOperation
     * @param userOp The UserOperation to validate
     * @param userOpHash Hash of the UserOperation (excluding signature)
     * @param missingAccountFunds Amount the account needs to pay to EntryPoint for gas
     * @return validationData 0 for success, 1 for signature failure, or packed validation data
     * @dev The account MUST pay `missingAccountFunds` to the EntryPoint (msg.sender)
     *      if it has sufficient balance. This payment happens before execution.
     *      The account may receive partial or full refund after execution via postOp.
     */
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        returns (uint256 validationData);
}

/**
 * @title IAccountExecute
 * @notice Optional interface for accounts that support direct execution
 * @dev This interface allows the EntryPoint to call execute directly
 */
interface IAccountExecute {
    /**
     * @notice Execute a transaction from the account
     * @param target The target address to call
     * @param value The ETH value to send
     * @param data The calldata to send
     * @return result The return data from the call
     */
    function execute(address target, uint256 value, bytes calldata data) external returns (bytes memory result);

    /**
     * @notice Execute multiple transactions from the account
     * @param targets The target addresses to call
     * @param values The ETH values to send
     * @param datas The calldatas to send
     */
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas) external;
}
