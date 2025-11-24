#!/bin/bash
# =============================================================================
# local-dev/setup-vault.sh
# Starts a local HashCorp Vault in dev mode and seeds it with secrets
# =============================================================================
#
# Usage:
#   ./setup-vault.sh              # Start Vault and seed secrets
#   DRY_RUN=true ./setup-vault.sh # Preview without changes
#
# Prerequisites:
#   - Docker installed and running
#   - .env.secrets file configured (see .env.secrets.example)
#   - SSH key for ArgoCD (location configured in root .env or default)
#
# This script:
#   1. Starts Vault container in dev mode
#   2. Enables KV secrets engine
#   3. Seeds all config from .env.secrets into Vault
#
# =============================================================================

set -euo pipefail

# =============================================================================
# Load Utilities & Configuration
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "${REPO_ROOT}/scripts/_utils.sh"

# Load root .env if exists (for SSH_KEYS_BASE_PATH)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  source "${REPO_ROOT}/.env"
fi

# =============================================================================
# Configuration (Local Vault Container Settings)
# =============================================================================

VAULT_CONTAINER_NAME="vault-dev"
VAULT_INTERNAL_PORT=8200
VAULT_HOST_PORT=8200
VAULT_HOST_IP="127.0.0.1"
VAULT_EXTERNAL_ADDR="http://${VAULT_HOST_IP}:${VAULT_HOST_PORT}"

# File paths
SECRETS_FILE="${SCRIPT_DIR}/.env.secrets"
SSH_KEY_FILE="${SSH_KEYS_BASE_PATH:-${HOME}/.ssh/opencloudhub}/argocd_gitops_ed25519"
SUMMARY_OUTPUT_DIR="${SCRIPT_DIR}/output"

# Dry run mode
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# Runtime Variables (populated from .env.secrets)
# =============================================================================

VAULT_ROOT_TOKEN=""
GITOPS_SSH_PRIVATE_KEY=""

# =============================================================================
# Helper Functions
# =============================================================================

vault_cmd() {
  docker exec \
    -e "VAULT_ADDR=http://127.0.0.1:${VAULT_INTERNAL_PORT}" \
    -e "VAULT_TOKEN=${VAULT_ROOT_TOKEN}" \
    "$VAULT_CONTAINER_NAME" vault "$@"
}

