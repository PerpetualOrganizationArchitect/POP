// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/**
 * @title AgentLib
 * @notice Library for AI agent configuration in POA organizations
 * @dev Defines structs and constants for agent policies, vouching rules, and capabilities
 *
 * Design Decisions:
 * 1. Agent-to-agent vouching: DEFAULT ON - Agents are first-class members. Bad vouching
 *    damages the voucher's reputation, making the system self-correcting.
 *
 * 2. Founder role for agents: DEFAULT OFF - Safe default, but orgs can explicitly enable
 *    for high-reputation agents (500+ from 3+ orgs).
 *
 * 3. Reputation sources: DEFAULT to all POA orgs deployed via OrgDeployer. Orgs can
 *    customize their allowlist/blocklist.
 *
 * 4. Agent-friendly badge: Orgs with allowAgents && !extraVouchingRequired && minReputation == 0
 *    are flagged as agent-friendly in the UI/subgraph.
 */
library AgentLib {
    /*═══════════════════════════════════════════ CONSTANTS ═══════════════════════════════════════════*/

    /// @notice Agent type identifiers (stored as keccak256 for comparison)
    bytes32 public constant AGENT_TYPE_AI = keccak256("ai");
    bytes32 public constant AGENT_TYPE_HUMAN = keccak256("human");
    bytes32 public constant AGENT_TYPE_HYBRID = keccak256("hybrid");

    /// @notice Reputation tag constants for POA-specific feedback
    string public constant TAG_TASK_COMPLETION = "poaTaskCompletion";
    string public constant TAG_TASK_APPROVAL = "poaTaskApproval";
    string public constant TAG_VOUCH = "poaVouch";
    string public constant TAG_GOVERNANCE = "poaGovernance";

    /// @notice Default thresholds
    int128 public constant DEFAULT_HIGH_REP_THRESHOLD = 500;
    uint8 public constant DEFAULT_MIN_ORG_COUNT = 3;
    uint8 public constant DEFAULT_VOUCH_WEIGHT = 100; // 100 = full weight

    /*═══════════════════════════════════════════ STRUCTS ═══════════════════════════════════════════*/

    /**
     * @notice Organization-level agent policy
     * @dev Configures global agent settings for the entire organization
     *
     * @param allowAgents Whether agents can join this organization at all
     * @param requireAgentDeclaration If true, members must declare agent status in ERC-8004 registration
     * @param agentVouchingRequired If true, agents need vouching even if humans don't
     * @param agentVouchQuorum Additional vouches required for agents (0 = same as humans)
     * @param minAgentReputation Minimum cross-org reputation score required for agents
     * @param minAgentFeedbackCount Minimum number of feedback signals required
     * @param trustedOrgCount Number of trusted orgs in the trustedOrgs array
     */
    struct AgentPolicy {
        bool allowAgents;
        bool requireAgentDeclaration;
        bool agentVouchingRequired;
        uint8 agentVouchQuorum;
        int128 minAgentReputation;
        uint64 minAgentFeedbackCount;
        uint8 trustedOrgCount;
    }

    /**
     * @notice Per-hat agent rules
     * @dev Each role (hat) can have its own agent configuration
     *
     * @param allowAgents Whether agents can wear this specific hat
     * @param requireExtraVouching Whether agents need extra vouching beyond org policy
     * @param extraVouchesRequired Number of extra vouches for agents
     * @param minReputation Role-specific minimum reputation (overrides org policy if higher)
     * @param canVouchForAgents Whether wearers of this hat can vouch for agents
     * @param canVouchForHumans Whether wearers of this hat can vouch for humans
     */
    struct HatAgentRules {
        bool allowAgents;
        bool requireExtraVouching;
        uint8 extraVouchesRequired;
        int128 minReputation;
        bool canVouchForAgents;
        bool canVouchForHumans;
    }

    /**
     * @notice Vouching permission matrix
     * @dev Controls who can vouch for whom and with what weight
     *
     * @param humansCanVouchForHumans Default: true
     * @param humansCanVouchForAgents Default: true
     * @param agentsCanVouchForHumans Default: false (configurable) - CONSERVATIVE DEFAULT
     * @param agentsCanVouchForAgents Default: true - AGENTS ARE FIRST-CLASS MEMBERS
     * @param humanVouchWeight Weight of human vouches (100 = full)
     * @param agentVouchWeight Weight of agent vouches (100 = full, 50 = half)
     */
    struct VouchingMatrix {
        bool humansCanVouchForHumans;
        bool humansCanVouchForAgents;
        bool agentsCanVouchForHumans;
        bool agentsCanVouchForAgents;
        uint8 humanVouchWeight;
        uint8 agentVouchWeight;
    }

    /**
     * @notice Agent capabilities within the organization
     * @dev Fine-grained control over what agents can do
     *
     * @param canClaimTasks Whether agents can claim tasks
     * @param canSubmitTasks Whether agents can submit task completions
     * @param canCreateTasks Whether agents can create new tasks (if they have role)
     * @param canApproveTasks Whether agents can approve tasks (if they have APPROVER role)
     * @param canVote Whether agents can vote on governance proposals
     * @param canCreateProposals Whether agents can create governance proposals
     * @param votingWeightPercent Percentage of full voting weight (100 = full, 50 = half)
     * @param canReceivePayouts Whether agents can receive task payouts
     */
    struct AgentCapabilities {
        bool canClaimTasks;
        bool canSubmitTasks;
        bool canCreateTasks;
        bool canApproveTasks;
        bool canVote;
        bool canCreateProposals;
        uint8 votingWeightPercent;
        bool canReceivePayouts;
    }

    /**
     * @notice Complete agent configuration for an organization
     * @dev Aggregates all agent-related settings
     */
    struct AgentConfig {
        AgentPolicy policy;
        VouchingMatrix vouchingMatrix;
        AgentCapabilities capabilities;
    }

    /**
     * @notice Agent registration info
     * @dev Stored when a member registers as an ERC-8004 agent
     *
     * @param agentId ERC-8004 agent ID
     * @param agentType Type hash (ai, human, hybrid)
     * @param registeredAt Block timestamp of registration
     * @param reputationSnapshot Cached reputation at last check
     * @param feedbackCountSnapshot Cached feedback count at last check
     * @param lastReputationUpdate Block number of last reputation update
     */
    struct AgentInfo {
        uint256 agentId;
        bytes32 agentType;
        uint64 registeredAt;
        int128 reputationSnapshot;
        uint64 feedbackCountSnapshot;
        uint64 lastReputationUpdate;
    }

    /*═══════════════════════════════════════════ DEFAULTS ═══════════════════════════════════════════*/

    /**
     * @notice Returns default agent policy (agent-friendly)
     * @dev Used when org doesn't specify agent configuration
     */
    function defaultAgentPolicy() internal pure returns (AgentPolicy memory) {
        return AgentPolicy({
            allowAgents: true,
            requireAgentDeclaration: true,
            agentVouchingRequired: false,
            agentVouchQuorum: 0,
            minAgentReputation: 0,
            minAgentFeedbackCount: 0,
            trustedOrgCount: 0
        });
    }

    /**
     * @notice Returns default vouching matrix
     * @dev Agents can vouch for agents, but not for humans by default
     */
    function defaultVouchingMatrix() internal pure returns (VouchingMatrix memory) {
        return VouchingMatrix({
            humansCanVouchForHumans: true,
            humansCanVouchForAgents: true,
            agentsCanVouchForHumans: false, // Conservative default
            agentsCanVouchForAgents: true, // Agents are first-class members
            humanVouchWeight: 100,
            agentVouchWeight: 100
        });
    }

    /**
     * @notice Returns default agent capabilities (full access)
     * @dev Agents have same capabilities as humans by default
     */
    function defaultAgentCapabilities() internal pure returns (AgentCapabilities memory) {
        return AgentCapabilities({
            canClaimTasks: true,
            canSubmitTasks: true,
            canCreateTasks: true,
            canApproveTasks: true,
            canVote: true,
            canCreateProposals: true,
            votingWeightPercent: 100,
            canReceivePayouts: true
        });
    }

    /**
     * @notice Returns default hat agent rules (allow agents, same rules as humans)
     */
    function defaultHatAgentRules() internal pure returns (HatAgentRules memory) {
        return HatAgentRules({
            allowAgents: true,
            requireExtraVouching: false,
            extraVouchesRequired: 0,
            minReputation: 0,
            canVouchForAgents: true,
            canVouchForHumans: true
        });
    }

    /**
     * @notice Returns restrictive hat rules for sensitive roles (FOUNDER)
     * @dev Agents not allowed by default for founder/admin roles
     */
    function restrictiveHatAgentRules() internal pure returns (HatAgentRules memory) {
        return HatAgentRules({
            allowAgents: false,
            requireExtraVouching: true,
            extraVouchesRequired: 3,
            minReputation: DEFAULT_HIGH_REP_THRESHOLD,
            canVouchForAgents: true,
            canVouchForHumans: true
        });
    }

    /*═══════════════════════════════════════════ HELPERS ═══════════════════════════════════════════*/

    /**
     * @notice Checks if an organization is "agent-friendly"
     * @dev Used for UI badges and discovery
     * @param policy The organization's agent policy
     * @return True if the org is welcoming to agents
     */
    function isAgentFriendly(AgentPolicy memory policy) internal pure returns (bool) {
        return policy.allowAgents && !policy.agentVouchingRequired && policy.minAgentReputation == 0
            && policy.minAgentFeedbackCount == 0;
    }

    /**
     * @notice Calculates effective vouch count with weights
     * @param humanVouches Number of human vouches
     * @param agentVouches Number of agent vouches
     * @param matrix Vouching matrix with weights
     * @return Effective vouch count (scaled by 100 for precision)
     */
    function calculateEffectiveVouches(uint32 humanVouches, uint32 agentVouches, VouchingMatrix memory matrix)
        internal
        pure
        returns (uint32)
    {
        uint256 humanContribution = uint256(humanVouches) * uint256(matrix.humanVouchWeight);
        uint256 agentContribution = uint256(agentVouches) * uint256(matrix.agentVouchWeight);
        return uint32((humanContribution + agentContribution) / 100);
    }

    /**
     * @notice Checks if an agent type hash represents an AI agent
     * @param agentType The keccak256 hash of the agent type string
     * @return True if the agent is an AI (not human or hybrid)
     */
    function isAIAgent(bytes32 agentType) internal pure returns (bool) {
        return agentType == AGENT_TYPE_AI;
    }

    /**
     * @notice Packs agent policy into a single uint256 for gas-efficient storage
     * @param policy The agent policy to pack
     * @return packed The packed representation
     */
    function packAgentPolicy(AgentPolicy memory policy) internal pure returns (uint256 packed) {
        packed = uint256(policy.allowAgents ? 1 : 0);
        packed |= uint256(policy.requireAgentDeclaration ? 1 : 0) << 1;
        packed |= uint256(policy.agentVouchingRequired ? 1 : 0) << 2;
        packed |= uint256(policy.agentVouchQuorum) << 8;
        packed |= uint256(uint128(policy.minAgentReputation)) << 16;
        packed |= uint256(policy.minAgentFeedbackCount) << 144;
        packed |= uint256(policy.trustedOrgCount) << 208;
    }

    /**
     * @notice Unpacks agent policy from uint256
     * @param packed The packed representation
     * @return policy The unpacked agent policy
     */
    function unpackAgentPolicy(uint256 packed) internal pure returns (AgentPolicy memory policy) {
        policy.allowAgents = (packed & 1) == 1;
        policy.requireAgentDeclaration = ((packed >> 1) & 1) == 1;
        policy.agentVouchingRequired = ((packed >> 2) & 1) == 1;
        policy.agentVouchQuorum = uint8((packed >> 8) & 0xFF);
        policy.minAgentReputation = int128(uint128((packed >> 16) & type(uint128).max));
        policy.minAgentFeedbackCount = uint64((packed >> 144) & type(uint64).max);
        policy.trustedOrgCount = uint8((packed >> 208) & 0xFF);
    }
}
