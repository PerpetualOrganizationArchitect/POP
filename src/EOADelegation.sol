// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {IAccount, IAccountExecute} from "./interfaces/IAccount.sol";
import {PackedUserOperation} from "./interfaces/PackedUserOperation.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title EOADelegation
 * @author POA Team
 * @notice Minimal ERC-4337 account for EIP-7702 delegated EOAs.
 *
 * @dev When an EOA sets its code via EIP-7702 to delegate to this contract,
 *      the EntryPoint can call `validateUserOp` on the EOA. This contract
 *      validates ECDSA signatures (secp256k1) — the EOA's native key.
 *
 *      Design:
 *      - No storage, no initializer — the "owner" is address(this) (the EOA during delegation)
 *      - Same execute(address,uint256,bytes) selector 0xb61d27f6 as PasskeyAccount,
 *        so PaymasterHub's parseExecuteCall and whitelist validation work identically
 *      - Wallet signs the UserOp hash via personal_sign (EIP-191 prefix)
 *      - Deploy once via DeterministicDeployer, same address on all chains
 */
contract EOADelegation is IAccount, IAccountExecute {
    /*──────────────────── Constants ────────────────────*/

    /// @notice ERC-4337 v0.7 EntryPoint
    address public constant ENTRY_POINT = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    /// @notice Signature validation failed sentinel
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    /*──────────────────── Errors ────────────────────*/

    error OnlyEntryPoint();
    error OnlySelf();
    error ArrayLengthMismatch();

    /*──────────────────── Events ────────────────────*/

    event Executed(address indexed target, uint256 value, bytes data, bytes result);
    event BatchExecuted(uint256 count);

    /*──────────────────── IAccount ────────────────────*/

    /// @inheritdoc IAccount
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        override
        returns (uint256 validationData)
    {
        if (msg.sender != ENTRY_POINT) revert OnlyEntryPoint();

        // Recover signer from ECDSA signature over EIP-191 prefixed hash.
        // The wallet signs via personal_sign which prepends "\x19Ethereum Signed Message:\n32".
        address recovered = ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(userOpHash), userOp.signature);

        // During 7702 delegation, address(this) IS the EOA.
        validationData = (recovered == address(this)) ? 0 : SIG_VALIDATION_FAILED;

        // Pay prefund to EntryPoint
        if (missingAccountFunds > 0) {
            // solhint-disable-next-line no-unused-vars
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            // Return value intentionally ignored — EntryPoint validates the deposit
        }
    }

    /*──────────────────── Execution ────────────────────*/

    /// @inheritdoc IAccountExecute
    function execute(address target, uint256 value, bytes calldata data)
        external
        override
        returns (bytes memory result)
    {
        if (msg.sender != ENTRY_POINT && msg.sender != address(this)) revert OnlySelf();

        bool success;
        (success, result) = target.call{value: value}(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit Executed(target, value, data, result);
    }

    /// @inheritdoc IAccountExecute
    function executeBatch(address[] calldata targets, uint256[] calldata values, bytes[] calldata datas)
        external
        override
    {
        if (msg.sender != ENTRY_POINT && msg.sender != address(this)) revert OnlySelf();
        if (targets.length != values.length || targets.length != datas.length) revert ArrayLengthMismatch();

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory result) = targets[i].call{value: values[i]}(datas[i]);
            if (!success) {
                assembly {
                    revert(add(result, 32), mload(result))
                }
            }
        }

        emit BatchExecuted(targets.length);
    }

    /*──────────────────── Receive ────────────────────*/

    /// @dev Accept native token transfers (ETH/xDAI) for gas prefunding.
    receive() external payable {}
}
