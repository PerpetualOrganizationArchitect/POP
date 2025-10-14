// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ISnapshotToken
 * @notice Interface for ERC20 tokens with snapshot functionality
 */
interface ISnapshotToken is IERC20 {
    /**
     * @notice Creates a new snapshot
     * @return The ID of the created snapshot
     */
    function snapshot() external returns (uint256);

    /**
     * @notice Gets the balance of an account at a specific snapshot
     * @param account The address to query
     * @param snapshotId The snapshot ID
     * @return The balance at the snapshot
     */
    function balanceOfAt(address account, uint256 snapshotId) external view returns (uint256);

    /**
     * @notice Gets the total supply at a specific snapshot
     * @param snapshotId The snapshot ID
     * @return The total supply at the snapshot
     */
    function totalSupplyAt(uint256 snapshotId) external view returns (uint256);

    /**
     * @notice Gets the current snapshot ID
     * @return The current snapshot ID
     */
    function currentSnapshotId() external view returns (uint256);
}