#!/bin/bash
# =============================================================================
# local-development/2-load-images.sh
# Load pre-pulled Docker images into Minikube (optional, speeds up bootstrap)
# =============================================================================
#
# Usage:
#   ./2-load-images.sh           # Load all cached images
#   ./2-load-images.sh --list    # Show image list without loading
#   ./2-load-images.sh --pull    # Pull images to host first, then load
#
# Note:
#   Images loaded with 'minikube image load' persist across stop/start
#   but NOT across 'minikube delete'. Run this after fresh minikube start.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# =============================================================================
# Image List (organized by component)
# =============================================================================

IMAGES=(
  # ArgoCD
  "quay.io/argoproj/argocd:v3.2.0"
  "public.ecr.aws/docker/library/redis:8.2.2-alpine"
  "ghcr.io/dexidp/dex:v2.43.0"
  "quay.io/argoprojlabs/argocd-image-updater:v1.0.1"

  # External Secrets
  "oci.external-secrets.io/external-secrets/external-secrets:v1.0.0"

  # Istio
  "docker.io/istio/pilot:1.28.0-distroless"
  "docker.io/istio/proxyv2:1.28.0-distroless"
  "docker.io/istio/install-cni:1.28.0-distroless"
  "docker.io/istio/ztunnel:1.28.0-distroless"

  # Cert Manager
  "quay.io/jetstack/cert-manager-controller:v1.19.1"
  "quay.io/jetstack/cert-manager-cainjector:v1.19.1"
  "quay.io/jetstack/cert-manager-webhook:v1.19.1"
  "quay.io/jetstack/cert-manager-startupapicheck:v1.19.1"

  # CloudNativePG
  "ghcr.io/cloudnative-pg/cloudnative-pg:1.26.0"
  "ghcr.io/cloudnative-pg/postgresql:17.5"
  "ghcr.io/cloudnative-pg/pgbouncer:1.24.1"
  "docker.io/dpage/pgadmin4:9.8"

  # MinIO
  "quay.io/minio/operator:v7.1.1"
  "quay.io/minio/operator-sidecar:v7.0.1"
  "quay.io/minio/minio:RELEASE.2025-04-08T15-41-24Z"

  # Grafana Stack
  "docker.io/grafana/grafana:12.3.0"
  "docker.io/grafana/loki:3.5.7"
  "docker.io/grafana/loki-canary:3.5.7"
  "docker.io/grafana/tempo:2.9.0"
  "docker.io/grafana/beyla:2.7.5"
  "docker.io/grafana/alloy:v1.11.3"
  "ghcr.io/grafana/alloy-operator:1.4.0"
  "docker.io/kiwigrid/k8s-sidecar:1.30.10"
  "quay.io/kiwigrid/k8s-sidecar:1.30.10"
  "docker.io/nginxinc/nginx-unprivileged:1.29-alpine"

  # Prometheus Stack
  "quay.io/prometheus/prometheus:v3.7.3"
  "quay.io/prometheus/pushgateway:v1.11.2"
  "quay.io/prometheus/node-exporter:v1.10.2"
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.87.0"
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.81.0"
  "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.17.0"
  "ghcr.io/opencost/opencost:1.117.6"
  "prom/memcached-exporter:v0.15.3"
  "memcached:1.6.39-alpine"
  "ghcr.io/grafana/helm-chart-toolbox-kubectl:0.1.1"

  # MLOps
  "burakince/mlflow:3.6.0"
  "quay.io/argoproj/argocli:v3.7.3"
  "quay.io/argoproj/workflow-controller:v3.7.3"
  "quay.io/kuberay/operator:v1.5.1"
  "rayproject/ray-llm:2.51.0-py311-cu128"
  "ghcr.io/grafana/k6-operator:controller-v1.1.0"

  # GitHub Actions Runner Controller
  "ghcr.io/actions/gha-runner-scale-set-controller:0.13.0"

  # Demo Apps
  "opencloudhuborg/demo-app-frontend:main-da9e301"
  "opencloudhuborg/demo-app-genai-backend:main-dc41d35"
  "opencloudhuborg/fashion-mnist-classifier-serving:main-8718b6e"
  "opencloudhuborg/wine-classifier-serving:main-7fe444c"

  # Utilities
  "docker.io/curlimages/curl:8.9.1"
)

# =============================================================================
# Functions
# =============================================================================

show_list() {
  echo "Images to load (${#IMAGES[@]} total):"
  echo ""
  for img in "${IMAGES[@]}"; do
    echo "  $img"
  done
}

pull_images() {
  log_step "Pulling images to host Docker"

  local failed=()
  for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
      log_info "Already present: $img"
    else
      log_info "Pulling: $img"
      if ! docker pull "$img"; then
        failed+=("$img")
      fi
    fi
  done

  if (( ${#failed[@]} > 0 )); then
    log_warning "Failed to pull ${#failed[@]} images:"
    printf '  %s\n' "${failed[@]}"
  fi
}

load_images() {
  log_step "Loading images into Minikube"

  # Check minikube is running
  if ! minikube status &>/dev/null; then
    log_error "Minikube is not running. Start it first with ./1-setup-minikube.sh"
    return 1
  fi

  local loaded=0
  local skipped=0
  local failed=()

  for img in "${IMAGES[@]}"; do
    if docker image inspect "$img" &>/dev/null; then
      log_info "Loading: $img"
      if minikube image load "$img" 2>/dev/null; then
        loaded=$((loaded + 1))
      else
        failed+=("$img")
      fi
    else
      log_debug "Skipping (not on host): $img"
      skipped=$((skipped + 1))
    fi
  done


  echo ""
  log_success "Loaded: $loaded images"
  if (( skipped > 0 )); then
    log_warning "Skipped: $skipped images (not on host - run with --pull first)"
  fi
  if (( ${#failed[@]} > 0 )); then
    log_warning "Failed: ${#failed[@]} images"
    printf '  %s\n' "${failed[@]}"
  fi
}

# =============================================================================
# Main
# =============================================================================

main() {
  case "${1:-}" in
    --list)
      show_list
      ;;
    --pull-only)
      pull_images
      ;;
    --pull)
      pull_images
      load_images
      ;;
    --help|-h)
      echo "Usage: $0 [--list|--pull-only|--pull]"
      echo ""
      echo "  (no args)    Load cached images from host Docker into Minikube"
      echo "  --list       Show image list without loading"
      echo "  --pull-only  Pull images to host Docker only (no Minikube required)"
      echo "  --pull       Pull images to host, then load into Minikube"
      ;;
    *)
      load_images
      ;;
  esac
}

main "$@"
