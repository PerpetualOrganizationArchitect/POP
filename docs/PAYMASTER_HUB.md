# PaymasterHub - Technical Documentation

## Overview

PaymasterHub is a shared gas sponsorship system for worker cooperatives built on ERC-4337 account abstraction. Instead of each organization deploying their own expensive paymaster contract, a single PaymasterHub serves unlimited organizations through a multi-tenant architecture.

### The Solidarity Fund

At the core of PaymasterHub is a solidarity fund that enables mutual aid at the protocol level. Every transaction automatically contributes 1% of its gas cost to a shared pool. This pool is then redistributed based on a progressive tier system designed to support small organizations.

**How it works:**
- **Grace Period (90 days):** New cooperatives get 0.01 ETH (~$30) worth of free gas with zero deposits required (spending-only limit, ~3000 tx on cheap L2s)
- **Tier 1 ($10 deposit):** Organizations deposit 0.003 ETH (~$10) and receive 0.006 ETH match (2x) → 0.009 ETH (~$30) total budget per 90 days
- **Tier 2 ($20 deposit):** Organizations deposit 0.006 ETH (~$20) and receive 0.009 ETH match (declining rate) → 0.015 ETH (~$50) total budget per 90 days
- **Tier 3 (Self-Sufficient):** Organizations with larger deposits (0.017+ ETH) are self-funded and become net contributors

**Progressive design:** The first $10 you deposit gets the BEST match rate (2x). The next $10 gets a lower match rate (1x). This maximizes support for small organizations while keeping the fund sustainable.

**50/50 split:** Every transaction splits costs between your deposit and solidarity - you benefit immediately, even if you don't use your full allowance.

**Native currency only:** All limits are enforced in native currency (ETH). Transaction counts mentioned throughout are reference values only - PoaManager adjusts native currency amounts to target approximate transaction counts based on network gas prices.

This creates infrastructure where cooperatives support each other automatically, with the most support going to those who need it most.

### Technical Specs

- **Standard:** ERC-4337 (Account Abstraction)
- **Pattern:** UUPS Upgradeable Proxy
- **Storage:** ERC-7201 Namespaced
- **Access Control:** Hats Protocol
- **Entry Point:** v0.7 (`0x0000000071727De22E5E9d8BAf0edAc6f37da032`)
- **Solidarity Fee:** 1% automatic contribution

---

## Table of Contents

