#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# testnet-e2e.sh - End-to-end cross-chain test suite
#
# Tests the full cross-chain flow:
#   Sepolia (home) <--Hyperlane--> Base Sepolia (satellite)
#
# Test 1: Cross-chain beacon upgrade (MSG_UPGRADE_BEACON)
# Test 2: Cross-chain admin call   (MSG_ADMIN_CALL)
#
# Prerequisites:
#   - .env with PRIVATE_KEY (funded on both Sepolia and Base Sepolia)
#   - forge build must succeed
#   - jq (for JSON parsing: brew install jq)
#
# Usage:
#   ./script/testnet-e2e.sh                # Full deploy + all tests
#   ./script/testnet-e2e.sh --skip-deploy  # Skip infrastructure, run tests only
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/e2e/e2e-state.json"

# ── Chain Configuration ──
HOME_RPC="sepolia"
HOME_DOMAIN=11155111
HOME_MAILBOX="0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766"

SAT_RPC="base-sepolia"
SAT_DOMAIN=84532
SAT_MAILBOX="0x6966b0E55883d49BFB24539356a2f8A673E02039"

# ── Load Environment ──
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a
    source "$PROJECT_DIR/.env"
    set +a
fi

# Support both PRIVATE_KEY and DEPLOYER_PRIVATE_KEY
if [ -z "${PRIVATE_KEY:-}" ] && [ -n "${DEPLOYER_PRIVATE_KEY:-}" ]; then
    export PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY"
fi

if [ -z "${PRIVATE_KEY:-}" ]; then
    echo "ERROR: PRIVATE_KEY (or DEPLOYER_PRIVATE_KEY) not set in .env"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq required for JSON parsing. Install with: brew install jq"
    exit 1
fi

# ── Helper: extract JSON field ──
json_get() {
    jq -r ".$2" "$1"
}

echo "============================================================"
echo "  POA Cross-Chain E2E Test"
echo "  Home:      Sepolia (domain $HOME_DOMAIN)"
echo "  Satellite: Base Sepolia (domain $SAT_DOMAIN)"
echo "============================================================"
echo ""

###########################################################################
# STEP 0: Build
###########################################################################
echo ">>> STEP 0: Building contracts..."
cd "$PROJECT_DIR"
forge build --silent
echo "    Build complete."
echo ""

if [ "${1:-}" != "--skip-deploy" ]; then

###########################################################################
# STEP 1: Deploy DeterministicDeployer on BOTH chains
###########################################################################
echo ">>> STEP 1a: Deploy DeterministicDeployer on Sepolia..."
forge script script/DeployDeterministicDeployer.s.sol:DeployDeterministicDeployer \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow \
    2>&1 | tee /tmp/e2e-dd-home.log
echo ""

echo ">>> STEP 1b: Deploy DeterministicDeployer on Base Sepolia..."
forge script script/DeployDeterministicDeployer.s.sol:DeployDeterministicDeployer \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow \
    2>&1 | tee /tmp/e2e-dd-sat.log
echo ""

# Extract DeterministicDeployer address (same on both chains via CREATE2)
# Handle both fresh deploy ("Deployed at:") and idempotent re-run ("Already deployed at:")
DD_ADDR=$(grep "Already deployed at:" /tmp/e2e-dd-home.log 2>/dev/null | awk '{print $NF}' || echo "")
if [ -z "$DD_ADDR" ]; then
    DD_ADDR=$(grep "Deployed at:" /tmp/e2e-dd-home.log 2>/dev/null | awk '{print $NF}' || echo "")
fi
if [ -z "$DD_ADDR" ]; then
    DD_ADDR=$(grep "Predicted address:" /tmp/e2e-dd-home.log 2>/dev/null | awk '{print $NF}' || echo "")
fi

if [ -z "$DD_ADDR" ]; then
    echo "ERROR: Could not extract DeterministicDeployer address from logs."
    echo "Check /tmp/e2e-dd-home.log for details."
    exit 1