load_secrets_file() {
  if [[ ! -f "$SECRETS_FILE" ]]; then
    log_error "Secrets file not found: $SECRETS_FILE"
    log_info "Copy .env.secrets.example to .env.secrets and fill in your values"
    return 1
  fi

  # Source the secrets file
  set -a
  # shellcheck source=/dev/null
  source "$SECRETS_FILE"
  set +a

  # Default VAULT_ROOT_TOKEN if not set
  VAULT_ROOT_TOKEN="${VAULT_ROOT_TOKEN:-${VAULT_TOKEN:-1234}}"

  # Validate required variables are set
  local required_vars=(
    # GitOps
    "GITOPS_REPO_URL"
    "ARGO_WORKFLOWS_GITHUB_SERVICE_ACCOUNT_TOKEN"
    # Docker
    "DOCKERHUB_USERNAME"
    "DOCKERHUB_TOKEN"
    # Keycloak
    "KEYCLOAK_ADMIN_PASSWORD"
    "KEYCLOAK_SMTP_INTERNAL_HOST"
    "KEYCLOAK_SMTP_INTERNAL_PORT"
    "KEYCLOAK_SMTP_INTERNAL_USER"
    "KEYCLOAK_SMTP_INTERNAL_PASSWORD"
    "KEYCLOAK_SMTP_INTERNAL_FROM"
    "KEYCLOAK_SMTP_INTERNAL_FROM_NAME"
    "KEYCLOAK_SMTP_EXTERNAL_HOST"
    "KEYCLOAK_SMTP_EXTERNAL_PORT"
    "KEYCLOAK_SMTP_EXTERNAL_USER"
    "KEYCLOAK_SMTP_EXTERNAL_PASSWORD"
    "KEYCLOAK_SMTP_EXTERNAL_FROM"
    "KEYCLOAK_SMTP_EXTERNAL_FROM_NAME"
    # OAuth2 Proxy
    "OAUTH2_PROXY_CLIENT_ID_INTERNAL"
    "OAUTH2_PROXY_CLIENT_SECRET_INTERNAL"
    "OAUTH2_PROXY_COOKIE_SECRET_INTERNAL"
    "OAUTH2_PROXY_CLIENT_ID_EXTERNAL"
    "OAUTH2_PROXY_CLIENT_SECRET_EXTERNAL"
    "OAUTH2_PROXY_COOKIE_SECRET_EXTERNAL"
    # Database
    "DB_SUPERUSER"
    "DB_SUPERUSER_PASSWORD"
    "DB_KEYCLOAK_USER"
    "DB_KEYCLOAK_PASSWORD"
    "DB_MLFLOW_USER"
    "DB_MLFLOW_PASSWORD"
    "DB_DEMO_APP_USER"
    "DB_DEMO_APP_PASSWORD"
    # pgAdmin
    "PGADMIN_PASSWORD"
    # MinIO
    "MINIO_ACCESS_KEY"
    "MINIO_TENANT_PASSWORD"
    # Grafana
    "GRAFANA_ADMIN_USER"
    "GRAFANA_ADMIN_PASSWORD"
  )

  local missing=()
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required variables in $SECRETS_FILE:"
    for var in "${missing[@]}"; do
      echo "  - $var" >&2
    done
    return 1
  fi

  log_success "Loaded configuration from: $SECRETS_FILE"
}

load_ssh_key() {
  if [[ ! -f "$SSH_KEY_FILE" ]]; then
    log_error "SSH key not found: $SSH_KEY_FILE"
    log_info "This key is required for ArgoCD to access the gitops repository"
    log_info "Set SSH_KEYS_BASE_PATH in root .env or ensure key exists at default location"
    return 1
  fi

  GITOPS_SSH_PRIVATE_KEY=$(<"$SSH_KEY_FILE")

  if [[ -z "$GITOPS_SSH_PRIVATE_KEY" ]]; then
    log_error "SSH key file is empty: $SSH_KEY_FILE"
    return 1
  fi

  log_success "Loaded SSH key: $SSH_KEY_FILE"
}

# =============================================================================
# Setup Steps
# =============================================================================

step_check_prerequisites() {
  log_step "Checking prerequisites"

  validate_command_exists docker "https://docs.docker.com/get-docker/"
  load_secrets_file
  load_ssh_key

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warning "DRY RUN MODE - No changes will be applied"
  fi

  log_success "Prerequisites check passed"
}

step_start_vault_container() {
  log_step "Starting Vault container"

  # Remove existing container if present
  if docker ps -a --format '{{.Names}}' | grep -qx "$VAULT_CONTAINER_NAME"; then
    log_info "Removing existing container: $VAULT_CONTAINER_NAME"
    docker rm -f "$VAULT_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would start Vault container"
    return 0
  fi

  log_info "Starting Vault in dev mode..."
  docker run -d \
    --name "$VAULT_CONTAINER_NAME" \
    --cap-add=IPC_LOCK \
    -p "${VAULT_HOST_PORT}:${VAULT_INTERNAL_PORT}" \
    hashicorp/vault \
    server -dev \
    -dev-root-token-id="$VAULT_ROOT_TOKEN" \
    -dev-listen-address="0.0.0.0:${VAULT_INTERNAL_PORT}"

  # Wait for container to be ready
  sleep 3

  if [[ "$(docker inspect -f '{{.State.Running}}' "$VAULT_CONTAINER_NAME" 2>/dev/null)" != "true" ]]; then
    log_error "Vault container failed to start"
    docker logs "$VAULT_CONTAINER_NAME" 2>&1 || true
    return 1
  fi

  log_success "Vault container running: $VAULT_CONTAINER_NAME"
}

