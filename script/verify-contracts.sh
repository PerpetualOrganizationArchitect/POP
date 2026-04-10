#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# verify-contracts.sh — Verify all deployed contracts on Blockscout
#
# Blockscout verification is FREE (no API key needed).
# Uses forge verify-contract with --verifier blockscout.
#
# Usage:
#   ./script/verify-contracts.sh                    # Verify all on both chains
#   ./script/verify-contracts.sh --chain arbitrum    # Arbitrum only
#   ./script/verify-contracts.sh --chain gnosis      # Gnosis only
#   ./script/verify-contracts.sh --dry-run           # Print commands without running
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

CHAIN_FILTER=""
DRY_RUN=false
OPTIMIZER_RUNS=200
OPTIMIZER_RUNS_PAYMASTER=150  # PaymasterHub exceeds EIP-170 at 200

while [[ $# -gt 0 ]]; do
    case "$1" in
        --chain)    CHAIN_FILTER="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        *)          echo "Unknown option: $1"; exit 1 ;;
    esac
done

PASS=0
FAIL=0
SKIP=0

verify() {
    local chain="$1"
    local address="$2"
    local contract="$3"
    local label="$4"
    local constructor_args="${5:-}"
    local extra_flags="${6:-}"

    local verifier_url
    case "$chain" in
        arbitrum)  verifier_url="https://arbitrum.blockscout.com/api/" ;;
        gnosis)    verifier_url="https://gnosis.blockscout.com/api/" ;;
        *)         echo -e "${RED}Unknown chain: $chain${NC}"; return 1 ;;
    esac

    echo -ne "${BLUE}[$chain]${NC} $label ($address) ... "

    local cmd="FOUNDRY_PROFILE=production forge verify-contract $address $contract --chain $chain --verifier blockscout --verifier-url $verifier_url"

    if [ -n "$constructor_args" ]; then
        cmd="$cmd --constructor-args $constructor_args"
    fi

    if [ -n "$extra_flags" ]; then
        cmd="$cmd $extra_flags"
    fi

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}DRY RUN${NC}"
        echo "  $cmd"
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
echo -e "${BLUE}  POA Protocol — Contract Verification (Blockscout)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo ""

# ═══════════════════════════════════════════════════════════
#  ARBITRUM
# ═══════════════════════════════════════════════════════════

