# PoaManagerHub V2: Satellite-Only Admin Calls

## Problem

The current `PoaManagerHub.adminCallCrossChain(target, data)` always executes on the **home chain first**, then broadcasts to all satellites. This breaks when the `target` contract has **different addresses** on different chains.

**Concrete example**: PaymasterHub proxies are at `0xD665...` (Arbitrum) and `0xdEf1...` (Gnosis). Calling `adminCallCrossChain(0xD665..., setSolidarityFee(500))`:
- Arbitrum: calls `0xD665...` (correct PM) — works
- Gnosis: calls `0xD665...` (no code) — silent no-op, fee not set

This prevents governance from managing chain-specific contracts like PaymasterHub, and blocks the Poa Executor from taking over protocol admin duties.

## Solution: Hub V2

Redeploy the Hub with two new functions:

### `adminCallSatelliteOnly(uint32 domain, address target, bytes data)`

Sends a `MSG_ADMIN_CALL` to a **specific satellite** without executing on the home chain. Enables targeting different contract addresses per chain.

```solidity
function adminCallSatelliteOnly(uint32 domain, address target, bytes calldata data)
    external payable onlyOwner
{
    if (paused) revert IsPaused();
    bytes memory payload = abi.encode(MSG_ADMIN_CALL, target, data);

    // Find the satellite for this domain and dispatch
    uint256 len = satellites.length;
    for (uint256 i; i < len;) {
        SatelliteConfig storage sat = satellites[i];
        if (sat.active && sat.domain == domain) {
            mailbox.dispatch{value: msg.value}(sat.domain, sat.satellite, payload);
            emit CrossChainAdminCallDispatched(target, data);
            return;
        }
        unchecked { ++i; }
    }
    revert SatelliteNotActive();
}
```

### `adminCallPerChain(address homeTarget, bytes homeData, uint32 satDomain, address satTarget, bytes satData)`

Executes different admin calls on home chain and a specific satellite in one transaction. Useful for governance proposals that need to update the same setting on both chains with different target addresses.

```solidity
function adminCallPerChain(
    address homeTarget, bytes calldata homeData,
    uint32 satDomain, address satTarget, bytes calldata satData
) external payable onlyOwner {
    if (paused) revert IsPaused();

    // Execute on home chain
    poaManager.adminCall(homeTarget, homeData);

    // Send to specific satellite
    bytes memory payload = abi.encode(MSG_ADMIN_CALL, satTarget, satData);
    // ... find satellite and dispatch
}
```

## Satellite Changes: None

The existing `PoaManagerSatellite.handle()` already processes `MSG_ADMIN_CALL` messages by calling `poaManager.adminCall(target, data)`. No changes needed — the satellite doesn't care whether the message came from `adminCallCrossChain` or `adminCallSatelliteOnly`.

## Migration Plan

### Step 1: Deploy Hub V2

Hub V2 is a new contract (Hub is not upgradeable — plain `Ownable2Step`). Constructor takes the same params: `(poaManager, mailbox)`.

```solidity
constructor(address _poaManager, address _mailbox) Ownable(msg.sender) {
    poaManager = PoaManager(_poaManager);
    mailbox = IMailbox(_mailbox);
}
```

### Step 2: Re-register Satellites

Copy satellite registrations from Hub V1 to Hub V2:
```solidity
hubV2.registerSatellite(100, gnosisSatelliteAddress); // Gnosis domain 100
```

### Step 3: Transfer PoaManager Ownership

The Arbitrum PoaManager is owned by Hub V1. Transfer to Hub V2:
```solidity
// From Hub V1 (as current owner):
hubV1.transferPoaManagerOwnership(address(hubV2));

// Hub V2 accepts:
hubV2.poaManager().acceptOwnership(); // if Ownable2Step
// OR: PoaManager uses Ownable (single-step), so transfer is immediate
```

**Note**: PoaManager uses `Ownable` (not `Ownable2Step`), so `transferOwnership` takes effect immediately. Hub V1's `transferPoaManagerOwnership` calls `poaManager.transferOwnership(newOwner)`.

