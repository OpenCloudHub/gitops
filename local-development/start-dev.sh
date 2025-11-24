#!/bin/bash
# =============================================================================
# local-dev/start-dev.sh
# Sets up complete local development environment with Minikube
# =============================================================================
#
# Usage:
#   ./start-dev.sh                    # Full setup
#   DRY_RUN=true ./start-dev.sh       # Preview without changes
#   SKIP_VAULT=true ./start-dev.sh    # Skip Vault setup (reuse existing)
#   SKIP_BOOTSTRAP=true ./start-dev.sh # Skip GitOps bootstrap
#
# Prerequisites:
#   - Docker installed and running
#   - Minikube installed
#   - kubectl installed
#   - NVIDIA drivers + nvidia-container-toolkit (for GPU support)
#   - .env.secrets file configured (see .env.secrets.example)
#   - SSH keys for ArgoCD in ~/.ssh/opencloudhub/
#
# This script:
#   1. Starts Minikube with GPU support
#   2. Creates persistent storage for MinIO and PostgreSQL
#   3. Starts local Vault and seeds secrets
#   4. Bootstraps GitOps (ArgoCD + applications)
#   5. Configures /etc/hosts for local access
#   6. Starts Minikube tunnel for LoadBalancer access
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Load Utilities
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# =============================================================================
# Cleanup on exit
# =============================================================================

cleanup() {
  rm -f /tmp/minikube-tunnel.pid
}

trap cleanup EXIT INT TERM

# =============================================================================
# Configuration
# =============================================================================

# Minikube settings
CLUSTER_NAME="minikube"
MINIKUBE_CPUS="${MINIKUBE_CPUS:-16}"
MINIKUBE_MEMORY="${MINIKUBE_MEMORY:-36g}"
MINIKUBE_DISK="${MINIKUBE_DISK:-100g}"

# Persistent data paths (inside Minikube VM, survives restarts)
MINIO_DATA_PATH="/data/minio"
POSTGRES_DATA_PATH="/data/postgres"

# Skip flags
SKIP_VAULT="${SKIP_VAULT:-false}"
SKIP_BOOTSTRAP="${SKIP_BOOTSTRAP:-false}"
DRY_RUN="${DRY_RUN:-false}"

# Output directory
SUMMARY_OUTPUT_DIR="${SCRIPT_DIR}/output"

# =============================================================================
# Runtime Variables
# =============================================================================

GATEWAY_IP=""
TUNNEL_PID=""
START_TIME=""

# =============================================================================
# Setup Steps
# =============================================================================

