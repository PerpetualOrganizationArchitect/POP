// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";

interface IPaymasterHub {
    struct OrgConfig {
        uint256 adminHatId;
        uint256 operatorHatId;
        bool paused;
        uint40 registeredAt;
        bool bannedFromSolidarity;
    }

    function getOrgConfig(bytes32 orgId) external view returns (OrgConfig memory);

    function setRulesBatch(
        bytes32 orgId,
        address[] calldata targets,
        bytes4[] calldata selectors,
        bool[] calldata allowed,
        uint32[] calldata maxCallGasHints
    ) external;
}

interface IHats {
    function isWearerOfHat(address wearer, uint256 hatId) external view returns (bool);
}

/**
 * @title FixKubiOrgMetaRules
 * @notice Adds the `updateOrgMetaAsAdmin(bytes32,bytes,bytes32)` paymaster rule for KUBI's
 *         OrgRegistry on Gnosis. Without this rule, passkey/4337 users hit
 *         RuleDenied(OrgRegistry, 0x3d2d2382) when editing org metadata on the Settings page.
 *
 *         OrgRegistry is deployed at the same CREATE2 address on Gnosis as on Arbitrum
 *         (0x3744b372abc41589226313F2bB1dB3aCAa22A854). KUBI is registered on the Gnosis
 *         PaymasterHub, so the rule lands there.
 *
 *         Caller must wear KUBI's adminHat or operatorHat on Gnosis (per onlyOrgOperator
 *         in PaymasterHub).
 *
 * Dry-run:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixKubiOrgMetaRules.s.sol:FixKubiOrgMetaRulesSim \
 *     --rpc-url gnosis
 *
 * Broadcast:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixKubiOrgMetaRules.s.sol:FixKubiOrgMetaRules \
 *     --rpc-url gnosis --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 */
contract FixKubiOrgMetaRulesBase is Script {
    // Gnosis addresses
    address constant GNOSIS_PM = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant ORG_REGISTRY = 0x3744b372abc41589226313F2bB1dB3aCAa22A854; // same on Gnosis + Arbitrum (CREATE2)
    address constant HATS = 0x3bc1A0Ad72417f2d411118085256fC53CBdDd137;

    // KUBI org
    bytes32 constant KUBI_ORG = 0xc0f2765d555e21bfad5c6b05accef86a5758e0dee3e9a5b4ee3c3f3069c2102e;

    // Selector for updateOrgMetaAsAdmin(bytes32,bytes,bytes32)
    bytes4 constant SEL_UPDATE_ORG_META = 0x3d2d2382;

    function _buildRuleArgs()
        internal
        pure
        returns (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints)
    {
        targets = new address[](1);
        sels = new bytes4[](1);
        allowed = new bool[](1);
        hints = new uint32[](1);

        targets[0] = ORG_REGISTRY;
        sels[0] = SEL_UPDATE_ORG_META;
        allowed[0] = true;
        hints[0] = 0;
    }

    function _preflightChecks(address caller) internal view {
        IPaymasterHub.OrgConfig memory cfg = IPaymasterHub(GNOSIS_PM).getOrgConfig(KUBI_ORG);
        require(cfg.registeredAt != 0, "KUBI not registered on Gnosis PaymasterHub");

        bool isAdmin = cfg.adminHatId != 0 && IHats(HATS).isWearerOfHat(caller, cfg.adminHatId);
        bool isOperator = cfg.operatorHatId != 0 && IHats(HATS).isWearerOfHat(caller, cfg.operatorHatId);
        require(isAdmin || isOperator, "Caller must wear KUBI adminHat or operatorHat on Gnosis");

        console.log("KUBI registered on Gnosis: PASS");
        console.log("KUBI adminHatId:    ", cfg.adminHatId);
        console.log("KUBI operatorHatId: ", cfg.operatorHatId);
        console.log("Caller is admin:    ", isAdmin);
        console.log("Caller is operator: ", isOperator);
    }
}

contract FixKubiOrgMetaRulesSim is FixKubiOrgMetaRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  KUBI OrgMeta Rules Fix (DRY RUN)");
        console.log("========================================");
        console.log("Caller:        ", deployer);
        console.log("PaymasterHub:  ", GNOSIS_PM);
        console.log("OrgRegistry:   ", ORG_REGISTRY);

        _preflightChecks(deployer);

        (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints) =
            _buildRuleArgs();

        console.log("\n--- Rule to add ---");
        console.log("  target:", targets[0]);
        console.logBytes4(sels[0]);
        console.log("  allowed:", allowed[0]);

        vm.prank(deployer);
        IPaymasterHub(GNOSIS_PM).setRulesBatch(KUBI_ORG, targets, sels, allowed, hints);

        console.log("\nsetRulesBatch simulated successfully: PASS");
        console.log("To broadcast, run FixKubiOrgMetaRules:run with --broadcast");
    }
}

contract FixKubiOrgMetaRules is FixKubiOrgMetaRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  KUBI OrgMeta Rules Fix (BROADCAST)");
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
