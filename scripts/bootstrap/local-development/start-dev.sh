#!/bin/bash
# ==============================================
# scripts/bootstrap/local-development/start-dev.sh
# Spin up KIND cluster and bootstrap environment
# ==============================================

set -euo pipefail

# ------------------------------
# Load Common Libraries
# ------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
source "$REPO_ROOT/scripts/bootstrap/_utils.sh"

# ------------------------------
# Configuration Inputs
# ------------------------------
EXPOSED_SERVICES=($(get_exposed_services))

# Derived configurations
KIND_CONFIG="$REPO_ROOT/scripts/bootstrap/local-development/kind-cluster.yaml"
SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/start-dev-summary.json"
BOOTSTRAP_CLUSTER_SCRIPT="$REPO_ROOT/scripts/bootstrap/bootstrap.sh"
SETUP_LOCAL_VAULT_SCRIPT="$REPO_ROOT/scripts/bootstrap/local-development/setup-vault.sh"
BOOTSTRAP_SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/bootstrap-summary.json"
VAULT_SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/setup-vault-summary.json"

CLUSTER_NAME="$(yq '.name' "$KIND_CONFIG" 2>/dev/null || awk '/^name:/ { print $2; exit }' "$KIND_CONFIG" || echo "opencloudhub-local")"



# ------------------------------
# Helper Functions
# ------------------------------
show_resource_info() {
  local total_cpus total_mem_mb cluster_name node_count
  local cpu_limit mem_limit_gb
  
  total_cpus=$(nproc)
  total_mem_mb=$(free -m | awk '/^Mem:/ { print $2 }')
  cluster_name="$1"
  cpu_limit="$2"
  mem_limit_gb="$3"
  
  # Count Kind node containers
  node_count=$(docker ps --format '{{.Names}}' | grep -c "^${cluster_name}" || echo 0)
  
  if (( node_count == 0 )); then
    log_warning "⚠️  No containers found for cluster '$cluster_name'. Skipping resource limit application."
    return 1
  fi
  
  # Convert limits for display (extract numeric part)
  local mem_limit_numeric=${mem_limit_gb%g}  # Remove 'g' suffix
  local mem_limit_mb=$((mem_limit_numeric * 1024))
  local total_cpus_alloc=$((cpu_limit * node_count))
  local total_mem_alloc_mb=$((mem_limit_mb * node_count))
  
  echo "📦 Hardcoded per-node limits:"
  echo "    🧠 Memory: ${mem_limit_gb} (${mem_limit_mb} MiB)"
  echo "    ⚙️  CPU:    ${cpu_limit} vCPU(s)"
  echo "📊 Total reserved by Kind cluster (${node_count} nodes):"
  echo "    🧠 ${total_mem_alloc_mb} MiB memory (~$((mem_limit_numeric * node_count)) GB)"
  echo "    ⚙️  ${total_cpus_alloc} vCPUs"
  echo "💻 Host capacity:"
  echo "    🧠 ${total_mem_mb} MiB total (~$((total_mem_mb / 1024)) GiB)"
  echo "    ⚙️  ${total_cpus} vCPUs total"
  echo "📈 Resource utilization:"
  echo "    🧠 Memory: $((total_mem_alloc_mb * 100 / total_mem_mb))% of host"
  echo "    ⚙️  CPU:    $((total_cpus_alloc * 100 / total_cpus))% of host"
  
  log_info "📦 Applying hardcoded limits: CPUs=${cpu_limit}, Memory=${mem_limit_gb}g per node"
  return 0
}

apply_resource_limits() {
  local cluster_name="$1"
  
  # Hardcoded limits - optimized for your MLOps stack
  local cpu_limit="2"      # 2 CPUs per node
  local mem_limit="6g"    # 6GB per node
  
  show_resource_info "$cluster_name" "$cpu_limit" "$mem_limit" || return 0
  
  local containers
  mapfile -t containers < <(docker ps --format '{{.Names}}' --filter "name=^${cluster_name}")

  for node in "${containers[@]}"; do
    log_info "🔧 Limiting node container: $node to ${cpu_limit} CPUs, ${mem_limit} memory"
    docker update --cpus "$cpu_limit" --memory "$mem_limit" --memory-swap -1 "$node"
  done
}


# ------------------------------
# Dev Setup Steps
# ------------------------------

dev_setup_check_prerequisites() {
    log_step "Check prerequisites"

    validate_command_exists kind "https://kind.sigs.k8s.io/"
    validate_command_exists cloud-provider-kind "https://github.com/kubernetes-sigs/cloud-provider-kind"
    validate_command_exists awk 
    validate_command_exists yq "https://github.com/mikefarah/yq"
    validate_command_exists argocd "https://argo-cd.readthedocs.io/en/stable/cli_installation/"
    validate_file_exists "$KIND_CONFIG" "KIND cluster configuration"
}

dev_setup_setup_local_vault() {
    log_step "Setup local Hashicorp Vault"
    bash "$SETUP_LOCAL_VAULT_SCRIPT"
}

dev_setup_prepare_kind_cluster() {
    log_step "Setting up KIND cluster: $CLUSTER_NAME"

    if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
        log_warning "KIND cluster '$CLUSTER_NAME' already exists"
        read -rp "Delete and recreate it? [y/N]: " CONFIRM
        [[ "$CONFIRM" =~ ^[Yy]$ ]] || { log_info "Continuing with existing cluster"; return 0; }

        log_info "Deleting existing cluster..."
        kind delete cluster --name "$CLUSTER_NAME"
    fi

    log_info "Creating KIND cluster with config: $(basename "$KIND_CONFIG")"
    kind create cluster --config "$KIND_CONFIG"

    log_info "Applying resource limits to KIND nodes"
    apply_resource_limits "$CLUSTER_NAME"

    kubectl wait --for=condition=Ready nodes --all --timeout=300s
    sleep 2
    log_success "KIND cluster is ready"
}