fi
echo "    DeterministicDeployer: $DD_ADDR"
echo ""

###########################################################################
# STEP 2: Deploy Home Chain Infrastructure
###########################################################################
echo ">>> STEP 2: Deploy Home Chain (PoaManager + Hub + HybridVoting v1)..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
MAILBOX=$HOME_MAILBOX \
forge script script/e2e/TestnetE2EHomeChain.s.sol:TestnetE2EHomeChain \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

HUB_ADDR=$(json_get "$STATE_FILE" "homeChain.hub")
HOME_PM=$(json_get "$STATE_FILE" "homeChain.poaManager")
echo "    Hub: $HUB_ADDR"
echo "    Home PoaManager: $HOME_PM"
echo ""

###########################################################################
# STEP 3: Deploy Satellite Infrastructure
###########################################################################
echo ">>> STEP 3: Deploy Satellite (PoaManager + Satellite + HybridVoting v1)..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
HUB_DOMAIN=$HOME_DOMAIN \
HUB_ADDRESS=$HUB_ADDR \
MAILBOX=$SAT_MAILBOX \
forge script script/e2e/TestnetE2ESatellite.s.sol:TestnetE2ESatellite \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo ""

SAT_ADDR=$(json_get "$STATE_FILE" "satellite.satellite")
SAT_PM=$(json_get "$STATE_FILE" "satellite.poaManager")
echo "    Satellite: $SAT_ADDR"
echo "    Satellite PoaManager: $SAT_PM"
echo ""

###########################################################################
# STEP 4: Register Satellite on Hub
###########################################################################
echo ">>> STEP 4: Register satellite on Hub..."
HUB=$HUB_ADDR \
SATELLITE_DOMAIN=$SAT_DOMAIN \
SATELLITE_ADDRESS=$SAT_ADDR \
forge script script/e2e/RegisterSatellite.s.sol:RegisterSatellite \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo "    Satellite registered."
echo ""

###########################################################################
# STEP 4b: Register infra types on BOTH chains (for infra upgrade test)
###########################################################################
echo ">>> STEP 4b: Register infra types (OrgDeployer, PaymasterHub, UniversalAccountRegistry)..."

echo "    Home chain (via Hub)..."
HUB=$HUB_ADDR \
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/InfraUpgradeE2E.s.sol:RegisterInfraTypesHome \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

echo "    Satellite (via Satellite)..."
SATELLITE=$SAT_ADDR \
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/InfraUpgradeE2E.s.sol:RegisterInfraTypesSatellite \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo "    Infra types registered on both chains."
echo ""

else
    # --skip-deploy: Read state from existing JSON
    echo ">>> Skipping deployment, reading existing state..."
    if [ ! -f "$STATE_FILE" ]; then
        echo "ERROR: --skip-deploy requires existing $STATE_FILE"
        exit 1
    fi
    DD_ADDR=$(json_get "$STATE_FILE" "deterministicDeployer")
    HUB_ADDR=$(json_get "$STATE_FILE" "homeChain.hub")
    HOME_PM=$(json_get "$STATE_FILE" "homeChain.poaManager")
    SAT_ADDR=$(json_get "$STATE_FILE" "satellite.satellite")
    SAT_PM=$(json_get "$STATE_FILE" "satellite.poaManager")
    echo "    DeterministicDeployer: $DD_ADDR"
    echo "    Hub: $HUB_ADDR"
    echo "    Satellite: $SAT_ADDR"
    echo ""
fi

###########################################################################
#  TEST 1: Cross-Chain Beacon Upgrade (MSG_UPGRADE_BEACON)
###########################################################################
echo "============================================================"
echo "  TEST 1: Cross-Chain Beacon Upgrade"
echo "============================================================"
echo ""

