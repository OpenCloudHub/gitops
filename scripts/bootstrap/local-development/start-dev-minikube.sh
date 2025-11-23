#!/bin/bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
source "$REPO_ROOT/scripts/_utils.sh"

CLUSTER_NAME="minikube"
CPUS="${MINIKUBE_CPUS:-16}"
MEMORY="${MINIKUBE_MEMORY:-36g}"
DISK="${MINIKUBE_DISK:-100g}"

main() {
    print_banner "🚀 Start Minikube Dev Environment"

    log_step "Delete existing minikube cluster if present"
    minikube delete 2>/dev/null || true

    log_step "Start minikube with GPU support"
    minikube start \
        --driver docker \
        --container-runtime docker \
        --cpus "$CPUS" \
        --memory "$MEMORY" \
        --disk-size "$DISK" \
        --gpus all

    log_step "Create persistent data directories inside minikube"
    minikube ssh "sudo mkdir -p $MINIO_DATA_PATH $POSTGRES_DATA_PATH && sudo chmod 777 $MINIO_DATA_PATH $POSTGRES_DATA_PATH"

    log_step "✅ Minikube started with persistent storage"
    echo "   CPUs: $CPUS"
    echo "   Memory: $MEMORY"
    echo "   Disk: $DISK"
    echo "   MinIO data: $MINIO_DATA_PATH (persists across restarts)"
    echo "   Postgres data: $POSTGRES_DATA_PATH (persists across restarts)"

    log_step "Start minikube tunnel (background)"
    # Kill any existing tunnels
    pkill -f "minikube tunnel" 2>/dev/null || true
    nohup minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &
    TUNNEL_PID=$!
    log_success "Minikube tunnel started (PID: $TUNNEL_PID)"
    echo "$TUNNEL_PID" > /tmp/minikube-tunnel.pid
    sleep 5

    log_step "Setup local Vault"
    bash "$REPO_ROOT/scripts/bootstrap/local-development/setup-vault.sh"

    log_step "Bootstrap GitOps stack"
    bash "$REPO_ROOT/scripts/bootstrap/bootstrap.sh"

    log_step "Wait for ingress gateway"
    for i in {1..60}; do
        GATEWAY_IP=$(kubectl get svc -n istio-ingress ingress-gateway-istio \
            -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
        [[ -n "$GATEWAY_IP" ]] && break
        sleep 5
    done

    if [[ -z "$GATEWAY_IP" ]]; then
        log_error "Gateway IP not available after 5 minutes"
        exit 1
    fi

    log_step "Update /etc/hosts"
    EXPOSED_SERVICES=($(get_exposed_services))

    # Remove old entries
    if sudo grep -q "# Added by opencloudhub-gitops" /etc/hosts 2>/dev/null; then
        sudo sed -i '/# Added by opencloudhub-gitops/,/^$/d' /etc/hosts
    fi

    # Add new entries
    {
        echo "# Added by opencloudhub-gitops start-dev-minikube.sh"
        printf '%s\n' "${EXPOSED_SERVICES[@]/#/$GATEWAY_IP }"
        echo ""
    } | sudo tee -a /etc/hosts >/dev/null

    log_step "Verify GPU access"
    kubectl run gpu-test --rm -it --restart=Never \
        --image=nvidia/cuda:12.2.0-base-ubuntu22.04 \
        -- nvidia-smi || log_warning "GPU test failed - check: kubectl get nodes -o json | jq '.items[].status.allocatable'"

    log_success "✅ Minikube dev environment ready!"
    echo ""
    echo "Gateway IP: $GATEWAY_IP"
    echo "Tunnel PID: $TUNNEL_PID (log: /tmp/minikube-tunnel.log)"
    echo ""
    echo "To stop:"
    echo "  kill $TUNNEL_PID"
    echo "  minikube delete"
}

main "$@"
