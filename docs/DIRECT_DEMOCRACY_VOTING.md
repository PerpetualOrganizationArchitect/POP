# Direct Democracy Voting Contract

**Version:** 1.0
**License:** MIT

---

## The Vision: One Person, One Voice

In traditional corporate structures, power follows capital. Shareholders with more money get more votes. Workers—the people who actually build and sustain an organization—are reduced to cogs in someone else's machine.

**Poa reimagines this.**

The `DirectDemocracyVoting` contract encodes this principle into immutable smart contract logic:

> **Every eligible member gets exactly one vote, weighted equally.**

Founding member or newest hire—your voice matters just as much as anyone else's. This is the essence of worker and community ownership. Best suited for smaller groups or high-trust organizations; you can always migrate to HybridVoting later if needed.

---

## What is DirectDemocracyVoting?

`DirectDemocracyVoting` is an on-chain governance contract that enables cooperatives, DAOs, and worker-owned organizations to make collective decisions through transparent, tamper-proof voting.

### Key Features

| Feature | Description |
|---------|-------------|
| **Equal Voting Weight** | Each eligible voter has exactly 100 voting points to distribute |
| **Multi-Option Proposals** | Support for up to 50 options per proposal (not just yes/no) |
| **Weighted Distribution** | Voters can split their vote across multiple options |
| **Role-Based Permissions** | Hats Protocol integration for fine-grained access control |
| **On-Chain Execution** | Winning proposals can automatically execute smart contract calls |
| **Poll-Specific Voting** | Restrict certain votes to specific roles (e.g., department decisions) |
| **Upgradeable** | UUPS proxy pattern for safe evolution |

### What Makes It Different

Unlike token-weighted voting (where whales dominate) or delegation systems (where power concentrates), DirectDemocracyVoting ensures:

- **No plutocracy:** Wealth cannot buy influence
- **No apathy capture:** You can't delegate away your voice
- **Full transparency:** All votes are on-chain and auditable
- **True equality:** 1 person = 1 vote, always

---

## Core Principles

### 1. Participation is a Right, Not a Privilege

Anyone wearing a valid voting hat can participate. No minimum stake requirement, no time-weighted reputation—just membership.

```
If you're a member → You can vote
If you vote → Your vote counts equally
```

### 2. Decisions Belong to Those Affected

Poll-specific hat restrictions allow organizations to limit certain decisions to the people most affected:

- **Kitchen renovation?** Let the kitchen workers decide.
- **Engineering tooling?** Let the engineers decide.
- **Organization-wide policy?** Everyone votes.

### 3. Majority Rules, With Nuance

The contract requires a **strict majority** for winner determination. The winning option must:

1. Exceed the quorum threshold (configurable, e.g., 50%)
2. Have more votes than any other option

This prevents plurality wins where a minority option squeaks through.

### 4. Transparency

Every proposal, vote, and outcome is permanently recorded on-chain. No backroom deals. No revisionist history.

---

## How It Works

### Proposal Lifecycle