###########################################################################
# STEP 5: Deploy HybridVoting v2 on BOTH chains
###########################################################################
echo ">>> STEP 5a: Deploy HybridVoting v2 on Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/DeployV2AndUpgrade.s.sol:DeployV2Impl \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

echo ">>> STEP 5b: Deploy HybridVoting v2 on Base Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/DeployV2AndUpgrade.s.sol:DeployV2Impl \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo ""

###########################################################################
# STEP 6: Trigger cross-chain upgrade from Hub (skip if already applied)
###########################################################################
echo ">>> STEP 6: Trigger cross-chain upgrade..."
if POAMANAGER=$HOME_PM \
   DETERMINISTIC_DEPLOYER=$DD_ADDR \
   forge script script/e2e/VerifyUpgrade.s.sol:VerifyUpgrade \
       --rpc-url $HOME_RPC 2>&1 | grep -q "PASS"; then
    echo "    Already upgraded — skipping trigger."
else
    HUB=$HUB_ADDR \
    DETERMINISTIC_DEPLOYER=$DD_ADDR \
    forge script script/e2e/DeployV2AndUpgrade.s.sol:TriggerCrossChainUpgrade \
        --rpc-url $HOME_RPC \
        --broadcast \
        --slow
fi
echo ""

###########################################################################
# STEP 7: Verify home chain immediately
###########################################################################
echo ">>> STEP 7: Verify home chain upgrade..."
POAMANAGER=$HOME_PM \
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/VerifyUpgrade.s.sol:VerifyUpgrade \
    --rpc-url $HOME_RPC
echo "    Home chain verified."
echo ""

###########################################################################
# STEP 8: Poll satellite chain (Hyperlane relay ~2-5 min)
###########################################################################
echo ">>> STEP 8: Waiting for Hyperlane relay to Base Sepolia..."
echo "    Polling every 30s, max 10 minutes."
echo ""

MAX_ATTEMPTS=20
ATTEMPT=0
UPGRADE_OK=false
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Attempt $ATTEMPT/$MAX_ATTEMPTS..."

    if POAMANAGER=$SAT_PM \
       DETERMINISTIC_DEPLOYER=$DD_ADDR \
       forge script script/e2e/VerifyUpgrade.s.sol:VerifyUpgrade \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        echo ""
        echo "  >> Cross-chain upgrade verified on both chains!"
        echo "     Home (Sepolia):          HybridVoting beacon -> V2"
        echo "     Satellite (Base Sepolia): HybridVoting beacon -> V2"
        echo ""
        UPGRADE_OK=true
        break
    fi

    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "    Not yet upgraded. Sleeping 30s..."
        sleep 30
    fi
done

if [ "$UPGRADE_OK" != "true" ]; then
    echo ""
    echo "  >> WARNING: Satellite upgrade not verified after 10 minutes."
    echo "     Hyperlane relay may be slow. Continuing to admin call test..."
    echo ""
fi

###########################################################################
#  TEST 2: Cross-Chain Admin Call (MSG_ADMIN_CALL)
###########################################################################
echo "============================================================"
echo "  TEST 2: Cross-Chain Admin Call"
echo "============================================================"
echo ""

###########################################################################
# STEP 9: Deploy AdminCallTarget on BOTH chains
###########################################################################
echo ">>> STEP 9a: Deploy AdminCallTarget on Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/TriggerAdminCall.s.sol:DeployAdminCallTarget \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

echo ">>> STEP 9b: Deploy AdminCallTarget on Base Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/TriggerAdminCall.s.sol:DeployAdminCallTarget \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo ""

###########################################################################
# STEP 10: Trigger cross-chain admin call from Hub (skip if already applied)
###########################################################################
echo ">>> STEP 10: Trigger cross-chain admin call (setValue(42))..."
if DETERMINISTIC_DEPLOYER=$DD_ADDR \
   forge script script/e2e/VerifyAdminCall.s.sol:VerifyAdminCall \
       --rpc-url $HOME_RPC 2>&1 | grep -q "PASS"; then
    echo "    Already applied — skipping trigger."
