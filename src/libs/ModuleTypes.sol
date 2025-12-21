// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title ModuleTypes
 * @author POA Team
 * @notice Central registry of module type identifiers (pre-computed keccak256 hashes)
 * @dev These constants represent keccak256(moduleName) pre-computed at compile time
 *      to eliminate runtime hashing and minimize bytecode size.
 *
 *      Design rationale:
 *      - PoaManager internally uses bytes32 typeIds (keccak256 of module names)
 *      - OrgRegistry requires bytes32 typeIds for contract registration
 *      - Pre-computing these hashes eliminates redundant runtime computation
 *      - Using constants instead of functions reduces deployment gas
 *
 *      Migration notes:
 *      - Legacy code using string-based lookups remains compatible via PoaManager.getBeacon(string)
 *      - New code should use typeId-based lookups via PoaManager.getBeaconById(bytes32)
 */
library ModuleTypes {
    // Pre-computed keccak256 hashes of module names
    // These values MUST match exactly with the type names registered in PoaManager

    /// @dev keccak256("Executor")
    bytes32 constant EXECUTOR_ID = 0xeb35d5f9843d4076628c4747d195abdd0312e0b8b8f5812a706f3d25ea0b1074;

    /// @dev keccak256("QuickJoin")
    bytes32 constant QUICK_JOIN_ID = 0x4784d0eb49be96744b28df0ac228d16d518300f3918df72816b3b561765905e2;

    /// @dev keccak256("ParticipationToken")
    bytes32 constant PARTICIPATION_TOKEN_ID = 0x61653188976d6d9ecf5e33b147788ec0830eac3e633a227b8852151b9bc260ff;

    /// @dev keccak256("TaskManager")
    bytes32 constant TASK_MANAGER_ID = 0x32f7a2c64ebedb84c7786a459012ac8953c5a63d5dcc8715f2fa3e32bdb3b434;

    /// @dev keccak256("EducationHub")
    bytes32 constant EDUCATION_HUB_ID = 0xa871f070b566fe185ede7c7d071cb2f92e7c75c6a2912b6f37c86a50cdc6bad3;

    /// @dev keccak256("HybridVoting")
    bytes32 constant HYBRID_VOTING_ID = 0xb8dd67d452899bbfb87b5b09ad416a7e087658a191da37d41f9ea7dee2fa659a;

    /// @dev keccak256("EligibilityModule")
    bytes32 constant ELIGIBILITY_MODULE_ID = 0x4227a68d7c497034bee963ad52ac7718fa79a916edc119c0f7e6589c8b2d4ea7;

    /// @dev keccak256("ToggleModule")
    bytes32 constant TOGGLE_MODULE_ID = 0x75dfb681d193a73a66b628a5adc66bb1ca7bb3feb9a5692cd0a1560ccd9b851a;

    /// @dev keccak256("PaymentManager")
    bytes32 constant PAYMENT_MANAGER_ID = 0x27c0a50afefb382eb18d87e6a049659a778b9a2f11c89b8723c63e6fab6fa323;

    /// @dev keccak256("PaymasterHub")
    bytes32 constant PAYMASTER_HUB_ID = 0x846374a1b9aebfa243bcd01b2b2c7d94ce66a1b22f9ed17ed1d6fd61a8c93891;

    /// @dev keccak256("DirectDemocracyVoting")
    bytes32 constant DIRECT_DEMOCRACY_VOTING_ID = 0xf7339bb8aed66291ac713d0a14749e830b09b2288976ec5d45de7e64df0f2aeb;

    /// @dev keccak256("PasskeyAccount")
    bytes32 constant PASSKEY_ACCOUNT_ID = 0xda41a9794e00ddb18f1b3c615f12a80255bfb0a79706263eee63314d8f817c10;

    /// @dev keccak256("PasskeyAccountFactory")
    bytes32 constant PASSKEY_ACCOUNT_FACTORY_ID = 0x82da23c7ff6e2ce257dee836273bf72af382187589631ce71ae1388c80777930;
}
