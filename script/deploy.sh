#!/usr/bin/env bash
set -euo pipefail

#############################################################################
# deploy.sh - Full cross-chain protocol deployment
#
# Orchestrates MainDeploy.s.sol across 4 chains:
#   Home:       Arbitrum
#   Satellites: Ethereum, Optimism, Gnosis
#
# Prerequisites:
#   - .env with DEPLOYER_PRIVATE_KEY (funded on all 4 chains)
#   - Python 3 (for JSON parsing)
#   - foundry.toml with RPC endpoints configured
#
# Usage:
#   ./script/deploy.sh                          # Full deployment (all 4 steps)
#   ./script/deploy.sh --step 1                 # Deploy home chain only
#   ./script/deploy.sh --step 2                 # Deploy all satellites
#   ./script/deploy.sh --step 2 --satellite 1   # Deploy Optimism satellite only
#   ./script/deploy.sh --step 3                 # Register satellites + transfer ownership
#   ./script/deploy.sh --step 4                 # Verify deployment
#   ./script/deploy.sh --step summary           # Print deployed addresses
#   ./script/deploy.sh --verify                 # Enable Etherscan verification
#   ./script/deploy.sh --dry-run                # Simulate without broadcasting
#   ./script/deploy.sh --yes                    # Skip confirmation prompt
#############################################################################

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_FILE="$SCRIPT_DIR/main-deploy-state.json"

# ═══════════════════════════ Chain Configuration ═══════════════════════════

# Home Chain: Arbitrum
HOME_RPC="arbitrum"
HOME_DOMAIN=42161
HOME_MAILBOX="0x979Ca5202784112f4738403dBec5D0F3B9daabB9"

# Satellite Chains (parallel arrays)
SAT_NAMES=("Ethereum"  "Optimism"  "Gnosis")
SAT_RPCS=("mainnet"    "optimism"  "gnosis")
SAT_DOMAINS=(1          10          100)
SAT_MAILBOXES=(
    "0xc005dc82818d67AF737725bD4bf75435d065D239"
    "0xd4C1905BB1D26BC93DAC913e13CaCC278CdCC80D"
    "0xaD09d78f4c6b9dA2Ae82b1D34107802d380Bb74f"
)

# ═══════════════════════════ Output Helpers ═══════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo ""
}

# ═══════════════════════════ JSON Helper ═══════════════════════════

json_get() {
    local file="$1" dot_path="$2"
    python3 -c "
import json
d = json.load(open('$file'))
for k in '$dot_path'.strip('.').split('.'):
    d = d[k]
print(d)
" 2>/dev/null
}

# ═══════════════════════════ Argument Parsing ═══════════════════════════

VERIFY_FLAG=false
STEP=""
SATELLITE_INDEX=""
DRY_RUN=false
SKIP_CONFIRM=false

usage() {
    cat <<'USAGE'
Usage: ./script/deploy.sh [OPTIONS]

Deploys the full POA protocol across 4 chains.

Steps:
  1  Deploy home chain infrastructure + governance org (Arbitrum)
  2  Deploy satellite infrastructure (Ethereum, Optimism, Gnosis)
  3  Register satellites on Hub + transfer ownership to governance
  4  Verify deployment (read-only)

Options:
  --step N           Run only step N (1-4, or 'summary')
  --satellite N      With --step 2, deploy only satellite at index N
                       0 = Ethereum, 1 = Optimism, 2 = Gnosis
  --verify           Enable Etherscan contract verification
  --dry-run          Simulate without broadcasting transactions
  --yes, -y          Skip confirmation prompt
  --help, -h         Show this help

Examples:
  ./script/deploy.sh                          Full deployment
  ./script/deploy.sh --step 2 --satellite 1   Deploy Optimism satellite only
  ./script/deploy.sh --verify --yes           Full deploy with verification, no prompt
  ./script/deploy.sh --step summary           Print all deployed addresses
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)     VERIFY_FLAG=true; shift ;;
        --step)       STEP="$2"; shift 2 ;;
        --satellite)  SATELLITE_INDEX="$2"; shift 2 ;;
        --dry-run)    DRY_RUN=true; shift ;;
        --yes|-y)     SKIP_CONFIRM=true; shift ;;
        --help|-h)    usage; exit 0 ;;
        *)            error "Unknown option: $1"; usage; exit 1 ;;
    esac