else
    HUB=$HUB_ADDR \
    DETERMINISTIC_DEPLOYER=$DD_ADDR \
    forge script script/e2e/TriggerAdminCall.s.sol:TriggerAdminCall \
        --rpc-url $HOME_RPC \
        --broadcast \
        --slow
fi
echo ""

###########################################################################
# STEP 11: Verify home chain admin call immediately
###########################################################################
echo ">>> STEP 11: Verify home chain admin call (should be instant)..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/VerifyAdminCall.s.sol:VerifyAdminCall \
    --rpc-url $HOME_RPC
echo "    Home chain admin call verified."
echo ""

###########################################################################
# STEP 12: Poll satellite chain for admin call (Hyperlane relay ~2-5 min)
###########################################################################
echo ">>> STEP 12: Waiting for Hyperlane relay of admin call to Base Sepolia..."
echo "    Polling every 30s, max 10 minutes."
echo ""

MAX_ATTEMPTS=20
ATTEMPT=0
ADMIN_CALL_OK=false
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Attempt $ATTEMPT/$MAX_ATTEMPTS..."

    if DETERMINISTIC_DEPLOYER=$DD_ADDR \
       forge script script/e2e/VerifyAdminCall.s.sol:VerifyAdminCall \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        echo ""
        echo "  >> Cross-chain admin call verified on both chains!"
        echo "     Home (Sepolia):          AdminCallTarget.value() == 42"
        echo "     Satellite (Base Sepolia): AdminCallTarget.value() == 42"
        echo ""
        ADMIN_CALL_OK=true
        break
    fi

    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "    Not yet applied. Sleeping 30s..."
        sleep 30
    fi
done

if [ "$ADMIN_CALL_OK" != "true" ]; then
    echo ""
    echo "  >> WARNING: Satellite admin call not verified after 10 minutes."
    echo "     This may be normal -- Hyperlane relay can take longer on testnets."
    echo "     Check the Hyperlane Explorer: https://explorer.hyperlane.xyz"
    echo ""
    echo "     Re-run verification manually:"
    echo "     DETERMINISTIC_DEPLOYER=$DD_ADDR \\"
    echo "       forge script script/e2e/VerifyAdminCall.s.sol:VerifyAdminCall \\"
    echo "       --rpc-url base-sepolia"
    echo ""
fi

###########################################################################
#  TEST 3: Cross-Chain Infra Beacon Upgrades
#  (OrgDeployer, PaymasterHub, UniversalAccountRegistry)
###########################################################################
echo "============================================================"
echo "  TEST 3: Cross-Chain Infra Beacon Upgrades"
echo "============================================================"
echo ""

###########################################################################
# STEP 13: Deploy infra v2 implementations on BOTH chains
###########################################################################
echo ">>> STEP 13a: Deploy infra v2 implementations on Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/InfraUpgradeE2E.s.sol:DeployInfraV2 \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

echo ">>> STEP 13b: Deploy infra v2 implementations on Base Sepolia..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/InfraUpgradeE2E.s.sol:DeployInfraV2 \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo ""

###########################################################################
# STEP 14: Trigger cross-chain infra upgrades from Hub (skip if already applied)
###########################################################################
echo ">>> STEP 14: Trigger cross-chain infra upgrades..."
if POAMANAGER=$HOME_PM \
   DETERMINISTIC_DEPLOYER=$DD_ADDR \
   forge script script/e2e/InfraUpgradeE2E.s.sol:VerifyInfraUpgrade \
       --rpc-url $HOME_RPC 2>&1 | grep -q "PASS"; then
    echo "    Already upgraded — skipping trigger."
else
    HUB=$HUB_ADDR \
    DETERMINISTIC_DEPLOYER=$DD_ADDR \
    forge script script/e2e/InfraUpgradeE2E.s.sol:TriggerCrossChainInfraUpgrade \
        --rpc-url $HOME_RPC \
        --broadcast \
        --slow