step_configure_vault() {
  log_step "Configuring Vault"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would enable KV secrets engine"
    return 0
  fi

  # Enable KV v2 secrets engine
  vault_cmd secrets enable -path=kv -version=2 kv 2>/dev/null || \
    log_warning "KV engine already enabled (this is OK)"

  log_success "Vault configured"
}

step_seed_secrets() {
  log_step "Seeding secrets into Vault"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) Would seed secrets into Vault"
    return 0
  fi

  # ===== Platform Secrets ===== #
  # GitOps / ArgoCD
  log_info "Seeding GitOps secrets..."
  vault_cmd kv put kv/platform/gitops/repos/gitops \
    url="$GITOPS_REPO_URL" \
    type="git" \
    sshPrivateKey="$GITOPS_SSH_PRIVATE_KEY"
  vault_cmd kv put kv/platform/gitops/argo-workflows/github-service-account-token \
    token="$ARGO_WORKFLOWS_GITHUB_SERVICE_ACCOUNT_TOKEN"

  # Docker registry
  log_info "Seeding Docker registry secrets..."
  vault_cmd kv put kv/platform/docker/registry \
    username="$DOCKERHUB_USERNAME" \
    password="$DOCKERHUB_TOKEN"

  # Database credentials
  log_info "Seeding database secrets..."
  vault_cmd kv put kv/platform/storage/cnpg/superuser \
    username="$DB_SUPERUSER" \
    password="$DB_SUPERUSER_PASSWORD"
  vault_cmd kv put kv/platform/storage/cnpg/keycloak \
    username="$DB_KEYCLOAK_USER" \
    password="$DB_KEYCLOAK_PASSWORD"
  vault_cmd kv put kv/ai/storage/cnpg/mlflow \
    username="$DB_MLFLOW_USER" \
    password="$DB_MLFLOW_PASSWORD"
  vault_cmd kv put kv/demo-app/storage/cnpg/demo-app \
    username="$DB_DEMO_APP_USER" \
    password="$DB_DEMO_APP_PASSWORD"
  vault_cmd kv put kv/platform/storage/pgadmin/credentials \
    password="$PGADMIN_PASSWORD"

  # Authentication (Keycloak)
  log_info "Seeding authentication secrets..."
  vault_cmd kv put kv/platform/auth/keycloak/admin \
    password="$KEYCLOAK_ADMIN_PASSWORD"
  vault_cmd kv put kv/platform/auth/keycloak/realms/internal/smtp \
    host="$KEYCLOAK_SMTP_INTERNAL_HOST" \
    port="$KEYCLOAK_SMTP_INTERNAL_PORT" \
    user="$KEYCLOAK_SMTP_INTERNAL_USER" \
    password="$KEYCLOAK_SMTP_INTERNAL_PASSWORD" \
    from="$KEYCLOAK_SMTP_INTERNAL_FROM" \
    fromName="$KEYCLOAK_SMTP_INTERNAL_FROM_NAME"
  vault_cmd kv put kv/platform/auth/keycloak/realms/external/smtp \
    host="$KEYCLOAK_SMTP_EXTERNAL_HOST" \
    port="$KEYCLOAK_SMTP_EXTERNAL_PORT" \
    user="$KEYCLOAK_SMTP_EXTERNAL_USER" \
    password="$KEYCLOAK_SMTP_EXTERNAL_PASSWORD" \
    from="$KEYCLOAK_SMTP_EXTERNAL_FROM" \
    fromName="$KEYCLOAK_SMTP_EXTERNAL_FROM_NAME"

  # OAuth2 Proxy
  log_info "Seeding OAuth2 proxy secrets..."
  vault_cmd kv put kv/platform/auth/oauth2-proxy/internal \
    clientId="$OAUTH2_PROXY_CLIENT_ID_INTERNAL" \
    clientSecret="$OAUTH2_PROXY_CLIENT_SECRET_INTERNAL" \
    cookieSecret="$OAUTH2_PROXY_COOKIE_SECRET_INTERNAL"
  vault_cmd kv put kv/platform/auth/oauth2-proxy/external \
    clientId="$OAUTH2_PROXY_CLIENT_ID_EXTERNAL" \
    clientSecret="$OAUTH2_PROXY_CLIENT_SECRET_EXTERNAL" \
    cookieSecret="$OAUTH2_PROXY_COOKIE_SECRET_EXTERNAL"

  # Object storage (MinIO)
  log_info "Seeding MinIO secrets..."
  vault_cmd kv put kv/platform/storage/minio-tenant/credentials \
    accesskey="$MINIO_ACCESS_KEY" \
    secretkey="$MINIO_TENANT_PASSWORD"

  # Observability (Grafana)
  log_info "Seeding Grafana secrets..."
  vault_cmd kv put kv/platform/observability/grafana/credentials \
    username="$GRAFANA_ADMIN_USER" \
    password="$GRAFANA_ADMIN_PASSWORD"

  log_success "All secrets seeded into Vault"
}

