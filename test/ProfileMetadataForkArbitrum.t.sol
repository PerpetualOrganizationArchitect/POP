// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {PoaManager} from "../src/PoaManager.sol";

/**
 * @title ProfileMetadataForkArbitrumTest
 * @notice Simulates the UAR upgrade on Arbitrum (home chain) against real state.
 *
 * Run:
 *   forge test --match-contract ProfileMetadataForkArbitrumTest --fork-url arbitrum -vvv
 */
contract ProfileMetadataForkArbitrumTest is Test {
    // ─── Arbitrum Mainnet Addresses ───
    address constant ARB_POA_MANAGER = 0xFF585Fae4A944cD173B19158C6FC5E08980b0815;
    address constant ARB_UAR_PROXY = 0x01A13c92321E9CA2C02577b92A4F8d2FDC4d8513;
    address constant ARB_PAYMASTER_PROXY = 0xD6659bCaFAdCB9CC2F57B7aE923c7F1Ca4438a11;
    address constant DEPLOYER = 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9;

    UniversalAccountRegistry reg;
    PoaManager poaManager;

    function setUp() public {
        if (block.chainid == 31337) {
            console.log("SKIP: This test requires --fork-url arbitrum");
            return;
        }
        reg = UniversalAccountRegistry(ARB_UAR_PROXY);
        poaManager = PoaManager(ARB_POA_MANAGER);
    }

    modifier onlyFork() {
        if (block.chainid == 31337) return;
        _;
    }

    function _upgradeUAR() internal {
        UniversalAccountRegistry newImpl = new UniversalAccountRegistry();
        address pmOwner = poaManager.owner();
        vm.prank(pmOwner);
        poaManager.upgradeBeacon("UniversalAccountRegistry", address(newImpl), "v-arb-profile-test");
        console.log("Upgraded UAR on Arbitrum to:", address(newImpl));
    }

    function testFork_Arb_PreUpgrade_HudsonExists() public onlyFork {
        string memory username = reg.getUsername(DEPLOYER);
        assertEq(username, "hudsonhrh");
        console.log("PASS: hudsonhrh exists on Arbitrum");
    }

    function testFork_Arb_StoragePreserved() public onlyFork {
        string memory usernameBefore = reg.getUsername(DEPLOYER);
        uint256 nonceBefore = reg.nonces(DEPLOYER);
        address factoryBefore = reg.passkeyFactory();
        bytes32 dsBefore = reg.DOMAIN_SEPARATOR();

        _upgradeUAR();

        assertEq(reg.getUsername(DEPLOYER), usernameBefore, "username corrupted");
        assertEq(reg.nonces(DEPLOYER), nonceBefore, "nonce corrupted");
        assertEq(reg.passkeyFactory(), factoryBefore, "factory corrupted");
        assertEq(reg.DOMAIN_SEPARATOR(), dsBefore, "domain sep corrupted");
        assertEq(reg.getProfileMetadata(DEPLOYER), bytes32(0), "default not zero");

        console.log("PASS: Arbitrum storage layout safe");
        console.log("  username:", usernameBefore);
        console.log("  nonce:", nonceBefore);
        console.log("  factory:", factoryBefore);
    }

    function testFork_Arb_SetProfileMetadata() public onlyFork {
        _upgradeUAR();

        bytes32 hash = keccak256("arb-profile-test");
        vm.prank(DEPLOYER);
        reg.setProfileMetadata(hash);

        assertEq(reg.getProfileMetadata(DEPLOYER), hash);
        console.log("PASS: setProfileMetadata works on Arbitrum");
    }

    function testFork_Arb_DomainSeparatorDiffersFromGnosis() public onlyFork {
        _upgradeUAR();

        bytes32 ds = reg.DOMAIN_SEPARATOR();
        // Domain separator includes chainId and contract address, so it MUST be
        // different on Arbitrum vs Gnosis (different chainId AND different proxy address)
        // This test just verifies it's non-zero and logs the value
        assertTrue(ds != bytes32(0), "domain separator should not be zero");
        console.log("PASS: Arbitrum domain separator is non-zero");
        console.log("  chainId:", block.chainid);
        console.log("  contract:", address(reg));
    }
}
