// SPDX-License-Identifier: AGPL-3.0-only
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

// NOTE: This test file previously tested the old distributeRevenue() push-based API.
// All scenarios are now covered by:
//   - test/PaymentManagerMerkle.t.sol (26 tests for merkle distribution system)
//   - test/DeployerTest.t.sol (integration tests for pay/payERC20/optOut)
// Payment reception functions (pay, payERC20) remain unchanged and are tested in DeployerTest