### Step 4: Transfer Hub V2 Ownership to Governance

Once Hub V2 is operational, transfer its ownership to the Poa Executor:
```solidity
hubV2.transferOwnership(poaExecutorAddress);
// Executor accepts (Ownable2Step on Hub):
// Requires a governance proposal to call hubV2.acceptOwnership()
```

### Step 5: Verify

- Hub V2 owns PoaManager on Arbitrum
- Hub V2 has correct satellite registrations
- `adminCallSatelliteOnly(100, gnosisPaymasterHub, setSolidarityFee(500))` works
- `adminCall(arbPaymasterHub, setSolidarityFee(500))` works
- `upgradeBeaconCrossChain` works as before
- Hub V1 no longer owns anything (can be left in place or abandoned)

## Governance Flow After Migration

With Hub V2 owned by the Poa Executor, governance proposals can:

```
Proposal Option 1: "Raise solidarity fee to 5%"
Batch calls:
  1. Hub.adminCall(ARB_PM, setSolidarityFee(500))           // Arbitrum
  2. Hub.adminCallSatelliteOnly(100, GNOSIS_PM, setSolidarityFee(500))  // Gnosis
```

```
Proposal Option 2: "Upgrade PaymasterHub"
Batch calls:
  1. Hub.upgradeBeaconCrossChain("PaymasterHub", newImpl, "vN")  // Both chains
```

```
Proposal Option 3: "Add whitelist rule for KUBI on Gnosis only"
Batch calls:
  1. Hub.adminCallSatelliteOnly(100, GNOSIS_PM, adminBatchAddRules(...))
```

## Risk Assessment

**Low risk**:
- Satellite contract unchanged — message format identical
- All existing Hub V1 functions preserved in V2
- PoaManager transfer is a single-step operation (Ownable, not Ownable2Step)
- If anything fails, deploy another Hub V3 and transfer PoaManager ownership again

**Medium risk**:
- Brief window during PoaManager ownership transfer where neither Hub controls it
  - Mitigation: do transfer and satellite registration in one script/transaction
- Hub V1 becomes useless after transfer — any cached references (frontends, scripts) need updating

**No risk**:
- Satellite is unaffected — it validates `_sender == hubAddress`, but `hubAddress` is the Hub V1 address. The Hyperlane message from Hub V2 would have `_sender = Hub V2 address`, which doesn't match.

**WAIT — this is a problem.** The Satellite's `hubAddress` is immutable (set in constructor). It checks `_sender == hubAddress`. If we deploy Hub V2 at a different address, the Satellite will reject messages from Hub V2 with `UnauthorizedSender`.

## Satellite Update Required

The Satellite has `hubAddress` as an `immutable`. To accept messages from Hub V2, we need to either:

### Option A: Redeploy Satellite with Hub V2 address (preferred)

Deploy a new Satellite on Gnosis pointing to Hub V2's address. Transfer the Gnosis PoaManager ownership from old Satellite to new Satellite.

```solidity
// On Gnosis:
PoaManagerSatellite newSat = new PoaManagerSatellite(
    gnosisPoaManager,
    gnosisMailbox,
    42161,                    // hubDomain (Arbitrum)
    address(hubV2)            // NEW hub address
);

// Transfer Gnosis PoaManager ownership: old satellite → new satellite
// Old satellite must call:
oldSatellite.transferPoaManagerOwnership(address(newSat));
```

**Problem**: The old Satellite is owned by the deployer (Ownable2Step). `transferPoaManagerOwnership` is `onlyOwner`. So the deployer can do this.

But the Gnosis PoaManager is owned by the old Satellite. `transferOwnership` on the Gnosis PoaManager must be called by the old Satellite (its owner).

The old Satellite doesn't have a `transferPoaManagerOwnership` function... let me check:

