#!/bin/bash
# =============================================================================
# local-development/4-setup-network.sh
# Sets up Minikube tunnel and configures /etc/hosts for local access
# =============================================================================
#
# Usage:
#   ./4-setup-network.sh                    # Start tunnel + configure hosts
#   DRY_RUN=true ./4-setup-network.sh       # Preview without changes
#
# Prerequisites:
#   - Minikube running with Gateway deployed
#   - sudo access (for tunnel and /etc/hosts)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# =============================================================================
# Configuration
# =============================================================================

DRY_RUN="${DRY_RUN:-false}"
SUMMARY_OUTPUT_DIR="${SCRIPT_DIR}/output"

# =============================================================================
# Runtime Variables
# =============================================================================

GATEWAY_IP=""
TUNNEL_PID=""

# =============================================================================
# Cleanup
# =============================================================================

cleanup() {
  # Only clean PID file, don't kill tunnel on script exit
  :
}

trap cleanup EXIT INT TERM

# =============================================================================
# Steps
# =============================================================================

step_check_prerequisites() {
  log_step "Checking prerequisites"

  if ! minikube status &>/dev/null; then
    log_error "Minikube is not running"
    return 1
  fi

  if ! kubectl cluster-info &>/dev/null; then
    log_error "Cannot connect to cluster"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be applied"
  fi

  log_success "Prerequisites check passed"
}

step_wait_for_gateway_service() {
  log_step "Waiting for Gateway Service to be ready"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would wait for gateway service"
    return 0
  fi

  local max_attempts=120
  local attempt=1

  log_info "Waiting for gateway pod (up to 20 minutes)..."
  while [[ $attempt -le $max_attempts ]]; do
    local ready
    ready=$(kubectl get pods -n istio-ingress \
      -l gateway.networking.k8s.io/gateway-name=ingress-gateway \
      -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)

    if [[ "$ready" == "True" ]]; then
      log_success "Gateway pod is ready"
      return 0
    fi

    echo -n "."
    sleep 10
    ((attempt++))
  done

  echo ""
  log_error "Gateway not ready after 20 minutes"
  return 1
}

step_start_tunnel() {
  log_step "Starting Minikube tunnel"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would start Minikube tunnel"
    return 0
  fi

  # Kill any existing tunnel
  sudo pkill -f "minikube tunnel" 2>/dev/null || true
  sleep 2

  log_info "Tunnel requires sudo access..."
  if ! sudo -v; then
    log_error "sudo access required for tunnel"
    return 1
  fi

  # Capture user paths before sudo (sudo changes HOME to /root)
  local user_minikube_home="${MINIKUBE_HOME:-$HOME/.minikube}"
  local user_kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"

  log_info "Starting tunnel in background..."
  sudo MINIKUBE_HOME="$user_minikube_home" KUBECONFIG="$user_kubeconfig" \
    minikube tunnel > /tmp/minikube-tunnel.log 2>&1 &

  TUNNEL_PID=$!
  echo "$TUNNEL_PID" > /tmp/minikube-tunnel.pid

  sleep 3

  if ! ps -p "$TUNNEL_PID" &>/dev/null; then
    log_error "Tunnel process died immediately"
    log_info "Logs:"
    cat /tmp/minikube-tunnel.log 2>/dev/null | head -20
    return 1
  fi

  # Wait for LoadBalancer IPs
  local retries=5
  while (( retries > 0 )); do
    if kubectl get svc -A 2>/dev/null | grep -q "LoadBalancer.*<pending>"; then
      log_info "Waiting for LoadBalancer IPs... ($retries)"
      sleep 2
      ((retries--))
    else
      break
    fi
  done

  log_success "Tunnel started (PID: $TUNNEL_PID)"
}