```
┌─────────────────────────────────────────────────────────────────────┐
│                         PROPOSAL LIFECYCLE                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   1. CREATION                                                       │
│   ┌──────────┐                                                      │
│   │ Creator  │ ──> createProposal(title, description, options, ...)│
│   │ (hat)    │                                                      │
│   └──────────┘                                                      │
│        │                                                            │
│        ▼                                                            │
│   2. VOTING PERIOD                                                  │
│   ┌──────────────────────────────────────────────────────────┐     │
│   │  Members cast votes                                       │     │
│   │  vote(proposalId, [optionIndices], [weights])            │     │
│   │                                                           │     │
│   │  Timer: 1 minute → 30 days (configurable per proposal)   │     │
│   └──────────────────────────────────────────────────────────┘     │
│        │                                                            │
│        ▼                                                            │
│   3. FINALIZATION                                                   │
│   ┌──────────┐                                                      │
│   │ Anyone   │ ──> announceWinner(proposalId)                       │
│   └──────────┘                                                      │
│        │                                                            │
│        ▼                                                            │
│   4. EXECUTION (if applicable)                                      │
│   ┌──────────────────────────────────────────────────────────┐     │
│   │  Winning option's batch of calls executed via Executor    │     │
│   │  (e.g., mint hat to elected person, transfer funds, etc.) │     │
│   └──────────────────────────────────────────────────────────┘     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Voting Mechanics

Each voter receives **exactly 100 voting points** to distribute:

**Single-choice voting:**
```solidity
// Put all 100 points on option 0
vote(proposalId, [0], [100]);
```

**Split voting:**
```solidity
// 60 points to option A, 40 points to option B
vote(proposalId, [0, 1], [60, 40]);
```

**Multi-option support:**
```solidity
// Spread across three options
vote(proposalId, [0, 2, 4], [50, 30, 20]);
```

**Key constraints:**
- Weights must sum to exactly 100
- Each weight must be ≤ 100
- No duplicate option indices
- Cannot vote twice on the same proposal

### Winner Determination

The contract uses `VotingMath.pickWinnerMajority()` with **strict majority** requirement:

```solidity
// From VotingMath.sol
function pickWinnerMajority(
    uint256[] memory optionScores,
    uint256 totalWeight,
    uint8 quorumPct,
    bool requireStrictMajority  // ← true for DirectDemocracy
) internal pure returns (uint256 win, bool ok, uint256 hi, uint256 second) {
    // ...

    // Quorum check: hi * 100 > totalWeight * quorumPct
    bool quorumMet = (hi * 100 > totalWeight * quorumPct);
    bool meetsMargin = requireStrictMajority ? (hi > second) : (hi >= second);

    ok = quorumMet && meetsMargin;
}
```

**Example calculation:**

Say 10 workers vote on a proposal with 50% quorum:
- Total weight: 10 voters × 100 points = 1,000
- Quorum threshold: 1,000 × 50% = 500

| Option | Votes | Meets Quorum? | Wins? |
|--------|-------|---------------|-------|
| A      | 600   | Yes (600 > 500) | Yes (600 > 300) |
| B      | 300   | -             | No    |
| C      | 100   | -             | No    |

Option A wins with 600 votes, exceeding both quorum and second place.

**Invalid scenarios:**
- Tie: A=400, B=400, C=200 → No winner (A not > B)
- Low turnout: A=300, B=200, C=100 (6 voters) → No winner (300 < 500 quorum)

---

## Role-Based Access with Hats Protocol

[Hats Protocol](https://www.hatsprotocol.xyz/) provides the permission layer for DirectDemocracyVoting. Think of "hats" as organizational roles that can be dynamically assigned and revoked.

### Hat Types

```solidity
enum HatType {
    VOTING,   // Can vote on proposals
    CREATOR   // Can create proposals
}
```

### Permission Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    HATS PERMISSION FLOW                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────┐                                           │
│   │  Organization   │                                           │
│   │    Top Hat      │ ◄── Ultimate authority                    │
│   └────────┬────────┘                                           │
│            │                                                    │
│   ┌────────┴────────┬──────────────┬──────────────┐            │
│   │                 │              │              │            │
│   ▼                 ▼              ▼              ▼            │
│ ┌─────┐         ┌─────┐        ┌─────┐       ┌─────┐          │
│ │Admin│         │Voting│       │Creator│     │Dept A│          │
│ │ Hat │         │ Hat  │       │  Hat  │     │ Hat  │          │
│ └──┬──┘         └──┬───┘       └───┬───┘     └──┬───┘          │
│    │               │               │            │               │
│    ▼               ▼               ▼            ▼               │
│ Configure       Vote on         Create       Vote on            │
│ contract       proposals       proposals    restricted          │
│ settings       (general)       (general)    dept polls          │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Poll-Specific Restrictions

When creating a proposal, you can restrict voting to specific hat holders:

```solidity
// General proposal - anyone with voting hat can vote
createProposal(
    "Should we adopt a 4-day work week?",
    descHash,
    minutesDuration,
    2,  // Yes/No
    batches,
    []  // Empty = unrestricted
);

