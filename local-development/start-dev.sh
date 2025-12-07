#!/bin/bash
# =============================================================================
# local-development/start-dev.sh
# Orchestrates complete local development environment setup
# =============================================================================
#
# Usage:
#   ./start-dev.sh                        # Full setup
#   LOAD_IMAGES=true ./start-dev.sh       # Include image pre-loading
#   SKIP_VAULT=true ./start-dev.sh        # Skip Vault setup
#   SKIP_BOOTSTRAP=true ./start-dev.sh    # Skip GitOps bootstrap
#   SKIP_NETWORK=true ./start-dev.sh      # Skip tunnel/hosts setup
#   DRY_RUN=true ./start-dev.sh           # Preview all steps
#
# Steps:
#   1. Setup Minikube (delete + fresh start + PVs)
#   2. Load images (optional, opt-in with LOAD_IMAGES=true)
#   3. Setup Vault (local Docker Vault for secrets)
#   4. Bootstrap GitOps (ArgoCD + applications)
#   5. Setup Network (tunnel + /etc/hosts)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# =============================================================================
# Configuration
# =============================================================================

LOAD_IMAGES="${LOAD_IMAGES:-false}"
SKIP_VAULT="${SKIP_VAULT:-false}"
SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-false}"
SKIP_NETWORK="${SKIP_NETWORK:-false}"
DRY_RUN="${DRY_RUN:-false}"

SUMMARY_OUTPUT_DIR="${SCRIPT_DIR}/output"

# =============================================================================
# Main
# =============================================================================

main() {
  local start_time
  start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  print_banner "Local Development Setup" "minikube"

  # Export for child scripts
  export DRY_RUN
  export SUMMARY_OUTPUT_DIR

  # Step 1: Minikube
  log_step "Step 1/5: Minikube Setup"
  bash "${SCRIPT_DIR}/01-setup-minikube.sh"

  # Step 2: Images (opt-in)
  log_step "Step 2/5: Image Loading"
  if [[ "$LOAD_IMAGES" == "true" ]]; then
    bash "${SCRIPT_DIR}/02-load-images.sh"
  else
    log_info "Skipping image loading (set LOAD_IMAGES=true to enable)"
  fi

  # Step 3: Vault
  log_step "Step 3/5: Vault Setup"
  if [[ "$SKIP_VAULT" == "true" ]]; then
    log_info "Skipping Vault setup (SKIP_VAULT=true)"
  else
    bash "${SCRIPT_DIR}/03-setup-vault.sh"
  fi

  # Step 4: Bootstrap
  log_step "Step 4/5: GitOps Bootstrap"
  if [[ "$SKIP_BOOTSTRAP" == "true" ]]; then
    log_info "Skipping bootstrap (SKIP_BOOTSTRAP=true)"
  else
    bash "${REPO_ROOT}/scripts/bootstrap.sh"
  fi

  # Step 5: Network
  log_step "Step 5/5: Network Setup"
  if [[ "$SKIP_NETWORK" == "true" ]]; then
    log_info "Skipping network setup (SKIP_NETWORK=true)"
  else
    bash "${SCRIPT_DIR}/04-setup-network.sh"
  fi

  # Final summary
  _create_summary "$start_time"
  _print_completion
}

_create_summary() {
  local start_time="$1"

  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  mkdir -p "$SUMMARY_OUTPUT_DIR"

  local summary_file="${SUMMARY_OUTPUT_DIR}/dev-summary.json"
  cat > "$summary_file" <<EOF
{
  "environment": {
    "started": "$start_time",
    "completed": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "cluster": "minikube"
  },
  "options": {
    "load_images": $LOAD_IMAGES,
    "skip_vault": $SKIP_VAULT,
    "skip_bootstrap": $SKIP_BOOTSTRAP,
    "skip_network": $SKIP_NETWORK
  },
  "summaries": {
    "vault": "${SUMMARY_OUTPUT_DIR}/vault-summary.json",
    "bootstrap": "${SUMMARY_OUTPUT_DIR}/bootstrap-summary.json",
    "network": "${SUMMARY_OUTPUT_DIR}/network-summary.json"
  }
}
EOF

  log_success "Summary saved to: $summary_file"
}

_print_completion() {
  print_section_header "Development Environment Ready"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN completed - no changes were applied"
    return 0
  fi

  echo ""
  echo -e "  ${CYAN}Quick Access:${NC}"
  echo -e "    ArgoCD:  https://argocd.internal.opencloudhub.org"
  echo -e "    Grafana: https://grafana.internal.opencloudhub.org"
  echo -e "    MLflow:  https://mlflow.ai.internal.opencloudhub.org"
  echo ""
  echo -e "  ${CYAN}Summaries:${NC}"
  echo -e "    ${SUMMARY_OUTPUT_DIR}/dev-summary.json"
  echo ""
  echo -e "  ${YELLOW}Individual scripts:${NC}"
  echo -e "    ./1-setup-minikube.sh   # Minikube + PVs"
  echo -e "    ./2-load-images.sh      # Pre-load images"
  echo -e "    ./3-setup-vault.sh      # Local Vault"
  echo -e "    ./4-setup-network.sh    # Tunnel + hosts"
  echo ""
}

main "$@"
