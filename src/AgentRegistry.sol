// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "./interfaces/erc8004/IERC8004Identity.sol";
import "./interfaces/erc8004/IERC8004Reputation.sol";
import "./libs/AgentLib.sol";
import "../lib/hats-protocol/src/Interfaces/IHats.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title AgentRegistry
 * @notice Links POA organization members to ERC-8004 agent identities
 * @dev Enables agent discovery, reputation tracking, and policy enforcement
 *
 * Key Features:
 * - Bidirectional mapping between POA addresses and ERC-8004 agent IDs
 * - Agent type detection (AI, human, hybrid)
 * - Cross-org reputation aggregation from trusted sources
 * - Integration with EligibilityModule for policy enforcement
 *
 * Security Model:
 * - Only members can self-register as agents
 * - QuickJoin can auto-register new members
 * - Admins can update policy and trusted orgs
 * - Agent status is immutable once set (for reputation continuity)
 *
 * @custom:security-contact security@poa.earth
 */
contract AgentRegistry is Initializable, UUPSUpgradeable {
    using AgentLib for AgentLib.AgentPolicy;
    using AgentLib for AgentLib.VouchingMatrix;

    /*═══════════════════════════════════════════ ERRORS ═══════════════════════════════════════════*/

    error NotAdmin();
    error NotMember();
    error NotQuickJoin();
    error AlreadyRegistered();
    error NotRegistered();
    error InvalidAgentId();
    error IdentityRegistryNotSet();
    error ReputationRegistryNotSet();
    error AgentsNotAllowed();
    error InsufficientReputation();
    error InsufficientFeedback();
    error ZeroAddress();
    error ArrayLengthMismatch();
    error TrustedOrgLimitExceeded();

    /*═══════════════════════════════════════════ CONSTANTS ═══════════════════════════════════════════*/

    uint8 public constant MAX_TRUSTED_ORGS = 20;
    string public constant METADATA_KEY_AGENT_TYPE = "agentType";

    /*═════════════════════════════════════ ERC-7201 STORAGE ═════════════════════════════════════*/

    /// @custom:storage-location erc7201:poa.agentregistry.storage
    struct Layout {
        // External contracts
        IERC8004Identity identityRegistry;
        IERC8004Reputation reputationRegistry;
        IHats hats;
        address quickJoin;
        // Organization config
        uint256 orgId;
        uint256 memberHatId;
        uint256 adminHatId;
        // Agent policy (packed for gas efficiency)
        uint256 packedAgentPolicy;
        // Vouching matrix
        AgentLib.VouchingMatrix vouchingMatrix;
        // Agent capabilities
        AgentLib.AgentCapabilities capabilities;
        // Per-hat agent rules
        mapping(uint256 => AgentLib.HatAgentRules) hatAgentRules;
        mapping(uint256 => bool) hasCustomHatRules;
        // Member-to-agent mappings
        mapping(address => AgentLib.AgentInfo) agentInfo;
        mapping(uint256 => address) agentIdToMember;
        // Trusted org list for reputation
        address[] trustedOrgs;
        // Cache for reputation queries
        mapping(address => uint256) lastReputationBlock;
    }

    bytes32 private constant STORAGE_SLOT =
        keccak256(abi.encode(uint256(keccak256("poa.agentregistry.storage")) - 1)) & ~bytes32(uint256(0xff));

    function _layout() private pure returns (Layout storage s) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            s.slot := slot
        }
    }

    /*═══════════════════════════════════════════ EVENTS ═══════════════════════════════════════════*/

    event AgentRegistered(address indexed member, uint256 indexed agentId, bytes32 agentType);
    event AgentPolicyUpdated(AgentLib.AgentPolicy policy);
    event VouchingMatrixUpdated(AgentLib.VouchingMatrix matrix);
    event CapabilitiesUpdated(AgentLib.AgentCapabilities capabilities);
    event HatAgentRulesUpdated(uint256 indexed hatId, AgentLib.HatAgentRules rules);
    event TrustedOrgAdded(address indexed org);
    event TrustedOrgRemoved(address indexed org);
    event ReputationCacheUpdated(address indexed member, int128 reputation, uint64 feedbackCount);

    /*═══════════════════════════════════════════ MODIFIERS ═══════════════════════════════════════════*/

    modifier onlyAdmin() {
        Layout storage s = _layout();
        if (!s.hats.isWearerOfHat(msg.sender, s.adminHatId)) revert NotAdmin();
        _;
    }

    modifier onlyMemberOrQuickJoin() {
        Layout storage s = _layout();
        if (msg.sender != s.quickJoin && !s.hats.isWearerOfHat(msg.sender, s.memberHatId)) {
            revert NotMember();
        }
        _;
    }

    /*═══════════════════════════════════════════ INITIALIZATION ═══════════════════════════════════════════*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the agent registry
     * @param identityRegistry_ ERC-8004 Identity Registry address
     * @param reputationRegistry_ ERC-8004 Reputation Registry address
     * @param hats_ Hats Protocol address
     * @param quickJoin_ QuickJoin contract address
     * @param orgId_ POA organization ID
     * @param memberHatId_ Hat ID for members
     * @param adminHatId_ Hat ID for admins
     */
    function initialize(
        address identityRegistry_,
        address reputationRegistry_,
        address hats_,
        address quickJoin_,
        uint256 orgId_,
        uint256 memberHatId_,
        uint256 adminHatId_
    ) external initializer {
        __UUPSUpgradeable_init();

        if (hats_ == address(0)) revert ZeroAddress();

        Layout storage s = _layout();
        s.identityRegistry = IERC8004Identity(identityRegistry_);
        s.reputationRegistry = IERC8004Reputation(reputationRegistry_);
        s.hats = IHats(hats_);
        s.quickJoin = quickJoin_;
        s.orgId = orgId_;
        s.memberHatId = memberHatId_;
        s.adminHatId = adminHatId_;

        // Set defaults
        s.packedAgentPolicy = AgentLib.packAgentPolicy(AgentLib.defaultAgentPolicy());
        s.vouchingMatrix = AgentLib.defaultVouchingMatrix();
        s.capabilities = AgentLib.defaultAgentCapabilities();
    }

    /*═══════════════════════════════════════════ REGISTRATION ═══════════════════════════════════════════*/

    /**
     * @notice Register the caller as an ERC-8004 agent
     * @param agentType Type of agent ("ai", "human", or "hybrid")
     * @return agentId The assigned ERC-8004 agent ID
     */
    function registerSelf(string calldata agentType) external returns (uint256 agentId) {
        Layout storage s = _layout();
        if (!s.hats.isWearerOfHat(msg.sender, s.memberHatId)) revert NotMember();
        return _registerAgent(msg.sender, agentType);
    }

    /**
     * @notice Register a new member as an ERC-8004 agent (callable by QuickJoin)
     * @param member Address of the member to register
     * @param agentType Type of agent
     * @return agentId The assigned ERC-8004 agent ID
     */
    function registerMember(address member, string calldata agentType) external returns (uint256 agentId) {
        Layout storage s = _layout();
        if (msg.sender != s.quickJoin) revert NotQuickJoin();
        return _registerAgent(member, agentType);
    }

    /**
     * @notice Internal registration logic
     */
    function _registerAgent(address member, string calldata agentType) internal returns (uint256 agentId) {
        Layout storage s = _layout();

        // Check if already registered
        if (s.agentInfo[member].agentId != 0) revert AlreadyRegistered();

        // Check agent policy
        AgentLib.AgentPolicy memory policy = AgentLib.unpackAgentPolicy(s.packedAgentPolicy);

        bytes32 typeHash = keccak256(bytes(agentType));
        bool isAI = AgentLib.isAIAgent(typeHash);

        // If AI agent, check if agents are allowed
        if (isAI && !policy.allowAgents) revert AgentsNotAllowed();

        // Register with ERC-8004 if registry is set
        if (address(s.identityRegistry) != address(0)) {
            // Create minimal registration URI
            agentId = s.identityRegistry.register("");

            // Set agent type metadata
            s.identityRegistry.setMetadata(agentId, METADATA_KEY_AGENT_TYPE, bytes(agentType));
        } else {
            // Use address as pseudo-ID if no registry
            agentId = uint256(uint160(member));
        }

        // Store agent info
        s.agentInfo[member] = AgentLib.AgentInfo({
            agentId: agentId,
            agentType: typeHash,
            registeredAt: uint64(block.timestamp),
            reputationSnapshot: 0,
            feedbackCountSnapshot: 0,
            lastReputationUpdate: 0
        });

        s.agentIdToMember[agentId] = member;

        emit AgentRegistered(member, agentId, typeHash);
    }

    /*═══════════════════════════════════════════ AGENT QUERIES ═══════════════════════════════════════════*/

    /**
     * @notice Check if an address is a registered agent
     * @param member Address to check
     * @return True if registered as an agent
     */
    function isRegisteredAgent(address member) external view returns (bool) {
        return _layout().agentInfo[member].agentId != 0;
    }

    /**
     * @notice Check if an address is an AI agent
     * @param member Address to check
     * @return True if registered as AI type
     */
    function isAIAgent(address member) external view returns (bool) {
        Layout storage s = _layout();
        AgentLib.AgentInfo storage info = s.agentInfo[member];
        return info.agentId != 0 && AgentLib.isAIAgent(info.agentType);
    }

    /**
     * @notice Get agent info for a member
     * @param member Address to query
     * @return info The agent's info struct
     */
    function getAgentInfo(address member) external view returns (AgentLib.AgentInfo memory info) {
        info = _layout().agentInfo[member];
        if (info.agentId == 0) revert NotRegistered();
    }

    /**
     * @notice Get member address for an agent ID
     * @param agentId The ERC-8004 agent ID
     * @return member The POA member address
     */
    function getMember(uint256 agentId) external view returns (address member) {
        member = _layout().agentIdToMember[agentId];
        if (member == address(0)) revert InvalidAgentId();
    }

    /*═══════════════════════════════════════════ REPUTATION ═══════════════════════════════════════════*/

    /**
     * @notice Get aggregated reputation for a member from trusted sources
     * @param member Address to query
     * @return reputation Aggregated reputation score
     * @return feedbackCount Number of feedback signals
     */
    function getReputation(address member) external view returns (int128 reputation, uint64 feedbackCount) {
        Layout storage s = _layout();
        AgentLib.AgentInfo storage info = s.agentInfo[member];

        if (info.agentId == 0) return (0, 0);
        if (address(s.reputationRegistry) == address(0)) return (0, 0);

        // Get trusted reviewer addresses (approvers from trusted orgs)
        address[] memory trustedReviewers = _getTrustedReviewers();

        // Query reputation registry
        (uint64 count, int128 value,) =
            s.reputationRegistry.getSummary(info.agentId, trustedReviewers, AgentLib.TAG_TASK_COMPLETION, "");

        return (value, count);
    }

    /**
     * @notice Update cached reputation for a member
     * @param member Address to update
     */
    function updateReputationCache(address member) external {
        Layout storage s = _layout();
        AgentLib.AgentInfo storage info = s.agentInfo[member];

        if (info.agentId == 0) revert NotRegistered();
        if (address(s.reputationRegistry) == address(0)) return;

        address[] memory trustedReviewers = _getTrustedReviewers();
        (uint64 count, int128 value,) =
            s.reputationRegistry.getSummary(info.agentId, trustedReviewers, AgentLib.TAG_TASK_COMPLETION, "");

        info.reputationSnapshot = value;
        info.feedbackCountSnapshot = count;
        info.lastReputationUpdate = uint64(block.number);

        emit ReputationCacheUpdated(member, value, count);
    }

    /**
     * @notice Internal function to get trusted reviewer addresses
     */
    function _getTrustedReviewers() internal view returns (address[] memory) {
        // In production, this would query approver addresses from trusted orgs
        // For now, return empty array (accepts all reviewers)
        return new address[](0);
    }

    /*═══════════════════════════════════════════ ELIGIBILITY CHECKS ═══════════════════════════════════════════*/

    /**
     * @notice Check if a member meets agent eligibility requirements for a hat
     * @param member Address to check
     * @param hatId Hat being checked for
     * @return eligible Whether the member meets requirements
     * @return reason Reason code if not eligible (0 = eligible)
     */
    function checkAgentEligibility(address member, uint256 hatId) external view returns (bool eligible, uint8 reason) {
        Layout storage s = _layout();
        AgentLib.AgentInfo storage info = s.agentInfo[member];

        // Not an agent = eligible (no agent restrictions apply)
        if (info.agentId == 0) return (true, 0);

        // Not an AI = eligible (only AI agents have restrictions)
        if (!AgentLib.isAIAgent(info.agentType)) return (true, 0);

        // Get policies
        AgentLib.AgentPolicy memory policy = AgentLib.unpackAgentPolicy(s.packedAgentPolicy);
        AgentLib.HatAgentRules memory hatRules =
            s.hasCustomHatRules[hatId] ? s.hatAgentRules[hatId] : AgentLib.defaultHatAgentRules();

        // Check org-level agent allowance
        if (!policy.allowAgents) return (false, 1); // Agents not allowed

        // Check hat-level agent allowance
        if (!hatRules.allowAgents) return (false, 2); // Agents not allowed for this hat

        // Check reputation requirements
        int128 requiredRep =
            policy.minAgentReputation > hatRules.minReputation ? policy.minAgentReputation : hatRules.minReputation;

        if (requiredRep > 0 && info.reputationSnapshot < requiredRep) {
            return (false, 3); // Insufficient reputation
        }

        // Check feedback count requirements
        if (policy.minAgentFeedbackCount > 0 && info.feedbackCountSnapshot < policy.minAgentFeedbackCount) {
            return (false, 4); // Insufficient feedback count
        }

        return (true, 0);
    }

    /**
     * @notice Check if a voucher can vouch for a vouchee
     * @param voucher Address doing the vouching
     * @param vouchee Address being vouched for
     * @param hatId Hat being vouched for
     * @return canVouch Whether vouching is allowed
     * @return weight Weight of the vouch (0-100)
     */
    function checkVouchPermission(address voucher, address vouchee, uint256 hatId)
        external
        view
        returns (bool canVouch, uint8 weight)
    {
        Layout storage s = _layout();
        AgentLib.VouchingMatrix storage matrix = s.vouchingMatrix;

        bool voucherIsAI = _isAIAgent(voucher);
        bool voucheeIsAI = _isAIAgent(vouchee);

        // Get hat rules for voucher's permissions
        AgentLib.HatAgentRules memory voucherHatRules;
        // Would need to check voucher's hats - simplified for now

        // Check matrix permissions
        if (!voucherIsAI && !voucheeIsAI) {
            // Human vouching for human
            canVouch = matrix.humansCanVouchForHumans;
            weight = matrix.humanVouchWeight;
        } else if (!voucherIsAI && voucheeIsAI) {
            // Human vouching for agent
            canVouch = matrix.humansCanVouchForAgents;
            weight = matrix.humanVouchWeight;
        } else if (voucherIsAI && !voucheeIsAI) {
            // Agent vouching for human
            canVouch = matrix.agentsCanVouchForHumans;
            weight = matrix.agentVouchWeight;
        } else {
            // Agent vouching for agent
            canVouch = matrix.agentsCanVouchForAgents;
            weight = matrix.agentVouchWeight;
        }

        return (canVouch, weight);
    }

    function _isAIAgent(address member) internal view returns (bool) {
        Layout storage s = _layout();
        AgentLib.AgentInfo storage info = s.agentInfo[member];
        return info.agentId != 0 && AgentLib.isAIAgent(info.agentType);
    }

    /*═══════════════════════════════════════════ POLICY MANAGEMENT ═══════════════════════════════════════════*/

    /**
     * @notice Update the organization's agent policy
     * @param policy New agent policy
     */
    function setAgentPolicy(AgentLib.AgentPolicy calldata policy) external onlyAdmin {
        _layout().packedAgentPolicy = AgentLib.packAgentPolicy(policy);
        emit AgentPolicyUpdated(policy);
    }

    /**
     * @notice Update the vouching matrix
     * @param matrix New vouching matrix
     */
    function setVouchingMatrix(AgentLib.VouchingMatrix calldata matrix) external onlyAdmin {
        _layout().vouchingMatrix = matrix;
        emit VouchingMatrixUpdated(matrix);
    }

    /**
     * @notice Update agent capabilities
     * @param caps New capabilities
     */
    function setCapabilities(AgentLib.AgentCapabilities calldata caps) external onlyAdmin {
        _layout().capabilities = caps;
        emit CapabilitiesUpdated(caps);
    }

    /**
     * @notice Set custom agent rules for a specific hat
     * @param hatId Hat to configure
     * @param rules Agent rules for this hat
     */
    function setHatAgentRules(uint256 hatId, AgentLib.HatAgentRules calldata rules) external onlyAdmin {
        Layout storage s = _layout();
        s.hatAgentRules[hatId] = rules;
        s.hasCustomHatRules[hatId] = true;
        emit HatAgentRulesUpdated(hatId, rules);
    }

    /**
     * @notice Add a trusted organization for reputation
     * @param org Address of the org's AgentRegistry
     */
    function addTrustedOrg(address org) external onlyAdmin {
        Layout storage s = _layout();
        if (s.trustedOrgs.length >= MAX_TRUSTED_ORGS) revert TrustedOrgLimitExceeded();
        s.trustedOrgs.push(org);
        emit TrustedOrgAdded(org);
    }

    /**
     * @notice Remove a trusted organization
     * @param org Address to remove
     */
    function removeTrustedOrg(address org) external onlyAdmin {
        Layout storage s = _layout();
        uint256 len = s.trustedOrgs.length;
        for (uint256 i = 0; i < len; i++) {
            if (s.trustedOrgs[i] == org) {
                s.trustedOrgs[i] = s.trustedOrgs[len - 1];
                s.trustedOrgs.pop();
                emit TrustedOrgRemoved(org);
                return;
            }
        }
    }

    /*═══════════════════════════════════════════ VIEW FUNCTIONS ═══════════════════════════════════════════*/

    function getAgentPolicy() external view returns (AgentLib.AgentPolicy memory) {
        return AgentLib.unpackAgentPolicy(_layout().packedAgentPolicy);
    }

    function getVouchingMatrix() external view returns (AgentLib.VouchingMatrix memory) {
        return _layout().vouchingMatrix;
    }

    function getCapabilities() external view returns (AgentLib.AgentCapabilities memory) {
        return _layout().capabilities;
    }

    function getHatAgentRules(uint256 hatId) external view returns (AgentLib.HatAgentRules memory) {
        Layout storage s = _layout();
        return s.hasCustomHatRules[hatId] ? s.hatAgentRules[hatId] : AgentLib.defaultHatAgentRules();
    }

    function getTrustedOrgs() external view returns (address[] memory) {
        return _layout().trustedOrgs;
    }

    function isAgentFriendly() external view returns (bool) {
        return AgentLib.unpackAgentPolicy(_layout().packedAgentPolicy).isAgentFriendly();
    }

    /*═══════════════════════════════════════════ UUPS ═══════════════════════════════════════════*/

    function _authorizeUpgrade(address) internal override onlyAdmin {}
}