// Department-specific - only engineering team votes
createProposal(
    "Which CI/CD platform should we use?",
    descHash,
    minutesDuration,
    3,  // GitHub Actions / GitLab CI / Jenkins
    batches,
    [engineeringHatId]  // ← Only engineers can vote
);
```

This emits a `NewHatProposal` event instead of `NewProposal`, signaling the restriction.

---

## Code Walkthrough

### Contract Architecture

```
DirectDemocracyVoting.sol
├── Initializable (OpenZeppelin upgradeable)
├── ERC-7201 Namespaced Storage
├── Inline security (Pausable, ReentrancyGuard)
└── External integrations
    ├── IHats (Hats Protocol)
    ├── IExecutor (batch execution)
    ├── HatManager (hat permission utilities)
    ├── VotingMath (quorum & winner calculation)
    ├── VotingErrors (standardized errors)
    └── ValidationLib (input validation)
```

### Data Structures

**Proposal struct:**
```solidity
struct Proposal {
    uint128 totalWeight;              // Total voting points cast (voters × 100)
    uint64 endTimestamp;              // When voting closes
    PollOption[] options;             // Vote counts per option
    mapping(address => bool) hasVoted;// Prevent double voting
    IExecutor.Call[][] batches;       // Per-option execution batches
    uint256[] pollHatIds;             // Restricted voting (if any)
    bool restricted;                  // Quick check for restrictions
    mapping(uint256 => bool) pollHatAllowed; // O(1) hat lookup
}
```

**Storage layout (ERC-7201):**
```solidity
struct Layout {
    IHats hats;                       // Hats Protocol contract
    IExecutor executor;               // Execution contract
    mapping(address => bool) allowedTarget; // Execution whitelist
    uint256[] votingHatIds;           // Who can vote
    uint256[] creatorHatIds;          // Who can create proposals
    uint8 quorumPercentage;           // 1-100
    Proposal[] _proposals;            // All proposals
    bool _paused;                     // Emergency stop
    uint256 _lock;                    // Reentrancy guard
}
```

### Key Functions

#### `initialize()`
Sets up the contract with initial configuration:

```solidity
function initialize(
    address hats_,           // Hats Protocol address
    address executor_,       // Executor contract
    uint256[] calldata initialHats,      // Initial voting hats
    uint256[] calldata initialCreatorHats, // Initial creator hats
    address[] calldata initialTargets,   // Allowed execution targets
    uint8 quorumPct          // e.g., 50 for 50%
) external initializer
```

**Example:** A new cooperative initializes with:
- All members can vote (member hat)
- Only coordinators can create proposals (coordinator hat)
- 60% quorum required for valid decisions

#### `createProposal()`
Creates a new voting proposal:

```solidity
function createProposal(
    bytes calldata title,           // Human-readable title
    bytes32 descriptionHash,        // IPFS hash or keccak256 of description
    uint32 minutesDuration,         // 1 to 43,200 (30 days)
    uint8 numOptions,               // 1 to 50
    IExecutor.Call[][] calldata batches, // Execution per option
    uint256[] calldata hatIds       // Restricted voting (empty = open)
) external onlyCreator whenNotPaused
```

**Validation:**
- Title cannot be empty
- Duration within bounds
- Options count within limits
- Execution targets must be whitelisted

#### `vote()`
Casts a weighted vote:

```solidity
function vote(
    uint256 id,              // Proposal ID
    uint8[] calldata idxs,   // Option indices
    uint8[] calldata weights // Weights per option (must sum to 100)
) external exists(id) notExpired(id) whenNotPaused
```

**Checks performed:**
1. Proposal exists and is active
2. Caller has voting hat
3. If restricted, caller has poll-specific hat
4. Caller hasn't already voted
5. Weights are valid (sum to 100, no duplicates)

#### `announceWinner()`
Finalizes a proposal after voting ends:

```solidity
function announceWinner(uint256 id)
    external nonReentrant exists(id) isExpired(id) whenNotPaused
    returns (uint256 winner, bool valid)