1. [Core Architecture](#core-architecture)
2. [Features](#features)
3. [Solidarity Fund](#solidarity-fund)
4. [Grace Period](#grace-period)
5. [Progressive Tier System](#progressive-tier-system)
6. [Real-World Scenarios](#real-world-scenarios)
7. [Configuration](#configuration)
8. [Gas Costs](#gas-costs)
9. [Upgrades](#upgrades)
10. [Security](#security)

---

## Core Architecture

### Multi-Tenant Design

```
┌─────────────────────────────────────────────────────┐
│              PaymasterHub (Proxy)                   │
│                                                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────┐ │
│  │  Org Alpha   │  │   Org Beta   │  │ Org Gamma│ │
│  │              │  │              │  │          │ │
│  │ Rules        │  │ Rules        │  │ Rules    │ │
│  │ Budgets      │  │ Budgets      │  │ Budgets  │ │
│  │ Financials   │  │ Financials   │  │Financial │ │
│  └──────────────┘  └──────────────┘  └──────────┘ │
│                                                     │
│         ┌────────────────────────┐                 │
│         │   Solidarity Fund      │                 │
│         │   (Shared Pool)        │                 │
│         └────────────────────────┘                 │
└─────────────────────────────────────────────────────┘
                        │
                        ▼
            ┌───────────────────────┐
            │  EntryPoint v0.7      │
            │  (Canonical Singleton)│
            └───────────────────────┘
```

### Storage Layout (ERC-7201)

All storage uses **namespaced slots** to prevent collisions:

```solidity
// Main config
MAIN_STORAGE_LOCATION = keccak256("poa.paymasterhub.main") - 1
  └─ entryPoint, hats, poaManager

// Per-org data (isolated by orgId)
ORGS_STORAGE_LOCATION = keccak256("poa.paymasterhub.orgs") - 1
  └─ mapping(bytes32 orgId => OrgConfig)

FINANCIALS_STORAGE_LOCATION = keccak256("poa.paymasterhub.financials") - 1
  └─ mapping(bytes32 orgId => OrgFinancials)

RULES_STORAGE_LOCATION = keccak256("poa.paymasterhub.rules") - 1
  └─ mapping(bytes32 orgId => mapping(address target => mapping(bytes4 selector => Rule)))

BUDGETS_STORAGE_LOCATION = keccak256("poa.paymasterhub.budgets") - 1
  └─ mapping(bytes32 orgId => mapping(bytes32 subjectKey => Budget))

// Global pools
SOLIDARITY_STORAGE_LOCATION = keccak256("poa.paymasterhub.solidarity") - 1
  └─ SolidarityFund (balance, fees, numOrgs)

GRACEPERIOD_STORAGE_LOCATION = keccak256("poa.paymasterhub.graceperiod") - 1
  └─ GracePeriodConfig (days, maxSpend, minDeposit)
```

**Benefits:**
- ✅ No storage collisions between orgs
- ✅ Safe upgrades (can add new storage)
- ✅ Gas-efficient lookups
- ✅ Clear separation of concerns

---

## Features

### Organization Registration

`registerOrg(bytes32 orgId, uint256 adminHatId, uint256 operatorHatId)`

Creates isolated namespace with:
- Admin hat (full control)
- Optional operator hat (delegated management)
- Grace period tracking (90 days from registration)
- Solidarity fund access

### Access Control (Hats Protocol)

**Roles:**
- **Admin Hat:** Full control (pause, rules, budgets, fee caps, bounties)
- **Operator Hat:** Delegated management (rules, budgets, fee caps only)
- **PoaManager:** Protocol governance (upgrades, grace config, bans)

### Rules Engine

`setRule(bytes32 orgId, address target, bytes4 selector, bool allowed, uint32 maxCallGasHint)`

Per-target, per-selector validation with optional gas limits.

**Modes:**
- **GENERIC:** Validates nested calls (default for SimpleAccount)
- **EXECUTOR:** Validates account's own functions
- **COARSE:** Account-level only

### Budget System

`setBudget(bytes32 orgId, bytes32 subjectKey, uint128 capPerEpoch, uint32 epochLen)`

Time-based spending limits per:
- Account: `keccak256(abi.encodePacked(uint8(0), bytes20(account)))`
- Hat: `keccak256(abi.encodePacked(uint8(1), bytes20(hatId)))`
- Org: `bytes32(0)`

Auto-rolls epochs.

### Fee & Gas Caps

`setFeeCaps(...)` - Protect against gas spikes

### Bundler Bounties

`setBounty(bytes32 orgId, bool enabled, uint96 maxBountyWeiPerOp, uint16 pctBpCap)`

Incentivize fast inclusion. Bounty = `min(maxBountyWeiPerOp, gasCost * pctBpCap / 10000)`

---

## Solidarity Fund

### Structure

```solidity
struct SolidarityFund {
    uint128 balance;              // Current solidarity fund balance
    uint32 numActiveOrgs;         // Number of orgs with deposits > 0
    uint16 feePercentageBps;      // Fee as basis points (100 = 1%)
    uint208 reserved;             // Padding for future use
}

struct OrgFinancials {
    uint128 deposited;                  // Current balance deposited by org
    uint128 totalDeposited;             // Cumulative lifetime deposits (never decreases)
    uint128 spent;                      // Total spent from org's own deposits
    uint128 solidarityUsedThisPeriod;   // Solidarity used in current 90-day period
    uint32 periodStart;                 // Timestamp when current 90-day period started
    uint224 reserved;                   // Padding for future use
}
```

### Fee Collection

1% automatic fee on all gas spending:
```solidity
solidarityFee = (actualGasCost * 100) / 10000
```

### Donations

```javascript
depositForOrg(orgId, {value: amount})  // Support specific org
donateToSolidarity({value: amount})    // Support solidarity pool
```

---

## Grace Period

### Configuration

```solidity
struct GracePeriodConfig {
    uint32 initialGraceDays;      // Default: 90
    uint128 maxSpendDuringGrace;  // Default: 0.01 ETH (~$30, represents ~3000 tx on L2s)
    uint128 minDepositRequired;   // Default: 0.003 ETH (~$10)
}
```

### Initial Grace (Day 0-90)

- Zero deposits required
- **Spending limit:** 0.01 ETH (~$30 value)
  - Represents ~3000 transactions on cheap L2s (~$0.01 each)
  - Or ~100 transactions on mainnet (~$0.30 each)
  - Configurable by PoaManager to adapt to gas prices
- All spending from solidarity pool
- Purpose: Prove you're real, bootstrap with zero capital

**Example:** On Base with 0.01 ETH limit, you can do ~3000 transactions at $0.01 each. On mainnet with same limit, you get ~100 transactions at $0.30 each. PoaManager can adjust the native currency amount to target a specific transaction count.

### Post-Grace (Day 91+)

Enter tier system based on deposit size. Must maintain minimum deposit (0.003 ETH) to access solidarity.

Checks current `deposited` balance, not cumulative.

### Network Configs

| Network | Grace Days | Max Spend | Equivalent TX Count | Min Deposit |
|---------|-----------|-----------|---------------------|-------------|
| Mainnet | 90 | 0.01 ETH (~$30) | ~100 tx @ $0.30 each | 0.01 ETH (~$30) |
| L2s | 90 | 0.01 ETH (~$30) | ~3000 tx @ $0.01 each | 0.003 ETH (~$10) |
| Cheap L2s | 90 | 0.01 ETH (~$30) | ~30000 tx @ $0.001 each | 0.003 ETH (~$10) |

**Note:** Only native currency amounts are enforced on-chain. Transaction counts are reference values that PoaManager uses when setting `maxSpendDuringGrace` to adapt to gas prices.

---

## Progressive Tier System

### Tiers Based on Deposit Size

**Tier 1: Micro Orgs**
- Deposit: 0.003 ETH (~$10)
- Match: 2x (0.006 ETH)
- Total budget: 0.009 ETH (~$30) per 90 days
- Best for: Small co-ops spending ~$10/month

**Tier 2: Small Orgs**
- Deposit: 0.006 ETH (~$20)
- Match: First 0.003 at 2x (=0.006) + second 0.003 at 1x (=0.003) = 0.009 ETH total
- Total budget: 0.015 ETH (~$50) per 90 days
- Best for: Growing co-ops spending ~$16/month on gas

**Tier 3: Self-Sufficient**
- Deposit: 0.017+ ETH (~$50+)
- Match: None (self-funded threshold)
- Net contributors to ecosystem via 1% fee on all their spending

### Match Calculation

```solidity
function _calculateMatchAllowance(uint256 deposited, uint256 minDeposit) internal pure returns (uint256) {
    if (deposited < minDeposit) return 0;

    // Tier 1: 2x match
    if (deposited <= minDeposit) {
        return deposited * 2;
    }

    // Tier 2: Declining match (2x first, 1x second)
    if (deposited <= minDeposit * 2) {
        return (minDeposit * 2) + (deposited - minDeposit);
    }

    // Tier 3: No match
    return 0;
}
```

Gas cost: ~150 gas (pure function)

### 90-Day Periods with Dual Reset

Solidarity allowances reset when:
1. **Time-based:** 90 days elapse since period start, OR
2. **Deposit-based:** Balance crosses minimum threshold

```solidity
// Reset triggers
if (block.timestamp >= periodStart + 90 days) {
    resetPeriod();  // Time trigger
}
if (wasBelowMinimum && willBeAboveMinimum) {
    resetPeriod();  // Deposit trigger
}
```

**Why:** Natural commitment mechanism without per-tx overhead. Only costs gas on deposit (~3000 gas per reset).

### Payment Priority

**During grace (Day 0-90):**
```solidity
fromSolidarity = actualGasCost;  // 100% from solidarity
fromDeposits = 0;
```

**After grace (Day 91+):**
```solidity
// Calculate tier-based allowance
matchAllowance = _calculateMatchAllowance(deposited, minDeposit);
solidarityRemaining = matchAllowance - solidarityUsedThisPeriod;

// Try 50/50 split
halfCost = actualGasCost / 2;
fromDeposits = min(halfCost, depositAvailable);
fromSolidarity = min(halfCost, solidarityRemaining);

// If one pool short, use the other
if (fromDeposits + fromSolidarity < actualGasCost) {
    // Try deposits first, then solidarity
    // Revert if neither can cover
}
```

**Result:** Immediate benefit from 50/50 split. Even if you don't use full deposit, you still got solidarity support.

---

## Future Feature: Micro-Org Exemption (V2)

**Concept:** Organizations with consistently low activity (< $5/month rolling average) can operate indefinitely without deposits.

**Rationale:**
- Small community groups shouldn't be forced to deposit
- Example: Neighborhood garden with 10 governance votes/month
- Still subject to anti-gaming checks (PoaManager can ban)

**Implementation considerations:**
- Track 30-day rolling average spending
- Exempt from deposit requirement if below threshold
- Still subject to algorithmic allocation limits
- Prevents forcing tiny legitimate orgs to maintain minimum balance

**Status:** Documented for future implementation. Not in current version.

---

## Real-World Scenarios

### Bootstrapping Co-op (Tier 1)

New food co-op on Base with zero funds:

**Month 1-3 (Grace Period):**
- Spending: 0.0083 ETH (~$25, ~2500 tx)
- From solidarity: 0.0083 ETH (100%)
- Deposits: 0 ETH
- Status: Within 0.01 ETH grace limit ✅

**Month 4 (Enter Tier 1):**
- Deposits: 0.003 ETH ($10)
- Match allowance: 0.006 ETH ($20)
- Total budget: 0.009 ETH ($30) per 90 days
- Period starts: April 1

**Month 4-6 (First Period):**
- Spending: $27 over 3 months
- Payment via 50/50 split + fallback:
  - From deposits: $10 (fully exhausted)
  - From solidarity: $17 (used $17 of $20 allowance, $3 remaining)
- Contributed via 1% fee: ~$0.27

**Month 7 (Second Period):**
- Deposits another $10 (crosses threshold → period resets!)
- Fresh allowance: $20
- Can spend: $30 total
- **Annual total:** Deposit $40, spend $110 in gas → $70 net benefit

### Growing Co-op (Tier 2)

Tech co-op with growing user base on Arbitrum:

**Month 4:**
- Deposits: 0.006 ETH ($20)
- Match calculation:
  - First 0.003 ETH at 2x rate = 0.006 ETH
  - Second 0.003 ETH at 1x rate = 0.003 ETH
  - Total match allowance: 0.009 ETH ($30)
- Total budget: 0.015 ETH ($50) per 90 days (can spend $20 from deposits + $30 from solidarity)

**Month 4-6 (First Period):**
- Spending: $45 over 3 months
- Payment via 50/50 split + fallback:
  - From deposits: $20 (fully exhausted)
  - From solidarity: $25 (used $25 of $30 allowance, $5 remaining)
- Contributed via 1% fee: ~$0.45

**Result:** $20 deposit enables $45 in spending → $25 net benefit from solidarity

### Established Co-op (Tier 3)

Profitable co-op with 200 users:

**Month 4:**
- Deposits: 0.05 ETH ($150) for operations
- Match: $0 (Tier 3, self-sufficient)
- Spending: $300/month

**Monthly:**
- From deposits: $150
- From solidarity: $0 (opted out or no match)
- Contributes via 1% fee: $3/month

**Result:** Net contributor to ecosystem ($36/year in fees)

### Temporary Hardship

Normal co-op hits rough patch:
- **Month 1-11:** Normal operations with $10/month deposits
- **Month 12:** Can't deposit, solidarity access cut off
- **Month 13:** Community donates $50 via `depositForOrg()`, access restored

### Malicious Actor

Scam tries to exploit:
- **Day 1-90:** Burns through grace period with spam
- **Day 95:** PoaManager bans from solidarity via `setBanFromSolidarity()`
- **Result:** Can only use own deposits, pool protected

---

## Configuration

### Network Settings

| Network | Max Fee | Priority Fee | Call Gas | Ver Gas | PreVer Gas |
|---------|---------|--------------|----------|---------|------------|
| Mainnet | 200 gwei | 20 gwei | 1M | 500k | 200k |
| L2s | 1 gwei | 0.1 gwei | 2M | 1M | 500k |
| Cheap L2s | 0.1 gwei | 0.01 gwei | 3M | 1.5M | 700k |

### Example Configs

**Conservative:**
- Whitelist specific contracts/functions
- Daily per-member budgets
- Low gas caps
- No bounties

**Progressive:**
- Block only high-risk operations
- Weekly budgets
- High gas caps
- High bounties for fast inclusion

**Hybrid:**
- Tiered rules by risk
- Role-based budgets (member/operator/treasurer)
- Moderate caps and bounties

---

## Gas Costs

### Deployment

| Operation | Gas | Mainnet | L2 |
|-----------|-----|---------|-----|
| Implementation | ~4M | ~$500 | ~$1 |
| Beacon proxy | ~200k | ~$25 | ~$0.05 |
| Register org | ~65k | ~$8 | ~$0.02 |

**Savings:** 99.8% vs traditional paymaster (~40M gas per org)

### Per-Transaction Overhead

After gas optimizations (removed transaction counting and unused tracking):

| Component | Gas Cost | Notes |
|-----------|----------|-------|
| Budget check | ~600 | Includes epoch rolling logic |
| Rule validation | ~400 | Target/selector extraction |
| Solidarity checks | ~250 | Grace period or tier validation |
| Financial updates (postOp) | ~10,300 | 2 SSTOREs + fee calculation |
| **Total per transaction** | **~11,550** | ~7% of typical 150k gas UserOp |

**Breakdown of postOp (where most cost is):**
- `org.spent` update: 5,000 gas (warm SSTORE)
- `org.solidarityUsedThisPeriod` update: 5,000 gas (warm SSTORE)
- `solidarity.balance` updates (2x): ~300 gas (same slot)
- Fee calculation: ~100 gas
- Match calculation: ~150 gas (pure function)

**Optimizations applied:**
- ✅ Removed transaction counting (-2,900 gas)
- ✅ Removed unused `solidarityUsed` lifetime tracking (-2,900 gas)
- ✅ Removed unused `feesContributed` tracking (-2,900 gas)
- ✅ Removed `totalFeesCollected` tracking (-2,900 gas)
- **Total saved:** ~11,600 gas per transaction (reduced from 19k to ~10.3k)

Overhead is ~7% of total UserOp cost (~150k gas), which is excellent for a multi-tenant paymaster with solidarity fund accounting.

---

## Upgrade System

### UUPS Pattern

PaymasterHub uses **Universal Upgradeable Proxy Standard (UUPS)**.

**Architecture:**
```
User/Bundler
    │
    ▼
┌─────────────────┐
│  Proxy Contract │ ← Permanent address
│  (Storage)      │
└────────┬────────┘
         │ delegatecall
         ▼
┌─────────────────┐
│ Implementation  │ ← Can be upgraded
│ (Logic)         │
└─────────────────┘
```

**Benefits:**
- ✅ Address stays the same
- ✅ Storage preserved
- ✅ Can fix bugs
- ✅ Can add features

### Governance

**Only PoaManager can upgrade:**

```solidity
function _authorizeUpgrade(address newImplementation) internal override {
    if (msg.sender != _getMainStorage().poaManager) {
        revert NotPoaManager();
    }
}
```

**Upgrade Process:**

1. **PoaManager** deploys new implementation
   ```javascript
   PaymasterHub newImpl = new PaymasterHub()
   ```

2. **Register** with PoaManager
   ```javascript
   poaManager.addContractType("PaymasterHub", address(newImpl))
   ```

3. **Upgrade** proxy
   ```javascript
   // From PoaManager or authorized account
   UUPSUpgradeable(paymasterHubProxy).upgradeTo(address(newImpl))
   ```

4. **All orgs** automatically use new logic
   - No redeployment needed ✅
   - Storage intact ✅
   - Solidarity fund preserved ✅

### Storage Safety

**ERC-7201 Namespaced Storage:**
```solidity
// Each feature has dedicated slot
ORGS_STORAGE_LOCATION = keccak256("poa.paymasterhub.orgs") - 1
SOLIDARITY_STORAGE_LOCATION = keccak256("poa.paymasterhub.solidarity") - 1
```

**Storage Gap:**
```solidity
uint256[50] private __gap;
```

Reserves 50 storage slots for future additions without breaking existing storage layout.

**Example Upgrade:**
```solidity
// v1 (current)
struct OrgFinancials {
    uint128 deposited;
    uint128 totalDeposited;
    uint128 spent;
    uint128 solidarityUsedThisPeriod;
    uint32 periodStart;
    uint224 reserved;
}

// v2 (future upgrade - example)
struct OrgFinancials {
    uint128 deposited;
    uint128 totalDeposited;
    uint128 spent;
    uint128 solidarityUsedThisPeriod;
    uint32 periodStart;
    uint32 reputationScore;  // ← NEW FIELD (using reserved space)
    uint192 reserved;        // ← Reduced reserved space
}
```

Storage positions unchanged, new data added safely.

---

## Security Considerations

### Access Control

**Three-Tier Permissions:**

1. **Org Admin** (Hats Protocol)
   - Set rules, budgets, fee caps
   - Pause org
   - Set operator hat
   - Configure bounties

2. **Org Operator** (Optional delegation)
   - Set rules, budgets, fee caps
   - Cannot pause
   - Cannot change admin/operator hats

3. **PoaManager** (Protocol governance)
   - Upgrade PaymasterHub
   - Set grace period config
   - Ban malicious orgs
   - Adjust solidarity fee

**Decentralization:** No single point of failure. Hats-based admin means multiple members can manage.

### Financial Isolation

**Per-Org Accounting:**
```solidity
struct OrgFinancials {
    uint128 deposited;                  // Org's current balance
    uint128 totalDeposited;             // Lifetime deposits (never decreases)
    uint128 spent;                      // Spent from own deposits
    uint128 solidarityUsedThisPeriod;   // Solidarity used this 90-day period
    uint32 periodStart;                 // When current period started
    uint224 reserved;                   // Future use
}
```

**Protections:**
- ✅ Orgs can't spend each other's deposits
- ✅ Solidarity usage tracked separately per 90-day period
- ✅ Tier-based limits prevent pool drainage (small orgs get most support)
- ✅ Grace period spending limits (0.01 ETH max during first 90 days)
- ✅ Minimum deposit requirement after grace (must maintain 0.003 ETH)
- ✅ Ban mechanism for malicious actors (PoaManager can ban from solidarity)

### Reentrancy Protection

```solidity
contract PaymasterHub is ... ReentrancyGuardUpgradeable {

    function postOp(...) external override onlyEntryPoint nonReentrant {
        // Can't be called recursively
        // Protects solidarity fund from extraction attacks
    }
}
```

### Overflow Protection

```solidity
// Solidity 0.8+ has built-in overflow checks
org.deposited += uint128(msg.value);  // Reverts on overflow
solidarity.balance += uint128(solidarityFee);
```

**Safe casting:**
```solidity
// Always check before casting
if (value > type(uint128).max) revert ValueTooLarge();
uint128 safeValue = uint128(value);
```

### Signature Validation

**Not required!** Unlike CitizenWallet's paymaster:
- ✅ No off-chain signer needed
- ✅ All validation on-chain
- ✅ No private key management
- ✅ Rules enforced autonomously

### Upgrade Safety

**UUPS requires explicit authorization:**
```solidity
function _authorizeUpgrade(address newImplementation) internal override {
    if (msg.sender != poaManager) revert NotPoaManager();
}
```

**Cannot be upgraded by:**
- ❌ Org admins
- ❌ Random users
- ❌ Bundlers
- ❌ EntryPoint

**Only:** PoaManager (decentralized governance)

### Grace Period Abuse Prevention

**Spending Limits:**
```solidity
// During initial grace period (first 90 days)
if (org.solidarityUsedThisPeriod + maxCost > grace.maxSpendDuringGrace) {
    revert GracePeriodSpendLimitReached();
}
```

**Minimum Deposit Requirement:**
```solidity
// After grace period
if (org.deposited < grace.minDepositRequired) {
    revert InsufficientDepositForSolidarity();
}
```

**Ban Mechanism:**
```solidity
if (config.bannedFromSolidarity) {
    revert OrgIsBanned();
}
```

**Monitoring:** Off-chain services can detect suspicious patterns (e.g., burning through grace period with spam transactions) and report to PoaManager for banning.

---

## Conclusion

**PaymasterHub** represents a new paradigm in blockchain infrastructure: **solidarity economics at the protocol level**.

### Technical Achievements

- ✅ 99.8% reduction in deployment costs
- ✅ Multi-tenant architecture (unlimited orgs)
- ✅ ERC-7201 storage (safe upgrades)
- ✅ Hats Protocol integration (decentralized control)
- ✅ UUPS upgradeable (future-proof)
- ✅ <1% gas overhead per transaction

### Economic Achievements

- ✅ Automatic mutual aid (1% contribution on all transactions)
- ✅ Progressive tier-based fairness (small orgs get best match rates)
- ✅ Bootstrapping support (90-day grace period with spending limit)
- ✅ Dual-reset model (90 days OR deposit threshold crossing)
- ✅ Immediate 50/50 benefit (don't have to exhaust deposits first)
- ✅ Permissionless donations (anyone can support any org)

### Social Achievements

- ✅ Built for worker cooperatives
- ✅ Enables zero-capital startups
- ✅ Rewards contribution over extraction
- ✅ Self-balancing economic model
- ✅ Protocol-level solidarity

**This isn't just code. It's infrastructure for a cooperative economy.**

---

## Further Reading

- [ERC-4337: Account Abstraction](https://eips.ethereum.org/EIPS/eip-4337)
- [ERC-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)
- [UUPS Proxies](https://eips.ethereum.org/EIPS/eip-1822)
- [Hats Protocol Documentation](https://docs.hatsprotocol.xyz/)
- [Worker Cooperative Principles](https://www.ica.coop/en/cooperatives/cooperative-identity)

---

**Document Version:** 1.0
**Last Updated:** 2024
**Maintainers:** POA Engineering Team
**License:** MIT
