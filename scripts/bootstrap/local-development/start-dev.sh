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
# (utils sourcing skipped as requested)
# shellcheck disable=SC1091
source "$REPO_ROOT/scripts/_utils.sh"

# ------------------------------
# Configuration Inputs
# ------------------------------
# shellcheck disable=SC2207
EXPOSED_SERVICES=($(get_exposed_services))
RESOURCE_LIMITS_CONFIG="$REPO_ROOT/scripts/bootstrap/local-development/resource-limits.yaml"

# Select KIND configuration interactively
select_kind_config() {
    local kind_dir="$REPO_ROOT/scripts/bootstrap/local-development/kind"
    local configs=()

    # Use find instead of ls with xargs for safer filename handling
    while IFS= read -r -d '' file; do
        configs+=("$(basename "$file")")
    done < <(find "$kind_dir" -name "*.yaml" -print0 2>/dev/null)

    if [[ ${#configs[@]} -eq 0 ]]; then
        log_error "No KIND configs found in $kind_dir"
        exit 1
    fi

    echo "Available KIND configurations:"
    for i in "${!configs[@]}"; do
        echo "  $((i+1))) ${configs[i]}"
    done

    while true; do
        read -rp "Select config [1-${#configs[@]}]: " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#configs[@]} )); then
            KIND_CONFIG="$kind_dir/${configs[$((choice-1))]}"
            break
        fi
        echo "Invalid selection. Please choose 1-${#configs[@]}."
    done
}

select_kind_config

# Derived configurations
SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/start-dev-summary.json"
BOOTSTRAP_CLUSTER_SCRIPT="$REPO_ROOT/scripts/bootstrap/bootstrap.sh"
SETUP_LOCAL_VAULT_SCRIPT="$REPO_ROOT/scripts/bootstrap/local-development/setup-vault.sh"
BOOTSTRAP_SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/bootstrap-summary.json"
VAULT_SUMMARY_FILE="$REPO_ROOT/bootstrap-summaries/setup-vault-summary.json"

CLUSTER_NAME="$(yq '.name' "$KIND_CONFIG" 2>/dev/null || awk '/^name:/ { print $2; exit }' "$KIND_CONFIG" || echo "opencloudhub-local")"

# ------------------------------
# Resource Management Functions
# ------------------------------

detect_cluster_type() {
    # Simple hardcoded detection based on config filename
    local config_basename
    config_basename=$(basename "$KIND_CONFIG")

    case "$config_basename" in
        "basic.yaml")
            echo "single_node" ;;
        "multinode-gpu.yaml")
            echo "multi_node" ;;
        *)
            # Default to single_node for any other configs
            echo "single_node" ;;
    esac
}

get_node_type() {
    local container_name="$1"
    local cluster_name="$2"

    # Try to get node type from Kubernetes labels first
    local k8s_node_name
    k8s_node_name=$(docker exec "$container_name" hostname 2>/dev/null || echo "")

    if [[ -n "$k8s_node_name" ]]; then
        local node_type
        node_type=$(kubectl get node "$k8s_node_name" -o jsonpath='{.metadata.labels.node\.opencloudhub\.org/type}' 2>/dev/null || echo "")
        if [[ -n "$node_type" ]]; then
            echo "$node_type"
            return
        fi
    fi

    # Fallback: detect from container name patterns
    case "$container_name" in
        *control-plane*) echo "control-plane" ;;
        *worker*)
            # For worker nodes, we can't easily distinguish type from name alone
            # Default to application type
            echo "application" ;;
        *) echo "unknown" ;;
    esac
}

