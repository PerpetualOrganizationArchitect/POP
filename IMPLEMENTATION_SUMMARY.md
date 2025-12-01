# Device Wrap Registry with Guardian Council - Implementation Summary

## Overview

This implementation adds a **Guardian Council** system governed by the **POA Manager** using **Hats Protocol** for role management. The system provides:

1. **Account recovery** via guardian quorum approval
2. **Over-cap device wrap approval** (4th generation+ devices) via guardian quorum

## Key Differences from Original Plan

The main modification from the original plan is the use of **Hats Protocol** for guardian role management instead of a simple mapping:

### Original Approach
```solidity
mapping(address => bool) isGuardian;
uint256 guardianCount;
```

### Implemented Approach (with Hats)
```solidity
IHats hats;                  // Hats Protocol interface
uint256 guardianHatId;       // Single hat ID for guardian role
```

**Benefits:**
- Leverages existing Hats Protocol infrastructure in the codebase
- Centralized role management through Hats
- POA Manager can manage guardian membership via Hats Protocol
- More flexible and maintainable

## Contracts Modified/Created

### 1. UniversalAccountRegistry (Modified)

**File:** `src/UniversalAccountRegistry.sol`

**Changes:**
- Added `recoveryCaller` storage field - address authorized to call recovery
- Added `orgApprover` storage field - optional org-level recovery approver
- Added `recoverAccount(address from, address to)` function - transfers username from one address to another
- Added admin functions: `setRecoveryCaller()`, `setOrgApprover()`
- Added view functions: `getRecoveryCaller()`, `getOrgApprover()`
- Added new errors: `NotAuthorizedRecoveryCaller`, `NoUsername`, `SameAddress`, `AddressAlreadyHasUsername`
- Added new events: `RecoveryCallerChanged`, `OrgApproverChanged`, `AccountRecovered`

**Key Function:**
```solidity
function recoverAccount(address from, address to) external {
    // Only authorized recovery caller or org approver can call
    if (msg.sender != l.recoveryCaller && msg.sender != l.orgApprover) {
        revert NotAuthorizedRecoveryCaller();
    }
    // Transfer username from 'from' address to 'to' address
    // ...
}
```

### 2. DeviceWrapRegistry (New)

**File:** `src/DeviceWrapRegistry.sol`

**Purpose:** Manages encrypted device wraps with guardian-gated approval system

**Key Features:**

#### Storage Structure
```solidity
struct Layout {
    mapping(address => Wrap[]) wrapsOf;           // User's device wraps
    mapping(address => mapping(uint256 => uint256)) approvalsWrap;  // Approval counts
    mapping(address => mapping(uint256 => mapping(address => bool))) votedWrap;  // Vote tracking
    uint256 maxInstantWraps;                      // Cap for instant approval (default: 3)

    // Hats integration
    IHats hats;                                   // Hats Protocol interface
    uint256 guardianHatId;                        // Guardian role hat ID
    uint256 guardianThreshold;                    // Quorum threshold (default: 1)

    // Recovery state
    mapping(bytes32 => TransferState) transfer;   // Account transfer proposals
    IUniversalAccountRegistry uar;                // Registry reference
}
```

#### Wrap Lifecycle

1. **Add Wrap** (`addWrap`)
   - If active wraps < `maxInstantWraps` (3) → **Active** immediately
   - If active wraps >= `maxInstantWraps` → **Pending** (requires guardian approval)

2. **Guardian Approve Wrap** (`guardianApproveWrap`)
   - Only guardian hat wearers can approve
   - Tracks approvals and prevents double-voting
   - Auto-finalizes when threshold reached

3. **Revoke Wrap** (`revokeWrap`)
   - Owner can always revoke their own wraps

#### Account Recovery Flow

1. **Propose Transfer** (`proposeAccountTransfer`)
   - Anyone can propose a transfer
   - Creates deterministic transfer ID: `keccak256(contractAddress, chainId, from, to)`

2. **Guardian Approve Transfer** (`guardianApproveTransfer`)
   - Only guardian hat wearers can approve
   - Tracks approvals and prevents double-voting
   - Auto-executes when threshold reached

3. **Execute Transfer** (`executeTransfer` or auto-execute)
   - Calls `UAR.recoverAccount(from, to)`
   - Transfers username from old address to new address

#### Guardian Management (POA Manager Only)

```solidity
function setGuardianHat(uint256 hatId) external onlyOwner;
function setGuardianThreshold(uint256 t) external onlyOwner;
function setMaxInstantWraps(uint256 n) external onlyOwner;
```

#### Guardian Check (via Hats Protocol)

```solidity
modifier onlyGuardian() {
    if (guardianHatId == 0 || !hats.isWearerOfHat(msg.sender, guardianHatId)) {
        revert NotGuardian();
    }
    _;
}
```

### 3. DeviceWrapRegistry Tests (New)

**File:** `test/DeviceWrapRegistry.t.sol`

**Test Coverage (12 tests, all passing):**