done

# ═══════════════════════════ Environment ═══════════════════════════

load_env() {
    if [ -f "$PROJECT_DIR/.env" ]; then
        set -a
        # shellcheck disable=SC1091
        source "$PROJECT_DIR/.env"
        set +a
    fi

    # Support both PRIVATE_KEY and DEPLOYER_PRIVATE_KEY
    if [ -z "${PRIVATE_KEY:-}" ] && [ -n "${DEPLOYER_PRIVATE_KEY:-}" ]; then
        export PRIVATE_KEY="$DEPLOYER_PRIVATE_KEY"
    fi

    if [ -z "${PRIVATE_KEY:-}" ]; then
        error "PRIVATE_KEY (or DEPLOYER_PRIVATE_KEY) not set. Add it to .env"
        exit 1
    fi
}

# ═══════════════════════════ Verification Flags ═══════════════════════════

build_verify_flags() {
    local rpc_name="$1"

    if [ "$VERIFY_FLAG" != true ]; then
        echo ""
        return
    fi

    # Chain-specific API keys, fall back to ETHERSCAN_API_KEY
    local api_key=""
    case "$rpc_name" in
        arbitrum)  api_key="${ARBISCAN_API_KEY:-${ETHERSCAN_API_KEY:-}}" ;;
        mainnet)   api_key="${ETHERSCAN_API_KEY:-}" ;;
        optimism)  api_key="${OPTIMISM_ETHERSCAN_API_KEY:-${ETHERSCAN_API_KEY:-}}" ;;
        gnosis)    api_key="${GNOSISSCAN_API_KEY:-${ETHERSCAN_API_KEY:-}}" ;;
    esac

    if [ -z "$api_key" ]; then
        warn "No API key for $rpc_name. Skipping verification for this chain."
        echo ""
        return
    fi

    local flags="--verify --etherscan-api-key $api_key"

    # Chain-specific verifier URLs (mainnet uses default)
    case "$rpc_name" in
        arbitrum)  flags="$flags --verifier-url https://api.arbiscan.io/api" ;;
        optimism)  flags="$flags --verifier-url https://api-optimistic.etherscan.io/api" ;;
        gnosis)    flags="$flags --verifier-url https://api.gnosisscan.io/api" ;;
    esac

    echo "$flags"
}

# ═══════════════════════════ Error Handling ═══════════════════════════

CURRENT_STEP=""
CURRENT_STEP_NUM=""
CURRENT_SAT_INDEX=""

cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ -n "${CURRENT_STEP:-}" ]; then
        echo ""
        error "Failed during: ${CURRENT_STEP}"
        echo ""
        error "To resume, run:"
        if [ "${CURRENT_STEP_NUM:-}" = "2" ] && [ -n "${CURRENT_SAT_INDEX:-}" ]; then
            error "  ./script/deploy.sh --step 2 --satellite $CURRENT_SAT_INDEX"
        elif [ -n "${CURRENT_STEP_NUM:-}" ]; then
            error "  ./script/deploy.sh --step $CURRENT_STEP_NUM"
        fi
    fi
}
trap cleanup EXIT

# ═══════════════════════════ Pre-flight Checks ═══════════════════════════