dev_setup_assign_external_ip() {
    log_step "Setting up Cloud-Provider-Kind for external IPs"

    CLOUD_KIND_PIDS=$(pgrep -f "cloud-provider-kind" || true)
    if [[ -n "$CLOUD_KIND_PIDS" ]]; then
        log_info "Killing old cloud-provider-kind processes (PIDs: $CLOUD_KIND_PIDS)"
        echo "$CLOUD_KIND_PIDS" | xargs kill
    fi

    cloud-provider-kind >/dev/null 2>&1 &
    CLOUD_PROVIDER_PID=$!
    log_success "Cloud provider started (PID: $CLOUD_PROVIDER_PID)"
}

dev_setup_bootstrap_cluster() {
    log_step "Bootstrapping GitOps stack"
    bash "$BOOTSTRAP_CLUSTER_SCRIPT"
}

dev_setup_update_hosts() {
    log_step "Updating /etc/hosts for local access"

    local GATEWAY_IP=""
    for i in {1..300}; do
        GATEWAY_IP=$(kubectl get svc -n istio-ingress ingress-gateway-istio \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        [[ -n "$GATEWAY_IP" ]] && break
        sleep 2
    done
    [[ -z "$GATEWAY_IP" ]] && { log_error "No gateway IP found"; exit 1; }

    local needs_update=false
    for entry in "${EXPOSED_SERVICES[@]}"; do
        if ! grep -q "$entry" /etc/hosts 2>/dev/null; then
            needs_update=true
            break
        fi
    done

    if [[ "$needs_update" == "true" ]]; then
        log_info "Adding entries to /etc/hosts (requires sudo)..."
        {
            echo "# Added by opencloudhub-gitops start-dev.sh on $(date)"
            printf '%s\n' "${EXPOSED_SERVICES[@]/#/$GATEWAY_IP }"
        } | sudo tee -a /etc/hosts >/dev/null
        log_success "Updated /etc/hosts"
    else
        log_info "/etc/hosts already contains required entries"
    fi
}

dev_setup_open_uis() {
    log_step "Opening web interfaces"

    read -rp "Open ArgoCD UI in browser? [y/N]: " OPEN_BROWSER
    if [[ "$OPEN_BROWSER" =~ ^[Yy]$ ]]; then
        if command -v xdg-open >/dev/null 2>&1; then
            xdg-open "$ARGOCD_URL" >/dev/null 2>&1 &
        elif command -v open >/dev/null 2>&1; then
            open "$ARGOCD_URL" >/dev/null 2>&1 &
        else
            log_info "Cannot auto-open browser, please visit: $ARGOCD_URL"
        fi
    fi
}

create_summary() {
    log_step "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd || {
        log_error "ArgoCD deployment not ready."
        exit 1
    }

    local timestamp
    timestamp="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    local argocd_password argocd_url vault_addr
    argocd_password=$(jq -r '.argocd.password' "$BOOTSTRAP_SUMMARY_FILE" 2>/dev/null || echo "<unknown>")
    vault_addr=$(jq -r '.environment_exports.VAULT_ADDR' "$VAULT_SUMMARY_FILE" 2>/dev/null || echo "<unknown>")
    argocd_url="https://argocd.core.internal.opencloudhub.org"

    if ! curl -k --connect-timeout 5 "$argocd_url" >/dev/null 2>&1; then
        log_warning "ArgoCD not accessible via ingress. Port-forward may be needed."
        argocd_url="https://localhost:8080"
    fi

    # Safely build JSON array string
    local exposed_services_json
    exposed_services_json=$(printf '"%s",' "${EXPOSED_SERVICES[@]}")
    exposed_services_json="[${exposed_services_json%,}]"

    log_step "Creating start-dev summary JSON"
    cat > "$SUMMARY_FILE" <<EOF
{
  "start_dev_info": {
    "timestamp": "$timestamp",
    "cluster_name": "$CLUSTER_NAME",
    "kind_config": "$(basename "$KIND_CONFIG")",
    "exposed_services": $exposed_services_json
  },
  "argocd": {
    "url": "$argocd_url",
    "username": "admin",
    "password": "$argocd_password"
  },
  "vault": {
    "addr": "$vault_addr"
  },
  "usage": {
    "port_forward": "kubectl port-forward svc/argocd-server -n argocd 8080:443",
    "argocd_app_list": "argocd app list",
    "check_pods": "kubectl get pods -A"
  }
}
EOF

    print_section_header "Dev Environment Ready"
    echo "📋 Summary written to: $SUMMARY_FILE"
    echo
    echo "🔗 ArgoCD: $argocd_url"
    echo "🔐 Vault:  $vault_addr"
    echo
    echo "Use this to port-forward:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo
    echo "To inspect Argo apps:"
    echo "  argocd app list"
    echo
    log_success "Development environment is ready! 🎉"
}

# ------------------------------
# Entry Point
# ------------------------------

main() {
    print_banner "🚀 Start KIND Dev Environment"

    dev_setup_check_prerequisites
    dev_setup_setup_local_vault
    dev_setup_prepare_kind_cluster
    dev_setup_assign_external_ip
    dev_setup_bootstrap_cluster
    dev_setup_update_hosts
    create_summary
    dev_setup_open_uis
}

main "$@"
