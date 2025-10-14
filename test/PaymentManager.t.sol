// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PaymentManager} from "../src/PaymentManager.sol";
import {IPaymentManager} from "../src/interfaces/IPaymentManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

// NOTE: All PaymentManager tests have been commented out because they test
// the old distributeRevenue() API which has been removed.
// TODO: Rewrite tests to use the new merkle-based distribution system:
//   - createDistribution() for creating distributions
//   - claimDistribution() for claiming
//   - See scripts/GenerateDistributionMerkle.s.sol for merkle tree generation