1. ✅ `testInitialization` - Verifies default values
2. ✅ `testIsGuardian` - Checks guardian hat verification
3. ✅ `testAddWrapWithinCap` - Instant approval for wraps within cap
4. ✅ `testAddWrapOverCapRequiresApproval` - Pending status for over-cap wraps
5. ✅ `testGuardianApproveWrap` - Single guardian approval with threshold=1
6. ✅ `testGuardianApproveWrapWithThreshold` - Multi-guardian approval with threshold=2
7. ✅ `testRevokeWrap` - Owner can revoke wraps
8. ✅ `testProposeAccountTransfer` - Transfer proposal creation
9. ✅ `testGuardianApproveTransfer` - Single guardian transfer approval
10. ✅ `testGuardianApproveTransferWithThreshold` - Multi-guardian transfer approval
11. ✅ `testCannotApproveWrapTwice` - Prevents double-voting
12. ✅ `testNonGuardianCannotApprove` - Access control enforcement

## Deployment & Setup Flow

```solidity
// 1. Deploy UniversalAccountRegistry
UniversalAccountRegistry uar = new UniversalAccountRegistry();
uar.initialize(poaManager);

// 2. Deploy DeviceWrapRegistry
DeviceWrapRegistry dwr = new DeviceWrapRegistry();
dwr.initialize(poaManager, address(uar), address(hats));

// 3. POA Manager sets guardian hat
dwr.setGuardianHat(GUARDIAN_HAT_ID);

// 4. POA Manager sets threshold (optional, default is 1)
dwr.setGuardianThreshold(2); // Require 2 guardians

// 5. POA Manager authorizes DWR to call recovery in UAR
uar.setRecoveryCaller(address(dwr));

// 6. POA Manager can update maxInstantWraps (optional, default is 3)
dwr.setMaxInstantWraps(5);
```

## Usage Examples

### User Adds Device Wraps

```solidity
// User adds first 3 devices - instant approval
for (uint i = 0; i < 3; i++) {
    Wrap memory wrap = Wrap({
        credentialHint: keccak256(credentialId),
        salt: hkdfSalt,
        iv: aesGcmIv,
        aadHash: keccak256(rpIdHash || credentialHint || owner),
        cid: "ipfs://Qm...",
        status: WrapStatus.Active,
        createdAt: 0
    });

    uint256 idx = dwr.addWrap(wrap);
    // Wrap is Active immediately
}

// User adds 4th device - requires guardian approval
Wrap memory wrap4 = Wrap({...});
uint256 idx = dwr.addWrap(wrap4);
// Wrap is Pending, awaits guardian approval
```

### Guardians Approve Over-Cap Wrap

```solidity
// Guardian 1 approves
dwr.guardianApproveWrap(userAddress, wrapIndex);

// If threshold > 1, Guardian 2 approves
dwr.guardianApproveWrap(userAddress, wrapIndex);

// Once threshold reached, wrap auto-finalizes to Active
```

### Account Recovery

```solidity
// Step 1: Propose transfer (anyone can propose)
dwr.proposeAccountTransfer(lostAddress, newAddress);

// Step 2: Guardians approve
dwr.guardianApproveTransfer(lostAddress, newAddress);
// (If threshold=1, executes immediately)

// Step 3: Additional guardians if needed
dwr.guardianApproveTransfer(lostAddress, newAddress);
// (Auto-executes when threshold reached)

// Username is now transferred from lostAddress to newAddress
```

## Security Considerations

1. **Guardian Hat Management**: POA Manager must ensure guardian hat is properly configured in Hats Protocol before use
2. **Threshold Configuration**: Threshold must be ≤ number of guardian hat wearers
3. **Recovery Authorization**: UAR must have DWR set as `recoveryCaller` for recovery to work
4. **No Timelocks**: Approvals execute immediately upon reaching quorum (as specified in requirements)
5. **Double-Vote Prevention**: System prevents same guardian from approving twice
6. **Access Control**: Only guardian hat wearers can approve, only POA Manager can configure

## Gas Optimization Notes

- Uses ERC-7201 storage pattern for upgradeability
- Batch operations not implemented (future enhancement)
- Efficient storage layout with packed structs where possible

## Future Enhancements

1. **Batch Operations**: Add batch approval functions for guardians
2. **Timelock Option**: Add optional timelock/delay for sensitive operations
3. **Wrap Expiry**: Add expiration timestamps for wraps
4. **Transfer History**: Track full recovery history
5. **Guardian Rotation**: Support for changing guardian hat without disrupting ongoing approvals

## Testing

All contracts compile successfully and pass comprehensive test suite:
- 12/12 tests passing
- Coverage includes happy paths, access control, and error cases
- Integration testing with MockHats for Hats Protocol simulation

## Files Changed

- ✅ `src/UniversalAccountRegistry.sol` (modified)
- ✅ `src/DeviceWrapRegistry.sol` (new)
- ✅ `test/DeviceWrapRegistry.t.sol` (new)

## Branch

`device-wrap-guardian-hats`
