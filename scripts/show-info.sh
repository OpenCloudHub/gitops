#!/bin/bash
# Show environment summaries from JSON files
#
# Usage: show-info.sh [vault|bootstrap|dev|all]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../local-development/output"

show_vault() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "🔐 VAULT SUMMARY"
  echo "══════════════════════════════════════════════════"
  echo ""
  if [ -f "${OUTPUT_DIR}/vault-summary.json" ]; then
    echo "  Container: $(jq -r '.vault.container' "${OUTPUT_DIR}/vault-summary.json")"
    echo "  Address:   $(jq -r '.vault.address' "${OUTPUT_DIR}/vault-summary.json")"
    echo "  Token:     $(jq -r '.vault.token' "${OUTPUT_DIR}/vault-summary.json")"
    echo "  Started:   $(jq -r '.vault.timestamp' "${OUTPUT_DIR}/vault-summary.json")"
    echo ""
    echo "  Secrets Paths:"
    jq -r '.secrets_paths[]' "${OUTPUT_DIR}/vault-summary.json" | sed 's/^/    - /'
  else
    echo "  (no vault summary found - run 'make vault' first)"
  fi
  echo ""
  echo "══════════════════════════════════════════════════"
  echo ""
}

show_bootstrap() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "🚢 ARGOCD BOOTSTRAP SUMMARY"
  echo "══════════════════════════════════════════════════"
  echo ""
  if [ -f "${OUTPUT_DIR}/bootstrap-summary.json" ]; then
    echo "  Context:   $(jq -r '.bootstrap.context' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo "  Timestamp: $(jq -r '.bootstrap.timestamp' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo "  Version:   $(jq -r '.bootstrap.script_version' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo ""
    echo "  ArgoCD:"
    echo "    URL:      $(jq -r '.argocd.url' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo "    Username: $(jq -r '.argocd.username' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo "    Password: $(jq -r '.argocd.password' "${OUTPUT_DIR}/bootstrap-summary.json")"
    echo ""
    echo "  Repositories:"
    jq -r '.repositories[] | "    - \(.name): \(.url)"' "${OUTPUT_DIR}/bootstrap-summary.json"
  else
    echo "  (no bootstrap summary found - run 'make dev' first)"
  fi
  echo ""
  echo "══════════════════════════════════════════════════"
  echo ""
}

show_dev() {
  echo ""
  echo "══════════════════════════════════════════════════"
  echo "🖥️  DEV ENVIRONMENT SUMMARY"
  echo "══════════════════════════════════════════════════"
  echo ""
  if [ -f "${OUTPUT_DIR}/dev-summary.json" ]; then
    echo "  Cluster:   $(jq -r '.environment.cluster' "${OUTPUT_DIR}/dev-summary.json")"
    echo "  Started:   $(jq -r '.environment.started' "${OUTPUT_DIR}/dev-summary.json")"
    echo "  Completed: $(jq -r '.environment.completed' "${OUTPUT_DIR}/dev-summary.json")"
    echo ""
    echo "  Minikube:"
    echo "    CPUs:   $(jq -r '.minikube.cpus' "${OUTPUT_DIR}/dev-summary.json")"
    echo "    Memory: $(jq -r '.minikube.memory' "${OUTPUT_DIR}/dev-summary.json")"
    echo "    Disk:   $(jq -r '.minikube.disk' "${OUTPUT_DIR}/dev-summary.json")"
    echo ""
    echo "  Network:"
    echo "    Gateway IP: $(jq -r '.network.gateway_ip' "${OUTPUT_DIR}/dev-summary.json")"
    echo "    Tunnel PID: $(jq -r '.network.tunnel_pid' "${OUTPUT_DIR}/dev-summary.json")"
  else
    echo "  (no dev summary found - run 'make dev' first)"
  fi
  echo ""
  echo "══════════════════════════════════════════════════"
  echo ""
}

case "${1:-all}" in
  vault)     show_vault ;;
  bootstrap) show_bootstrap ;;
  dev)       show_dev ;;
  all)       show_dev; show_vault; show_bootstrap ;;
  *)         echo "Usage: $0 [vault|bootstrap|dev|all]"; exit 1 ;;
esac
