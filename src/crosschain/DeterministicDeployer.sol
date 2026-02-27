// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {CREATE3} from "solady/utils/CREATE3.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title DeterministicDeployer
/// @notice Deploys contracts to deterministic addresses using CREATE3.
///         The resulting address depends only on this deployer's address + the salt,
///         NOT on the creation bytecode. Deploy this contract to the same address on
///         every chain (via CREATE2) and the same salt yields the same address everywhere.
/// @dev    Uses Ownable2Step to prevent accidental ownership loss. Ownership cannot be
///         renounced since losing it permanently bricks the cross-chain deploy pipeline.
contract DeterministicDeployer is Ownable2Step {
    constructor(address _owner) Ownable(_owner) {}

    /*──────────── Errors ───────────*/
    error CannotRenounce();
    error EmptyBytecode();

    /// @dev Ownership cannot be renounced — losing it bricks the deployer permanently.
    function renounceOwnership() public pure override {
        revert CannotRenounce();
    }

    /*──────────── Events ──────────*/
    event Deployed(bytes32 indexed salt, address deployed);

    /// @notice Deploy a contract to a deterministic address.
    /// @param salt          CREATE3 salt (use `computeSalt` for the standard derivation).
    /// @param creationCode  Full creation bytecode including constructor args.
    /// @return deployed     The address of the newly deployed contract.
    function deploy(bytes32 salt, bytes calldata creationCode) external onlyOwner returns (address deployed) {
        if (creationCode.length == 0) revert EmptyBytecode();
        deployed = CREATE3.deployDeterministic(creationCode, salt);
        emit Deployed(salt, deployed);
    }

    /// @notice Predict the address for a given salt (without deploying).
    function computeAddress(bytes32 salt) external view returns (address) {
        return CREATE3.predictDeterministicAddress(salt);
    }

    /// @notice Standard salt derivation used across all POP chains.
    /// @param typeName  Contract type name, e.g. "HybridVoting".
    /// @param version   Version string, e.g. "v2".
    function computeSalt(string calldata typeName, string calldata version) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("POA_IMPL", keccak256(bytes(typeName)), keccak256(bytes(version))));
    }
}
