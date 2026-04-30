// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ParticipationToken} from "../src/ParticipationToken.sol";
import {PoaManager} from "../src/PoaManager.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/**
 * @title SimulateParticipationTokenSetters
 * @notice Fork-simulates the v2 ParticipationToken upgrade against Argus's
 *         live PT proxy on Gnosis, then renames it and verifies the new
 *         setName / setSymbol setters work end-to-end.
 *
 * Verifies:
 *  - v2 impl deploys via DD
 *  - Beacon upgrade routes existing Argus PT proxy to the new impl
 *  - executor can rename the token (short and long strings)
 *  - balances and totalSupply are unchanged after rename
 *  - non-executor calls revert
 *
 * Usage:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/SimulateParticipationTokenSetters.s.sol:SimulateParticipationTokenSetters \
 *     --rpc-url https://rpc.gnosischain.com
 */
contract SimulateParticipationTokenSetters is Script {
    address constant GNOSIS_PM = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
    address constant DD = 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a;

    // Argus on Gnosis (real on-chain addresses from subgraph)
    address constant ARGUS_PT = 0x5cafc2FA0653b34BDC51d738D67E70409A4b4806;
    address constant ARGUS_EXECUTOR = 0x9116BB47EF766cD867151fee8823e662da3bDad9;

    function run() public {
        ParticipationToken pt = ParticipationToken(ARGUS_PT);

        console.log("\n========================================");
        console.log("  ParticipationToken v2 fork simulation");
        console.log("========================================");
        console.log("Argus PT proxy:", ARGUS_PT);
        console.log("Argus executor:", ARGUS_EXECUTOR);
        console.log("Pre-upgrade name:  ", pt.name());
        console.log("Pre-upgrade symbol:", pt.symbol());

        // 1. Confirm pre-upgrade impl is missing setName (call should revert)
        console.log("\n--- Pre-upgrade: setName should NOT exist on v1 impl ---");
        vm.prank(ARGUS_EXECUTOR);
        (bool ok,) = ARGUS_PT.call(abi.encodeWithSignature("setName(string)", "ShouldFail"));
        require(!ok, "setName should not exist on v1 impl");
        console.log("OK: setName reverted on v1 impl as expected");

        // 2. Deploy + upgrade beacon to v2 in-memory
        console.log("\n--- Upgrading beacon to v2 ---");
        DeterministicDeployer dd = DeterministicDeployer(DD);
        bytes32 salt = dd.computeSalt("ParticipationToken", "v2");
        address v2Impl = dd.computeAddress(salt);

        if (v2Impl.code.length == 0) {
            address deployer = vm.addr(vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY")));
            vm.prank(deployer);
            dd.deploy(salt, type(ParticipationToken).creationCode);
            console.log("Deployed v2 impl:", v2Impl);
        } else {
            console.log("v2 impl already deployed:", v2Impl);
        }

        // Upgrade beacon as PoaManager owner (the satellite on Gnosis)
        PoaManager pm = PoaManager(GNOSIS_PM);
        address pmOwner = pm.owner();
        vm.prank(pmOwner);
        pm.upgradeBeacon("ParticipationToken", v2Impl, "v2");
        console.log("Beacon upgraded. Current impl:");
        console.log("  ", pm.getCurrentImplementationById(keccak256("ParticipationToken")));

        // 3. Snapshot balances / totalSupply before rename
        uint256 supplyBefore = pt.totalSupply();
        // Pick a few likely-non-zero holders; if zero, that's still fine.
        address sample = ARGUS_EXECUTOR;
        uint256 sampleBalBefore = pt.balanceOf(sample);
        console.log("\n--- Pre-rename state ---");
        console.log("totalSupply:", supplyBefore);

        // 4. Rename via executor
        console.log("\n--- Rename via executor ---");
        vm.prank(ARGUS_EXECUTOR);
        pt.setName("Argus Reputation");
        vm.prank(ARGUS_EXECUTOR);
        pt.setSymbol("ARG");
        console.log("Post-rename name:  ", pt.name());
        console.log("Post-rename symbol:", pt.symbol());
        require(keccak256(bytes(pt.name())) == keccak256("Argus Reputation"), "name not updated");
        require(keccak256(bytes(pt.symbol())) == keccak256("ARG"), "symbol not updated");

        // 5. Critical: balances + totalSupply unchanged
        require(pt.totalSupply() == supplyBefore, "totalSupply corrupted");
        require(pt.balanceOf(sample) == sampleBalBefore, "balance corrupted");
        console.log("Balances preserved: PASS");

        // 6. Non-executor caller must revert
        console.log("\n--- Non-executor caller test ---");
        address random = address(0xC0FFEE);
        vm.prank(random);
        (ok,) = ARGUS_PT.call(abi.encodeWithSignature("setName(string)", "Hijacked"));
        require(!ok, "non-executor was able to setName");
        console.log("Non-executor setName reverted: PASS");

        // 7. Long-string path
        console.log("\n--- Long-string rename ---");
        string memory longName = "Argus Sprint Cycle Reputation Token!"; // 36 bytes
        vm.prank(ARGUS_EXECUTOR);
        pt.setName(longName);
        require(keccak256(bytes(pt.name())) == keccak256(bytes(longName)), "long name not updated");
        console.log("Post long-string name:", pt.name());
        require(pt.totalSupply() == supplyBefore, "totalSupply corrupted by long-string write");

        console.log("\n========================================");
        console.log("  ALL CHECKS PASSED");
        console.log("========================================");
    }
}