if [ -z "$CHAIN_FILTER" ] || [ "$CHAIN_FILTER" = "arbitrum" ]; then
    echo -e "${BLUE}═══ Arbitrum One ═══${NC}"
    echo ""

    echo "--- Direct Deploys ---"
    # PoaManager has constructor arg: address(0)
    verify arbitrum 0xFF585Fae4A944cD173B19158C6FC5E08980b0815 \
        "src/PoaManager.sol:PoaManager" "PoaManager" \
        "$(cast abi-encode 'constructor(address)' 0x0000000000000000000000000000000000000000)"

    # PoaManagerHub(poaManager, mailbox)
    verify arbitrum 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71 \
        "src/crosschain/PoaManagerHub.sol:PoaManagerHub" "PoaManagerHub" \
        "$(cast abi-encode 'constructor(address,address)' 0xFF585Fae4A944cD173B19158C6FC5E08980b0815 0x979Ca5202784112f4738403dBec5D0F3B9daabB9)"

    # DeterministicDeployer(owner)
    verify arbitrum 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a \
        "src/crosschain/DeterministicDeployer.sol:DeterministicDeployer" "DeterministicDeployer" \
        "$(cast abi-encode 'constructor(address)' 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9)"

    # No-arg factories
    verify arbitrum 0x24Fd3b269905AF10A6E5c67D93F0502Cd11Af875 \
        "src/factories/GovernanceFactory.sol:GovernanceFactory" "GovernanceFactory"

    verify arbitrum 0x124679c4825728221D7a8f0aA5996347ea288071 \
        "src/factories/AccessFactory.sol:AccessFactory" "AccessFactory"

    verify arbitrum 0x1939354B93CCc8954Cabb885487d79227A8d0e55 \
        "src/factories/ModulesFactory.sol:ModulesFactory" "ModulesFactory"

    verify arbitrum 0x3744b372abc41589226313F2bB1dB3aCAa22A854 \
        "src/HatsTreeSetup.sol:HatsTreeSetup" "HatsTreeSetup"

    echo ""
    echo "--- Beacon Implementations (v7 — current, DD-deployed) ---"
    # 6 DD-upgraded contracts (same address on both chains)
    verify arbitrum 0xE3FD4f329E83e7F14C2648a4E38b4fC567FC1556 \
        "src/HybridVoting.sol:HybridVoting" "HybridVoting impl"

    verify arbitrum 0x9eB10cE2d91F77cc11FA264C0E56D0cAbE9E03e0 \
        "src/DirectDemocracyVoting.sol:DirectDemocracyVoting" "DDVoting impl"

    verify arbitrum 0x395c699ab2aD412AffD19D16e69A8e0791B316b9 \
        "src/QuickJoin.sol:QuickJoin" "QuickJoin impl"

    verify arbitrum 0x5DEca9c1413FDD080bD32df0790b92130f5F2914 \
        "src/ParticipationToken.sol:ParticipationToken" "ParticipationToken impl"

    verify arbitrum 0x29eabF5f37D320ea4ea228E29d6776fBd12695aA \
        "src/OrgDeployer.sol:OrgDeployer" "OrgDeployer impl"

    verify arbitrum 0x12a3006c5389496e39Ba238Da633ab24de30A241 \
        "src/PaymasterHub.sol:PaymasterHub" "PaymasterHub impl"

    echo "--- Beacon Implementations (Arbitrum-only, original deploy) ---"
    # These were deployed directly on Arbitrum (not via DD), unchanged source
    verify arbitrum 0x6B5E116688A0903a80d9eb9E0CbBDbd3aD3ce025 \
        "src/Executor.sol:Executor" "Executor impl"

    verify arbitrum 0x86f5cC27A97Df40c355e01798Ec798781ce94bD7 \
        "src/TaskManager.sol:TaskManager" "TaskManager impl"

    verify arbitrum 0xfA172367178917001eB7F1B9243088Af0D3B7E81 \
        "src/EducationHub.sol:EducationHub" "EducationHub impl"

    verify arbitrum 0xf9F54a507599d52974e370F89dF3dAbED26cE797 \
        "src/PaymentManager.sol:PaymentManager" "PaymentManager impl"

    verify arbitrum 0x536b1e00257cf89163214C334CE3E875909cc697 \
        "src/UniversalAccountRegistry.sol:UniversalAccountRegistry" "AccountRegistry impl"

    verify arbitrum 0xFc6a50438fF47359F3C162f5d9DB32125eBA8e5C \
        "src/EligibilityModule.sol:EligibilityModule" "EligibilityModule impl"

    verify arbitrum 0xFD210251338825E2EeFfCeC88e134C1442F4d5FB \
        "src/ToggleModule.sol:ToggleModule" "ToggleModule impl"

    verify arbitrum 0x1Ad133bc87FF58236036599cc9770a7507c84b0c \
        "src/PasskeyAccount.sol:PasskeyAccount" "PasskeyAccount impl"

    verify arbitrum 0x294c24BaF73f891879483746E94BaF5acbF57f3D \
        "src/PasskeyAccountFactory.sol:PasskeyAccountFactory" "PasskeyAccountFactory impl"

    verify arbitrum 0x4AeDEb6cA3049729269A83894D3e3D8C08FC2728 \
        "src/OrgRegistry.sol:OrgRegistry" "OrgRegistry impl"

    verify arbitrum 0x331d50497dC58f3Ff248acE13214F202aA0f0eD8 \
        "src/ImplementationRegistry.sol:ImplementationRegistry" "ImplRegistry impl"

    echo ""
fi

# ═══════════════════════════════════════════════════════════
#  GNOSIS
# ═══════════════════════════════════════════════════════════

