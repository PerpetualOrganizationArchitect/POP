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
 * @title FixTest6EducationRules
 * @notice Adds createModule, updateModule, removeModule paymaster rules for Test6's
 *         EducationHub on Gnosis.
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
 *     script/FixTest6EducationRules.s.sol:FixTest6EducationRulesSim \
 *     --rpc-url gnosis
 *
 * Broadcast:
 *   source .env && FOUNDRY_PROFILE=production forge script \
 *     script/FixTest6EducationRules.s.sol:FixTest6EducationRules \
 *     --rpc-url gnosis --broadcast --slow --private-key $DEPLOYER_PRIVATE_KEY
 */
contract FixTest6EducationRulesBase is Script {
    // Gnosis addresses
    address constant GNOSIS_PM = 0xdEf1038C297493c0b5f82F0CDB49e929B53B4108;
    address constant GNOSIS_SATELLITE = 0x4Ad70029a9247D369a5bEA92f90840B9ee58eD06;
    address constant GNOSIS_POAMANAGER = 0x794fD39e75140ee1545B1B022E5486B7c863789b;

    // Test6 org (on Gnosis)
    bytes32 constant TEST6_ORG = 0x263b2b29f392647f0fb8ddbb26f099e812ab4ba2777e5e07b906277164181f6b;
    address constant TEST6_EDU_HUB = 0x6a29222E29FDc0000AbA55329DfF0a50D9a8e8F9;

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
            targets[i] = TEST6_EDU_HUB;
            allowed[i] = true;
            hints[i] = 0;
        }
        sels[0] = SEL_CREATE_MODULE;
        sels[1] = SEL_UPDATE_MODULE;
        sels[2] = SEL_REMOVE_MODULE;
    }

    function _preflightChecks(address caller) internal view {
        // Verify Test6 is registered
        IPaymasterHub.OrgConfig memory cfg = IPaymasterHub(GNOSIS_PM).getOrgConfig(TEST6_ORG);
        require(cfg.registeredAt != 0, "Test6 not registered on Gnosis PaymasterHub");

        // Verify Satellite ownership chain
        address satOwner = IPoaManagerSatellite(GNOSIS_SATELLITE).owner();
        require(satOwner == caller, "Caller must own the Satellite");

        address satPM = IPoaManagerSatellite(GNOSIS_SATELLITE).poaManager();
        require(satPM == GNOSIS_POAMANAGER, "Satellite's poaManager mismatch");

        console.log("Test6 registered:      PASS");
        console.log("Test6 adminHatId:      ", cfg.adminHatId);
        console.log("Test6 operatorHatId:   ", cfg.operatorHatId, "(expected 0 = not set)");
        console.log("Satellite owner:       ", satOwner);
        console.log("Satellite poaManager:  ", satPM);
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

contract FixTest6EducationRulesSim is FixTest6EducationRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  Test6 EducationHub Rules Fix (DRY RUN)");
        console.log("========================================");
        console.log("Caller:       ", deployer);
        console.log("Satellite:    ", GNOSIS_SATELLITE);
        console.log("PaymasterHub: ", GNOSIS_PM);
        console.log("EducationHub: ", TEST6_EDU_HUB);

        _preflightChecks(deployer);

        (address[] memory targets, bytes4[] memory sels,,) = _buildRuleArgs();
        console.log("\n--- Rules to add ---");
        for (uint256 i; i < sels.length; i++) {
            console.log("  target:", targets[i]);
            console.logBytes4(sels[i]);
        }

        bytes memory innerCalldata = _buildInnerCalldata();

        // Simulate: deployer calls Satellite.adminCall(PaymasterHub, innerCalldata)
        vm.prank(deployer);
        IPoaManagerSatellite(GNOSIS_SATELLITE).adminCall(GNOSIS_PM, innerCalldata);

        console.log("\nSatellite.adminCall -> PoaManager.adminCall -> PM.setRulesBatch: PASS");
        console.log("\nTo broadcast, run FixTest6EducationRules:run with --broadcast");
    }
}

contract FixTest6EducationRules is FixTest6EducationRulesBase {
    function run() public {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", vm.envUint("DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(deployerKey);

        console.log("\n========================================");
        console.log("  Test6 EducationHub Rules Fix (BROADCAST)");
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
