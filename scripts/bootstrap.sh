#!/bin/bash
# =============================================================================
# scripts/bootstrap.sh
# GitOps Bootstrap - Installs ArgoCD and configures GitOps for the cluster
# =============================================================================
#
# Usage:
#   ./bootstrap.sh                    # Bootstrap current kubectl context
#   DRY_RUN=true ./bootstrap.sh       # Preview without applying changes
#
# Prerequisites:
#   - kubectl configured and connected to target cluster
#   - kustomize installed
#   - SSH keys for ArgoCD repository access (see SSH_KEYS_BASE_PATH)
#
# Environment Variables:
#   VAULT_TOKEN          - Token for Vault access (default: 1234)
#   SSH_KEYS_BASE_PATH   - Directory containing SSH keys (default: ~/.ssh/opencloudhub)
#   DRY_RUN              - Set to "true" to preview without applying (default: false)
#   SUMMARY_OUTPUT_DIR   - Directory for summary output (default: ./local-dev/output)
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Load Utilities
# =============================================================================

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
source "${REPO_ROOT}/scripts/_utils.sh"

# Load root .env if exists (for SSH_KEYS_BASE_PATH)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  source "${REPO_ROOT}/.env"
fi

# =============================================================================
# Configuration
# =============================================================================

# Vault token for External Secrets Operator
VAULT_TOKEN="${VAULT_TOKEN:-1234}"

# SSH keys directory for ArgoCD repository access
# Each repository needs a deploy key file in this directory
# Override with: SSH_KEYS_BASE_PATH=/path/to/keys ./bootstrap.sh
SSH_KEYS_BASE_PATH="${SSH_KEYS_BASE_PATH:-${HOME}/.ssh/opencloudhub}"

# Dry run mode - set to "true" to preview without applying
DRY_RUN="${DRY_RUN:-false}"

# Output directory for summary files
SUMMARY_OUTPUT_DIR="${SUMMARY_OUTPUT_DIR:-${REPO_ROOT}/local-dev/output}"

# Timeout for kubectl wait operations
KUBECTL_TIMEOUT="300s"

# -----------------------------------------------------------------------------
# ArgoCD Repository Configuration
# -----------------------------------------------------------------------------
# Format: "secret_name|repo_url|ssh_key_filename"
# - secret_name: Name of the Kubernetes secret to create
# - repo_url: Git SSH URL for the repository
# - ssh_key_filename: Name of the SSH private key file in SSH_KEYS_BASE_PATH
#
# To add more repositories, add entries to this array:
ARGOCD_REPOS=(
  "gitops|git@github.com:opencloudhub/gitops.git|argocd_gitops_ed25519"
  # "another-repo|git@github.com:opencloudhub/another.git|another_key_ed25519"
)

# =============================================================================
# Runtime Variables (set during execution)
# =============================================================================

BOOTSTRAP_TIMESTAMP=""
KUBECTL_CONTEXT=""

# =============================================================================
# Helper Functions
# =============================================================================

check_cluster_connectivity() {
  local current_context
  if ! current_context=$(kubectl config current-context 2>/dev/null); then
    log_error "No kubectl context found. Please configure kubectl first."
    return 1
  fi

  if kubectl cluster-info &>/dev/null; then
    log_success "Connected to cluster: $current_context"
    KUBECTL_CONTEXT="$current_context"
    return 0
  else
    log_error "Cannot connect to cluster: $current_context"
    return 1
  fi
}

check_ssh_keys() {
  if [[ ! -d "$SSH_KEYS_BASE_PATH" ]]; then
    log_error "SSH keys directory not found: $SSH_KEYS_BASE_PATH"
    log_info "Create the directory and add your ArgoCD deploy keys, or set SSH_KEYS_BASE_PATH"
    return 1
  fi

  # Verify each configured repo has its SSH key
  for repo_config in "${ARGOCD_REPOS[@]}"; do
    IFS='|' read -r secret_name repo_url key_file <<< "$repo_config"
    if [[ ! -f "${SSH_KEYS_BASE_PATH}/${key_file}" ]]; then
      log_error "SSH key not found: ${SSH_KEYS_BASE_PATH}/${key_file}"
      log_info "This key is required for repository: $repo_url"
      return 1
    fi
  done

  log_success "All SSH keys present in: $SSH_KEYS_BASE_PATH"
  return 0
}

# =============================================================================
# Bootstrap Steps
# =============================================================================

step_check_prerequisites() {
  log_step "Checking prerequisites"

  validate_command_exists kubectl "https://kubernetes.io/docs/tasks/tools/"
  validate_command_exists kustomize "https://kubectl.docs.kubernetes.io/installation/kustomize/"

  check_cluster_connectivity
  check_ssh_keys

  # Future: Enable git status check for production deployments
  # check_git_status

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be applied"
  fi

  log_success "Prerequisites check passed"
}

step_prepare_cluster() {
  log_step "Preparing cluster (namespaces, CRDs, secrets)"

  # Wait for API server readiness
  log_info "Waiting for Kubernetes API server..."
  kubectl wait --for=condition=Ready --timeout=60s \
    -n kube-system pod -l component=kube-apiserver 2>/dev/null || true
  sleep 3

  # Create essential namespaces
  log_info "Creating namespaces..."
  if [[ "$DRY_RUN" != "true" ]]; then
    kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  fi

  # Create Vault token secret for External Secrets Operator
  log_info "Creating Vault token secret..."
  if [[ "$DRY_RUN" != "true" ]]; then
    kubectl create secret generic vault-token \
      --from-literal=token="$VAULT_TOKEN" \
      -n external-secrets \
      --dry-run=client -o yaml | kubectl apply -f -
  fi

  # Install required CRDs
  log_info "Installing ServiceMonitor CRD..."
  if [[ "$DRY_RUN" != "true" ]]; then
    kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml
  fi

  log_info "Installing Gateway API CRDs..."
  if [[ "$DRY_RUN" != "true" ]]; then
    kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null || \
      kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml
  fi

  # Create ArgoCD repository secrets
  log_info "Creating ArgoCD repository secrets..."
  for repo_config in "${ARGOCD_REPOS[@]}"; do
    IFS='|' read -r secret_name repo_url key_file <<< "$repo_config"

    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "(DRY RUN) Would create secret: $secret_name"
      continue
    fi

    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${repo_url}
  sshPrivateKey: |
$(sed 's/^/    /' "${SSH_KEYS_BASE_PATH}/${key_file}")
EOF
    log_debug "Created repository secret: $secret_name"
  done

  log_success "Cluster preparation complete"
}