get_resource_limits() {
    local cluster_type="$1"
    local node_type="$2"

    # Get limits from config file
    local cpu memory

    if [[ "$cluster_type" == "single_node" ]]; then
        cpu=$(yq '.allocation_strategies.single_node.default.cpu' "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || echo "8")
        memory=$(yq '.allocation_strategies.single_node.default.memory' "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || echo "24g")
    else
        cpu=$(yq ".allocation_strategies.multi_node.${node_type}.cpu" "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || \
              yq '.allocation_strategies.multi_node.fallback.cpu' "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || echo "2")
        memory=$(yq ".allocation_strategies.multi_node.${node_type}.memory" "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || \
                 yq '.allocation_strategies.multi_node.fallback.memory' "$RESOURCE_LIMITS_CONFIG" 2>/dev/null || echo "6g")
    fi

    echo "${cpu}:${memory}"
}

show_resource_summary() {
    local cluster_name="$1"
    local cluster_type="$2"

    local total_cpus total_mem_mb
    total_cpus=$(nproc)
    total_mem_mb=$(free -m | awk '/^Mem:/ { print $2 }')

    local containers
    mapfile -t containers < <(docker ps --format '{{.Names}}' --filter "name=^${cluster_name}")

    echo "📊 Resource Allocation Summary:"
    echo "💻 Host capacity: ${total_cpus} vCPUs, ~$((total_mem_mb / 1024)) GB memory"
    echo "🏗️  Cluster type: ${cluster_type}"
    echo "📦 Node allocations:"

    local total_allocated_cpu=0
    local total_allocated_mem_gb=0

    for container in "${containers[@]}"; do
        local node_type
        node_type=$(get_node_type "$container" "$cluster_name")

        local limits
        limits=$(get_resource_limits "$cluster_type" "$node_type")
        local cpu="${limits%%:*}"
        local memory="${limits##*:}"
        local mem_numeric="${memory%g}"

        echo "    $container ($node_type): ${cpu} CPU, ${memory} memory"

        total_allocated_cpu=$((total_allocated_cpu + cpu))
        total_allocated_mem_gb=$((total_allocated_mem_gb + mem_numeric))
    done

    echo "📈 Total allocated: ${total_allocated_cpu} vCPUs ($((total_allocated_cpu * 100 / total_cpus))%), ${total_allocated_mem_gb}GB ($((total_allocated_mem_gb * 1024 * 100 / total_mem_mb))%)"
}

apply_resource_limits() {
    local cluster_name="$1"

    # Check if resource config exists
    if [[ ! -f "$RESOURCE_LIMITS_CONFIG" ]]; then
        log_warning "Resource limits config not found: $RESOURCE_LIMITS_CONFIG"
        log_info "Using default limits: 2 CPU, 6GB per node"

        # Fallback to old behavior
        local containers
        mapfile -t containers < <(docker ps --format '{{.Names}}' --filter "name=^${cluster_name}")
        for node in "${containers[@]}"; do
            log_info "🔧 Limiting $node: 2 CPUs, 6g memory"
            docker update --cpus "2" --memory "6g" --memory-swap -1 "$node"
        done
        return
    fi

    local cluster_type
    cluster_type=$(detect_cluster_type)

    log_info "Applying resource limits using config: $(basename "$RESOURCE_LIMITS_CONFIG")"
    show_resource_summary "$cluster_name" "$cluster_type"

    local containers
    mapfile -t containers < <(docker ps --format '{{.Names}}' --filter "name=^${cluster_name}")

    for container in "${containers[@]}"; do
        local node_type
        node_type=$(get_node_type "$container" "$cluster_name")

        local limits
        limits=$(get_resource_limits "$cluster_type" "$node_type")
        local cpu="${limits%%:*}"
        local memory="${limits##*:}"

        log_info "🔧 Limiting $container ($node_type): ${cpu} CPUs, ${memory} memory"
        docker update --cpus "$cpu" --memory "$memory" --memory-swap -1 "$container"
    done
}

# ------------------------------
# Dev Setup Steps
# ------------------------------

dev_setup_check_prerequisites() {
    log_step "Check prerequisites"

    validate_command_exists nvkind "https://github.com/NVIDIA/nvkind"
    validate_command_exists kind "https://kind.sigs.k8s.io/"
    validate_command_exists cloud-provider-kind "https://github.com/kubernetes-sigs/cloud-provider-kind"
    validate_command_exists helm "https://helm.sh/docs/intro/install/"
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
    # Use nvkind for all cluster creation
    nvkind cluster create --config-template="$KIND_CONFIG"

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
        log_info "Force killing old cloud-provider-kind processes (PIDs: $CLOUD_KIND_PIDS)"
        echo "$CLOUD_KIND_PIDS" | xargs kill -9 2>/dev/null || \
        echo "$CLOUD_KIND_PIDS" | xargs sudo kill -9 2>/dev/null || \
        log_warning "Could not force kill processes, continuing anyway..."
        sleep 2
    fi

    cloud-provider-kind >/dev/null 2>&1 &
    CLOUD_PROVIDER_PID=$!
    log_success "Cloud provider started (PID: $CLOUD_PROVIDER_PID)"
}

dev_setup_bootstrap_cluster() {
    log_step "Bootstrapping GitOps stack"
    bash "$BOOTSTRAP_CLUSTER_SCRIPT"
}

dev_setup_gpu_operator() {
    log_step "Setting up NVIDIA GPU Operator"

    local cluster_type
    cluster_type=$(detect_cluster_type)

    # Only install GPU operator for multi-node clusters with GPU support
    if [[ "$cluster_type" != "multi_node" ]]; then
        log_info "Skipping GPU operator installation for single-node cluster"
        return 0
    fi

    # Check if we have any GPU nodes
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l "nvidia.com/gpu.present=true" --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$gpu_nodes" -eq 0 ]]; then
        log_warning "No GPU nodes found, skipping GPU operator installation"
        return 0
    fi

    log_info "Found $gpu_nodes GPU node(s), installing NVIDIA GPU Operator..."

    # Add NVIDIA Helm repo
    if ! helm repo list | grep -q "nvidia"; then
        helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
    fi
    helm repo update nvidia

    # Install GPU operator with proper node targeting
    log_info "Installing GPU operator targeted to GPU nodes only..."
    helm upgrade --install gpu-operator \
        -n gpu-operator --create-namespace \
        nvidia/gpu-operator \
        --set driver.enabled=false \
        --set toolkit.enabled=false \
        --set operator.defaultRuntime=docker \
        --set devicePlugin.nodeSelector."nvidia\.com/gpu\.present"="true" \
        --set gfd.nodeSelector."nvidia\.com/gpu\.present"="true" \
        --set migManager.nodeSelector."nvidia\.com/gpu\.present"="true" \
        --set nodeStatusExporter.nodeSelector."nvidia\.com/gpu\.present"="true" \
        --wait --timeout=300s

    # Wait for device plugin to be ready
    log_info "Waiting for NVIDIA device plugin to be ready..."
    kubectl wait --for=condition=Ready pods -l app=nvidia-device-plugin-daemonset -n gpu-operator --timeout=120s || {
        log_warning "GPU device plugin pods may not be fully ready yet"
    }

    # Verify GPU resources are available
    local gpu_resources
    gpu_resources=$(kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels."nvidia.com/gpu.present" == "true") | {name: .metadata.name, "nvidia.com/gpu": .status.allocatable["nvidia.com/gpu"]}' 2>/dev/null || echo "")

    if [[ -n "$gpu_resources" ]]; then
        log_success "GPU operator installed successfully!"
        echo "GPU resources available:"
        echo "$gpu_resources"
    else
        log_warning "GPU operator installed but GPU resources not yet visible. This may take a few minutes."
        log_info "Check with: kubectl get nodes -o json | jq -r '.items[] | select(.metadata.labels.\"nvidia.com/gpu.present\" == \"true\") | {name: .metadata.name, \"nvidia.com/gpu\": .status.allocatable[\"nvidia.com/gpu\"]}'"
    fi
}

dev_setup_device_plugin() {
    log_step "Setting up NVIDIA k8s-device-plugin"

    local cluster_type
    cluster_type=$(detect_cluster_type)

    # Only install device plugin for multi-node clusters with GPU support
    if [[ "$cluster_type" != "multi_node" ]]; then
        log_info "Skipping device plugin installation for single-node cluster"
        return 0
    fi

    # Check if we have any GPU nodes
    local gpu_nodes
    gpu_nodes=$(kubectl get nodes -l "nvidia.com/gpu.present=true" --no-headers 2>/dev/null | wc -l || echo "0")

    if [[ "$gpu_nodes" -eq 0 ]]; then
        log_warning "No GPU nodes found, skipping device plugin installation"
        return 0
    fi

    log_info "Found $gpu_nodes GPU node(s), installing NVIDIA k8s-device-plugin..."

    # Add NVIDIA device plugin Helm repo if not already added
    if ! helm repo list | grep -q "nvidia.github.io/k8s-device-plugin"; then
        helm repo add nvdp https://nvidia.github.io/k8s-device-plugin
    fi
    helm repo update nvdp

    # Install k8s-device-plugin force targeted to GPU nodes ( auto detection fails to detect)
    helm upgrade -i \
        --namespace nvidia \
        --create-namespace \
        --set runtimeClassName=nvidia \
        nvidia-device-plugin nvdp/nvidia-device-plugin

    # Wait for device plugin to be ready
    log_info "Waiting for NVIDIA device plugin pods to be ready..."
    kubectl wait --for=condition=Ready pods -l app.kubernetes.io/name=nvidia-device-plugin -n nvidia --timeout=60s || {
        log_warning "NVIDIA device plugin pods may not be fully ready yet"
    }
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
            xdg-open "$argocd_url" >/dev/null 2>&1 &
        elif command -v open >/dev/null 2>&1; then
            open "$argocd_url" >/dev/null 2>&1 &
        else
            log_info "Cannot auto-open browser, please visit: $argocd_url"
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
    "resource_config": "$(basename "$RESOURCE_LIMITS_CONFIG")",
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
    dev_setup_device_plugin
    dev_setup_bootstrap_cluster
    dev_setup_update_hosts
    create_summary
    dev_setup_open_uis
}

main "$@"
