// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/AgentRegistry.sol";
import "../src/libs/AgentLib.sol";
import "../lib/hats-protocol/src/Hats.sol";

/**
 * @title AgentRegistryTest
 * @notice Comprehensive tests for the AgentRegistry contract
 * @dev Tests cover registration, eligibility, vouching, and policy management
 */
contract AgentRegistryTest is Test {
    AgentRegistry public registry;
    Hats public hats;

    // Test addresses
    address public admin = address(0x1);
    address public member1 = address(0x2);
    address public member2 = address(0x3);
    address public aiAgent = address(0x4);
    address public nonMember = address(0x5);
    address public quickJoin = address(0x6);

    // Hat IDs
    uint256 public topHatId;
    uint256 public adminHatId;
    uint256 public memberHatId;
    uint256 public approverHatId;
    uint256 public founderHatId;

    // Events to test
    event AgentRegistered(address indexed member, uint256 indexed agentId, bytes32 agentType);
    event AgentPolicyUpdated(AgentLib.AgentPolicy policy);
    event VouchingMatrixUpdated(AgentLib.VouchingMatrix matrix);
    event HatAgentRulesUpdated(uint256 indexed hatId, AgentLib.HatAgentRules rules);
    event TrustedOrgAdded(address indexed org);

    function setUp() public {
        // Deploy Hats Protocol
        hats = new Hats("Test Hats", "ipfs://");

        // Create hat tree
        vm.startPrank(admin);
        topHatId = hats.mintTopHat(admin, "Top Hat", "ipfs://");
        adminHatId = hats.createHat(topHatId, "Admin", 10, address(0), address(0), true, "ipfs://");
        memberHatId = hats.createHat(adminHatId, "Member", 1000, address(0), address(0), true, "ipfs://");
        approverHatId = hats.createHat(adminHatId, "Approver", 50, address(0), address(0), true, "ipfs://");
        founderHatId = hats.createHat(adminHatId, "Founder", 5, address(0), address(0), true, "ipfs://");

        // Mint hats
        hats.mintHat(adminHatId, admin);
        hats.mintHat(memberHatId, member1);
        hats.mintHat(memberHatId, member2);
        hats.mintHat(memberHatId, aiAgent);
        vm.stopPrank();

        // Deploy AgentRegistry
        registry = new AgentRegistry();

        // Initialize (no ERC-8004 registries for unit tests)
        registry.initialize(
            address(0), // No identity registry
            address(0), // No reputation registry
            address(hats),
            quickJoin,
            1, // orgId
            memberHatId,
            adminHatId
        );
    }

    /*═══════════════════════════════════════════ REGISTRATION TESTS ═══════════════════════════════════════════*/

    function test_RegisterSelf_Human() public {
        vm.prank(member1);
        uint256 agentId = registry.registerSelf("human");

        assertTrue(registry.isRegisteredAgent(member1));
        assertFalse(registry.isAIAgent(member1));
        assertEq(registry.getMember(agentId), member1);
    }

    function test_RegisterSelf_AIAgent() public {
        vm.prank(aiAgent);
        uint256 agentId = registry.registerSelf("ai");

        assertTrue(registry.isRegisteredAgent(aiAgent));
        assertTrue(registry.isAIAgent(aiAgent));
    }

    function test_RegisterSelf_Hybrid() public {
        vm.prank(member1);
        registry.registerSelf("hybrid");

        assertTrue(registry.isRegisteredAgent(member1));
        assertFalse(registry.isAIAgent(member1)); // Hybrid is not pure AI
    }

    function test_RegisterSelf_RevertIfNotMember() public {
        vm.prank(nonMember);
        vm.expectRevert(AgentRegistry.NotMember.selector);
        registry.registerSelf("human");
    }

    function test_RegisterSelf_RevertIfAlreadyRegistered() public {
        vm.startPrank(member1);
        registry.registerSelf("human");

        vm.expectRevert(AgentRegistry.AlreadyRegistered.selector);
        registry.registerSelf("ai");
        vm.stopPrank();
    }

    function test_RegisterMember_ByQuickJoin() public {
        vm.prank(quickJoin);
        uint256 agentId = registry.registerMember(member1, "ai");

        assertTrue(registry.isRegisteredAgent(member1));
        assertTrue(registry.isAIAgent(member1));
    }

    function test_RegisterMember_RevertIfNotQuickJoin() public {
        vm.prank(admin);
        vm.expectRevert(AgentRegistry.NotQuickJoin.selector);
        registry.registerMember(member1, "ai");
    }

    function test_RegisterSelf_EmitsEvent() public {
        vm.prank(member1);
        vm.expectEmit(true, true, false, true);
        emit AgentRegistered(member1, uint256(uint160(member1)), keccak256("human"));
        registry.registerSelf("human");
    }

    /*═══════════════════════════════════════════ POLICY TESTS ═══════════════════════════════════════════*/

    function test_DefaultPolicy_IsAgentFriendly() public {
        assertTrue(registry.isAgentFriendly());
    }

    function test_SetAgentPolicy_DisableAgents() public {
        AgentLib.AgentPolicy memory policy = AgentLib.AgentPolicy({
            allowAgents: false,
            requireAgentDeclaration: true,
            agentVouchingRequired: false,
            agentVouchQuorum: 0,
            minAgentReputation: 0,
            minAgentFeedbackCount: 0,
            trustedOrgCount: 0
        });

        vm.prank(admin);
        registry.setAgentPolicy(policy);

        assertFalse(registry.isAgentFriendly());

        // AI agent should not be able to register
        vm.prank(aiAgent);
        vm.expectRevert(AgentRegistry.AgentsNotAllowed.selector);
        registry.registerSelf("ai");

        // Human should still be able to register
        vm.prank(member1);
        registry.registerSelf("human");
        assertTrue(registry.isRegisteredAgent(member1));
    }

    function test_SetAgentPolicy_RequireReputation() public {
        AgentLib.AgentPolicy memory policy = AgentLib.AgentPolicy({
            allowAgents: true,
            requireAgentDeclaration: true,
            agentVouchingRequired: false,
            agentVouchQuorum: 0,
            minAgentReputation: 100,
            minAgentFeedbackCount: 5,
            trustedOrgCount: 0
        });

        vm.prank(admin);
        registry.setAgentPolicy(policy);

        // Agent can register (reputation checked at eligibility, not registration)
        vm.prank(aiAgent);
        registry.registerSelf("ai");
        assertTrue(registry.isRegisteredAgent(aiAgent));
    }

    function test_SetAgentPolicy_RevertIfNotAdmin() public {
        AgentLib.AgentPolicy memory policy = AgentLib.defaultAgentPolicy();

        vm.prank(member1);
        vm.expectRevert(AgentRegistry.NotAdmin.selector);
        registry.setAgentPolicy(policy);
    }

    function test_SetAgentPolicy_EmitsEvent() public {
        AgentLib.AgentPolicy memory policy = AgentLib.AgentPolicy({
            allowAgents: true,
            requireAgentDeclaration: false,
            agentVouchingRequired: true,
            agentVouchQuorum: 2,
            minAgentReputation: 50,
            minAgentFeedbackCount: 3,
            trustedOrgCount: 0
        });

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit AgentPolicyUpdated(policy);
        registry.setAgentPolicy(policy);
    }

    /*═══════════════════════════════════════════ VOUCHING MATRIX TESTS ═══════════════════════════════════════════*/

    function test_DefaultVouchingMatrix() public {
        AgentLib.VouchingMatrix memory matrix = registry.getVouchingMatrix();

        assertTrue(matrix.humansCanVouchForHumans);
        assertTrue(matrix.humansCanVouchForAgents);
        assertFalse(matrix.agentsCanVouchForHumans); // Conservative default
        assertTrue(matrix.agentsCanVouchForAgents); // Agents are first-class
        assertEq(matrix.humanVouchWeight, 100);
        assertEq(matrix.agentVouchWeight, 100);
    }

    function test_SetVouchingMatrix_AgentsCanVouchForHumans() public {
        AgentLib.VouchingMatrix memory matrix = AgentLib.VouchingMatrix({
            humansCanVouchForHumans: true,
            humansCanVouchForAgents: true,
            agentsCanVouchForHumans: true, // Enable this
            agentsCanVouchForAgents: true,
            humanVouchWeight: 100,
            agentVouchWeight: 100
        });

        vm.prank(admin);
        registry.setVouchingMatrix(matrix);

        AgentLib.VouchingMatrix memory updated = registry.getVouchingMatrix();
        assertTrue(updated.agentsCanVouchForHumans);
    }

    function test_SetVouchingMatrix_ReduceAgentWeight() public {
        AgentLib.VouchingMatrix memory matrix = AgentLib.VouchingMatrix({
            humansCanVouchForHumans: true,
            humansCanVouchForAgents: true,
            agentsCanVouchForHumans: false,
            agentsCanVouchForAgents: true,
            humanVouchWeight: 100,
            agentVouchWeight: 50 // Half weight for agent vouches
        });

        vm.prank(admin);
        registry.setVouchingMatrix(matrix);

        AgentLib.VouchingMatrix memory updated = registry.getVouchingMatrix();
        assertEq(updated.agentVouchWeight, 50);
    }

    function test_CheckVouchPermission_HumanToHuman() public {
        vm.prank(member1);
        registry.registerSelf("human");
        vm.prank(member2);
        registry.registerSelf("human");

        (bool canVouch, uint8 weight) = registry.checkVouchPermission(member1, member2, memberHatId);
        assertTrue(canVouch);
        assertEq(weight, 100);
    }

    function test_CheckVouchPermission_HumanToAgent() public {
        vm.prank(member1);
        registry.registerSelf("human");
        vm.prank(aiAgent);
        registry.registerSelf("ai");

        (bool canVouch, uint8 weight) = registry.checkVouchPermission(member1, aiAgent, memberHatId);
        assertTrue(canVouch);
        assertEq(weight, 100);
    }

    function test_CheckVouchPermission_AgentToHuman_DefaultDenied() public {
        vm.prank(aiAgent);
        registry.registerSelf("ai");
        vm.prank(member1);
        registry.registerSelf("human");

        (bool canVouch,) = registry.checkVouchPermission(aiAgent, member1, memberHatId);
        assertFalse(canVouch); // Default: agents can't vouch for humans
    }

    function test_CheckVouchPermission_AgentToAgent() public {
        vm.prank(aiAgent);
        registry.registerSelf("ai");

        // Register another AI agent
        vm.prank(admin);
        hats.mintHat(memberHatId, address(0x7));
        vm.prank(address(0x7));
        registry.registerSelf("ai");

        (bool canVouch, uint8 weight) = registry.checkVouchPermission(aiAgent, address(0x7), memberHatId);
        assertTrue(canVouch); // Agents can vouch for agents
        assertEq(weight, 100);
    }

    /*═══════════════════════════════════════════ HAT AGENT RULES TESTS ═══════════════════════════════════════════*/

    function test_DefaultHatRules_AllowAgents() public {
        AgentLib.HatAgentRules memory rules = registry.getHatAgentRules(memberHatId);
        assertTrue(rules.allowAgents);
        assertFalse(rules.requireExtraVouching);
        assertEq(rules.minReputation, 0);
    }

    function test_SetHatAgentRules_DisableAgentsForFounder() public {
        AgentLib.HatAgentRules memory rules = AgentLib.HatAgentRules({
            allowAgents: false,
            requireExtraVouching: true,
            extraVouchesRequired: 3,
            minReputation: 500,
            canVouchForAgents: true,
            canVouchForHumans: true
        });

        vm.prank(admin);
        registry.setHatAgentRules(founderHatId, rules);

        AgentLib.HatAgentRules memory updated = registry.getHatAgentRules(founderHatId);
        assertFalse(updated.allowAgents);
        assertTrue(updated.requireExtraVouching);
        assertEq(updated.extraVouchesRequired, 3);
        assertEq(updated.minReputation, 500);
    }

    function test_SetHatAgentRules_CustomRulesOverrideDefault() public {
        // Member hat should still have default rules
        AgentLib.HatAgentRules memory memberRules = registry.getHatAgentRules(memberHatId);
        assertTrue(memberRules.allowAgents);

        // Set custom rules for approver
        AgentLib.HatAgentRules memory approverRules = AgentLib.HatAgentRules({
            allowAgents: true,
            requireExtraVouching: true,
            extraVouchesRequired: 2,
            minReputation: 100,
            canVouchForAgents: true,
            canVouchForHumans: true
        });

        vm.prank(admin);
        registry.setHatAgentRules(approverHatId, approverRules);

        // Verify custom rules
        AgentLib.HatAgentRules memory updated = registry.getHatAgentRules(approverHatId);
        assertTrue(updated.requireExtraVouching);
        assertEq(updated.minReputation, 100);

        // Member rules should be unchanged
        memberRules = registry.getHatAgentRules(memberHatId);
        assertFalse(memberRules.requireExtraVouching);
    }

    /*═══════════════════════════════════════════ ELIGIBILITY TESTS ═══════════════════════════════════════════*/

    function test_CheckAgentEligibility_HumanAlwaysEligible() public {
        vm.prank(member1);
        registry.registerSelf("human");

        (bool eligible, uint8 reason) = registry.checkAgentEligibility(member1, memberHatId);
        assertTrue(eligible);
        assertEq(reason, 0);
    }

    function test_CheckAgentEligibility_UnregisteredAlwaysEligible() public {
        // Non-registered members have no agent restrictions
        (bool eligible, uint8 reason) = registry.checkAgentEligibility(member1, memberHatId);
        assertTrue(eligible);
        assertEq(reason, 0);
    }

    function test_CheckAgentEligibility_AIAgent_DefaultEligible() public {
        vm.prank(aiAgent);
        registry.registerSelf("ai");

        (bool eligible, uint8 reason) = registry.checkAgentEligibility(aiAgent, memberHatId);
        assertTrue(eligible);
        assertEq(reason, 0);
    }

    function test_CheckAgentEligibility_AIAgent_FailsWhenDisabled() public {
        // Disable agents
        AgentLib.AgentPolicy memory policy = AgentLib.AgentPolicy({
            allowAgents: false,
            requireAgentDeclaration: true,
            agentVouchingRequired: false,
            agentVouchQuorum: 0,
            minAgentReputation: 0,
            minAgentFeedbackCount: 0,
            trustedOrgCount: 0
        });

        vm.prank(admin);
        registry.setAgentPolicy(policy);

        // Register AI (before policy was strict)
        // Note: In real usage, registration would also fail
        // For test, we register first then check eligibility

        // Check eligibility - should fail
        // Since we can't register, test the eligibility check logic
        // by checking a pre-registered agent

        // First enable, register, then disable
        policy.allowAgents = true;
        vm.prank(admin);
        registry.setAgentPolicy(policy);

        vm.prank(aiAgent);
        registry.registerSelf("ai");

        policy.allowAgents = false;
        vm.prank(admin);
        registry.setAgentPolicy(policy);

        (bool eligible, uint8 reason) = registry.checkAgentEligibility(aiAgent, memberHatId);
        assertFalse(eligible);
        assertEq(reason, 1); // Agents not allowed
    }

    function test_CheckAgentEligibility_AIAgent_FailsForRestrictedHat() public {
        vm.prank(aiAgent);
        registry.registerSelf("ai");

        // Disable agents for founder hat
        AgentLib.HatAgentRules memory rules = AgentLib.HatAgentRules({
            allowAgents: false,
            requireExtraVouching: false,
            extraVouchesRequired: 0,
            minReputation: 0,
            canVouchForAgents: true,
            canVouchForHumans: true
        });

        vm.prank(admin);
        registry.setHatAgentRules(founderHatId, rules);

        (bool eligible, uint8 reason) = registry.checkAgentEligibility(aiAgent, founderHatId);
        assertFalse(eligible);
        assertEq(reason, 2); // Agents not allowed for this hat
    }

    /*═══════════════════════════════════════════ TRUSTED ORGS TESTS ═══════════════════════════════════════════*/

    function test_AddTrustedOrg() public {
        address trustedOrg = address(0x100);

        vm.prank(admin);
        registry.addTrustedOrg(trustedOrg);

        address[] memory orgs = registry.getTrustedOrgs();
        assertEq(orgs.length, 1);
        assertEq(orgs[0], trustedOrg);
    }

    function test_AddTrustedOrg_EmitsEvent() public {
        address trustedOrg = address(0x100);

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit TrustedOrgAdded(trustedOrg);
        registry.addTrustedOrg(trustedOrg);
    }

    function test_AddTrustedOrg_RevertIfLimitExceeded() public {
        vm.startPrank(admin);

        // Add max orgs
        for (uint256 i = 0; i < 20; i++) {
            registry.addTrustedOrg(address(uint160(0x100 + i)));
        }

        // 21st should fail
        vm.expectRevert(AgentRegistry.TrustedOrgLimitExceeded.selector);
        registry.addTrustedOrg(address(0x200));
        vm.stopPrank();
    }

    function test_RemoveTrustedOrg() public {
        address trustedOrg1 = address(0x100);
        address trustedOrg2 = address(0x101);

        vm.startPrank(admin);
        registry.addTrustedOrg(trustedOrg1);
        registry.addTrustedOrg(trustedOrg2);

        registry.removeTrustedOrg(trustedOrg1);
        vm.stopPrank();

        address[] memory orgs = registry.getTrustedOrgs();
        assertEq(orgs.length, 1);
        assertEq(orgs[0], trustedOrg2);
    }

    /*═══════════════════════════════════════════ CAPABILITIES TESTS ═══════════════════════════════════════════*/

    function test_DefaultCapabilities_FullAccess() public {
        AgentLib.AgentCapabilities memory caps = registry.getCapabilities();

        assertTrue(caps.canClaimTasks);
        assertTrue(caps.canSubmitTasks);
        assertTrue(caps.canCreateTasks);
        assertTrue(caps.canApproveTasks);
        assertTrue(caps.canVote);
        assertTrue(caps.canCreateProposals);
        assertEq(caps.votingWeightPercent, 100);
        assertTrue(caps.canReceivePayouts);
    }

    function test_SetCapabilities_WorkOnlyMode() public {
        AgentLib.AgentCapabilities memory caps = AgentLib.AgentCapabilities({
            canClaimTasks: true,
            canSubmitTasks: true,
            canCreateTasks: false,
            canApproveTasks: false,
            canVote: false,
            canCreateProposals: false,
            votingWeightPercent: 0,
            canReceivePayouts: true
        });

        vm.prank(admin);
        registry.setCapabilities(caps);

        AgentLib.AgentCapabilities memory updated = registry.getCapabilities();
        assertTrue(updated.canClaimTasks);
        assertFalse(updated.canVote);
        assertEq(updated.votingWeightPercent, 0);
    }

    /*═══════════════════════════════════════════ AGENT INFO TESTS ═══════════════════════════════════════════*/

    function test_GetAgentInfo() public {
        vm.prank(member1);
        registry.registerSelf("ai");

        AgentLib.AgentInfo memory info = registry.getAgentInfo(member1);

        assertEq(info.agentId, uint256(uint160(member1)));
        assertEq(info.agentType, keccak256("ai"));
        assertGt(info.registeredAt, 0);
    }

    function test_GetAgentInfo_RevertIfNotRegistered() public {
        vm.expectRevert(AgentRegistry.NotRegistered.selector);
        registry.getAgentInfo(member1);
    }

    function test_GetMember_RevertIfInvalidAgentId() public {
        vm.expectRevert(AgentRegistry.InvalidAgentId.selector);
        registry.getMember(999);
    }

    /*═══════════════════════════════════════════ AGENTLIB TESTS ═══════════════════════════════════════════*/

    function test_AgentLib_PackUnpackPolicy() public {
        AgentLib.AgentPolicy memory original = AgentLib.AgentPolicy({
            allowAgents: true,
            requireAgentDeclaration: false,
            agentVouchingRequired: true,
            agentVouchQuorum: 5,
            minAgentReputation: 100,
            minAgentFeedbackCount: 10,
            trustedOrgCount: 3
        });

        uint256 packed = AgentLib.packAgentPolicy(original);
        AgentLib.AgentPolicy memory unpacked = AgentLib.unpackAgentPolicy(packed);

        assertEq(unpacked.allowAgents, original.allowAgents);
        assertEq(unpacked.requireAgentDeclaration, original.requireAgentDeclaration);
        assertEq(unpacked.agentVouchingRequired, original.agentVouchingRequired);
        assertEq(unpacked.agentVouchQuorum, original.agentVouchQuorum);
        assertEq(unpacked.minAgentReputation, original.minAgentReputation);
        assertEq(unpacked.minAgentFeedbackCount, original.minAgentFeedbackCount);
        assertEq(unpacked.trustedOrgCount, original.trustedOrgCount);
    }

    function test_AgentLib_IsAgentFriendly() public {
        AgentLib.AgentPolicy memory friendly = AgentLib.defaultAgentPolicy();
        assertTrue(AgentLib.isAgentFriendly(friendly));

        AgentLib.AgentPolicy memory unfriendly = AgentLib.AgentPolicy({
            allowAgents: true,
            requireAgentDeclaration: true,
            agentVouchingRequired: true, // This makes it not friendly
            agentVouchQuorum: 2,
            minAgentReputation: 0,
            minAgentFeedbackCount: 0,
            trustedOrgCount: 0
        });
        assertFalse(AgentLib.isAgentFriendly(unfriendly));
    }

    function test_AgentLib_CalculateEffectiveVouches() public {
        AgentLib.VouchingMatrix memory matrix = AgentLib.VouchingMatrix({
            humansCanVouchForHumans: true,
            humansCanVouchForAgents: true,
            agentsCanVouchForHumans: true,
            agentsCanVouchForAgents: true,
            humanVouchWeight: 100,
            agentVouchWeight: 50 // Half weight
        });

        // 2 human vouches (100% each) + 2 agent vouches (50% each)
        // = 200 + 100 = 300 / 100 = 3 effective vouches
        uint32 effective = AgentLib.calculateEffectiveVouches(2, 2, matrix);
        assertEq(effective, 3);
    }

    function test_AgentLib_IsAIAgent() public {
        assertTrue(AgentLib.isAIAgent(keccak256("ai")));
        assertFalse(AgentLib.isAIAgent(keccak256("human")));
        assertFalse(AgentLib.isAIAgent(keccak256("hybrid")));
    }
}
