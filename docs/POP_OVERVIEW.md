# Perpetual Organization Protocol (POP)

**Version:** 1.0
**License:** MIT

---

## The Vision: Organizations That Belong to Those Who Build Them

The Perpetual Organization Protocol (POP) is a comprehensive smart contract system that enables the creation of **worker-owned and community-governed organizations on-chain**. It represents a fundamental reimagining of how organizations can operate—shifting power from capital to labor, from shareholders to stakeholders, and from centralized control to collective governance.

### The Problem with Traditional Organizations

Traditional corporate structures concentrate power and wealth in the hands of shareholders and executives. Workers—the people who actually create value—receive wages while ownership accumulates elsewhere. This creates organizations where:

- **Power follows capital:** More money means more control
- **Workers are expendable:** Labor is a cost to minimize, not value to nurture
- **Communities are extracted from:** Organizations optimize for shareholder returns, not stakeholder wellbeing
- **Decisions happen behind closed doors:** Governance is opaque and inaccessible

### The POP Alternative

POP inverts this model entirely. Every organization deployed through POP operates on fundamentally different principles:

```
Traditional Model:
  Worker → Labor → Company → Profits → Shareholders

POP Model:
  Worker → Labor → Participation Tokens → Ownership + Governance → Worker
```

**When you contribute to a POP organization, you earn ownership.** Your participation tokens represent real stake in the organization—voting power in governance, share of revenue distributions, and voice in the organization's direction.

---

## Core Principles

### 1. Work Creates Ownership

In POP organizations, **contribution is the path to ownership**. Complete a task, earn tokens. Finish a learning module, earn tokens. These aren't rewards—they're equity. Your labor builds your stake in the organization.

```solidity
// When a task is completed:
participationToken.mint(worker, tokenAmount);
// Worker now owns more of the organization
```

### 2. One Member, One Voice (Where It Matters)

POP offers governance models that ensure human participation—not capital—anchors the organization. Direct democracy voting gives every member equal say on fundamental decisions. No whales. No plutocracy. No buying influence.

### 3. Multiple Stakeholders, Proportional Voice

Not all decisions are the same. POP's hybrid voting system allows organizations to balance different constituencies—workers, token holders, users, community supporters—each with their configured share of governance power. A single proposal might allocate 50% weight to worker-members (one person, one vote) and 50% to labor contributors (weighted by earned tokens).

### 4. Collective Infrastructure, Individual Autonomy

Organizations share infrastructure—gas sponsorship, account abstraction, upgrade mechanisms—while maintaining full autonomy over their own governance and operations. The shared infrastructure creates solidarity between organizations; the autonomy preserves self-determination.

### 5. Transparency by Design

Every proposal, every vote, every task, every payment is recorded on-chain. There are no backroom deals, no hidden decisions, no revisionist history. Governance happens in public, creating permanent records of collective decision-making.

---

## System Architecture

POP is a modular system where each component serves a specific purpose in the worker-ownership ecosystem:

```
                    ┌─────────────────────────────────────────┐
                    │           Protocol Layer                 │
                    │  PoaManager · ImplementationRegistry    │
                    │  PaymasterHub · UniversalAccountRegistry │
                    └────────────────────┬────────────────────┘
                                         │
                    ┌────────────────────┴────────────────────┐
                    │           Deployment Layer               │
                    │        OrgDeployer · OrgRegistry         │
                    │          Factory Contracts               │
                    └────────────────────┬────────────────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         │                               │                               │
         ▼                               ▼                               ▼
┌─────────────────┐            ┌─────────────────┐            ┌─────────────────┐
│   Governance    │            │     Access      │            │    Operations   │
│                 │            │                 │            │                 │
│ • HybridVoting  │            │ • QuickJoin     │            │ • TaskManager   │
│ • DirectDemo    │            │ • Participation │            │ • EducationHub  │
│ • Executor      │            │   Token         │            │ • PaymentManager│
│ • Hats Protocol │            │                 │            │                 │
└─────────────────┘            └─────────────────┘            └─────────────────┘
```

### Protocol Layer

**Shared infrastructure that benefits all organizations:**

- **PaymasterHub:** Gasless transactions with solidarity-based mutual aid
- **UniversalAccountRegistry:** Shared identity layer for all participants
- **ImplementationRegistry:** Manages contract implementations and upgrades
- **PoaManager:** Protocol-level governance and configuration

### Deployment Layer

**How organizations come into existence:**

- **OrgDeployer:** Atomic deployment of complete organizations
- **OrgRegistry:** Central registry of all organizations and their contracts
- **Factory Contracts:** Create governance, access, and operational modules

### Organization Layer

Each organization consists of interconnected modules:

- **Governance:** How decisions are made
- **Access:** Who can participate and how
- **Operations:** How work gets coordinated and compensated

---