preflight_checks() {
    header "Pre-flight Checks"

    # Check required tools
    if ! command -v forge &>/dev/null; then
        error "forge not found. Install Foundry first."
        exit 1
    fi
    if ! command -v cast &>/dev/null; then
        error "cast not found. Install Foundry first."
        exit 1
    fi
    if ! command -v python3 &>/dev/null; then
        error "python3 required for JSON parsing."
        exit 1
    fi

    # Derive deployer address
    DEPLOYER_ADDRESS=$(cast wallet address "$PRIVATE_KEY" 2>/dev/null) || {
        error "Invalid PRIVATE_KEY. Could not derive address."
        exit 1
    }
    info "Deployer: $DEPLOYER_ADDRESS"
    echo ""

    # Check RPC connectivity and balances
    local all_rpcs=("$HOME_RPC" "${SAT_RPCS[@]}")
    local all_names=("Arbitrum (home)" "${SAT_NAMES[@]}")

    for i in "${!all_rpcs[@]}"; do
        local rpc="${all_rpcs[$i]}"
        local name="${all_names[$i]}"

        local balance
        balance=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$rpc" 2>/dev/null) || {
            error "Cannot reach $name (--rpc-url $rpc). Check foundry.toml."
            exit 1
        }
        local eth_balance
        eth_balance=$(cast from-wei "$balance" 2>/dev/null || echo "?")
        info "$name: $eth_balance ETH"
    done

    echo ""

    # Build with production profile
    info "Building contracts (FOUNDRY_PROFILE=production)..."
    FOUNDRY_PROFILE=production forge build --silent 2>/dev/null || FOUNDRY_PROFILE=production forge build --silent
    success "Build complete."
}

# ═══════════════════════════ Confirmation ═══════════════════════════

confirm_deployment() {
    if [ "$SKIP_CONFIRM" = true ]; then
        return
    fi
    if [ "$DRY_RUN" = true ]; then
        info "Dry run mode — no transactions will be broadcast."
        return
    fi

    echo ""
    warn "This will broadcast transactions on MAINNET chains:"
    echo "    Arbitrum  (home chain)"
    echo "    Ethereum  (satellite)"
    echo "    Optimism  (satellite)"
    echo "    Gnosis    (satellite)"
    echo ""
    echo "    Deployer: $DEPLOYER_ADDRESS"
    echo ""
    read -rp "  Type 'yes' to continue: " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        exit 0
    fi
}

# ═══════════════════════════ Forge Runner ═══════════════════════════

# Runs forge script with the correct broadcast/dry-run flag
run_forge_script() {
    local contract="$1"
    local rpc="$2"
    shift 2

    local broadcast_flag="--broadcast"
    if [ "$DRY_RUN" = true ]; then
        broadcast_flag=""
    fi

    local verify_flags
    verify_flags=$(build_verify_flags "$rpc")

    # shellcheck disable=SC2086
    FOUNDRY_PROFILE=production \
    forge script "script/MainDeploy.s.sol:${contract}" \
        --rpc-url "$rpc" \
        $broadcast_flag \
        --slow \
        $verify_flags \
        "$@"
}

# ═══════════════════════════ Step 1: Home Chain ═══════════════════════════

step1_deploy_home() {
    CURRENT_STEP="Deploy Home Chain (Arbitrum)"
    CURRENT_STEP_NUM=1
    header "Step 1: Deploy Home Chain (Arbitrum, domain $HOME_DOMAIN)"

    MAILBOX="$HOME_MAILBOX" \
    HUB_DOMAIN="$HOME_DOMAIN" \
    run_forge_script DeployHomeChain "$HOME_RPC"

    if [ ! -f "$STATE_FILE" ]; then
        error "State file not created: $STATE_FILE"
        exit 1
    fi

    echo ""
    success "Home chain deployed."
    info "  Hub:        $(json_get "$STATE_FILE" "homeChain.hub")"
    info "  PoaManager: $(json_get "$STATE_FILE" "homeChain.poaManager")"
    info "  Executor:   $(json_get "$STATE_FILE" "homeChain.governance.executor")"
}

# ═══════════════════════════ Step 2: Satellites ═══════════════════════════

