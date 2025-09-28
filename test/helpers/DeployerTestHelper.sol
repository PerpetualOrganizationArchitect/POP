// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Deployer} from "../../src/Deployer.sol";
import {IHybridVotingInit} from "../../src/libs/ModuleDeploymentLib.sol";

/// @title DeployerTestHelper
/// @notice Helper contract for tests to easily deploy organizations
/// @dev Provides a backward-compatible interface for existing tests
abstract contract DeployerTestHelper {
    
    /// @notice Deploy a full org using individual parameters
    /// @dev Wraps the struct-based deployFullOrgWithConfig for backward compatibility
    function deployFullOrgLegacy(
        Deployer deployer,
        bytes32 orgId,
        string memory orgName,
        address registryAddr,
        bool autoUpgrade,
        uint8 quorumPct,
        IHybridVotingInit.ClassConfig[] memory votingClasses,
        string[] memory roleNames,
        string[] memory roleImages,
        bool[] memory roleCanVote,
        Deployer.RoleAssignments memory roleAssignments,
        Deployer.PaymasterConfig memory paymasterConfig,
        uint256 value
    )
        internal
        returns (
            address hybridVoting,
            address executorAddr,
            address quickJoin,
            address participationToken,
            address taskManager,
            address educationHub,
            address paymentManager,
            address paymasterHub
        )
    {
        // Create the deployment config struct
        Deployer.DeployConfig memory config = Deployer.DeployConfig({
            orgId: orgId,
            orgName: orgName,
            registryAddr: registryAddr,
            autoUpgrade: autoUpgrade,
            quorumPct: quorumPct,
            votingClasses: votingClasses,
            roleNames: roleNames,
            roleImages: roleImages,
            roleCanVote: roleCanVote,
            roleAssignments: roleAssignments,
            paymasterConfig: paymasterConfig
        });
        
        // Call the deployer with the config
        return deployer.deployFullOrgWithConfig{value: value}(config);
    }
}