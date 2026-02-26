// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {DeterministicDeployer} from "../src/crosschain/DeterministicDeployer.sol";

/*──────────── Simple contract for deployment testing ───────────*/
contract SimpleContract {
    uint256 public value;

    function set(uint256 v) external {
        value = v;
    }
}

contract DeterministicDeployerTest is Test {
    DeterministicDeployer deployer;
    address nonOwner = address(0xBEEF);

    function setUp() public {
        deployer = new DeterministicDeployer();
    }

    // ══════════════════════════════════════════════════════════
    //  1. Deploy produces contract at predicted address
    // ══════════════════════════════════════════════════════════

    function testDeployProducesContractAtPredictedAddress() public {
        bytes32 salt = deployer.computeSalt("HybridVoting", "v1");
        address predicted = deployer.computeAddress(salt);

        address deployed = deployer.deploy(salt, type(SimpleContract).creationCode);

        assertEq(deployed, predicted, "Deployed address should match prediction");
        assertTrue(deployed.code.length > 0, "Contract should have code");
    }

    // ══════════════════════════════════════════════════════════
    //  2. computeSalt is deterministic
    // ══════════════════════════════════════════════════════════

    function testComputeSaltIsDeterministic() public view {
        bytes32 salt1 = deployer.computeSalt("HybridVoting", "v2");
        bytes32 salt2 = deployer.computeSalt("HybridVoting", "v2");
        assertEq(salt1, salt2, "Same inputs should produce same salt");
    }

    // ══════════════════════════════════════════════════════════
    //  3. Different inputs produce different salts
    // ══════════════════════════════════════════════════════════

    function testComputeSaltDifferentInputsDiffer() public view {
        bytes32 saltA = deployer.computeSalt("HybridVoting", "v1");
        bytes32 saltB = deployer.computeSalt("HybridVoting", "v2");
        bytes32 saltC = deployer.computeSalt("TaskManager", "v1");

        assertTrue(saltA != saltB, "Different versions should produce different salts");
        assertTrue(saltA != saltC, "Different type names should produce different salts");
        assertTrue(saltB != saltC, "All should be unique");
    }

    // ══════════════════════════════════════════════════════════
    //  4. Only owner can deploy
    // ══════════════════════════════════════════════════════════

    function testOnlyOwnerCanDeploy() public {
        bytes32 salt = deployer.computeSalt("Test", "v1");

        vm.prank(nonOwner);
        vm.expectRevert();
        deployer.deploy(salt, type(SimpleContract).creationCode);
    }

    // ══════════════════════════════════════════════════════════
    //  5. Empty bytecode reverts
    // ══════════════════════════════════════════════════════════

    function testDeployEmptyBytecodeReverts() public {
        bytes32 salt = deployer.computeSalt("Test", "v1");

        vm.expectRevert(DeterministicDeployer.EmptyBytecode.selector);
        deployer.deploy(salt, "");
    }

    // ══════════════════════════════════════════════════════════
    //  6. Same salt twice reverts
    // ══════════════════════════════════════════════════════════

    function testDeploySameSaltTwiceReverts() public {
        bytes32 salt = deployer.computeSalt("Executor", "v1");

        deployer.deploy(salt, type(SimpleContract).creationCode);

        vm.expectRevert();
        deployer.deploy(salt, type(SimpleContract).creationCode);
    }

    // ══════════════════════════════════════════════════════════
    //  7. Deployed contract is functional
    // ══════════════════════════════════════════════════════════

    function testDeployedContractIsCallable() public {
        bytes32 salt = deployer.computeSalt("Widget", "v1");
        address deployed = deployer.deploy(salt, type(SimpleContract).creationCode);

        SimpleContract sc = SimpleContract(deployed);
        sc.set(42);
        assertEq(sc.value(), 42, "Deployed contract should be functional");
    }

    // ══════════════════════════════════════════════════════════
    //  8. Two deployers produce different addresses for same salt
    // ══════════════════════════════════════════════════════════

    function testDifferentDeployersProduceDifferentAddresses() public {
        DeterministicDeployer deployer2 = new DeterministicDeployer();

        bytes32 salt = deployer.computeSalt("Test", "v1");
        address predicted1 = deployer.computeAddress(salt);
        address predicted2 = deployer2.computeAddress(salt);

        assertTrue(predicted1 != predicted2, "Different deployers should yield different addresses");
    }

    // ══════════════════════════════════════════════════════════
    //  9. Emits Deployed event
    // ══════════════════════════════════════════════════════════

    function testEmitsDeployedEvent() public {
        bytes32 salt = deployer.computeSalt("Token", "v1");
        address predicted = deployer.computeAddress(salt);

        vm.expectEmit(true, false, false, true);
        emit DeterministicDeployer.Deployed(salt, predicted);
        deployer.deploy(salt, type(SimpleContract).creationCode);
    }
}