```

**Actions:**
1. Calculate winner using `VotingMath.pickWinnerMajority()`
2. If valid and winner has execution batch:
   - Validate all targets still whitelisted
   - Execute batch via Executor
3. Emit `Winner` event

---

## Real-World Examples

### Example 1: Hiring a New Worker

A bakery cooperative wants to hire a new pastry chef. Three candidates applied.

**Setup:**
```solidity
// Create proposal with 3 candidates
createProposal(
    bytes("Hire new pastry chef"),
    keccak256("Alice: 5 years experience\nBob: CIA graduate\nCarla: Local hero"),
    10080,  // 7 days voting
    3,      // 3 candidates
    [[], [], []],  // No on-chain execution (HR handles onboarding)
    []      // All members vote
);
```

**Voting:**
```solidity
// Worker Maria votes for Alice
vote(0, [0], [100]);

// Worker Jose likes both Alice and Carla
vote(0, [0, 2], [60, 40]);

// Worker Chen supports Bob
vote(0, [1], [100]);
```

**Result:**
```
Alice: 160 points (Maria: 100, Jose: 60)
Bob:   100 points (Chen: 100)
Carla:  40 points (Jose: 40)

Total: 300 points (3 voters × 100)
Quorum (50%): 150 needed

Alice wins with 160 > 150 (quorum) and 160 > 100 (second place)
```

### Example 2: Electing a Coordinator

A tech cooperative elects their annual coordinator. This vote has **on-chain execution**—the winner automatically receives the coordinator hat.

**Setup:**
```solidity
// Prepare execution batches
IExecutor.Call[][] memory batches = new IExecutor.Call[][](3);

// Option 0: Alice wins → mint coordinator hat to Alice
batches[0] = new IExecutor.Call[](1);
batches[0][0] = IExecutor.Call({
    target: hatsAddress,
    value: 0,
    data: abi.encodeWithSignature(
        "mintHat(uint256,address)",
        coordinatorHatId,
        aliceAddress
    )
});

// Option 1: Bob wins → mint coordinator hat to Bob
batches[1] = new IExecutor.Call[](1);
batches[1][0] = IExecutor.Call({
    target: hatsAddress,
    value: 0,
    data: abi.encodeWithSignature(
        "mintHat(uint256,address)",
        coordinatorHatId,
        bobAddress
    )
});

// Option 2: Carla wins → mint coordinator hat to Carla
batches[2] = new IExecutor.Call[](1);
batches[2][0] = IExecutor.Call({
    target: hatsAddress,
    value: 0,
    data: abi.encodeWithSignature(
        "mintHat(uint256,address)",
        coordinatorHatId,
        carlaAddress
    )
});

// Create election
createProposal(
    bytes("2025 Coordinator Election"),
    electionDescHash,
    20160,  // 14 days voting
    3,
    batches,
    []  // All members vote
);
```

**After voting ends:**
```solidity
// Anyone can trigger finalization
announceWinner(proposalId);

// If Bob won:
// 1. Winner event emitted with (1, true)
// 2. Executor.execute() called with Bob's batch
// 3. Hats.mintHat(coordinatorHatId, bobAddress) executed
// 4. Bob now wears the coordinator hat!
```

### Example 3: Budget Allocation

A community organization decides how to allocate a 10 ETH grant between three projects.

**Setup:**
```solidity
// Execution batches for each allocation strategy
IExecutor.Call[][] memory batches = new IExecutor.Call[][](3);