fi
echo ""

###########################################################################
# STEP 15: Verify home chain infra upgrades immediately
###########################################################################
echo ">>> STEP 15: Verify home chain infra upgrades (should be instant)..."
POAMANAGER=$HOME_PM \
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/InfraUpgradeE2E.s.sol:VerifyInfraUpgrade \
    --rpc-url $HOME_RPC
echo "    Home chain infra upgrades verified."
echo ""

###########################################################################
# STEP 16: Poll satellite chain for infra upgrades
###########################################################################
echo ">>> STEP 16: Waiting for Hyperlane relay of infra upgrades to Base Sepolia..."
echo "    Polling every 30s, max 10 minutes."
echo ""

MAX_ATTEMPTS=20
ATTEMPT=0
INFRA_UPGRADE_OK=false
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Attempt $ATTEMPT/$MAX_ATTEMPTS..."

    if POAMANAGER=$SAT_PM \
       DETERMINISTIC_DEPLOYER=$DD_ADDR \
       forge script script/e2e/InfraUpgradeE2E.s.sol:VerifyInfraUpgrade \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        echo ""
        echo "  >> Cross-chain infra upgrades verified on both chains!"
        echo "     OrgDeployer, PaymasterHub, UniversalAccountRegistry -> v2"
        echo ""
        INFRA_UPGRADE_OK=true
        break
    fi

    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "    Not yet upgraded. Sleeping 30s..."
        sleep 30
    fi
done

if [ "$INFRA_UPGRADE_OK" != "true" ]; then
    echo ""
    echo "  >> WARNING: Satellite infra upgrades not verified after 10 minutes."
    echo "     Check the Hyperlane Explorer: https://explorer.hyperlane.xyz"
    echo ""
fi

###########################################################################
#  TEST 4: Admin Call → Real Infra Config
#  Calls registerImplementation() on the ImplementationRegistry (onlyOwner,
#  where owner == PoaManager). This is the exact same access-control path
#  that real infra config changes use (PaymasterHub, OrgDeployer, etc.)
###########################################################################
echo "============================================================"
echo "  TEST 4: Real Infra Config (admin call → ImplementationRegistry)"
echo "============================================================"
echo ""

INFRA_CONFIG_OK=false
HOME_REG=$(json_get "$STATE_FILE" "homeChain.implRegistry")
SAT_REG=$(json_get "$STATE_FILE" "satellite.implRegistry")
echo "    Home ImplementationRegistry:      $HOME_REG"
echo "    Satellite ImplementationRegistry: $SAT_REG"
echo ""

###########################################################################
# STEP 17: Config home chain ImplementationRegistry via Hub.adminCall
#          (skip if already applied — VersionExists revert on re-run)
###########################################################################
echo ">>> STEP 17: Config home ImplementationRegistry via Hub.adminCall..."
echo "    Hub.adminCall(implRegistry, registerImplementation('E2EConfigTest','v1',addr,true))"
echo "    implRegistry checks: onlyOwner (owner == PoaManager)"
if IMPL_REGISTRY=$HOME_REG \
   forge script script/e2e/InfraConfigE2E.s.sol:VerifyInfraConfig \
       --rpc-url $HOME_RPC 2>&1 | grep -q "PASS"; then
    echo "    Already configured — skipping trigger."
else
    HUB=$HUB_ADDR \
    IMPL_REGISTRY=$HOME_REG \
    forge script script/e2e/InfraConfigE2E.s.sol:TriggerInfraConfig \
        --rpc-url $HOME_RPC \
        --broadcast \
        --slow
fi
echo ""

###########################################################################
# STEP 18: Verify home chain config
###########################################################################
echo ">>> STEP 18: Verify home chain ImplementationRegistry config..."
IMPL_REGISTRY=$HOME_REG \
forge script script/e2e/InfraConfigE2E.s.sol:VerifyInfraConfig \
    --rpc-url $HOME_RPC
