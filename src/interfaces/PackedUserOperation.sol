// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

/// @notice Targets ERC-4337 v0.7 EntryPoint (0x0000000071727De22E5E9d8BAf0edAc6f37da032)
struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    bytes32 gasFees;
    bytes paymasterAndData;
    bytes signature;
}

library UserOpLib {
    function unpackAccountGasLimits(bytes32 accountGasLimits)
        internal
        pure
        returns (uint128 verificationGasLimit, uint128 callGasLimit)
    {
        verificationGasLimit = uint128(uint256(accountGasLimits));
        callGasLimit = uint128(uint256(accountGasLimits >> 128));
    }

    function packAccountGasLimits(uint128 verificationGasLimit, uint128 callGasLimit) internal pure returns (bytes32) {
        return bytes32(uint256(verificationGasLimit) | (uint256(callGasLimit) << 128));
    }

    /// @notice Unpack gasFees into maxPriorityFeePerGas and maxFeePerGas
    function unpackGasFees(bytes32 gasFees) internal pure returns (uint128 maxPriorityFeePerGas, uint128 maxFeePerGas) {
        maxPriorityFeePerGas = uint128(uint256(gasFees));
        maxFeePerGas = uint128(uint256(gasFees >> 128));
    }

    /// @notice Pack maxPriorityFeePerGas and maxFeePerGas into gasFees
    function packGasFees(uint128 maxPriorityFeePerGas, uint128 maxFeePerGas) internal pure returns (bytes32) {
        return bytes32(uint256(maxPriorityFeePerGas) | (uint256(maxFeePerGas) << 128));
    }
}