step_create_summary() {
  log_step "Creating Vault summary"

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "(DRY RUN) No summary created"
    return 0
  fi

  mkdir -p "$SUMMARY_OUTPUT_DIR"

  local summary_file="${SUMMARY_OUTPUT_DIR}/vault-summary.json"
  cat > "$summary_file" <<EOF
{
  "vault": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "container": "$VAULT_CONTAINER_NAME",
    "address": "$VAULT_EXTERNAL_ADDR",
    "token": "$VAULT_ROOT_TOKEN"
  },
  "secrets_paths": [
    "kv/platform/gitops/repos/gitops",
    "kv/platform/gitops/argo-workflows/github-service-account-token",
    "kv/platform/docker/registry",
    "kv/platform/storage/cnpg/superuser",
    "kv/platform/storage/cnpg/keycloak",
    "kv/platform/storage/pgadmin/credentials",
    "kv/platform/storage/minio-tenant/credentials",
    "kv/platform/auth/keycloak/admin",
    "kv/platform/auth/keycloak/realms/internal/smtp",
    "kv/platform/auth/keycloak/realms/external/smtp",
    "kv/platform/auth/oauth2-proxy/internal",
    "kv/platform/auth/oauth2-proxy/external",
    "kv/platform/observability/grafana/credentials",
    "kv/ai/storage/cnpg/mlflow",
    "kv/demo-app/storage/cnpg/demo-app"
  ]
}
EOF

  log_success "Summary saved to: $summary_file"
}

print_completion_summary() {
  print_section_header "Vault Setup Complete"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo ""
    log_info "DRY RUN completed - no changes were applied"
    echo ""
    return 0
  fi

  echo ""
  echo -e "  ${GREEN}Vault Access:${NC}"
  echo -e "    Address: ${VAULT_EXTERNAL_ADDR}"
  echo -e "    UI:      ${VAULT_EXTERNAL_ADDR}/ui"
  echo -e "    Token:   ${VAULT_ROOT_TOKEN}"
  echo ""
  echo -e "  ${CYAN}CLI Usage:${NC}"
  echo -e "    export VAULT_ADDR=${VAULT_EXTERNAL_ADDR}"
  echo -e "    export VAULT_TOKEN=${VAULT_ROOT_TOKEN}"
  echo -e "    vault kv list kv/"
  echo ""
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
  print_banner "Vault Setup (Dev Mode)"

  step_check_prerequisites
  step_start_vault_container
  step_configure_vault
  step_seed_secrets
  step_create_summary
  print_completion_summary
}

main "$@"