// Option 0: Equal split (3.33 ETH each)
batches[0] = new IExecutor.Call[](3);
batches[0][0] = IExecutor.Call({
    target: treasuryAddress,
    value: 0,
    data: abi.encodeWithSignature("transfer(address,uint256)", projectA, 3.33 ether)
});
batches[0][1] = IExecutor.Call({
    target: treasuryAddress,
    value: 0,
    data: abi.encodeWithSignature("transfer(address,uint256)", projectB, 3.33 ether)
});
batches[0][2] = IExecutor.Call({
    target: treasuryAddress,
    value: 0,
    data: abi.encodeWithSignature("transfer(address,uint256)", projectC, 3.34 ether)
});

// Option 1: Prioritize Project A (5 ETH A, 2.5 ETH B, 2.5 ETH C)
// ... similar structure

// Option 2: Community voted priorities
// ... similar structure

createProposal(
    bytes("Q1 Grant Allocation"),
    grantDescHash,
    4320,  // 3 days
    3,
    batches,
    []
);
```

### Example 4: Department-Specific Decisions

The engineering department needs to choose between two database solutions. Only engineers should vote on this technical decision.

**Setup:**
```solidity
// Only engineering hat holders can vote
uint256[] memory restrictedHats = new uint256[](1);
restrictedHats[0] = engineeringHatId;

createProposal(
    bytes("Database Selection: PostgreSQL vs MongoDB"),
    techDescHash,
    10080,  // 7 days
    2,
    [[], []],  // No auto-execution (infrastructure team implements)
    restrictedHats  // ← Only engineers vote!
);
```

**Voting:**
```solidity
// Engineer Alex votes
// ✅ Has voting hat AND engineering hat
vote(0, [0], [100]);  // Votes PostgreSQL

// Marketing Maria tries to vote
// ✅ Has voting hat
// ❌ Does NOT have engineering hat
vote(0, [1], [100]);  // REVERTS: RoleNotAllowed
```

This ensures technical decisions are made by those with relevant expertise, while maintaining democratic principles within that group.

---

## On-Chain Execution

The execution system allows proposals to automatically trigger smart contract calls when they pass. This makes governance **binding** rather than merely advisory.

### Executor Contract

```solidity
interface IExecutor {
    struct Call {
        address target;   // Contract to call
        uint256 value;    // ETH to send
        bytes data;       // Encoded function call
    }

    function execute(uint256 proposalId, Call[] calldata batch) external;
}
```

### Target Whitelisting

Only pre-approved contracts can be called:

```solidity
// Admin whitelists treasury contract
setConfig(ConfigKey.TARGET_ALLOWED, abi.encode(treasuryAddress, true));

// Admin whitelists Hats contract (for role changes)
setConfig(ConfigKey.TARGET_ALLOWED, abi.encode(hatsAddress, true));
```

### Security Checks

Before execution, the contract validates:

1. **Target not self:** Cannot call the voting contract itself
2. **Target whitelisted:** Must be in allowedTarget mapping
3. **Batch size limit:** Maximum 20 calls per option
4. **Reentrancy protection:** `nonReentrant` modifier

```solidity
function announceWinner(uint256 id) external nonReentrant ... {
    (winner, valid) = _calcWinner(id);

    if (valid && batch.length > 0) {
        // Validate before execution
        for (uint256 i; i < len;) {
            if (batch[i].target == address(this)) revert VotingErrors.TargetSelf();
            if (!l.allowedTarget[batch[i].target]) revert VotingErrors.TargetNotAllowed();
            ...
        }
        l.executor.execute(id, batch);
    }
    ...
}
```

---

## Security Considerations

### Protection Against Common Attacks

| Attack Vector | Protection |
|--------------|------------|
| **Double voting** | `hasVoted` mapping per proposal |
| **Vote manipulation** | Immutable on-chain storage |
| **Frontrunning** | Votes are binding; cannot change |
| **Reentrancy** | `nonReentrant` on `announceWinner` |
| **Overflow** | Solidity 0.8+ built-in checks |
| **Unauthorized access** | Hats Protocol role verification |
| **Malicious execution** | Target whitelist + self-call prevention |

### Emergency Controls

The Executor can pause the contract:

```solidity
// Pause all voting activity
function pause() external onlyExecutor { _pause(); }