step_install_argocd() {
  log_step "Installing ArgoCD"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would install ArgoCD"
    return 0
  fi

  # Build and apply ArgoCD manifests
  log_info "Building ArgoCD manifests..."
  local manifests
  if ! manifests=$(kustomize build --enable-helm "${REPO_ROOT}/src/platform/core/argocd/base"); then
    log_error "Failed to build ArgoCD manifests"
    return 1
  fi

  log_info "Applying ArgoCD manifests..."
  echo "$manifests" | kubectl apply -f -

  # Wait for ArgoCD server
  log_info "Waiting for ArgoCD server to be ready..."
  if ! kubectl wait --for=condition=available --timeout="$KUBECTL_TIMEOUT" \
    deployment/argocd-server -n argocd; then
    log_error "ArgoCD server failed to become ready"
    return 1
  fi

  log_success "ArgoCD installed successfully"
}

step_deploy_applications() {
  log_step "Deploying ArgoCD applications"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would deploy applications"
    return 0
  fi

  # Stage 1: Projects and Security
  log_info "Stage 1: Deploying projects and security..."
  kubectl apply -k "${REPO_ROOT}/src/app-projects/"
  kubectl apply -f "${REPO_ROOT}/src/application-sets/security/applicationset.yaml"
  sleep 10

  # # Stage 2: Platform infrastructure
  # log_info "Stage 2: Deploying platform infrastructure..."
  # kubectl apply -f "${REPO_ROOT}/src/application-sets/platform/applicationset.yaml"

  # # Wait for External Secrets Operator
  # log_info "Waiting for External Secrets Operator..."
  # local max_attempts=60
  # for ((i=1; i<=max_attempts; i++)); do
  #   if kubectl get deployment external-secrets -n external-secrets &>/dev/null; then
  #     if kubectl wait --for=condition=available --timeout=30s \
  #       deployment/external-secrets -n external-secrets 2>/dev/null; then
  #       break
  #     fi
  #   fi
  #   echo -n "."
  #   sleep 5
  # done
  # echo ""
  # log_success "External Secrets Operator ready"

  # Stage 3: Root app (self-management and AI workloads)
  log_info "Stage 3: Deploying root application..."
  kubectl apply -f "${REPO_ROOT}/src/root-app.yaml"

  # Trigger ArgoCD refresh
  # TODO: do we need?
  # log_info "Triggering ArgoCD refresh..."
  # sleep 15
  # kubectl rollout restart deployment/argocd-repo-server -n argocd
  # kubectl wait --for=condition=ready pod -n argocd \
  #   -l app.kubernetes.io/name=argocd-repo-server --timeout=120s || true

  log_success "Applications deployed successfully"
}

step_create_summary() {
  log_step "Creating bootstrap summary"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) No summary created"
    return 0
  fi

  # Ensure output directory exists
  mkdir -p "$SUMMARY_OUTPUT_DIR"

  # Get ArgoCD admin password
  local argocd_password="<not yet available>"
  if kubectl get secret argocd-initial-admin-secret -n argocd &>/dev/null; then
    argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
      -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "<failed to retrieve>")
  fi

  # Create summary JSON
  local summary_file="${SUMMARY_OUTPUT_DIR}/bootstrap-summary.json"
  cat > "$summary_file" <<EOF
{
  "bootstrap": {
    "timestamp": "$BOOTSTRAP_TIMESTAMP",
    "context": "$KUBECTL_CONTEXT",
    "script_version": "$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
  },
  "argocd": {
    "namespace": "argocd",
    "username": "admin",
    "password": "$argocd_password",
    "url": "https://argocd.core.internal.opencloudhub.org"
  },
  "repositories": [
$(for repo_config in "${ARGOCD_REPOS[@]}"; do
    IFS='|' read -r name url _ <<< "$repo_config"
    echo "    {\"name\": \"$name\", \"url\": \"$url\"},"
  done | sed '$ s/,$//')
  ]
}
EOF

  log_success "Summary saved to: $summary_file"
}

print_completion_summary() {
  print_section_header "Bootstrap Complete"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN completed - no changes were applied"
    echo ""
    return 0
  fi

  local argocd_password
  argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "<unavailable>")

  echo ""
  echo -e "  ${GREEN}ArgoCD Access:${NC}"
  echo -e "    URL:      https://argocd.core.internal.opencloudhub.org"
  echo -e "    Username: admin"
  echo -e "    Password: $argocd_password"
  echo ""
  echo -e "  ${CYAN}Summary file:${NC} ${SUMMARY_OUTPUT_DIR}/bootstrap-summary.json"
  echo ""
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
  BOOTSTRAP_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  print_banner "GitOps Bootstrap" "${KUBECTL_CONTEXT:-initializing}"

  step_check_prerequisites
  step_prepare_cluster
  step_install_argocd
  step_deploy_applications
  step_create_summary
  print_completion_summary
}

main "$@"
