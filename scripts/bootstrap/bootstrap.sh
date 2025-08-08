#!/bin/bash
# ==============================================
# scripts/bootstrap.sh
# GitOps Bootstrap Orchestrator
# ==============================================

set -euo pipefail

# ------------------------------
# Load Common Libraries
# ------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
source "$REPO_ROOT/scripts/bootstrap/_utils.sh"

# ------------------------------
# Configuration
# ------------------------------
KUBECONFIG_PATH="${KUBECONFIG_PATH:-}"
DRY_RUN="${DRY_RUN:-false}"
VAULT_TOKEN="${VAULT_TOKEN:-1234}"

# Runtime variables
BOOTSTRAP_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BOOTSTRAP_SUMMARY_FILE="${REPO_ROOT}/bootstrap-summaries/bootstrap-summary.json"
KUBECTL_CONTEXT=""

readonly SSH_KEYS_BASE_PATH="${HOME}/.ssh/opencloudhub"
readonly KUBECTL_TIMEOUT="300s"

# ------------------------------
# Helper Functions
# ------------------------------
check_cluster_connectivity() {
  local current_context
  if ! current_context=$(kubectl config current-context 2>/dev/null); then
    log_error "No kubectl context found. Please set up kubectl context first."
    return 1
  fi
  
  if kubectl cluster-info >/dev/null 2>&1; then
    log_success "Connected to cluster context: $current_context"
    KUBECTL_CONTEXT="$current_context"
    return 0
  else
    log_error "Cannot connect to cluster with context: $current_context"
    return 1
  fi
}

create_summary() {
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "🔍 DRY RUN completed - no changes were applied"
    return 0
  fi

  # Get ArgoCD admin password
  local argocd_password=""
  if kubectl get secret argocd-initial-admin-secret -n argocd >/dev/null 2>&1; then
    argocd_password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d 2>/dev/null || echo "failed to retrieve")
  fi
  
  # Create summary JSON
  cat > "$BOOTSTRAP_SUMMARY_FILE" << EOF
{
  "bootstrap_info": {
    "timestamp": "$BOOTSTRAP_TIMESTAMP",
    "kubectl_context": "$KUBECTL_CONTEXT",
    "dry_run": $DRY_RUN,
    "script_version": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
  },
  "argocd": {
    "username": "admin",
    "password": "$argocd_password"
  }
}
EOF
  
  print_section_header "Bootstrap Complete"
  log_info "✅ Bootstrap completed successfully!"
  log_info "📋 Summary and credentials saved to: ${BOOTSTRAP_SUMMARY_FILE}"
  log_info "🌐 Access ArgoCD at the configured URL with username 'admin'"
}

# ------------------------------
# Bootstrap Steps 
# ------------------------------
bootstrap_check_prerequisites() {
  log_step "Check prerequisites"
  validate_command_exists kubectl "https://kubernetes.io/docs/tasks/tools/"
  # check_git_status
  check_cluster_connectivity
  
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "🔍 DRY RUN MODE - No changes will be applied"
  fi
}

bootstrap_cluster_prep() {
  log_step "Install essential CRDs and secrets"
  
  # Create essential namespaces and secrets
  log_info "Creating essential namespaces..."
  kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  
  # Create vault token secret
  log_info "Creating vault token secret..."
  kubectl create secret generic vault-token --from-literal=token=$VAULT_TOKEN -n external-secrets --dry-run=client -o yaml | kubectl apply -f -
  
  # Create repository secrets for each repo
  log_info "Creating ArgoCD repository secrets..."
  local repos=(
    "gitops|git@github.com:opencloudhub/gitops.git|argocd_gitops_ed25519"
  )
  
  for repo_config in "${repos[@]}"; do
    IFS='|' read -r secret_name repo_url key_file <<< "$repo_config"
    
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "(DRY RUN) Would create repository secret: ${secret_name}"
      continue
    fi
    
    # Check if key file exists
    if [[ ! -f "${SSH_KEYS_BASE_PATH}/${key_file}" ]]; then
      log_error "SSH key file not found: ${SSH_KEYS_BASE_PATH}/${key_file}"
      return 1
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
$(cat ${SSH_KEYS_BASE_PATH}/${key_file} | sed 's/^/    /')
EOF
    
    log_success "Created repository secret: ${secret_name}"
  done
}

bootstrap_install_argocd() {
  log_step "Install ArgoCD and core applications"
  
  # Install base ArgoCD
  log_info "Installing ArgoCD base..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would install ArgoCD base"
  else
    local manifests
    if ! manifests=$(kustomize build --enable-helm "${REPO_ROOT}/src/apps/core/argocd/base"); then
      log_error "Failed to build ArgoCD base manifests"
      return 1
    fi
    
    echo "$manifests" | kubectl apply -f -
    log_success "ArgoCD base installed"
    
    # Wait for ArgoCD server to be ready
    log_info "Waiting for ArgoCD server to be ready..."
    if kubectl wait --for=condition=available --timeout="$KUBECTL_TIMEOUT" deployment/argocd-server -n argocd >/dev/null 2>&1; then
      log_success "ArgoCD server is ready"
    else
      log_error "ArgoCD server failed to become ready"
      return 1
    fi
  fi
  
  # Apply ArgoCD applications
  log_info "Applying ArgoCD applications..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would apply ArgoCD applications"
  else
    kubectl apply -f ${REPO_ROOT}/src/app-projects/
    kubectl apply -f ${REPO_ROOT}/src/application-sets/security/applicationset.yaml
    kubectl apply -f ${REPO_ROOT}/src/root-app.yaml
    log_success "ArgoCD applications applied"
  fi
}

# ------------------------------
# Bootstrap Entry
# ------------------------------
main() {
  print_banner "GitOps Bootstrap" "$(kubectl config current-context 2>/dev/null || echo 'unknown')"

  bootstrap_check_prerequisites
  bootstrap_cluster_prep
  bootstrap_install_argocd
  create_summary
}

main "$@"