// Resume operations
function unpause() external onlyExecutor { _unpause(); }
```

When paused:
- No new proposals
- No votes
- No winner announcements

### Configuration Changes

All configuration changes go through the Executor (governance-controlled):

```solidity
function setConfig(ConfigKey key, bytes calldata value) external onlyExecutor {
    if (key == ConfigKey.QUORUM) { ... }
    else if (key == ConfigKey.EXECUTOR) { ... }
    else if (key == ConfigKey.TARGET_ALLOWED) { ... }
    else if (key == ConfigKey.HAT_ALLOWED) { ... }
}
```

This means changing voting parameters itself requires a governance vote.

---

## Technical Reference

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MODULE_ID` | `0x6464766f` | "ddvo" identifier |
| `MAX_OPTIONS` | 50 | Maximum options per proposal |
| `MAX_CALLS` | 20 | Maximum execution calls per option |
| `MAX_DURATION_MIN` | 43,200 | Maximum voting duration (30 days) |
| `MIN_DURATION_MIN` | 1 | Minimum voting duration (1 minute, for testing) |

### Events

```solidity
// Hat configuration
event HatSet(HatType hatType, uint256 hat, bool allowed);
event CreatorHatSet(uint256 hat, bool allowed);

// Proposal lifecycle
event NewProposal(uint256 id, bytes title, bytes32 descriptionHash, uint8 numOptions, uint64 endTs, uint64 created);
event NewHatProposal(uint256 id, bytes title, bytes32 descriptionHash, uint8 numOptions, uint64 endTs, uint64 created, uint256[] hatIds);
event VoteCast(uint256 id, address voter, uint8[] idxs, uint8[] weights);
event Winner(uint256 id, uint256 winningIdx, bool valid);

// Configuration
event ExecutorUpdated(address newExecutor);
event TargetAllowed(address target, bool allowed);
event QuorumPercentageSet(uint8 pct);
event ProposalCleaned(uint256 id, uint256 cleaned);
```

### View Functions

```solidity
// Counts and config
function proposalsCount() external view returns (uint256);
function quorumPercentage() external view returns (uint8);
function paused() external view returns (bool);

// Addresses
function executor() external view returns (address);
function hats() external view returns (address);

// Permissions
function isTargetAllowed(address target) external view returns (bool);
function votingHats() external view returns (uint256[] memory);
function creatorHats() external view returns (uint256[] memory);
function votingHatCount() external view returns (uint256);
function creatorHatCount() external view returns (uint256);

// Poll-specific
function pollRestricted(uint256 id) external view returns (bool);
function pollHatAllowed(uint256 id, uint256 hat) external view returns (bool);
```

### DirectDemocracyVotingLens

A helper contract for efficient batch reads:

```solidity
contract DirectDemocracyVotingLens {
    function getAllVotingHats(DirectDemocracyVoting voting)
        external view returns (uint256[] memory hats, uint256 count);

    function getAllCreatorHats(DirectDemocracyVoting voting)
        external view returns (uint256[] memory hats, uint256 count);

    function getAllProposalHatIds(DirectDemocracyVoting voting, uint256 proposalId, uint256[] calldata hatIds)
        external view returns (bool[] memory);

    function getGovernanceConfig(DirectDemocracyVoting voting)
        external view returns (address executor, address hats, uint8 quorumPercentage, uint256 proposalCount);
}
```

---

## The Bigger Picture

The `DirectDemocracyVoting` contract is more than code—it's a statement about how organizations should work.

Every cooperative that deploys it adds another node to a network of organizations built on genuine equality. Every vote cast is proof that transparent, accountable governance isn't just possible—it's practical.

---

**Version:** 1.0
**Last Updated:** 2025
**License:** MIT
