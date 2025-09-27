// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct PackedUserOperation {
    address sender;
    uint256 nonce;
    bytes initCode;
    bytes callData;
    bytes32 accountGasLimits;
    uint256 preVerificationGas;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
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
    
    function packAccountGasLimits(uint128 verificationGasLimit, uint128 callGasLimit) 
        internal 
        pure 
        returns (bytes32) 
    {
        return bytes32(uint256(verificationGasLimit) | (uint256(callGasLimit) << 128));
    }
}