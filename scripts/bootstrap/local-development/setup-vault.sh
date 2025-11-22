#!/bin/bash
# ==============================================
# scripts/bootstrap/local-development/setup-vault.sh
# Spin up local Hashicorp Vault in dev mode and set up secrets
# ==============================================

set -euo pipefail

# ------------------------------
# Load Common Libraries
# ------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
source "$REPO_ROOT/scripts/_utils.sh"

# ------------------------------
# Configuration Inputs
# ------------------------------
ENV_FILE="${REPO_ROOT}/scripts/bootstrap/local-development/.env.local"
SSH_KEY_FILE="${HOME}/.ssh/opencloudhub/argocd_gitops_ed25519"

# Runtime variables
SETUP_SUMMARY_FILE="${REPO_ROOT}/bootstrap-summaries/setup-vault-summary.json"
# ------------------------------
# Helpers
# ------------------------------
vault_cmd() {
  docker exec -e "VAULT_ADDR=http://127.0.0.1:${VAULT_INTERNAL_PORT}" \
              -e "VAULT_TOKEN=$VAULT_ROOT_TOKEN" \
              "$VAULT_CONTAINER_NAME" vault "$@"
}

create_summary() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "🔍 DRY RUN completed - no changes were applied"
    return 0
  fi

  log_step "Creating Vault setup summary JSON: $SETUP_SUMMARY_FILE"

  cat > "$SETUP_SUMMARY_FILE" <<EOF
{
  "vault_info": {
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "container_name": "$VAULT_CONTAINER_NAME",
    "external_address": "$VAULT_EXTERNAL_ADDR",
    "internal_port": "$VAULT_INTERNAL_PORT",
    "host_ip": "$VAULT_HOST_IP",
    "host_port": "$VAULT_HOST_PORT",
    "vault_token": "$VAULT_ROOT_TOKEN"
  },
  "environment_exports": {
    "VAULT_ADDR": "$VAULT_EXTERNAL_ADDR",
    "VAULT_TOKEN": "$VAULT_ROOT_TOKEN"
  },
  "example_usage": [
    "vault login \$VAULT_TOKEN",
    "vault kv list kv/"
  ]
}
EOF

  log_success "Vault setup summary saved to: $SETUP_SUMMARY_FILE"

  print_section_header "Vault Setup Complete"
  echo "Vault container: $VAULT_CONTAINER_NAME"
  echo "UI: ${VAULT_EXTERNAL_ADDR}/ui"
  echo "Login Token: $VAULT_ROOT_TOKEN"
  echo
  echo "To load environment manually:"
  echo "  export VAULT_ADDR=${VAULT_EXTERNAL_ADDR}"
  echo "  export VAULT_TOKEN=${VAULT_ROOT_TOKEN}"
  echo
  echo "Example CLI usage:"
  echo "  vault login \$VAULT_TOKEN"
  echo "  vault kv list kv/"
  echo
}

# ------------------------------
# Vault Setup Steps
# ------------------------------
vault_setup_check_prerequisites() {
  log_step "Check prerequisites"

  validate_command_exists docker "https://docs.docker.com/get-docker/"
  validate_file_exists "$ENV_FILE" ".env file with Vault configuration"
  validate_file_exists "$SSH_KEY_FILE" "GitOps SSH private key"

  log_success "Checked prerequisites"
}