## Key Components

### ParticipationToken

The **ParticipationToken** is the foundation of worker ownership. Unlike traditional tokens, participation tokens are:

- **Non-transferable:** You can't buy influence—you earn it
- **Minted through contribution:** Tasks and education modules mint tokens
- **Self-delegating:** Votes automatically count for the holder
- **Voting-enabled:** Built-in vote tracking for governance

```
Total Supply: 10,000 tokens
Worker completes task → Mint 100 tokens
New Supply: 10,100 tokens

Worker now owns 100/10,100 ≈ 0.99% of the organization
```

Each token represents genuine ownership stake—a share of governance power and (if configured) revenue distributions.

### TaskManager

**TaskManager is how worker-owned organizations coordinate labor.** It transforms work from a wage relationship into an ownership relationship:

- **Projects** organize tasks with budgets and dedicated managers
- **Tasks** define work with token payouts and optional bounties
- **Applications** enable competitive selection for complex work
- **Completion** triggers automatic token minting and payment

**The Ownership Cycle:**
1. Organization creates task with token reward
2. Worker claims or applies for task
3. Worker completes and submits work
4. Reviewer approves completion
5. Worker receives ownership stake (participation tokens) + optional bounty

### EducationHub

**Learning as a path to ownership.** EducationHub creates on-chain educational modules that reward participation tokens:

- Organizations can create learning paths for onboarding
- Completing modules demonstrates competence and earns ownership
- Knowledge sharing becomes a form of contribution

### Governance: Voting Systems

POP offers two governance models:

**DirectDemocracyVoting:** Pure one-person-one-vote democracy
- Every eligible member gets exactly equal voting power
- Prevents plutocratic capture
- Ideal for high-trust, smaller organizations

**HybridVoting:** Multi-constituency governance
- Multiple stakeholder classes with configurable weights
- Balances different perspectives (workers, token holders, users)
- Supports quadratic voting to limit whale influence

Both systems feature:
- Multi-option proposals (not just yes/no)
- Weighted vote distribution across options
- Quorum requirements and strict majority
- On-chain execution of winning proposals

### Executor

The **Executor** is the "hands" of the organization. It can only act when instructed by approved governance:

- Executes batch transactions from approved proposals
- Controls module configuration
- Manages role assignments through Hats Protocol
- Cannot be controlled by any individual—only collective decisions

After deployment, the deployer **immediately renounces ownership**. The Executor becomes fully autonomous, controllable only through governance.

### QuickJoin

**Frictionless onboarding** for new members:

- Create username in shared account registry
- Automatically receive initial roles (Hats)
- Immediately ready to participate

QuickJoin removes barriers to participation while maintaining organizational integrity through role-based access control.

### PaymentManager

**Revenue distribution for worker-owners:**

- Accepts payments in ETH or any ERC-20 token
- Creates merkle-based distributions
- Members claim their share based on participation token holdings
- Supports opt-out for those who prefer alternative arrangements

### PaymasterHub

**Shared gas sponsorship with built-in solidarity:**

Traditional ERC-4337 paymasters cost ~$500 per organization to deploy. PaymasterHub is multi-tenant—unlimited organizations share one contract.

**The Solidarity System:**
- **Grace Period:** New organizations get 0.01 ETH (~3000 transactions) free for 90 days
- **Progressive Tiers:** Smaller organizations get better matching from the solidarity fund
- **Automatic Contribution:** 1% of all gas spending feeds the solidarity pool
- **50/50 Split:** Transactions split costs between organization deposits and solidarity

```
Tier 1 (Small Co-ops):  0.003 ETH deposit → 0.006 ETH match (2x)
Tier 2 (Growing Co-ops): 0.006 ETH deposit → 0.009 ETH match (1.5x)
Tier 3 (Established):   0.017+ ETH deposit → Self-sufficient (no match)
```

Successful organizations subsidize emerging ones—mutual aid at the protocol level.

---

## Role-Based Access Control with Hats Protocol

POP uses **Hats Protocol** for flexible, decentralized role management. "Hats" represent responsibilities and permissions:

```
              ┌──────────────┐
              │   Top Hat    │  ← Organization root
              │   (Admin)    │
              └──────┬───────┘
                     │
        ┌────────────┼────────────┐
        │            │            │
        ▼            ▼            ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐
   │ Member  │  │ Worker  │  │Reviewer │
   │   Hat   │  │   Hat   │  │   Hat   │
   └────┬────┘  └────┬────┘  └────┬────┘
        │            │            │
        ▼            ▼            ▼
     Can vote     Can claim    Can approve
   in proposals    tasks        work
```

**Hats enable:**
- Role-based voting restrictions
- Granular permission management
- Vouching systems for role progression
- Dynamic role assignment through governance

---

## Upgrade Architecture