step2_deploy_satellites() {
    CURRENT_STEP_NUM=2

    if [ ! -f "$STATE_FILE" ]; then
        error "Home chain state not found: $STATE_FILE"
        error "Run step 1 first: ./script/deploy.sh --step 1"
        exit 1
    fi

    # Determine which satellites to deploy
    local start=0
    local end=${#SAT_NAMES[@]}
    if [ -n "${SATELLITE_INDEX:-}" ]; then
        start=$SATELLITE_INDEX
        end=$((SATELLITE_INDEX + 1))
        if [ "$start" -ge "${#SAT_NAMES[@]}" ]; then
            error "Satellite index $SATELLITE_INDEX out of range (0-$((${#SAT_NAMES[@]} - 1))):"
            for i in "${!SAT_NAMES[@]}"; do
                error "  $i = ${SAT_NAMES[$i]}"
            done
            exit 1
        fi
    fi

    for i in $(seq "$start" "$((end - 1))"); do
        local name="${SAT_NAMES[$i]}"
        local rpc="${SAT_RPCS[$i]}"
        local domain="${SAT_DOMAINS[$i]}"
        local mailbox="${SAT_MAILBOXES[$i]}"

        CURRENT_STEP="Deploy Satellite: $name (domain $domain)"
        CURRENT_SAT_INDEX=$i
        header "Step 2.$((i + 1)): Deploy Satellite on $name (domain $domain)"

        MAILBOX="$mailbox" \
        SATELLITE_DOMAIN="$domain" \
        run_forge_script DeploySatellite "$rpc"

        local sat_state_file="$SCRIPT_DIR/satellite-state-${domain}.json"
        if [ ! -f "$sat_state_file" ]; then
            error "Satellite state file not created: $sat_state_file"
            exit 1
        fi

        echo ""
        success "$name satellite deployed."
        info "  Satellite: $(json_get "$sat_state_file" "satellite")"
        info "  PoaManager: $(json_get "$sat_state_file" "poaManager")"
    done
    CURRENT_SAT_INDEX=""
}

# ═══════════════════════════ Step 3: Register & Transfer ═══════════════════════════

step3_register_and_transfer() {
    CURRENT_STEP="Register Satellites & Transfer Ownership"
    CURRENT_STEP_NUM=3
    header "Step 3: Register Satellites & Transfer Hub Ownership"

    if [ ! -f "$STATE_FILE" ]; then
        error "Home chain state not found: $STATE_FILE"
        error "Run step 1 first."
        exit 1
    fi

    # Verify all satellite state files exist
    for i in "${!SAT_DOMAINS[@]}"; do
        local domain="${SAT_DOMAINS[$i]}"
        local sat_file="$SCRIPT_DIR/satellite-state-${domain}.json"
        if [ ! -f "$sat_file" ]; then
            error "Missing satellite state: $sat_file"
            error "Run step 2 for ${SAT_NAMES[$i]} first: ./script/deploy.sh --step 2 --satellite $i"
            exit 1
        fi
    done

    # Export numbered satellite domain env vars
    for i in "${!SAT_DOMAINS[@]}"; do
        export "SATELLITE_DOMAIN_${i}=${SAT_DOMAINS[$i]}"
    done

    NUM_SATELLITES=${#SAT_DOMAINS[@]} \
    run_forge_script RegisterAndTransfer "$HOME_RPC"

    echo ""
    success "Satellites registered and Hub ownership transferred to Executor."
}

# ═══════════════════════════ Step 4: Verify ═══════════════════════════

step4_verify() {
    CURRENT_STEP="Verify Deployment"
    CURRENT_STEP_NUM=4
    header "Step 4: Verify Deployment"

    if [ ! -f "$STATE_FILE" ]; then
        error "Home chain state not found: $STATE_FILE"
        exit 1
    fi

    forge script script/MainDeploy.s.sol:VerifyDeployment \
        --rpc-url "$HOME_RPC"

    echo ""
    success "Verification complete."
}

# ═══════════════════════════ Summary ═══════════════════════════

print_summary() {
    header "Deployment Summary"

    if [ ! -f "$STATE_FILE" ]; then
        error "No state file found: $STATE_FILE"
        exit 1
    fi

    echo "Home Chain: Arbitrum (domain $HOME_DOMAIN)"
    echo "  DeterministicDeployer: $(json_get "$STATE_FILE" "deterministicDeployer")"
    echo "  PoaManager:            $(json_get "$STATE_FILE" "homeChain.poaManager")"
    echo "  PoaManagerHub:         $(json_get "$STATE_FILE" "homeChain.hub")"
    echo "  ImplRegistry:          $(json_get "$STATE_FILE" "homeChain.implRegistry")"
    echo "  OrgRegistry:           $(json_get "$STATE_FILE" "homeChain.orgRegistry")"
    echo "  OrgDeployer:           $(json_get "$STATE_FILE" "homeChain.orgDeployer")"
    echo "  PaymasterHub:          $(json_get "$STATE_FILE" "homeChain.paymasterHub")"
    echo "  AccountRegistry:       $(json_get "$STATE_FILE" "homeChain.globalAccountRegistry")"
    echo ""
    echo "  Governance Org (Poa):"
    echo "    Executor:            $(json_get "$STATE_FILE" "homeChain.governance.executor")"
    echo "    HybridVoting:        $(json_get "$STATE_FILE" "homeChain.governance.hybridVoting")"
    echo "    DDVoting:            $(json_get "$STATE_FILE" "homeChain.governance.directDemocracyVoting")"
    echo "    QuickJoin:           $(json_get "$STATE_FILE" "homeChain.governance.quickJoin")"
    echo "    ParticipationToken:  $(json_get "$STATE_FILE" "homeChain.governance.participationToken")"
    echo "    TaskManager:         $(json_get "$STATE_FILE" "homeChain.governance.taskManager")"
    echo "    EducationHub:        $(json_get "$STATE_FILE" "homeChain.governance.educationHub")"
    echo "    PaymentManager:      $(json_get "$STATE_FILE" "homeChain.governance.paymentManager")"
    echo ""

    for i in "${!SAT_DOMAINS[@]}"; do
        local domain="${SAT_DOMAINS[$i]}"
        local name="${SAT_NAMES[$i]}"
        local sat_file="$SCRIPT_DIR/satellite-state-${domain}.json"
        if [ -f "$sat_file" ]; then
            echo "Satellite: $name (domain $domain)"
            echo "  PoaManagerSatellite:   $(json_get "$sat_file" "satellite")"
            echo "  PoaManager:            $(json_get "$sat_file" "poaManager")"
            echo "  ImplRegistry:          $(json_get "$sat_file" "implRegistry")"
            echo ""
        else
            warn "Satellite $name: state file not found ($sat_file)"
        fi
    done

    echo "State files:"
    info "  $STATE_FILE"
    for i in "${!SAT_DOMAINS[@]}"; do
        local domain="${SAT_DOMAINS[$i]}"
        local sat_file="$SCRIPT_DIR/satellite-state-${domain}.json"
        if [ -f "$sat_file" ]; then
            info "  $sat_file"
        fi
    done
}

# ═══════════════════════════ Main ═══════════════════════════

main() {
    load_env

    header "POA Protocol Cross-Chain Deployment"
    echo "  Home:       Arbitrum (domain $HOME_DOMAIN)"
    echo "  Satellites: Ethereum (1), Optimism (10), Gnosis (100)"

    preflight_checks

    if [ -z "$STEP" ]; then
        # Full deployment
        confirm_deployment
        step1_deploy_home
        step2_deploy_satellites
        step3_register_and_transfer
        step4_verify
        print_summary
    else
        case "$STEP" in
            1)
                confirm_deployment
                step1_deploy_home
                ;;
            2)
                confirm_deployment
                step2_deploy_satellites
                ;;
            3)
                confirm_deployment
                step3_register_and_transfer
                ;;
            4)
                step4_verify
                ;;
            summary)
                print_summary
                ;;
            *)
                error "Unknown step: $STEP (valid: 1, 2, 3, 4, summary)"
                exit 1
                ;;
        esac
    fi

    echo ""
    success "Done."
}

main
