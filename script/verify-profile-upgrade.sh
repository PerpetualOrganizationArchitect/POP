#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# verify-profile-upgrade.sh — Verify the 3 upgraded contracts on Blockscout
#
# Verifies:
#   1. UniversalAccountRegistry v4 (optimizer_runs=200)
#   2. OrgDeployer v5              (optimizer_runs=200)
#   3. PaymasterHub v12            (optimizer_runs=100)
#
# Same addresses on both chains (DD CREATE3).
#
# Usage:
#   ./script/verify-profile-upgrade.sh              # Both chains
#   ./script/verify-profile-upgrade.sh --dry-run    # Print commands only
#############################################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# DD-predicted addresses (same on both chains)
UAR_ADDR="0x71b6D7CD3872bba8BbeBC3e278F40d5B15F8CC07"
PM_ADDR="0x2D93B603F74D994CDF50AA035368cC7BaB252831"
OD_ADDR="0xAF02196f9AE9278f7D1C44F556E5407015b8fC6C"

PASS=0
FAIL=0
SKIP=0

verify() {
    local chain="$1"
    local address="$2"
    local contract="$3"
    local label="$4"
    local runs="$5"

    local verifier_url
    case "$chain" in
        arbitrum)  verifier_url="https://arbitrum.blockscout.com/api/" ;;
        gnosis)    verifier_url="https://gnosis.blockscout.com/api/" ;;
    esac

    local cmd="FOUNDRY_PROFILE=production forge verify-contract"
    cmd+=" $address $contract"
    cmd+=" --chain $chain"
    cmd+=" --verifier blockscout"
    cmd+=" --verifier-url $verifier_url"
    cmd+=" --optimizer-runs $runs"

    echo -ne "${BLUE}[$chain]${NC} $label ($address, runs=$runs) ... "

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN${NC}"
        echo "  $cmd"
        echo ""
        return 0
    fi

    local output
    if output=$(eval "$cmd" 2>&1); then
        echo -e "${GREEN}VERIFIED${NC}"
        PASS=$((PASS + 1))
    else
        if echo "$output" | grep -qi "already verified"; then
            echo -e "${GREEN}ALREADY VERIFIED${NC}"
            SKIP=$((SKIP + 1))
        else
            echo -e "${RED}FAILED${NC}"
            echo "  $output" | tail -3
            FAIL=$((FAIL + 1))
        fi
    fi
}

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Profile Metadata Upgrade — Contract Verification${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# ── Gnosis ──
echo -e "${BLUE}═══ Gnosis ═══${NC}"
verify gnosis "$UAR_ADDR" \
    "src/UniversalAccountRegistry.sol:UniversalAccountRegistry" \
    "UAR v4" 200

verify gnosis "$OD_ADDR" \
    "src/OrgDeployer.sol:OrgDeployer" \
    "OrgDeployer v5" 200

verify gnosis "$PM_ADDR" \
    "src/PaymasterHub.sol:PaymasterHub" \
    "PaymasterHub v12" 100

echo ""

# ── Arbitrum ──
echo -e "${BLUE}═══ Arbitrum ═══${NC}"
verify arbitrum "$UAR_ADDR" \
    "src/UniversalAccountRegistry.sol:UniversalAccountRegistry" \
    "UAR v4" 200

verify arbitrum "$OD_ADDR" \
    "src/OrgDeployer.sol:OrgDeployer" \
    "OrgDeployer v5" 200

verify arbitrum "$PM_ADDR" \
    "src/PaymasterHub.sol:PaymasterHub" \
    "PaymasterHub v12" 100

echo ""
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "  Verified: ${GREEN}$PASS${NC}  Already: ${GREEN}$SKIP${NC}  Failed: ${RED}$FAIL${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
