# Gas Complexity Audit Report

## Executive Summary

This audit identifies potential gas-related breaking points in the Perpetual Organization Protocol (POP) where unbounded growth in data structures could lead to transactions exceeding the block gas limit. The analysis focuses on O(n) and O(n²) complexity patterns that could cause denial-of-service conditions as the protocol scales.

**Audit Date:** December 2024
**Scope:** All Solidity contracts in `/src/`

---

## Critical Severity Issues

### 1. TaskManager._permMask() - Unbounded Permission Hat Iteration

**Location:** `src/TaskManager.sol:629-660`

**Description:** The `_permMask` function iterates over ALL hats in `permissionHatIds` array for every permission check. This array grows unboundedly as more hats are granted permissions.

```solidity
function _permMask(address user, bytes32 pid) internal view returns (uint8 m) {
    Layout storage l = _layout();
    uint256 len = l.permissionHatIds.length;  // ← Unbounded
    if (len == 0) return 0;

    // Creates arrays of size `len`
    address[] memory wearers = new address[](len);
    uint256[] memory hats_ = new uint256[](len);
    for (uint256 i; i < len;) {  // ← O(n) loop
        wearers[i] = user;
        hats_[i] = l.permissionHatIds[i];
        unchecked { ++i; }
    }
    uint256[] memory bal = l.hats.balanceOfBatch(wearers, hats_);  // External call with n items

    for (uint256 i; i < len;) {  // ← Another O(n) loop
        // ... permission checking
        unchecked { ++i; }
    }
}
```

**Impact:**
- Called on EVERY task operation: `createTask`, `claimTask`, `assignTask`, `submitTask`, `completeTask`, `cancelTask`
- If 100 hats have permissions, each task operation:
  - Allocates 2 arrays of 100 elements
  - Makes an external `balanceOfBatch` call with 100 items
  - Iterates 200 times total
- **Breaking Point:** ~500-1000 permission hats could cause transactions to fail

**Affected Functions:**
- `_checkPerm()` → `_permMask()`
- `_requireCanCreate()` → `_checkPerm()`
- `_requireCanClaim()` → `_checkPerm()`
- `_requireCanAssign()` → `_checkPerm()`
- `createTask()`, `updateTask()`, `claimTask()`, `assignTask()`, `completeTask()`, `cancelTask()`, `createAndAssignTask()`

**Recommendation:**
1. Implement a cap on permission hats per project (e.g., MAX_PERMISSION_HATS = 20)
2. Use a more efficient data structure (e.g., EnumerableSet with batch checking)
3. Consider caching permission results per-transaction

---

### 2. HybridVotingCore.vote() - O(classes × hatIds) Per Vote

**Location:** `src/libs/HybridVotingCore.sol:31-100`

**Description:** The voting function has nested complexity that multiplies across classes and hat IDs.

```solidity
function vote(uint256 id, uint8[] calldata idxs, uint8[] calldata weights) external {
    // ...
    uint256 classCount = p.classesSnapshot.length;

    for (uint256 c; c < classCount;) {  // ← O(classes)
        HybridVoting.ClassConfig memory cls = p.classesSnapshot[c];
        uint256 rawPower = _calculateClassPower(voter, cls, l);  // ← Contains O(hatIds) loop
        // ...
    }

    // Another nested loop for accumulation
    for (uint256 i; i < len2;) {  // ← O(weights)
        for (uint256 c; c < classCount;) {  // ← O(classes)
            // ...
        }
    }
}

function _calculateClassPower(...) internal view returns (uint256) {
    // ...
    if (!hasClassHat && cls.hatIds.length > 0) {
        for (uint256 i; i < cls.hatIds.length;) {  // ← O(hatIds per class)
            if (l.hats.isWearerOfHat(voter, cls.hatIds[i])) {
                // External call per hat
            }
        }
    }
}
```

**Impact:**
- Total complexity per vote: **O(classes × hatIds + weights × classes)**
- With 8 classes and 10 hats per class: 80 external calls + 50 × 8 = 480 iterations
- **Breaking Point:** Large number of hats per class or many voting options

