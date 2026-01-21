// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

interface IEntryPoint {
    function depositTo(address account) external payable;
    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external;
    function balanceOf(address account) external view returns (uint256);
}
