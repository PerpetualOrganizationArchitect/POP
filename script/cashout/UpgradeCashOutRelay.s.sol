// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {CashOutRelay} from "../../src/cashout/CashOutRelay.sol";

/**
 * @title UpgradeCashOutRelay
 * @notice Deploys a new CashOutRelay implementation and upgrades the existing
 *         UUPS proxy on Base to point at it. Run as the relay owner (the EOA
 *         that initialized the proxy).
 *
 *         The current upgrade carries the "full-fill only" change:
 *         createZkp2pDeposit pins `intentAmountRange.min == max == amount` so
 *         partial fills can no longer leave sub-min dust stranded in deposits.
 *
 *   FOUNDRY_PROFILE=production forge script \
 *     script/cashout/UpgradeCashOutRelay.s.sol \
 *     --rpc-url base --broadcast --slow \
 *     --private-key $DEPLOYER_PRIVATE_KEY
 */
contract UpgradeCashOutRelay is Script {
    /// @dev Deployed proxy on Base. Update only if redeploying from scratch.
    address constant PROXY = 0xA65414A21dc114199cAfD7c6c3ed99488Eb9eFE5;

    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n=== Upgrade CashOutRelay on Base ===");
        console.log("Proxy:    ", PROXY);
        console.log("Deployer: ", deployer);

        // Sanity: caller must be the relay owner (UUPS _authorizeUpgrade enforces)
        address currentOwner = CashOutRelay(payable(PROXY)).owner();
        require(currentOwner == deployer, "deployer is not relay owner");

        vm.startBroadcast(deployerKey);

        CashOutRelay newImpl = new CashOutRelay();
        console.log("New impl:", address(newImpl));

        // Upgrade proxy. No re-init data — storage layout is append-compatible.
        CashOutRelay(payable(PROXY)).upgradeToAndCall(address(newImpl), "");

        vm.stopBroadcast();

        console.log("\nUpgrade complete. New cashouts use the full-fill-only intent range.");
        console.log("Existing deposits (pre-upgrade) keep their old range; depositors can");
        console.log("withdraw any sub-min residue via EscrowV2.withdrawDeposit(depositId).");
    }
}