**Mitigating Factors:**
- `MAX_CLASSES = 8` provides an upper bound on classes
- `MAX_OPTIONS = 50` bounds the options

**Recommendation:**
1. Add `MAX_HATS_PER_CLASS` constant (e.g., 10)
2. Use batch `balanceOfBatch` instead of individual `isWearerOfHat` calls
3. Consider caching class membership per-vote

---

### 3. HatsTreeSetup - O(roles × additionalWearers) Nested Loops

**Location:** `src/HatsTreeSetup.sol:193, 258`

**Description:** During organization deployment, nested loops iterate over roles and their additional wearers.

```solidity
// Line 179-196
for (uint256 i = 0; i < len; i++) {  // ← O(roles)
    RoleConfig memory role = params.roles[i];
    // ...
    for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {  // ← O(wearers per role)
        // External calls for minting
    }
}

// Line 240-265
for (uint256 i = 0; i < len; i++) {  // ← O(roles)
    // ...
    for (uint256 j = 0; j < role.distribution.additionalWearers.length; j++) {  // ← O(wearers per role)
        // ...
    }
}
```

**Impact:**
- Org deployment complexity: **O(roles × avg_wearers_per_role)**
- 20 roles × 50 wearers each = 1000 iterations + external calls
- **Breaking Point:** Organizations with many roles and many initial wearers

**Mitigating Factors:**
- One-time cost at deployment, not ongoing operations
- Deployer can split into multiple transactions

**Recommendation:**
1. Add `MAX_ADDITIONAL_WEARERS_PER_ROLE` constant
2. Consider batching large deployments

---

## High Severity Issues

### 4. HatManager - Linear Search Operations

**Location:** `src/libs/HatManager.sol:108-116, 24-41, 51-58`

**Description:** All hat management operations use linear search through arrays.

```solidity
// findHatIndex - O(n)
function findHatIndex(uint256[] storage hatArray, uint256 hatId) internal view returns (uint256) {
    for (uint256 i; i < hatArray.length;) {  // ← Unbounded
        if (hatArray[i] == hatId) return i;
        unchecked { ++i; }
    }
    return type(uint256).max;
}

// setHatInArray calls findHatIndex - O(n)
function setHatInArray(uint256[] storage hatArray, uint256 hatId, bool allowed) internal returns (bool modified) {
    uint256 existingIndex = findHatIndex(hatArray, hatId);  // ← O(n)
    // ...
}

// hasAnyHat - O(n) with external calls
function hasAnyHat(IHats hats, uint256[] storage hatArray, address user) internal view returns (bool) {
    uint256 len = hatArray.length;  // ← Unbounded
    // Batch check still processes all hats
    return _checkHatsBatch(hats, hatArray, user);
}
```

**Affected Arrays:**
- `votingHatIds` in DirectDemocracyVoting
- `creatorHatIds` in DirectDemocracyVoting, HybridVoting, TaskManager
- `permissionHatIds` in TaskManager
- `pollHatIds` per proposal

**Impact:**
- Every governance action checks creator permissions via `hasAnyHat`
- Adding/removing hats requires O(n) search
- **Breaking Point:** ~100-200 hats in any array

**Recommendation:**
1. Use OpenZeppelin's EnumerableSet for O(1) contains check
2. Or maintain a mapping alongside array for O(1) lookups

---

### 5. DirectDemocracyVoting.vote() - Poll Hat Iteration

**Location:** `src/DirectDemocracyVoting.sol:369-380`

**Description:** For restricted polls, each vote iterates through all allowed poll hats.

```solidity
if (p.restricted) {
    bool hasAllowedHat = false;
    uint256 pollHatLen = p.pollHatIds.length;  // ← Unbounded per proposal
    for (uint256 i = 0; i < pollHatLen;) {
        if (l.hats.isWearerOfHat(_msgSender(), p.pollHatIds[i])) {  // External call per hat
            hasAllowedHat = true;
            break;  // ← Early exit helps
        }
        unchecked { ++i; }
    }
}
```

**Mitigating Factors:**
- Early exit on first match
- `pollHatAllowed` mapping exists at line 48 (but not used here!)