Actually — the Satellite IS `Ownable2Step`. Its owner can call any function. But the Satellite doesn't have a function to transfer the PoaManager's ownership. The PoaManager's owner IS the Satellite. To change it, we'd need the Satellite to call `poaManager.transferOwnership(newSatellite)`.

The Satellite doesn't expose this. But `poaManager` is a public immutable, and the Satellite is the owner. We could:
1. Add `transferPoaManagerOwnership` to the Satellite (but it's not upgradeable)
2. Use a Hyperlane message from Hub V1 to call `poaManager.transferOwnership` on Gnosis via `adminCallCrossChain`

Wait — `adminCallCrossChain` calls `poaManager.adminCall(target, data)`, and `adminCall` does `target.call(data)`. If we set `target = gnosisPoaManager` and `data = transferOwnership(newSatellite)`, then:
- `poaManager.adminCall(poaManager, transferOwnership(newSat))`
- The PoaManager calls itself with `transferOwnership`
- `msg.sender` at `transferOwnership` is the PoaManager itself, but `transferOwnership` requires `msg.sender == owner()` which is the Satellite, not the PoaManager.

This doesn't work either. The PoaManager can't transfer its own ownership.

### Option B: Make Satellite's hubAddress mutable (requires new Satellite)

Deploy a new Satellite with a `setHubAddress(address)` function that the owner can call. The deployer (who owns the Satellite) can update the hub address after Hub V2 is deployed.

But the current Satellite can't be modified — it's not upgradeable.

### Option C: Deploy Hub V2 at the SAME address as Hub V1

Use CREATE2/CREATE3 to deploy Hub V2 at Hub V1's address. This requires:
1. Destroying Hub V1 (SELFDESTRUCT was removed in Dencun)
2. Not possible — SELFDESTRUCT no longer destroys contract code

### Resolution: Coordinated Migration Script

The full migration requires:

1. Deploy Hub V2 on Arbitrum
2. Deploy new Satellite on Gnosis (pointing to Hub V2)
3. Hub V1: `adminCallCrossChain(gnosisPoaManager, transferOwnership(newSatellite))`
   - This fails because adminCall targets can't be the PoaManager itself for ownership transfer

Actually, let me reconsider. The Gnosis PoaManager is owned by the old Satellite. The old Satellite has `Ownable2Step` and the deployer is the owner. Does the old Satellite have any way to call arbitrary functions on the PoaManager?

Looking at the Satellite code: it has `poaManager` as immutable and calls `poaManager.upgradeBeacon(...)`, `poaManager.addContractType(...)`, `poaManager.adminCall(...)` in the `handle` function. But there's no owner-callable function to transfer PoaManager ownership.

**The fix**: send a `MSG_ADMIN_CALL` via Hub V1 to the Gnosis Satellite, targeting the **Gnosis PoaManager** with `transferOwnership(newSatellite)`. The Satellite calls `poaManager.adminCall(gnosisPoaManager, transferOwnership(newSat))`. Then `poaManager.adminCall` does `gnosisPoaManager.call(transferOwnership(newSat))`. The `msg.sender` for `transferOwnership` is the PoaManager calling itself. But `owner()` is the old Satellite, not the PoaManager.

This still doesn't work. The only entity that can call `transferOwnership` on the Gnosis PoaManager is the old Satellite.

**Real fix**: Add a `transferPoaManagerOwnership` function to the Satellite. But the Satellite isn't upgradeable.

**Actual resolution**: The Satellite already calls `poaManager.transferOwnership` indirectly — the Hub V1 has `transferPoaManagerOwnership` which calls `poaManager.transferOwnership`. On the home chain this works because Hub V1 owns the Arbitrum PoaManager. On Gnosis, we'd need the Satellite to expose a similar function.

Since the Satellite is `Ownable2Step` and the deployer is the owner, the deployer could:
1. Deploy a new Satellite with `hubAddress = Hub V2`
2. From Hub V1, send a Hyperlane message that the OLD Satellite handles: `MSG_ADMIN_CALL` targeting the Gnosis PoaManager with a call that the PoaManager would execute as `adminCall`. But the PoaManager's `adminCall` is `onlyOwner` (owner = old Satellite).

Wait — let me re-read `PoaManager.adminCall`:
```solidity
function adminCall(address target, bytes calldata data) external onlyOwner returns (bytes memory) {
    (bool success, bytes memory result) = target.call(data);
```

It's `onlyOwner` — only the Satellite can call it on Gnosis. And the Satellite only calls it from `handle()` when receiving Hyperlane messages from Hub V1.

So the flow IS: Hub V1 → Hyperlane → Satellite → `poaManager.adminCall(target, data)` → `target.call(data)`.

If `target = address(poaManager)` and `data = abi.encodeCall(transferOwnership, newSatellite)`:
- Satellite calls `poaManager.adminCall(poaManager, transferOwnership(newSat))`
- PoaManager checks `msg.sender == owner()` → `msg.sender` is the Satellite, `owner()` is the Satellite → passes
- PoaManager does `poaManager.call(transferOwnership(newSat))`
- At `transferOwnership`: `msg.sender` is the PoaManager itself, `owner()` is the Satellite → **fails**

The PoaManager is calling itself, so `msg.sender` at the inner `transferOwnership` is the PoaManager, not the Satellite.

**Final resolution**: Need the Satellite to directly call `poaManager.transferOwnership(newSatellite)`, not via `adminCall`. Add a dedicated Hyperlane message type `MSG_TRANSFER_PM_OWNERSHIP` to the Satellite, OR deploy a new Satellite that includes this function.

Since both Hub and Satellite need redeployment anyway, this is fine — just include it in the new Satellite.

## Revised Migration Plan

### Contracts to Deploy

1. **Hub V2** — Hub V1 + `adminCallSatelliteOnly` + `adminCallPerChain`
2. **Satellite V2** — Satellite V1 + `transferPoaManagerOwnership(address)` owner-callable function + `setHubAddress(address)` owner-callable function (to point to Hub V2 without redeployment)

### Migration Steps

1. Deploy Satellite V2 on Gnosis (pointing to Hub V1 initially)
2. Hub V1: `adminCallCrossChain(gnosisPoaManager, transferOwnership(satelliteV2))` — transfers Gnosis PoaManager to Satellite V2 via the old Satellite
   - Wait, same problem. Old Satellite → `poaManager.adminCall(poaManager, transferOwnership(satV2))` → PoaManager calls itself → fails.
   - **Alternative**: Deploy Satellite V2. Old Satellite owner (deployer) calls... the old Satellite has no `transferPoaManagerOwnership`.

   Actually — PoaManager uses `Ownable` (single-step), not `Ownable2Step`. Let me check:

```solidity
contract PoaManager is Ownable(msg.sender) {
```

It's `Ownable` with `msg.sender` as initial owner. But the Satellite deployed the PoaManager? No — the PoaManager was deployed separately, then ownership was transferred to the Satellite.

The current Gnosis PoaManager owner is the old Satellite (`0x4Ad7...`). To transfer ownership, the old Satellite must call `poaManager.transferOwnership(newOwner)`. The old Satellite doesn't have a function for this.

**Breakthrough**: The PoaManager's `adminCall` is `onlyOwner` and does `target.call(data)`. If we call `adminCall(address(poaManager), abi.encodeCall(Ownable.transferOwnership, (newSatellite)))`:
- Satellite calls `poaManager.adminCall(poaManager, transferOwnership(newSat))`
- `adminCall` checks `msg.sender == owner()` → Satellite == Satellite → passes
- `adminCall` does `address(poaManager).call(transferOwnership(newSat))`
- This is the PoaManager calling its own `transferOwnership`
- At `transferOwnership`: `msg.sender = poaManager` (self-call), `owner() = satellite` → **FAILS**

The self-call problem is fundamental. `adminCall` wraps the call, changing `msg.sender`.

**Real solution**: Add `transferPoaManagerOwnership` to Satellite V2, OR:

Use a helper contract deployed on Gnosis that the old Satellite can call via `adminCall`:

```solidity
contract OwnershipHelper {
    function transferOwnership(address pm, address newOwner) external {
        Ownable(pm).transferOwnership(newOwner);
    }
}
```

Then: Hub V1 → `adminCallCrossChain(helperAddress, transferOwnership(poaManager, newSatellite))` → Satellite → `poaManager.adminCall(helper, ...)` → helper calls `poaManager.transferOwnership(newSat)`.

At `transferOwnership`: `msg.sender = helper`, `owner() = satellite` → **still fails**.

The issue is that NO intermediary can call `transferOwnership` because only the direct owner (Satellite) can. And `adminCall` always introduces the PoaManager as an intermediary.

**Actual final solution**: The deployer owns the Satellite (Ownable2Step). Add a simple pass-through to the new Satellite, but since we can't modify the old one...

Actually, the old Satellite IS Ownable2Step and the deployer is the owner. But the Satellite has NO function to call `poaManager.transferOwnership`. The only way to do it is via Hyperlane messages (which go through `handle()` → `poaManager.adminCall()`), and `adminCall` changes `msg.sender`.

**TRUE FINAL SOLUTION**: Deploy Satellite V2 with `hubAddress = Hub V2`. The deployer transfers Gnosis PoaManager ownership by having Hub V1 send a special message... no, that still doesn't work.

The only way is to add a function to the Satellite that directly calls `poaManager.transferOwnership`. Since the current Satellite can't be modified, we need an alternative approach:

The PoaManager's `transferOwnership` is `Ownable.transferOwnership(address)` which requires `msg.sender == owner()`. The owner is the old Satellite. The old Satellite can only call `poaManager` functions through `handle()` → `adminCall()`, which wraps the call.

**Unless**: we can get the old Satellite to execute arbitrary code as itself (not through the PoaManager). But the Satellite only exposes `handle()` for external calls (besides ownership functions).

The old Satellite's owner (deployer) can call... let me check what `Ownable2Step` exposes: `transferOwnership(address)`, `acceptOwnership()`, `renounceOwnership()` (reverts), `owner()`. None of these help.

**CONCLUSION**: Transferring the Gnosis PoaManager ownership from the old Satellite to a new Satellite requires deploying a new PoaManager on Gnosis (with the new Satellite as initial owner), and migrating all beacon registrations. OR: deploy a modified version of the old Satellite that includes `transferPoaManagerOwnership`.

Since deploying a new Satellite requires a new PoaManager (to set the correct initial owner), the migration is:

1. Deploy new PoaManager on Gnosis (owned by deployer initially)
2. Deploy Satellite V2 on Gnosis (pointing to new PoaManager + Hub V2)
3. Transfer new PoaManager ownership to Satellite V2
4. Re-register all beacons on the new PoaManager (copy from old)
5. Upgrade all beacon proxies to point to the new PoaManager's beacons
6. Deploy Hub V2 on Arbitrum, register new Satellite V2
7. Transfer Arbitrum PoaManager from Hub V1 to Hub V2

This is a significant migration but fully scriptable.

## Timeline Estimate

- Hub V2 contract: 1 hour (add 2 functions to existing Hub)
- Satellite V2 contract: 30 min (add `transferPoaManagerOwnership`)
- Migration script: 2-3 hours (multi-step, multi-chain, with verification)
- Testing: 2-3 hours (fork tests for the full migration)
- Execution: 30 min (run scripts + wait for Hyperlane)

## Alternative: Minimal Fix

If the full migration is too risky right now, continue using `protocolAdmin` on PaymasterHub for Gnosis-specific admin calls. This works for all PaymasterHub functions that accept `protocolAdmin` (currently `adminBatchAddRules` and `setSolidarityFee` in v18). Add `protocolAdmin` to more functions as needed.

The governance handoff (deployer → Poa Executor) can still happen for Arbitrum-only operations via Hub V1. Gnosis operations go through `protocolAdmin` (a multisig or the Executor directly).
