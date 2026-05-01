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

interface IPoaManagerSatellite {
    function adminCall(address target, bytes calldata data) external returns (bytes memory);
    function owner() external view returns (address);
    function poaManager() external view returns (address);
}

/**
 * @title FixTest6OrgMetaRules
 * @notice Adds the `updateOrgMetaAsAdmin(bytes32,bytes,bytes32)` paymaster rule for Test6's
 *         OrgRegistry on Gnosis. Without this rule, passkey/4337 users hit
 *         RuleDenied(OrgRegistry, 0x3d2d2382) when editing org metadata on the Settings page.
 *
 *         Test6 has operatorHatId = 0 (not set) and the deployer does NOT wear its admin hat,
 *         so we cannot call setRulesBatch directly as a hat wearer. Instead we route through:
 *
 *           deployer → Satellite.adminCall → PoaManager.adminCall → PaymasterHub.setRulesBatch
 *
 *         PaymasterHub's onlyOrgOperator modifier bypasses hat checks when
 *         msg.sender == poaManager, so this works.
 *
 * Dry-run:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixTest6OrgMetaRules.s.sol:FixTest6OrgMetaRulesSim \
 *     --rpc-url gnosis
 *
 * Broadcast:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixTest6OrgMetaRules.s.sol:FixTest6OrgMetaRules \
 *     --rpc-url gnosis --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 */
contract FixTest6OrgMetaRulesBase is Script {
    // Gnosis addresses
    address constant GNOSIS_PM = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant GNOSIS_SATELLITE = 0x4Ad70029a9247D369a5bEA92f90840B9ee58eD06;
    address constant GNOSIS_POAMANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;
    address constant ORG_REGISTRY = 0x3744b372abc41589226313F2bB1dB3aCAa22A854; // same on Gnosis + Arbitrum (CREATE2)

    // Test6 org
    bytes32 constant TEST6_ORG = 0x263b2b29f392647f0fb8ddbb26f099e812ab4ba2777e5e07b906277164181f6b;

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
        IPaymasterHub.OrgConfig memory cfg = IPaymasterHub(GNOSIS_PM).getOrgConfig(TEST6_ORG);
        require(cfg.registeredAt != 0, "Test6 not registered on Gnosis PaymasterHub");

        address satOwner = IPoaManagerSatellite(GNOSIS_SATELLITE).owner();
        require(satOwner == caller, "Caller must own the Satellite");

        address satPM = IPoaManagerSatellite(GNOSIS_SATELLITE).poaManager();
        require(satPM == GNOSIS_POAMANAGER, "Satellite's poaManager mismatch");

        console.log("Test6 registered on Gnosis: PASS");
        console.log("Test6 adminHatId:    ", cfg.adminHatId);
        console.log("Test6 operatorHatId: ", cfg.operatorHatId, "(expected 0 = not set)");
        console.log("Satellite owner:     ", satOwner);
        console.log("Satellite poaManager:", satPM);
        console.log("Caller owns Satellite: PASS");
    }

    function _buildInnerCalldata() internal pure returns (bytes memory) {
        (address[] memory targets, bytes4[] memory sels, bool[] memory allowed, uint32[] memory hints) =
            _buildRuleArgs();
        return abi.encodeWithSignature(
            "setRulesBatch(bytes32,address[],bytes4[],bool[],uint32[])", TEST6_ORG, targets, sels, allowed, hints
        );
    }
}

contract FixTest6OrgMetaRulesSim is FixTest6OrgMetaRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  Test6 OrgMeta Rules Fix (DRY RUN)");
        console.log("========================================");
        console.log("Caller:        ", deployer);
        console.log("Satellite:     ", GNOSIS_SATELLITE);
        console.log("PaymasterHub:  ", GNOSIS_PM);
        console.log("OrgRegistry:   ", ORG_REGISTRY);

        _preflightChecks(deployer);

        (address[] memory targets, bytes4[] memory sels,,) = _buildRuleArgs();
        console.log("\n--- Rule to add ---");
        console.log("  target:", targets[0]);
        console.logBytes4(sels[0]);

        bytes memory innerCalldata = _buildInnerCalldata();

        // Simulate: deployer calls Satellite.adminCall(PaymasterHub, innerCalldata)
        vm.prank(deployer);
        IPoaManagerSatellite(GNOSIS_SATELLITE).adminCall(GNOSIS_PM, innerCalldata);

        console.log("\nSatellite.adminCall -> PoaManager.adminCall -> PM.setRulesBatch: PASS");
        console.log("To broadcast, run FixTest6OrgMetaRules:run with --broadcast");
    }
}

contract FixTest6OrgMetaRules is FixTest6OrgMetaRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  Test6 OrgMeta Rules Fix (BROADCAST)");
        console.log("========================================");
        console.log("Caller:", deployer);

        _preflightChecks(deployer);

        bytes memory innerCalldata = _buildInnerCalldata();

        vm.startBroadcast(deployerKey);
        IPoaManagerSatellite(GNOSIS_SATELLITE).adminCall(GNOSIS_PM, innerCalldata);
        vm.stopBroadcast();

        console.log("\nadminCall broadcast submitted");
    }
}