Organizations can evolve through the **SwitchableBeacon** system:

**Mirror Mode:** Automatically follow protocol upgrades
- Zero administrative overhead
- Immediate access to improvements
- Trust the protocol team

**Static Mode:** Pin to a specific version
- Complete upgrade autonomy
- Requires governance vote to change
- Full organizational control

Organizations can switch modes through governance, balancing innovation with stability.

---

## Creating an Organization

When `OrgDeployer.deployFullOrg()` is called, an entire organization is created in a single atomic transaction:

```
1. Validate role configurations
2. Create org in bootstrap mode
3. Deploy governance infrastructure (Executor, Voting, Hats)
4. Set executor and register hats tree
5. Register with PaymasterHub (shared gas sponsorship)
6. Deploy access infrastructure (QuickJoin, ParticipationToken)
7. Deploy operational modules (TaskManager, EducationHub, PaymentManager)
8. Wire cross-module connections
9. Configure role permissions and vouching
10. Renounce ownership
```

**The Final Step Matters:** When deployment completes, the deployer renounces all special privileges. From that moment, the organization belongs to its members and can only be controlled through collective governance.

---

## Real-World Applications

### Worker Cooperatives

Traditional cooperatives struggle with governance at scale and distributed decision-making. POP provides:

- Transparent, auditable voting
- Automatic compensation for completed work
- Democratic governance with cryptographic guarantees
- No need for trusted intermediaries

### Community Organizations

Neighborhood associations, mutual aid networks, and community groups can:

- Coordinate collective work and compensate contributors
- Make binding decisions through transparent voting
- Build shared ownership among participants
- Accept and distribute community funds fairly

### DAOs and Collectives

Decentralized autonomous organizations gain:

- Robust multi-stakeholder governance
- Clear role hierarchies with Hats Protocol
- Gas-efficient infrastructure through shared resources
- Upgrade paths that respect organizational autonomy

### Creator Collectives

Artists, writers, musicians, and other creators can:

- Pool resources and share infrastructure
- Make collective decisions about direction
- Compensate contributors fairly based on participation
- Build lasting organizations that outlive any individual

---

## The Bigger Picture

POP isn't just a set of smart contracts—it's infrastructure for a different kind of economy. One where:

- **Work creates ownership,** not just wages
- **Governance is democratic,** not plutocratic
- **Organizations serve their members,** not external shareholders
- **Collective decisions are transparent,** not hidden
- **Infrastructure creates solidarity,** not silos

Every organization deployed through POP adds another node to a network of worker-owned, democratically-governed entities. Every task completed transfers ownership to those who do the work. Every vote cast demonstrates that transparent, accountable governance is not just possible—it's practical.

---

## Technical Foundation

### Upgradeable Contracts

All POP contracts use the UUPS proxy pattern with ERC-7201 namespaced storage, enabling:

- Safe upgrades without storage collisions
- Organization-specific upgrade preferences
- Protocol-wide improvements when organizations opt in

### Security

POP implements multiple security layers:

- Reentrancy guards on all state-changing functions
- Role-based access control through Hats Protocol
- Comprehensive input validation
- Emergency pause capabilities
- Atomic deployment with no intermediate states

### Gas Optimization

POP is built for practical use:

- Bitmap-based permission management
- Packed storage layouts
- Batch operations for common patterns
- Shared infrastructure to reduce per-organization costs

---

## Getting Started

For organizations ready to embrace worker ownership:

1. **Define your structure:** What roles exist? How should governance work?
2. **Configure voting:** Direct democracy, hybrid, or custom?
3. **Set up work coordination:** What tasks will earn ownership?
4. **Deploy:** One transaction creates your complete organization
5. **Onboard members:** QuickJoin makes participation easy
6. **Build together:** Every contribution grows collective ownership

---

## Documentation Index

Detailed documentation for each component:

- [DirectDemocracyVoting](./DIRECT_DEMOCRACY_VOTING.md) - One person, one vote governance
- [HybridVoting](./HYBRID_VOTING.md) - Multi-constituency voting system
- [TaskManager](./TASK_MANAGER.md) - Work coordination and token rewards
- [OrgDeployer](./ORG_DEPLOYER.md) - Atomic organization deployment
- [PaymasterHub](./PAYMASTER_HUB.md) - Shared gas sponsorship with solidarity
- [SwitchableBeacon](../SWITCHABLE_BEACON.md) - Upgrade management architecture

---

## The Promise

POP exists because we believe organizations can—and should—belong to the people who build them. Not to investors who extract value, not to executives who hoard power, but to workers and communities who create value together.

Every line of code in POP serves this vision: **organizations that are owned by those who participate in them, governed by collective decision-making, and designed to persist beyond any individual founder.**

Build together. Own together. Govern together.

---

*The Perpetual Organization Protocol is open source software under the MIT license.*
