// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

import {OrgDeployer, ITaskManagerBootstrap} from "../../src/OrgDeployer.sol";
import {RegistryRelay} from "../../src/crosschain/RegistryRelay.sol";
import {SatelliteOnboardingHelper} from "../../src/crosschain/SatelliteOnboardingHelper.sol";
import {PoaManager} from "../../src/PoaManager.sol";
import {IHybridVotingInit} from "../../src/libs/ModuleDeploymentLib.sol";
import {RoleConfigStructs} from "../../src/libs/RoleConfigStructs.sol";
import {ModulesFactory} from "../../src/factories/ModulesFactory.sol";

/**
 * @title DeploySatelliteOrg
 * @notice Deploys an org on the satellite chain using OrgDeployer.deployFullOrg,
 *         then deploys a SatelliteOnboardingHelper and authorizes it on the relay.
 *
 *         Org name claim is dispatched optimistically to the hub during deployFullOrg
 *         (no separate pre-claim step needed).
 *
 * Required env vars:
 *   PRIVATE_KEY
 *
 * Reads:  script/e2e/e2e-state.json
 * Writes: script/e2e/e2e-state.json (adds org section)
 */
contract DeploySatelliteOrg is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        string memory state = vm.readFile("script/e2e/e2e-state.json");
        address orgDeployerAddr = vm.parseJsonAddress(state, ".satellite.orgDeployer");
        address relayAddr = vm.parseJsonAddress(state, ".satellite.registryRelay");
        address pmAddr = vm.parseJsonAddress(state, ".satellite.poaManager");

        console.log("\n=== Deploy Satellite Org ===");
        console.log("Deployer:", deployer);
        console.log("OrgDeployer:", orgDeployerAddr);
        console.log("RegistryRelay:", relayAddr);

        vm.startBroadcast(deployerKey);

        // Build deployment params for a simple test org
        OrgDeployer.DeploymentParams memory params = _buildOrgParams(deployer, relayAddr);

        // Deploy the org
        OrgDeployer.DeploymentResult memory result = OrgDeployer(orgDeployerAddr).deployFullOrg(params);

        console.log("Org deployed!");
        console.log("Executor:", result.executor);
        console.log("QuickJoin:", result.quickJoin);
        console.log("HybridVoting:", result.hybridVoting);

        // Deploy SatelliteOnboardingHelper for this org
        PoaManager pm = PoaManager(pmAddr);
        address helperBeacon = pm.getBeaconById(keccak256("SatelliteOnboardingHelper"));
        bytes memory helperInit = abi.encodeCall(
            SatelliteOnboardingHelper.initialize,
            (deployer, relayAddr, result.quickJoin, address(0)) // no passkey factory for e2e
        );
        SatelliteOnboardingHelper helper = SatelliteOnboardingHelper(address(new BeaconProxy(helperBeacon, helperInit)));
        console.log("SatelliteOnboardingHelper:", address(helper));

        // Authorize the helper on the relay so it can call registerAccountForUser
        RegistryRelay(payable(relayAddr)).setAuthorizedCaller(address(helper), true);
        console.log("Helper authorized on relay");

        vm.stopBroadcast();

        // Write org addresses to state (append to satellite section)
        _appendOrgState(state, result, address(helper));

        console.log("\n=== Satellite Org Deployment Complete ===");
        console.log("NOTE: SatelliteOnboardingHelper is authorized on relay but NOT");
        console.log("      wired as QuickJoin's masterDeployAddress (requires governance).");
        console.log("      The helper can still dispatch username claims via the relay.");
    }

    function _buildOrgParams(address deployer, address registryAddr)
        internal
        pure
        returns (OrgDeployer.DeploymentParams memory params)
    {
        params.orgId = keccak256("e2e-sat-org");
        params.orgName = "E2ETestOrg";
        params.metadataHash = bytes32(0);
        params.registryAddr = registryAddr;
        params.deployerAddress = deployer;
        params.deployerUsername = "";
        params.autoUpgrade = true;
        params.hybridQuorumPct = 50;
        params.ddQuorumPct = 50;

        // Simple 2-role config: MEMBER + CONTRIBUTOR
        params.roles = new RoleConfigStructs.RoleConfig[](2);
        address[] memory emptyAddrs = new address[](0);

        params.roles[0] = RoleConfigStructs.RoleConfig({
            name: "MEMBER",
            image: "",
            metadataCID: bytes32(0),
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: false, additionalWearers: emptyAddrs
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });

        params.roles[1] = RoleConfigStructs.RoleConfig({
            name: "CONTRIBUTOR",
            image: "",
            metadataCID: bytes32(0),
            canVote: true,
            vouching: RoleConfigStructs.RoleVouchingConfig({
                enabled: false, quorum: 0, voucherRoleIndex: 0, combineWithHierarchy: false
            }),
            defaults: RoleConfigStructs.RoleEligibilityDefaults({eligible: true, standing: true}),
            hierarchy: RoleConfigStructs.RoleHierarchyConfig({adminRoleIndex: type(uint256).max}),
            distribution: RoleConfigStructs.RoleDistributionConfig({
                mintToDeployer: true, additionalWearers: emptyAddrs
            }),
            hatConfig: RoleConfigStructs.HatConfig({maxSupply: type(uint32).max, mutableHat: true})
        });

        // Voting classes
        params.hybridClasses = new IHybridVotingInit.ClassConfig[](1);
        uint256[] memory emptyHatIds = new uint256[](0);
        params.hybridClasses[0] = IHybridVotingInit.ClassConfig({
            strategy: IHybridVotingInit.ClassStrategy.DIRECT,
            slicePct: 100,
            quadratic: false,
            minBalance: 0,
            asset: address(0),
            hatIds: emptyHatIds
        });

        // Role assignments: MEMBER (index 0) gets quickJoin
        params.roleAssignments = OrgDeployer.RoleAssignments({
            quickJoinRolesBitmap: 1, // bit 0 = MEMBER role
            tokenMemberRolesBitmap: 3,
            tokenApproverRolesBitmap: 2,
            taskCreatorRolesBitmap: 2,
            educationCreatorRolesBitmap: 2,
            educationMemberRolesBitmap: 3,
            hybridProposalCreatorRolesBitmap: 2,
            ddVotingRolesBitmap: 3,
            ddCreatorRolesBitmap: 2
        });

        params.ddInitialTargets = new address[](0);
        params.metadataAdminRoleIndex = type(uint256).max;
        params.educationHubConfig = ModulesFactory.EducationHubConfig({enabled: false});
        params.passkeyEnabled = false;
        params.paymasterConfig.operatorRoleIndex = type(uint256).max;
    }

    function _appendOrgState(string memory existingState, OrgDeployer.DeploymentResult memory result, address helper)
        internal
    {
        // Re-read all fields and rewrite with org section added
        address ddAddr = vm.parseJsonAddress(existingState, ".deterministicDeployer");
        address homePm = vm.parseJsonAddress(existingState, ".homeChain.poaManager");
        address homeReg = vm.parseJsonAddress(existingState, ".homeChain.implRegistry");
        address homeHub = vm.parseJsonAddress(existingState, ".homeChain.hub");
        address homeHv = vm.parseJsonAddress(existingState, ".homeChain.hybridVotingV1");
        address homeUar = vm.parseJsonAddress(existingState, ".homeChain.uar");
        address nameHub = vm.parseJsonAddress(existingState, ".homeChain.nameRegistryHub");

        address satPm = vm.parseJsonAddress(existingState, ".satellite.poaManager");
        address satReg = vm.parseJsonAddress(existingState, ".satellite.implRegistry");
        address satSat = vm.parseJsonAddress(existingState, ".satellite.satellite");
        address satRelay = vm.parseJsonAddress(existingState, ".satellite.registryRelay");
        address satAdapter = vm.parseJsonAddress(existingState, ".satellite.nameClaimAdapter");
        address satOrgReg = vm.parseJsonAddress(existingState, ".satellite.orgRegistry");
        address satOrgDep = vm.parseJsonAddress(existingState, ".satellite.orgDeployer");
        address satHv = vm.parseJsonAddress(existingState, ".satellite.hybridVotingV1");

        string memory json1 = string.concat(
            "{\n",
            '  "deterministicDeployer": "',
            vm.toString(ddAddr),
            '",\n',
            '  "homeChain": {\n',
            '    "poaManager": "',
            vm.toString(homePm),
            '",\n',
            '    "implRegistry": "',
            vm.toString(homeReg),
            '",\n',
            '    "hub": "',
            vm.toString(homeHub),
            '",\n'
        );

        string memory json2 = string.concat(
            '    "hybridVotingV1": "',
            vm.toString(homeHv),
            '",\n',
            '    "uar": "',
            vm.toString(homeUar),
            '",\n',
            '    "nameRegistryHub": "',
            vm.toString(nameHub),
            '"\n',
            "  },\n"
        );

        string memory json3 = string.concat(
            '  "satellite": {\n',
            '    "poaManager": "',
            vm.toString(satPm),
            '",\n',
            '    "implRegistry": "',
            vm.toString(satReg),
            '",\n',
            '    "satellite": "',
            vm.toString(satSat),
            '",\n',
            '    "registryRelay": "',
            vm.toString(satRelay),
            '",\n'
        );

        string memory json4 = string.concat(
            '    "nameClaimAdapter": "',
            vm.toString(satAdapter),
            '",\n',
            '    "orgRegistry": "',
            vm.toString(satOrgReg),
            '",\n',
            '    "orgDeployer": "',
            vm.toString(satOrgDep),
            '",\n',
            '    "hybridVotingV1": "',
            vm.toString(satHv),
            '"\n',
            "  },\n"
        );

        string memory json5 = string.concat(
            '  "satelliteOrg": {\n',
            '    "executor": "',
            vm.toString(result.executor),
            '",\n',
            '    "quickJoin": "',
            vm.toString(result.quickJoin),
            '",\n',
            '    "hybridVoting": "',
            vm.toString(result.hybridVoting),
            '",\n',
            '    "onboardingHelper": "',
            vm.toString(helper),
            '"\n',
            "  }\n",
            "}\n"
        );

        vm.writeFile("script/e2e/e2e-state.json", string.concat(json1, json2, json3, json4, json5));
    }
}
