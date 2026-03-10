#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# testnet-e2e.sh - End-to-end cross-chain test suite
#
# Tests the full cross-chain flow:
#   Sepolia (home) <--Hyperlane--> Base Sepolia (satellite)
#
# Test Coverage:
#   1. Cross-chain beacon upgrades (HybridVoting v1 -> v2)
#   2. Cross-chain name registry (username + org name claims)
#   3. Satellite org deployment (org name uniqueness via cross-chain)
#   4. Satellite onboarding infrastructure verification
#
# Prerequisites:
#   - .env with PRIVATE_KEY (funded on both Sepolia and Base Sepolia)
#   - forge build must succeed
#   - jq (for JSON parsing: brew install jq)
#
# Usage:
#   ./script/testnet-e2e.sh                # Full deploy + all tests
#   ./script/testnet-e2e.sh --skip-deploy  # Skip infrastructure, test upgrade only
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
echo ">>> STEP 2: Deploy Home Chain (PoaManager + Hub + UAR + NameRegistryHub)..."
DETERMINISTIC_DEPLOYER=$DD_ADDR \
MAILBOX=$HOME_MAILBOX \
forge script script/e2e/TestnetE2EHomeChain.s.sol:TestnetE2EHomeChain \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

HUB_ADDR=$(json_get "$STATE_FILE" "homeChain.hub")
NAME_HUB_ADDR=$(json_get "$STATE_FILE" "homeChain.nameRegistryHub")
HOME_PM=$(json_get "$STATE_FILE" "homeChain.poaManager")
HOME_UAR=$(json_get "$STATE_FILE" "homeChain.uar")
echo "    PoaManagerHub: $HUB_ADDR"
echo "    NameRegistryHub: $NAME_HUB_ADDR"
echo "    UAR: $HOME_UAR"
echo "    Home PoaManager: $HOME_PM"
echo ""

###########################################################################
# STEP 3: Deploy Full Satellite Infrastructure
###########################################################################
echo ">>> STEP 3: Deploy Satellite (full infra: PoaManager, Satellite, RegistryRelay,"
echo "            NameClaimAdapter, OrgRegistry, OrgDeployer, factories, PaymasterHub)..."
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
RELAY_ADDR=$(json_get "$STATE_FILE" "satellite.registryRelay")
echo "    Satellite: $SAT_ADDR"
echo "    RegistryRelay: $RELAY_ADDR"
echo "    Satellite PoaManager: $SAT_PM"
echo ""

###########################################################################
# STEP 4: Register Satellite on Hub + RegistryRelay on NameRegistryHub
###########################################################################
echo ">>> STEP 4: Register satellite + relay on hubs..."
HUB=$HUB_ADDR \
NAME_HUB=$NAME_HUB_ADDR \
SATELLITE_DOMAIN=$SAT_DOMAIN \
SATELLITE_ADDRESS=$SAT_ADDR \
RELAY_ADDRESS=$RELAY_ADDR \
forge script script/e2e/RegisterSatellite.s.sol:RegisterSatellite \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo "    Satellite + relay registered."
echo ""

###########################################################################
# STEP 4b: Dispatch Name Registry Tests on Satellite
###########################################################################
echo ">>> STEP 4b: Dispatch name registry test on satellite..."
RELAY=$RELAY_ADDR \
forge script script/e2e/DispatchNameRegistryTest.s.sol:DispatchNameRegistryTest \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow
echo "    Name registry test dispatched (username + org name)."
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
    NAME_HUB_ADDR=$(json_get "$STATE_FILE" "homeChain.nameRegistryHub")
    HOME_PM=$(json_get "$STATE_FILE" "homeChain.poaManager")
    HOME_UAR=$(json_get "$STATE_FILE" "homeChain.uar")
    SAT_ADDR=$(json_get "$STATE_FILE" "satellite.satellite")
    SAT_PM=$(json_get "$STATE_FILE" "satellite.poaManager")
    RELAY_ADDR=$(json_get "$STATE_FILE" "satellite.registryRelay")
    echo "    DeterministicDeployer: $DD_ADDR"
    echo "    Hub: $HUB_ADDR"
    echo "    NameRegistryHub: $NAME_HUB_ADDR"
    echo "    Satellite: $SAT_ADDR"
    echo "    RegistryRelay: $RELAY_ADDR"
    echo ""
