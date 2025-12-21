// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

contract ComputeStorageLocations is Script {
    function run() public view {
        console2.log("ERC-7201 Storage Locations:");
        console2.log("Config:", vm.toString(keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.config")) - 1))));
        console2.log("FeeCaps:", vm.toString(keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.feeCaps")) - 1))));
        console2.log("Rules:", vm.toString(keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.rules")) - 1))));
        console2.log("Budgets:", vm.toString(keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.budgets")) - 1))));
        console2.log("Bounty:", vm.toString(keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.bounty")) - 1))));
    }
}