vault_setup_load_env_vars() {
  log_step "Loading environment variables"

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    IFS='=' read -r key value <<< "$line"
    value="${value%%#*}"
    value="$(echo -e "${value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    export "$key=$value"
  done < "$ENV_FILE"


  VAULT_EXTERNAL_ADDR="http://${VAULT_HOST_IP}:${VAULT_HOST_PORT}"

  local required_vars=(
    "VAULT_HOST_IP"
    "VAULT_HOST_PORT"
    "VAULT_INTERNAL_PORT"
    "VAULT_CONTAINER_NAME"
    "VAULT_ROOT_TOKEN"
    "GITOPS_REPO_URL"
    "ARGO_WORKFLOWS_GITHUB_SERVICE_ACCOUNT_TOKEN"
    "DOCKERHUB_USERNAME"
    "DOCKERHUB_TOKEN"
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
    "OAUTH2_PROXY_CLIENT_ID_INTERNAL"
    "OAUTH2_PROXY_CLIENT_SECRET_INTERNAL"
    "OAUTH2_PROXY_COOKIE_SECRET_INTERNAL"
    "OAUTH2_PROXY_CLIENT_ID_EXTERNAL"
    "OAUTH2_PROXY_CLIENT_SECRET_EXTERNAL"
    "OAUTH2_PROXY_COOKIE_SECRET_EXTERNAL"
    "DB_SUPERUSER"
    "DB_SUPERUSER_PASSWORD"
    "DB_KEYCLOAK_USER"
    "DB_KEYCLOAK_PASSWORD"
    "DB_MLFLOW_USER"
    "DB_MLFLOW_PASSWORD"
    "DB_DEMO_APP_USER"
    "DB_DEMO_APP_PASSWORD"
    "PGADMIN_PASSWORD"
    "MINIO_ACCESS_KEY"
    "MINIO_TENANT_PASSWORD"
    "GRAFANA_ADMIN_USER"
    "GRAFANA_ADMIN_PASSWORD"
  )

  for var in "${required_vars[@]}"; do
    [[ -z "${!var:-}" ]] && log_error "Required env var '$var' is not set" && exit 1
  done

  log_success "Loaded environment variables from ${ENV_FILE}"
}

vault_setup_load_ssh_key() {
  log_step "Loading GitOps SSH private key"

  if [[ -f "$SSH_KEY_FILE" ]]; then
    GITOPS_SSH_PRIVATE_KEY=$(<"$SSH_KEY_FILE")
  else
    log_error "SSH key file not found at: $SSH_KEY_FILE"
    exit 1
  fi

  if [[ -z "$GITOPS_SSH_PRIVATE_KEY" ]]; then
    log_error "SSH key content is empty"
    exit 1
  fi

  log_success "SSH private key loaded"
}

vault_setup_check_existing_container() {
  log_step "Checking for existing Vault container"

  # Check if running
  if docker ps --format '{{.Names}}' | grep -qx "$VAULT_CONTAINER_NAME"; then
    log_success "Vault container '$VAULT_CONTAINER_NAME' is already running"
    return 1  # Don't recreate
  fi

  # Check if exists but stopped
  if docker ps -a --format '{{.Names}}' | grep -qx "$VAULT_CONTAINER_NAME"; then
    log_warning "Vault container '$VAULT_CONTAINER_NAME' exists but is stopped"
    read -rp "Start existing container? [Y/n]: " START
    if [[ ! "$START" =~ ^[Nn]$ ]]; then
      log_info "Starting existing container..."
      docker start "$VAULT_CONTAINER_NAME"
      log_success "Container started"
      return 1  # Don't recreate
    fi

    read -rp "Delete and recreate instead? [y/N]: " DELETE
    if [[ "$DELETE" =~ ^[Yy]$ ]]; then
      log_info "Removing existing container..."
      docker rm -f "$VAULT_CONTAINER_NAME" >/dev/null
      log_success "Container removed, will create new one"
      return 0  # Proceed to create
    fi

    log_info "Keeping stopped container as-is"
    return 1
  fi

  log_info "No existing Vault container found"
  return 0  # Proceed to create
}

vault_setup_start_container() {
  log_step "Starting Vault container in dev mode"

  docker run -d \
    --name "$VAULT_CONTAINER_NAME" \
    --cap-add=IPC_LOCK \
    -p "${VAULT_HOST_PORT}:${VAULT_INTERNAL_PORT}" \
    hashicorp/vault \
    server -dev \
    -dev-root-token-id="$VAULT_ROOT_TOKEN" \
    -dev-listen-address="0.0.0.0:${VAULT_INTERNAL_PORT}"

  sleep 3

  if [[ "$(docker inspect -f '{{.State.Running}}' "$VAULT_CONTAINER_NAME")" != "true" ]]; then
    log_error "Vault container failed to start"
    docker logs "$VAULT_CONTAINER_NAME"
    exit 1
  fi

  log_success "Vault container is running"
}

vault_setup_configure() {
  log_step "Configuring Vault"

  vault_cmd secrets enable -path=kv -version=2 kv 2>/dev/null || \
    log_warning "KV engine already enabled"

  log_success "Vault configured"
}

vault_setup_create_secrets() {
  log_step "Creating secrets in Vault"

  vault_cmd kv put kv/platform/gitops/repos/gitops \
    url="$GITOPS_REPO_URL" \
    type="git" \
    sshPrivateKey="$GITOPS_SSH_PRIVATE_KEY"

  vault_cmd kv put kv/platform/gitops/argo-workflows/github-service-account-token \
    token="$ARGO_WORKFLOWS_GITHUB_SERVICE_ACCOUNT_TOKEN"

  vault_cmd kv put kv/platform/docker/registry \
    username="$DOCKERHUB_USERNAME" \
    password="$DOCKERHUB_TOKEN"

  vault_cmd kv put kv/platform/storage/cnpg/superuser \
    username="$DB_SUPERUSER" password="$DB_SUPERUSER_PASSWORD"

  vault_cmd kv put kv/platform/storage/cnpg/keycloak \
    username="$DB_KEYCLOAK_USER" password="$DB_KEYCLOAK_PASSWORD"

  vault_cmd kv put kv/platform/auth/keycloak/admin \
    password="$KEYCLOAK_ADMIN_PASSWORD"

  vault_cmd kv put kv/platform/auth/keycloak/realms/internal/smtp \
    host="$KEYCLOAK_SMTP_INTERNAL_HOST" port="$KEYCLOAK_SMTP_INTERNAL_PORT" \
    user="$KEYCLOAK_SMTP_INTERNAL_USER" password="$KEYCLOAK_SMTP_INTERNAL_PASSWORD" \
    from="$KEYCLOAK_SMTP_INTERNAL_FROM" fromName="$KEYCLOAK_SMTP_INTERNAL_FROM_NAME"

  vault_cmd kv put kv/platform/auth/keycloak/realms/external/smtp \
    host="$KEYCLOAK_SMTP_EXTERNAL_HOST" port="$KEYCLOAK_SMTP_EXTERNAL_PORT" \
    user="$KEYCLOAK_SMTP_EXTERNAL_USER" password="$KEYCLOAK_SMTP_EXTERNAL_PASSWORD" \
    from="$KEYCLOAK_SMTP_EXTERNAL_FROM" fromName="$KEYCLOAK_SMTP_EXTERNAL_FROM_NAME"

  vault_cmd kv put kv/platform/auth/oauth2-proxy/internal \
    clientId="$OAUTH2_PROXY_CLIENT_ID_INTERNAL" clientSecret="$OAUTH2_PROXY_CLIENT_SECRET_INTERNAL" \
    cookieSecret="$OAUTH2_PROXY_COOKIE_SECRET_INTERNAL"

  vault_cmd kv put kv/platform/auth/oauth2-proxy/external \
    clientId="$OAUTH2_PROXY_CLIENT_ID_EXTERNAL" clientSecret="$OAUTH2_PROXY_CLIENT_SECRET_EXTERNAL" \
    cookieSecret="$OAUTH2_PROXY_COOKIE_SECRET_EXTERNAL"

  vault_cmd kv put kv/ai/storage/cnpg/mlflow \
    username="$DB_MLFLOW_USER" password="$DB_MLFLOW_PASSWORD"

  vault_cmd kv put kv/demo-app/storage/cnpg/demo-app \
    username="$DB_DEMO_APP_USER" password="$DB_DEMO_APP_PASSWORD"

  vault_cmd kv put kv/platform/storage/pgadmin/credentials \
    password="$PGADMIN_PASSWORD"

  vault_cmd kv put kv/platform/storage/minio-tenant/credentials \
    accesskey="$MINIO_ACCESS_KEY" secretkey="$MINIO_TENANT_PASSWORD"

  vault_cmd kv put kv/platform/observability/grafana/credentials \
    username="$GRAFANA_ADMIN_USER" password="$GRAFANA_ADMIN_PASSWORD"

  log_success "Secrets created"
}

# ------------------------------
# Vault Setup Entry Point
# ------------------------------
main() {
  print_banner "🔐 Setup Hashicorp Vault (Dev Mode)"

  vault_setup_check_prerequisites
  vault_setup_load_env_vars
  vault_setup_load_ssh_key
  vault_setup_check_existing_container && vault_setup_start_container && vault_setup_configure && vault_setup_create_secrets
  create_summary

  sleep 2
  log_success "Vault setup is ready! 🎉"
}

main "$@"