step_check_prerequisites() {
  log_step "Checking prerequisites"

  validate_command_exists docker "https://docs.docker.com/get-docker/"
  validate_command_exists minikube "https://minikube.sigs.k8s.io/docs/start/"
  validate_command_exists kubectl "https://kubernetes.io/docs/tasks/tools/"

  # Check for NVIDIA container toolkit (optional but warn if missing)
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

  # Clean up any existing cluster
  log_info "Removing existing Minikube cluster (if any)..."
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

step_setup_vault() {
  log_step "Setting up local Vault"

  if [[ "$SKIP_VAULT" == "true" ]]; then
    log_info "Skipping Vault setup (SKIP_VAULT=true)"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would run setup-vault.sh"
    return 0
  fi

  bash "${SCRIPT_DIR}/setup-vault.sh"
  sleep 5

  log_success "Vault setup complete"
}

step_bootstrap_gitops() {
  log_step "Bootstrapping GitOps stack"

  if [[ "$SKIP_BOOTSTRAP" == "true" ]]; then
    log_info "Skipping bootstrap (SKIP_BOOTSTRAP=true)"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would run bootstrap.sh"
    return 0
  fi

  # Pass the summary output dir to bootstrap
  SUMMARY_OUTPUT_DIR="$SUMMARY_OUTPUT_DIR" bash "${REPO_ROOT}/scripts/bootstrap.sh"

  log_success "GitOps bootstrap complete"
}

step_start_tunnel() {
  log_step "Starting Minikube tunnel"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would start Minikube tunnel"
    return 0
  fi

  pkill -f "minikube tunnel" 2>/dev/null || true
  sleep 2

  # Cache sudo credentials upfront
  log_info "Tunnel requires sudo access..."
  sudo -v

  log_info "Starting tunnel in background..."
  nohup sudo minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
  TUNNEL_PID=$!
  echo "$TUNNEL_PID" > /tmp/minikube-tunnel.pid

  sleep 5
  log_success "Tunnel started (PID: $TUNNEL_PID)"
}

step_wait_for_gateway() {
  log_step "Waiting for Ingress Gateway"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would wait for gateway IP"
    return 0
  fi

  log_info "Waiting for Gateway LoadBalancer IP (up to 5 minutes)..."
  local max_attempts=100
  for ((i=1; i<=max_attempts; i++)); do
    GATEWAY_IP=$(kubectl get svc -n istio-ingress ingress-gateway-istio \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)

    if [[ -n "$GATEWAY_IP" ]]; then
      log_success "Gateway IP: $GATEWAY_IP"
      return 0
    fi

    echo -n "."
    sleep 10
  done

  echo ""
  log_error "Gateway IP not available after 5 minutes"
  log_info "Check: kubectl get svc -n istio-ingress"
  return 1
}

step_configure_hosts() {
  log_step "Configuring /etc/hosts"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would update /etc/hosts"
    return 0
  fi

  if [[ -z "$GATEWAY_IP" ]]; then
    log_warning "No gateway IP - skipping /etc/hosts configuration"
    return 0
  fi

  # Get list of services
  local services
  services=$(get_exposed_services)

  # Remove ALL old opencloudhub entries (handles different comment formats)
  if sudo grep -q "opencloudhub" /etc/hosts 2>/dev/null; then
    log_info "Removing all old opencloudhub /etc/hosts entries..."
    # Remove our patterns
    sudo sed -i '/# opencloudhub-local-dev START/,/# opencloudhub-local-dev END/d' /etc/hosts
  fi

  # Add new entries
  log_info "Adding new /etc/hosts entries..."
  local entry_count=0
  {
    echo "# opencloudhub-local-dev START (added $(date '+%Y-%m-%d %H:%M:%S'))"
    while IFS= read -r hostname; do
      if [[ -n "$hostname" ]]; then
        echo "${GATEWAY_IP} ${hostname}"
        entry_count=$((entry_count + 1))
      fi
    done <<< "$services"
    echo "# opencloudhub-local-dev END"
  } | sudo tee -a /etc/hosts >/dev/null

  log_success "/etc/hosts configured ($entry_count entries added)"
}

step_verify_gpu() {
  log_step "Verifying GPU access"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would verify GPU access"
    return 0
  fi

  log_info "Running GPU test pod..."

  # Create a test pod YAML to avoid ArgoCD management
  local gpu_test_yaml="/tmp/gpu-test-pod.yaml"
  cat > "$gpu_test_yaml" <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: gpu-test
  namespace: default
  labels:
    app: gpu-test
    argocd.argoproj.io/instance: ignore  # Tell ArgoCD to ignore this
spec:
  restartPolicy: Never
  containers:
  - name: cuda
    image: nvidia/cuda:12.2.0-base-ubuntu22.04
    command: ["nvidia-smi"]
    resources:
      limits:
        nvidia.com/gpu: 1
EOF

  # Run the test with timeout
  if timeout 60s kubectl apply -f "$gpu_test_yaml" && \
     kubectl wait --for=condition=Ready pod/gpu-test -n default --timeout=30s 2>/dev/null && \
     kubectl logs -f gpu-test -n default 2>/dev/null; then
    log_success "GPU access verified ✓"
  else
    log_warning "GPU test failed - cluster may not have GPU access"
    log_info "Check GPU allocatable: kubectl get nodes -o json | jq '.items[].status.allocatable'"
  fi

  # Cleanup
  kubectl delete pod gpu-test -n default --ignore-not-found 2>/dev/null
  rm -f "$gpu_test_yaml"
}

step_create_summary() {
  log_step "Creating development environment summary"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) No summary created"
    return 0
  fi

  mkdir -p "$SUMMARY_OUTPUT_DIR"

  local end_time
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  local summary_file="${SUMMARY_OUTPUT_DIR}/dev-summary.json"
  cat > "$summary_file" <<EOF
{
  "environment": {
    "started": "$START_TIME",
    "completed": "$end_time",
    "cluster": "$CLUSTER_NAME"
  },
  "minikube": {
    "cpus": "$MINIKUBE_CPUS",
    "memory": "$MINIKUBE_MEMORY",
    "disk": "$MINIKUBE_DISK"
  },
  "network": {
    "gateway_ip": "${GATEWAY_IP:-null}",
    "tunnel_pid": "${TUNNEL_PID:-null}",
    "tunnel_log": "/tmp/minikube-tunnel.log"
  },
  "related_summaries": {
    "vault": "${SUMMARY_OUTPUT_DIR}/vault-summary.json",
    "bootstrap": "${SUMMARY_OUTPUT_DIR}/bootstrap-summary.json"
  }
}
EOF

  log_success "Summary saved to: $summary_file"
}

print_completion_summary() {
  print_section_header "Development Environment Ready"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN completed - no changes were applied"
    echo ""
    return 0
  fi

  echo ""
  echo -e "  ${GREEN}Cluster:${NC}"
  echo -e "    Name:   $CLUSTER_NAME"
  echo -e "    CPUs:   $MINIKUBE_CPUS"
  echo -e "    Memory: $MINIKUBE_MEMORY"
  echo -e "    Disk:   $MINIKUBE_DISK"
  echo ""
  echo -e "  ${GREEN}Network:${NC}"
  echo -e "    Gateway IP: ${GATEWAY_IP:-<pending>}"
  echo -e "    Tunnel PID: ${TUNNEL_PID:-<not started>}"
  echo ""
  echo -e "  ${CYAN}Quick Access:${NC}"
  echo -e "    ArgoCD:  https://argocd.internal.opencloudhub.org"
  echo -e "    Grafana: https://grafana.internal.opencloudhub.org"
  echo -e "    MLflow:  https://mlflow.ai.internal.opencloudhub.org"
  echo ""
  echo -e "  ${CYAN}Summaries:${NC}"
  echo -e "    ${SUMMARY_OUTPUT_DIR}/vault-summary.json"
  echo -e "    ${SUMMARY_OUTPUT_DIR}/bootstrap-summary.json"
  echo -e "    ${SUMMARY_OUTPUT_DIR}/dev-summary.json"
  echo ""
  echo -e "  ${YELLOW}To stop:${NC}"
  echo -e "    kill ${TUNNEL_PID:-\$(cat /tmp/minikube-tunnel.pid)}"
  echo -e "    minikube delete"
  echo ""
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
  START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  print_banner "Local Development Setup" "$CLUSTER_NAME"

  step_check_prerequisites
  step_start_minikube
  step_create_persistent_storage
  step_setup_vault
  step_bootstrap_gitops
  step_start_tunnel
  step_wait_for_gateway
  step_configure_hosts
  step_verify_gpu
  step_create_summary
  print_completion_summary
}

main "$@"