fi

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
# STEP 6: Trigger cross-chain upgrade from Hub
###########################################################################
echo ">>> STEP 6: Trigger cross-chain upgrade..."
HUB=$HUB_ADDR \
DETERMINISTIC_DEPLOYER=$DD_ADDR \
forge script script/e2e/DeployV2AndUpgrade.s.sol:TriggerCrossChainUpgrade \
    --rpc-url $HOME_RPC \
    --broadcast \
    --slow
echo ""

###########################################################################
# STEP 7: Verify home chain immediately
###########################################################################
echo ">>> STEP 7: Verify home chain upgrade (should be instant)..."
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

UPGRADE_OK=false
MAX_ATTEMPTS=20
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "    Attempt $ATTEMPT/$MAX_ATTEMPTS..."

    if POAMANAGER=$SAT_PM \
       DETERMINISTIC_DEPLOYER=$DD_ADDR \
       forge script script/e2e/VerifyUpgrade.s.sol:VerifyUpgrade \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        UPGRADE_OK=true
        echo "    Upgrade verified on satellite."
        break
    fi

    if [ $ATTEMPT -lt $MAX_ATTEMPTS ]; then
        echo "    Not yet upgraded. Sleeping 30s..."
        sleep 30
    fi
done
echo ""

###########################################################################
# STEP 9: Verify Name Registry on Home Chain
###########################################################################
echo ">>> STEP 9: Verify name registry on home chain..."
echo "    Checking username + org name were registered via cross-chain relay."
echo ""

# Derive deployer address from private key
USER_ADDR=$(cast wallet address --private-key $PRIVATE_KEY)

NAME_REG_OK=false
NR_MAX_ATTEMPTS=20
NR_ATTEMPT=0
while [ $NR_ATTEMPT -lt $NR_MAX_ATTEMPTS ]; do
    NR_ATTEMPT=$((NR_ATTEMPT + 1))
    echo "    Attempt $NR_ATTEMPT/$NR_MAX_ATTEMPTS..."

    if UAR=$HOME_UAR \
       NAME_HUB=$NAME_HUB_ADDR \
       USER=$USER_ADDR \
       forge script script/e2e/VerifyNameRegistry.s.sol:VerifyNameRegistry \
           --rpc-url $HOME_RPC 2>&1 | grep -q "PASS"; then
        NAME_REG_OK=true
        echo "    Name registry verified on home chain."
        break
    fi

    if [ $NR_ATTEMPT -lt $NR_MAX_ATTEMPTS ]; then
        echo "    Not yet synced. Sleeping 30s..."
        sleep 30
    fi
done
echo ""

###########################################################################
# STEP 10: Deploy Org on Satellite Chain (optimistic — no pre-confirmation needed)
###########################################################################
echo ">>> STEP 10: Deploy org on satellite chain (optimistic org name claim)..."
SAT_ORG_OK=false
if forge script script/e2e/DeploySatelliteOrg.s.sol:DeploySatelliteOrg \
    --rpc-url $SAT_RPC \
    --broadcast \
    --slow 2>&1 | tee /tmp/e2e-sat-org.log; then
    SAT_ORG_OK=true
    echo "    Satellite org deployed (org name claim dispatched optimistically)."
else
    echo "    Satellite org deployment failed."
fi
echo ""

###########################################################################
# STEP 11: Verify Satellite Onboarding Infrastructure
###########################################################################
SAT_ONBOARD_OK=false
if $SAT_ORG_OK; then
    echo ">>> STEP 11: Verify satellite onboarding infrastructure..."
    if forge script script/e2e/TestSatelliteOnboarding.s.sol:TestSatelliteOnboarding \
        --rpc-url $SAT_RPC \
        --broadcast \
        --slow 2>&1 | grep -q "PASS"; then
        SAT_ONBOARD_OK=true
        echo "    Satellite onboarding infrastructure verified."
    else
        echo "    Satellite onboarding verification failed."
    fi
    echo ""