echo ""

###########################################################################
# STEP 19: Config satellite ImplementationRegistry via Satellite.adminCall
#          (skip if already applied — VersionExists revert on re-run)
###########################################################################
echo ">>> STEP 19: Config satellite ImplementationRegistry via Satellite.adminCall..."
echo "    Satellite.adminCall(implRegistry, registerImplementation('E2EConfigTest','v1',addr,true))"
echo "    implRegistry checks: onlyOwner (owner == PoaManager)"
if IMPL_REGISTRY=$SAT_REG \
   forge script script/e2e/InfraConfigE2E.s.sol:VerifyInfraConfig \
       --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
    echo "    Already configured — skipping trigger."
else
    SATELLITE=$SAT_ADDR \
    IMPL_REGISTRY=$SAT_REG \
    forge script script/e2e/InfraConfigE2E.s.sol:TriggerInfraConfigSatellite \
        --rpc-url $SAT_RPC \
        --broadcast \
        --slow
fi
echo ""

###########################################################################
# STEP 20: Verify satellite config (retry a few times for RPC consistency)
###########################################################################
echo ">>> STEP 20: Verify satellite ImplementationRegistry config..."
echo "    (Retrying up to 5 times for RPC eventual consistency)"

VERIFY_ATTEMPTS=5
VERIFY_I=0
while [ $VERIFY_I -lt $VERIFY_ATTEMPTS ]; do
    VERIFY_I=$((VERIFY_I + 1))
    if IMPL_REGISTRY=$SAT_REG \
       forge script script/e2e/InfraConfigE2E.s.sol:VerifyInfraConfig \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        echo ""
        echo "  >> Infra config verified on both chains!"
        echo "     Home:      Hub.adminCall -> PM -> implRegistry.registerImplementation"
        echo "     Satellite: Satellite.adminCall -> PM -> implRegistry.registerImplementation"
        echo "     (ImplementationRegistry.onlyOwner passed - PoaManager is confirmed caller)"
        echo ""
        INFRA_CONFIG_OK=true
        break
    fi
    if [ $VERIFY_I -lt $VERIFY_ATTEMPTS ]; then
        echo "    Attempt $VERIFY_I/$VERIFY_ATTEMPTS - not yet visible, retrying in 10s..."
        sleep 10
    fi
done

if [ "$INFRA_CONFIG_OK" != "true" ]; then
    echo ""
    echo "  >> FAIL: Satellite infra config not applied after $VERIFY_ATTEMPTS attempts."
    echo ""
fi

###########################################################################
# SUMMARY
###########################################################################
echo "============================================================"
echo "  E2E Test Results"
echo "============================================================"
if [ "$UPGRADE_OK" = "true" ]; then
    echo "  TEST 1 (Beacon Upgrade):       PASS"
else
    echo "  TEST 1 (Beacon Upgrade):       TIMEOUT (check manually)"
fi
if [ "$ADMIN_CALL_OK" = "true" ]; then
    echo "  TEST 2 (Admin Call):           PASS"
else
    echo "  TEST 2 (Admin Call):           TIMEOUT (check manually)"
fi
if [ "$INFRA_UPGRADE_OK" = "true" ]; then
    echo "  TEST 3 (Infra Upgrades):       PASS"
else
    echo "  TEST 3 (Infra Upgrades):       TIMEOUT (check manually)"
fi
if [ "$INFRA_CONFIG_OK" = "true" ]; then
    echo "  TEST 4 (Gated Infra Config):   PASS"
else
    echo "  TEST 4 (Gated Infra Config):   FAIL"
fi
echo "============================================================"

if [ "$UPGRADE_OK" = "true" ] && [ "$ADMIN_CALL_OK" = "true" ] && [ "$INFRA_UPGRADE_OK" = "true" ] && [ "$INFRA_CONFIG_OK" = "true" ]; then
    exit 0
else
    exit 1
fi