**Recommendation:**
1. The contract already has `pollHatAllowed` mapping - use it for O(1) lookup:
```solidity
// Instead of iterating, check the mapping directly
// This requires knowing which hat the user has first
```
2. Or limit `pollHatIds.length` during proposal creation

---

### 6. EligibilityModule - Batch Operations Gas Limits

**Location:** `src/EligibilityModule.sol:260, 297, 327, 357, 378, 407, 494, 508, 637`

**Description:** Multiple batch functions iterate over input arrays without bounds.

```solidity
// setBulkWearerEligibility - O(n)
function setBulkWearerEligibility(address[] calldata wearers, uint256 hatId, bool _eligible, bool _standing) external {
    uint256 length = wearers.length;  // ← No limit
    for (uint256 i; i < length;) {
        // Storage writes per wearer
    }
}

// batchSetWearerEligibility - O(n)
// batchSetWearerEligibilityMultiHat - O(n)
// batchSetDefaultEligibility - O(n)
// batchMintHats - O(n) with external calls
// batchRegisterHatCreation - O(n)
// batchConfigureVouching - O(n)
```

**Impact:**
- Admin operations could exceed gas limits with large inputs
- **Breaking Point:** ~500-1000 items in batch operations

**Recommendation:**
1. Add `MAX_BATCH_SIZE` constant (e.g., 200)
2. Split large operations into multiple transactions

---

## Medium Severity Issues

### 7. HybridVotingCore.announceWinner() - Matrix Construction

**Location:** `src/libs/HybridVotingCore.sol:137-203`

**Description:** Winner calculation builds a 2D matrix of options × classes.

```solidity
function announceWinner(uint256 id) external returns (uint256 winner, bool valid) {
    // ...
    uint256 numOptions = p.options.length;      // ← Up to 50
    uint256 numClasses = p.classesSnapshot.length;  // ← Up to 8
    uint256[][] memory perOptionPerClassRaw = new uint256[][](numOptions);

    for (uint256 opt; opt < numOptions;) {  // ← O(options)
        perOptionPerClassRaw[opt] = new uint256[](numClasses);
        for (uint256 cls; cls < numClasses;) {  // ← O(classes)
            // ...
        }
    }
    // More iteration in pickWinnerNSlices
}
```

**Impact:**
- Memory allocation: 50 × 8 = 400 uint256 values
- Total iterations: ~800 (bounded by MAX_OPTIONS × MAX_CLASSES)

**Mitigating Factors:**
- Hard caps: `MAX_OPTIONS = 50`, `MAX_CLASSES = 8`
- Total complexity bounded at ~400 iterations

---

### 8. Task Applicants Array

**Location:** `src/TaskManager.sol:455`

**Description:** Task applicants array grows with each application.

```solidity
function applyForTask(uint256 id, bytes32 applicationHash) external {
    // ...
    l.taskApplicants[id].push(applicant);  // ← Unbounded growth
}
```

**Impact:**
- Each task can accumulate unlimited applicants
- `getLensData` type 7 returns all applicants - could exceed return data limits

**Mitigating Factors:**
- Array cleared on approval: `delete l.taskApplicants[id]`
- Array cleared on cancellation: `delete l.taskApplicants[id]`
- No iteration over this array in critical paths

**Recommendation:**
1. Add `MAX_APPLICANTS_PER_TASK` constant
2. Or implement pagination for viewing applicants

---

### 9. PasskeyAccount - Recovery IDs Array

**Location:** `src/PasskeyAccount.sol:342`

**Description:** `pendingRecoveryIds` array grows with each recovery initiation.

```solidity
function initiateRecovery(...) external override onlyGuardian {
    // ...
    l.pendingRecoveryIds.push(recoveryId);  // ← No cleanup
}
```

**Impact:**
- Array never cleaned up (completed/cancelled recoveries remain)
- Could grow indefinitely over account lifetime

**Mitigating Factors:**
- Only guardian can initiate
- Not iterated in critical paths

**Recommendation:**
1. Remove completed/cancelled recovery IDs
2. Or use a mapping instead

---

## Low Severity Issues