step_wait_for_gateway_ip() {
  log_step "Waiting for Gateway LoadBalancer IP"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would wait for gateway IP"
    return 0
  fi

  log_info "Waiting for external IP (up to 2 minutes)..."
  local max_attempts=12
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
  log_error "Gateway IP not assigned - check tunnel status"
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

  local services
  services=$(get_exposed_services)

  if [[ ! -f /etc/hosts ]]; then
    log_warning "/etc/hosts not found - manual DNS configuration required"
    _print_manual_hosts_instructions "$services"
    return 0
  fi

  if ! sudo -n true 2>/dev/null; then
    log_info "sudo access needed for /etc/hosts update"
    if ! sudo -v; then
      log_warning "Could not obtain sudo access - manual configuration required"
      _print_manual_hosts_instructions "$services"
      return 0
    fi
  fi

  # Remove old entries
  if sudo grep -q "opencloudhub-local-dev" /etc/hosts 2>/dev/null; then
    log_info "Removing old opencloudhub /etc/hosts entries..."
    sudo sed -i '/# opencloudhub-local-dev START/,/# opencloudhub-local-dev END/d' /etc/hosts
  fi

  # Add new entries
  log_info "Adding new /etc/hosts entries..."
  local entry_count=0
  local hosts_block
  hosts_block="# opencloudhub-local-dev START (added $(date '+%Y-%m-%d %H:%M:%S'))"$'\n'
  while IFS= read -r hostname; do
    if [[ -n "$hostname" ]]; then
      hosts_block+="${GATEWAY_IP} ${hostname}"$'\n'
      entry_count=$((entry_count + 1))
    fi
  done <<< "$services"
  hosts_block+="# opencloudhub-local-dev END"

  if echo "$hosts_block" | sudo tee -a /etc/hosts >/dev/null; then
    log_success "/etc/hosts configured ($entry_count entries added)"
  else
    log_warning "Failed to update /etc/hosts - manual configuration required"
    _print_manual_hosts_instructions "$services"
  fi
}

_print_manual_hosts_instructions() {
  local services="$1"

  echo ""
  log_info "Add the following to your DNS or hosts file:"
  echo ""
  echo "# opencloudhub-local-dev"
  while IFS= read -r hostname; do
    if [[ -n "$hostname" ]]; then
      echo "${GATEWAY_IP} ${hostname}"
    fi
  done <<< "$services"
  echo ""
  log_info "On Linux/Mac: sudo nano /etc/hosts"
  log_info "On Windows: C:\\Windows\\System32\\drivers\\etc\\hosts (as admin)"
  echo ""
}

step_update_summary() {
  log_step "Updating summary"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) No summary updated"
    return 0
  fi

  mkdir -p "$SUMMARY_OUTPUT_DIR"

  local summary_file="${SUMMARY_OUTPUT_DIR}/network-summary.json"
  cat > "$summary_file" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "gateway_ip": "${GATEWAY_IP:-null}",
  "tunnel_pid": "${TUNNEL_PID:-null}",
  "tunnel_log": "/tmp/minikube-tunnel.log",
  "pid_file": "/tmp/minikube-tunnel.pid"
}
EOF

  log_success "Summary saved to: $summary_file"
}

print_completion_summary() {
  print_section_header "Network Setup Complete"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN completed - no changes were applied"
    return 0
  fi

  echo ""
  echo -e "  ${GREEN}Network:${NC}"
  echo -e "    Gateway IP: ${GATEWAY_IP:-<pending>}"
  echo -e "    Tunnel PID: ${TUNNEL_PID:-<not started>}"
  echo -e "    Tunnel Log: /tmp/minikube-tunnel.log"
  echo ""
  echo -e "  ${CYAN}Quick Access:${NC}"
  echo -e "    ArgoCD:  https://argocd.internal.opencloudhub.org"
  echo -e "    Grafana: https://grafana.internal.opencloudhub.org"
  echo -e "    MLflow:  https://mlflow.ai.internal.opencloudhub.org"
  echo ""
  echo -e "  ${YELLOW}To stop tunnel:${NC}"
  echo -e "    sudo kill ${TUNNEL_PID:-\$(cat /tmp/minikube-tunnel.pid)}"
  echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
  print_banner "Network Setup" "minikube"

  step_check_prerequisites
  step_wait_for_gateway_service
  step_start_tunnel
  step_wait_for_gateway_ip
  step_configure_hosts
  step_update_summary
  print_completion_summary
}

main "$@"
