// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @title PaymasterCalldataLib
/// @author POA Engineering
/// @notice Calldata parsing for ERC-4337 execute(address,uint256,bytes) envelope validation
/// @dev Extracts and validates the target, value, and inner selector from a UserOp's callData
///      when it follows the standard SimpleAccount/PasskeyAccount execute pattern.
///      All functions are internal pure (inlined at compile time) for zero gas overhead.
library PaymasterCalldataLib {
    /// @notice Selector for execute(address,uint256,bytes)
    bytes4 internal constant EXECUTE_SELECTOR = 0xb61d27f6;

    /// @notice Parse and validate an execute(address,uint256,bytes) calldata envelope
    /// @dev Checks: callData >= 4 bytes, outer selector = EXECUTE_SELECTOR, callData >= 0x64 bytes,
    ///      target matches expectedTarget, and value == 0. If all pass, extracts the inner selector
    ///      from the nested bytes parameter (if available).
    /// @param callData The full callData from the UserOperation
    /// @param expectedTarget The required target address in the execute call
    /// @return valid True if all structural checks pass (selector, length, target, value)
    /// @return innerSelector First 4 bytes of the inner data payload (bytes4(0) if unavailable)
    function parseExecuteCall(bytes calldata callData, address expectedTarget)
        internal
        pure
        returns (bool valid, bytes4 innerSelector)
    {
        // Must have at least a 4-byte selector
        if (callData.length < 4) return (false, bytes4(0));

        // Outer selector must be execute(address,uint256,bytes)
        if (bytes4(callData[0:4]) != EXECUTE_SELECTOR) return (false, bytes4(0));

        // Need at least 0x64 bytes for execute(address, uint256, bytes offset)
        if (callData.length < 0x64) return (false, bytes4(0));

        address target;
        uint256 value;
        assembly {
            target := calldataload(add(callData.offset, 0x04))
            value := calldataload(add(callData.offset, 0x24))
            // Read inner bytes data (offset at 0x44, must be standard 0x60)
            let dataOffset := calldataload(add(callData.offset, 0x44))
            if eq(dataOffset, 0x60) {
                let dataStart := add(add(0x04, dataOffset), 0x20)
                if lt(dataStart, callData.length) {
                    innerSelector := calldataload(add(callData.offset, dataStart))
                }
            }
        }
        innerSelector = bytes4(innerSelector);

        // Target must match and value must be zero
        if (target != expectedTarget || value != 0) return (false, bytes4(0));

        valid = true;
    }
}