### 10. OrgRegistry.orgIds Array

**Location:** `src/OrgRegistry.sol:117, 140`

**Description:** Global array of all organization IDs.

```solidity
l.orgIds.push(orgId);
```

**Impact:**
- `getOrgIds()` returns entire array - gas cost grows with orgs
- Not iterated in write operations

**Mitigating Factors:**
- View function only
- Permissioned creation (only owner)

---

### 11. ImplementationRegistry Version Arrays

**Location:** `src/ImplementationRegistry.sol:80, 84`

**Description:** Version history arrays grow with each upgrade.

```solidity
l.typeIds.push(tId);
l._meta[tId].versions.push(vId);
```

**Impact:**
- Version history unbounded
- Read operations scale with version count

**Mitigating Factors:**
- Upgrades are rare events
- Not in critical paths

---

### 12. PasskeyAccount Credentials

**Location:** `src/PasskeyAccount.sol:248`

**Description:** Credential array bounded by MAX_CREDENTIALS.

```solidity
uint8 maxCreds = _getMaxCredentials();
if (l.credentialIds.length >= maxCreds) {
    revert MaxCredentialsReached();
}
```

**Status:** ✅ Properly bounded by `MAX_CREDENTIALS = 10`

---

### 13. Voting Hat Arrays (Bounded)

**Location:** `src/HybridVoting.sol:21, src/HybridVotingConfig.sol:24`

**Description:** Class configuration bounded by MAX_CLASSES.

```solidity
uint8 public constant MAX_CLASSES = 8;

if (newClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();
```

**Status:** ✅ Properly bounded

---

## Summary Table

| Issue | Location | Complexity | Bounded? | Breaking Point |
|-------|----------|------------|----------|----------------|
| TaskManager._permMask | TaskManager.sol:629 | O(n) | ❌ | ~500 permission hats |
| HybridVoting.vote | HybridVotingCore.sol:31 | O(c×h) | Partial | Many hats per class |
| HatsTreeSetup loops | HatsTreeSetup.sol:193 | O(r×w) | ❌ | Large deployments |
| HatManager.findHatIndex | HatManager.sol:108 | O(n) | ❌ | ~200 hats |
| DDVoting poll hats | DirectDemocracyVoting.sol:369 | O(n) | ❌ | Many poll hats |
| EligibilityModule batches | EligibilityModule.sol | O(n) | ❌ | ~500 items |
| Task applicants | TaskManager.sol:455 | O(n) | ❌ | Many applicants |
| PasskeyAccount recovery | PasskeyAccount.sol:342 | O(n) | ❌ | Many recoveries |

---

## Recommendations Summary

### Immediate Actions
1. **Add MAX_PERMISSION_HATS** to TaskManager (cap at 20-50)
2. **Add MAX_HATS_PER_CLASS** to HybridVoting (cap at 10-20)
3. **Add MAX_BATCH_SIZE** to EligibilityModule (cap at 200)
4. **Add MAX_APPLICANTS_PER_TASK** to TaskManager (cap at 100)

### Architectural Improvements
1. Replace hat arrays with EnumerableSet for O(1) membership checks
2. Use batch external calls instead of per-item calls where possible
3. Consider pagination for view functions returning large arrays
4. Implement cleanup mechanisms for completed/cancelled entries

### Testing Recommendations
1. Create gas benchmark tests with edge-case array sizes
2. Test deployment with maximum expected org size
3. Simulate long-running organizations to validate scalability

---

## Appendix: Gas Estimation Formulas

**TaskManager Permission Check:**
```
Gas ≈ BASE + (n × SLOAD) + (n × 2 × MEMORY_ALLOC) + EXTERNAL_CALL(n)
Where n = permissionHatIds.length
```

**HybridVoting Vote:**
```
Gas ≈ BASE + (c × h × EXTERNAL_CALL) + (w × c × ARITHMETIC)
Where c = classes, h = hats per class, w = weight indices
```

**HatsTreeSetup Deployment:**
```
Gas ≈ BASE + (r × BASE_ROLE) + (r × w × EXTERNAL_MINT)
Where r = roles, w = avg wearers per role
```