if [ -z "$CHAIN_FILTER" ] || [ "$CHAIN_FILTER" = "gnosis" ]; then
    echo -e "${BLUE}═══ Gnosis Chain ═══${NC}"
    echo ""

    echo "--- Direct Deploys ---"
    verify gnosis 0x794fD39e75140ee1545B1B022E5486B7c863789b \
        "src/PoaManager.sol:PoaManager" "PoaManager" \
        "$(cast abi-encode 'constructor(address)' 0x0000000000000000000000000000000000000000)"

    # PoaManagerSatellite(poaManager, mailbox, hubDomain, hubAddress)
    verify gnosis 0x4Ad70029a9247D369a5bEA92f90840B9ee58eD06 \
        "src/crosschain/PoaManagerSatellite.sol:PoaManagerSatellite" "PoaManagerSatellite" \
        "$(cast abi-encode 'constructor(address,address,uint32,address)' 0x794fD39e75140ee1545B1B022E5486B7c863789b 0xaD09d78f4c6b9dA2Ae82b1D34107802d380Bb74f 42161 0xB72840B343654eAfb2CFf7acC4Fc6b59E6c3CC71)"

    verify gnosis 0x4aC8B5ebEb9D8C3dE3180ddF381D552d59e8835a \
        "src/crosschain/DeterministicDeployer.sol:DeterministicDeployer" "DeterministicDeployer" \
        "$(cast abi-encode 'constructor(address)' 0xA6F4D9f44Dd980b7168D829d5f74c2b00a46b2c9)"

    # Gnosis factories (deployed via DD, no constructor args for the impl)
    verify gnosis 0x7B023B9566b96616D54935AE8De80579c93f62aC \
        "src/factories/GovernanceFactory.sol:GovernanceFactory" "GovernanceFactory"

    verify gnosis 0x24Fd3b269905AF10A6E5c67D93F0502Cd11Af875 \
        "src/factories/AccessFactory.sol:AccessFactory" "AccessFactory"

    verify gnosis 0x124679c4825728221D7a8f0aA5996347ea288071 \
        "src/factories/ModulesFactory.sol:ModulesFactory" "ModulesFactory"

    verify gnosis 0x1939354B93CCc8954Cabb885487d79227A8d0e55 \
        "src/HatsTreeSetup.sol:HatsTreeSetup" "HatsTreeSetup"

    echo ""
    echo "--- Beacon Implementations (Gnosis-specific addresses) ---"
    # v7 DD-deployed implementations (same address as Arbitrum)
    verify gnosis 0xE3FD4f329E83e7F14C2648a4E38b4fC567FC1556 \
        "src/HybridVoting.sol:HybridVoting" "HybridVoting impl"

    verify gnosis 0x9eB10cE2d91F77cc11FA264C0E56D0cAbE9E03e0 \
        "src/DirectDemocracyVoting.sol:DirectDemocracyVoting" "DDVoting impl"

    verify gnosis 0x395c699ab2aD412AffD19D16e69A8e0791B316b9 \
        "src/QuickJoin.sol:QuickJoin" "QuickJoin impl"

    verify gnosis 0x5DEca9c1413FDD080bD32df0790b92130f5F2914 \
        "src/ParticipationToken.sol:ParticipationToken" "ParticipationToken impl"

    verify gnosis 0x29eabF5f37D320ea4ea228E29d6776fBd12695aA \
        "src/OrgDeployer.sol:OrgDeployer" "OrgDeployer impl"

    verify gnosis 0x12a3006c5389496e39Ba238Da633ab24de30A241 \
        "src/PaymasterHub.sol:PaymasterHub" "PaymasterHub impl"

    # Gnosis-only implementations (deployed during satellite setup, different from Arbitrum)
    verify gnosis 0x06DeBc1Eed238b78168394Fd47932F00BEedCAC2 \
        "src/Executor.sol:Executor" "Executor impl (Gnosis)"

    verify gnosis 0x47dc2cC3aDF26718665B2A007D9Ee370472292f0 \
        "src/TaskManager.sol:TaskManager" "TaskManager impl (Gnosis)"

    verify gnosis 0x00a5147dB38C06A29a9B18CcbA03aF25e6745D40 \
        "src/EducationHub.sol:EducationHub" "EducationHub impl (Gnosis)"

    verify gnosis 0x70f1F2dDC1B1098E12ED0A4E26387f5E7B783fCe \
        "src/PaymentManager.sol:PaymentManager" "PaymentManager impl (Gnosis)"

    verify gnosis 0xbA7c34C851e2ac947168053Ba673FE20418cd7F5 \
        "src/UniversalAccountRegistry.sol:UniversalAccountRegistry" "AccountRegistry impl (Gnosis)"

    verify gnosis 0xb387B8383BF9e63Ce1FAd4b11c37F39AC523CCd3 \
        "src/EligibilityModule.sol:EligibilityModule" "EligibilityModule impl (Gnosis)"

    verify gnosis 0xe767e9Cc07A9Ea7a26688Fd48f177F9AEa5B278D \
        "src/ToggleModule.sol:ToggleModule" "ToggleModule impl (Gnosis)"

    verify gnosis 0xBD3c72eC41Bda3F07211f2548FB6E73edcCB12FB \
        "src/PasskeyAccount.sol:PasskeyAccount" "PasskeyAccount impl (Gnosis)"

    verify gnosis 0x1aa7cB76f127B7BFEB3d3326E868a34C0D9509ef \
        "src/PasskeyAccountFactory.sol:PasskeyAccountFactory" "PasskeyFactory impl (Gnosis)"

    verify gnosis 0xdE64609aE6C1526559D6BE3111DA37925F8951Ba \
        "src/OrgRegistry.sol:OrgRegistry" "OrgRegistry impl (Gnosis)"

    verify gnosis 0x73B760C26E72cC97D28d0506Ee911969D26eF92b \
        "src/ImplementationRegistry.sol:ImplementationRegistry" "ImplRegistry impl (Gnosis)"

    echo ""
fi

# ═══════════════════════════════════════════════════════════
#  Summary
# ═══════════════════════════════════════════════════════════

echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
echo -e "  Verified: ${GREEN}$PASS${NC}  Already: ${GREEN}$SKIP${NC}  Failed: ${RED}$FAIL${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