fi

###########################################################################
# STEP 12: Verify Org Name Round-Trip on Satellite (Hyperlane confirmation)
###########################################################################
echo ">>> STEP 12: Verify org name confirmed back on satellite relay..."
echo "    Waiting for Hyperlane to deliver MSG_CONFIRM_ORG_NAME to satellite."
echo "    (Org already deployed optimistically — this just confirms the name.)"
echo ""

ORG_NAME_SAT_OK=false
ON_MAX_ATTEMPTS=20
ON_ATTEMPT=0
while [ $ON_ATTEMPT -lt $ON_MAX_ATTEMPTS ]; do
    ON_ATTEMPT=$((ON_ATTEMPT + 1))
    echo "    Attempt $ON_ATTEMPT/$ON_MAX_ATTEMPTS..."

    if RELAY=$RELAY_ADDR \
       ORG_NAME="E2ETestOrg" \
       forge script script/e2e/VerifySatelliteOrgName.s.sol:VerifySatelliteOrgName \
           --rpc-url $SAT_RPC 2>&1 | grep -q "PASS"; then
        ORG_NAME_SAT_OK=true
        echo "    Org name confirmed on satellite relay."
        break
    fi

    if [ $ON_ATTEMPT -lt $ON_MAX_ATTEMPTS ]; then
        echo "    Not yet confirmed. Sleeping 30s..."
        sleep 30
    fi
done
echo ""

###########################################################################
# Final Results
###########################################################################
echo "============================================================"
echo "  E2E Test Results"
echo "============================================================"
echo ""

if $UPGRADE_OK; then
    echo "  [PASS] Cross-chain beacon upgrade"
    echo "         Home (Sepolia):           HybridVoting beacon -> V2"
    echo "         Satellite (Base Sepolia): HybridVoting beacon -> V2"
else
    echo "  [FAIL] Cross-chain beacon upgrade (timeout)"
    echo "         Satellite not upgraded after 10 minutes."
    echo "         Check: https://explorer.hyperlane.xyz"
fi
echo ""

if $NAME_REG_OK; then
    echo "  [PASS] Cross-chain name registry"
    echo "         Username registered on home chain UAR"
    echo "         Org name reserved on NameRegistryHub"
else
    echo "  [FAIL] Cross-chain name registry (timeout)"
    echo "         Name registry not synced after 10 minutes."
    echo "         Check: https://explorer.hyperlane.xyz"
fi
echo ""

if $SAT_ORG_OK; then
    echo "  [PASS] Satellite org deployment (optimistic)"
    echo "         Org deployed on satellite via OrgDeployer"
    echo "         Org name claim dispatched optimistically to hub"
    echo "         SatelliteOnboardingHelper deployed + authorized on relay"
else
    echo "  [FAIL] Satellite org deployment"
    echo "         Deployment failed — check logs"
fi
echo ""

if $ORG_NAME_SAT_OK; then
    echo "  [PASS] Org name round-trip confirmation"
    echo "         Org name confirmed back on satellite relay"
else
    echo "  [FAIL] Org name round-trip confirmation (timeout)"
    echo "         Org name not confirmed on satellite after 10 minutes."
fi
echo ""

if ${SAT_ONBOARD_OK:-false}; then
    echo "  [PASS] Satellite onboarding infrastructure"
    echo "         Org registered, helper authorized, username dispatched"
else
    echo "  [FAIL] Satellite onboarding infrastructure"
fi
echo ""

echo "============================================================"

ALL_PASS=true
$UPGRADE_OK || ALL_PASS=false
$NAME_REG_OK || ALL_PASS=false
$ORG_NAME_SAT_OK || ALL_PASS=false
$SAT_ORG_OK || ALL_PASS=false

if $ALL_PASS; then
    echo "  ALL TESTS PASSED"
    echo "============================================================"
    exit 0
else
    echo "  SOME TESTS FAILED — see above for details"
    echo "============================================================"
    exit 1
fi
