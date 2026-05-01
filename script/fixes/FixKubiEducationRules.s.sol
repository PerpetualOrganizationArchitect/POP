// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPaymasterHub {
    function setRulesBatch(
        bytes32 orgId,
        address[] calldata targets,
        bytes4[] calldata selectors,
        bool[] calldata allowed,
        uint32[] calldata maxCallGasHints
    ) external;

    struct OrgConfig {
        uint256 adminHatId;
        uint256 operatorHatId;
        bool paused;
        uint40 registeredAt;
        bool bannedFromSolidarity;
    }

    function getOrgConfig(bytes32 orgId) external view returns (OrgConfig memory);

    struct Rule {
        uint32 maxCallGasHint;
        bool allowed;
    }
    // Rule storage is exposed via mapping getter? Use direct storage read for verification.
}

interface IHats {
    function isWearerOfHat(address wearer, uint256 hatId) external view returns (bool);
}

/**
 * @title FixKubiEducationRules
 * @notice Adds createModule, updateModule, removeModule paymaster rules for KUBI's
 *         EducationHub on Gnosis. Callable by any address wearing KUBI's operatorHat
 *         (deployer is a wearer).
 *
 * Dry-run (fork simulate):
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixKubiEducationRules.s.sol:FixKubiEducationRulesSim \
 *     --rpc-url gnosis
 *
 * Broadcast:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixKubiEducationRules.s.sol:FixKubiEducationRules \
 *     --rpc-url gnosis --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 */
contract FixKubiEducationRulesBase is Script {
    // Gnosis addresses
    address constant GNOSIS_PM = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    // KUBI org
    bytes32 constant KUBI_ORG = 0xc0f2765d555e21bfad5c6b05accef86a5758e0dee3e9a5b4ee3c3f3069c2102e;
    address constant KUBI_EDU_HUB = 0x83C7Aa49C0C5a55E22640AC164abA838E6f1f7ae;

    // Selectors
    bytes4 constant SEL_CREATE_MODULE = 0x7febbf23; // createModule(bytes,bytes32,uint256,uint8)
    bytes4 constant SEL_UPDATE_MODULE = 0x0803ae1d; // updateModule(uint256,bytes,bytes32,uint256)
    bytes4 constant SEL_REMOVE_MODULE = 0xd8e55e14; // removeModule(uint256)

    function _buildRuleArgs()
        internal
        pure
        returns (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints)
    {
        targets = new address[](3);
        sels = new bytes4[](3);
        allowed = new bool[](3);
        hints = new uint32[](3);

        for (uint256 i; i < 3; i++) {
            targets[i] = KUBI_EDU_HUB;
            allowed[i] = true;
            hints[i] = 0;
        }
        sels[0] = SEL_CREATE_MODULE;
        sels[1] = SEL_UPDATE_MODULE;
        sels[2] = SEL_REMOVE_MODULE;
    }

    function _preflightChecks(address caller) internal view returns (uint256 operatorHatId) {
        // Verify KUBI is registered
        IPaymasterHub.OrgConfig memory cfg = IPaymasterHub(GNOSIS_PM).getOrgConfig(KUBI_ORG);
        require(cfg.registeredAt != 0, "KUBI not registered on Gnosis PaymasterHub");
        operatorHatId = cfg.operatorHatId;
        require(operatorHatId != 0, "KUBI has no operatorHatId set");

        // Verify caller wears the operator hat
        bool isOperator = IHats(HATS).isWearerOfHat(caller, operatorHatId);
        bool isAdmin = IHats(HATS).isWearerOfHat(caller, cfg.adminHatId);
        require(isOperator || isAdmin, "Caller must wear KUBI adminHat or operatorHat");

        console.log("KUBI registered: PASS");
        console.log("KUBI adminHatId:", cfg.adminHatId);
        console.log("KUBI operatorHatId:", operatorHatId);
        console.log("Caller is operator:", isOperator);
        console.log("Caller is admin:   ", isAdmin);
    }
}

/**
 * @notice Dry-run: simulates the setRulesBatch call without broadcasting.
 *         Also performs pre-flight verification.
 */
contract FixKubiEducationRulesSim is FixKubiEducationRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  KUBI EducationHub Rules Fix (DRY RUN)");
        console.log("========================================");
        console.log("Caller:", deployer);
        console.log("PaymasterHub:", GNOSIS_PM);
        console.log("EducationHub:", KUBI_EDU_HUB);

        _preflightChecks(deployer);

        (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints) =
            _buildRuleArgs();

        console.log("\n--- Rules to add ---");
        for (uint256 i; i < sels.length; i++) {
            console.log("  target:", targets[i]);
            console.logBytes4(sels[i]);
            console.log("  allowed:", allowed[i]);
        }

        // Simulate via prank
        vm.prank(deployer);
        IPaymasterHub(GNOSIS_PM).setRulesBatch(KUBI_ORG, targets, sels, allowed, hints);

        console.log("\nsetRulesBatch simulated successfully: PASS");
        console.log("\nTo broadcast, run FixKubiEducationRules:run with --broadcast");
    }
}

/**
 * @notice Broadcast: actually sends the setRulesBatch tx as the deployer.
 */
contract FixKubiEducationRules is FixKubiEducationRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  KUBI EducationHub Rules Fix (BROADCAST)");
        console.log("========================================");
        console.log("Caller:", deployer);

        _preflightChecks(deployer);

        (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints) =
            _buildRuleArgs();

        vm.startBroadcast(deployerKey);
        IPaymasterHub(GNOSIS_PM).setRulesBatch(KUBI_ORG, targets, sels, allowed, hints);
        vm.stopBroadcast();

        console.log("\nsetRulesBatch broadcast submitted");
    }
}
