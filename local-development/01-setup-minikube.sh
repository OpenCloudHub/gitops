#!/bin/bash
# =============================================================================
# local-development/01-setup-minikube.sh
# Sets up Minikube cluster with GPU support and persistent storage
# =============================================================================
#
# Usage:
#   ./01-setup-minikube.sh                    # Full setup (deletes existing)
#   DRY_RUN=true ./01-setup-minikube.sh       # Preview without changes
#
# Prerequisites:
#   - Docker installed and running
#   - Minikube installed
#   - kubectl installed
#   - NVIDIA drivers + nvidia-container-toolkit (for GPU support)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# =============================================================================
# Configuration
# =============================================================================

CLUSTER_NAME="minikube"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-16}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-48g}"
MINIKUBE_DISK="${MINIKUBE_DISK:-100g}"

# Persistent data paths (inside Minikube VM)
MINIO_DATA_PATH="/data/minio"
POSTGRES_DATA_PATH="/data/postgres"

DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# Steps
# =============================================================================

step_check_prerequisites() {
  log_step "Checking prerequisites"

  validate_command_exists docker "https://docs.docker.com/get-docker/"
  validate_command_exists minikube "https://minikube.sigs.k8s.io/docs/start/"
  validate_command_exists kubectl "https://kubernetes.io/docs/tasks/tools/"

  if ! command -v nvidia-smi &>/dev/null; then
    log_warning "nvidia-smi not found - GPU support may not work"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be applied"
  fi

  log_success "Prerequisites check passed"
}

step_start_minikube() {
  log_step "Starting Minikube cluster"

  log_info "Removing existing Minikube cluster..."
  minikube delete 2>/dev/null || true

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would start Minikube with:"
    log_info "  CPUs: $MINIKUBE_CPUS"
    log_info "  Memory: $MINIKUBE_MEMORY"
    log_info "  Disk: $MINIKUBE_DISK"
    return 0
  fi

  log_info "Starting Minikube with GPU support..."
  minikube start \
    --driver docker \
    --container-runtime docker \
    --cpus "$MINIKUBE_CPUS" \
    --memory "$MINIKUBE_MEMORY" \
    --disk-size "$MINIKUBE_DISK" \
    --gpus all

  log_success "Minikube started successfully"
}

step_create_persistent_storage() {
  log_step "Creating persistent storage directories"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would create directories in Minikube VM"
    return 0
  fi

  log_info "Creating data directories inside Minikube VM..."
  minikube ssh "
    # MinIO directories (uid 1000)
    sudo mkdir -p ${MINIO_DATA_PATH}/data-0 ${MINIO_DATA_PATH}/data-1
    sudo chown -R 1000:1000 ${MINIO_DATA_PATH}
    sudo chmod -R 755 ${MINIO_DATA_PATH}

    # PostgreSQL directories (uid 26 for CNPG)
    sudo mkdir -p ${POSTGRES_DATA_PATH}/mlflow-1 ${POSTGRES_DATA_PATH}/mlflow-2
    sudo mkdir -p ${POSTGRES_DATA_PATH}/demo-app-1 ${POSTGRES_DATA_PATH}/demo-app-2
    sudo chown -R 26:26 ${POSTGRES_DATA_PATH}
    sudo chmod -R 700 ${POSTGRES_DATA_PATH}
  "

  log_info "Applying storage manifests..."
  kubectl apply -k "${SCRIPT_DIR}/manifests"

  log_success "Persistent storage configured"
}

# =============================================================================
# Main
# =============================================================================

main() {
  print_banner "Minikube Setup" "$CLUSTER_NAME"

  step_check_prerequisites
  step_start_minikube
  step_create_persistent_storage

  echo ""
  log_success "Minikube ready!"
  log_info "Next: ./02-load-images.sh (optional) or ./03-setup-vault.sh"
}

main "$@"
