#!/bin/bash
# =============================================================================
# scripts/_utils.sh
# Common utilities and functions used across all bootstrap scripts
# =============================================================================
#
# Usage: source "$REPO_ROOT/scripts/_utils.sh"
#
# Provides:
#   - Logging functions (log_info, log_error, log_warning, log_success, log_step, log_debug)
#   - UI functions (print_banner, print_section_header)
#   - Validation functions (validate_file_exists, validate_command_exists)
#   - Git utilities (check_git_status)
#   - Service discovery (get_exposed_services)
#
# =============================================================================

set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_UTILS_LOADED:-}" ]] && return 0
readonly _UTILS_LOADED=1

# =============================================================================
# Terminal Colors & Formatting
# =============================================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'  # No Color

readonly ICON_SUCCESS="✅"
readonly ICON_ERROR="❌"
readonly ICON_WARNING="⚠️"
readonly ICON_INFO="ℹ️"
readonly ICON_STEP="🔄"

# =============================================================================
# Configuration
# =============================================================================

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
readonly DEFAULT_TIMEOUT="5m"

# =============================================================================
# Logging Functions
# =============================================================================

_get_timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

_log_with_level() {
  local level="$1"
  local color="$2"
  local icon="$3"
  local message="$4"
  echo -e "${color}${icon} $(_get_timestamp) [${level}]${NC} ${message}" >&2
}

log_info() {
  _log_with_level "INFO" "$CYAN" "$ICON_INFO" "$1"
}

log_error() {
  _log_with_level "ERROR" "${RED}${BOLD}" "$ICON_ERROR" "$1"
}

log_warning() {
  _log_with_level "WARNING" "${YELLOW}${BOLD}" "$ICON_WARNING" "$1"
}

log_success() {
  _log_with_level "SUCCESS" "${GREEN}${BOLD}" "$ICON_SUCCESS" "$1"
}

log_debug() {
  _log_with_level "DEBUG" "$DIM" "🔍" "$1"
}

log_step() {
  echo "" >&2
  echo -e "${BLUE}${BOLD}${ICON_STEP} $1${NC}" >&2
}

# =============================================================================
# UI Functions
# =============================================================================

print_banner() {
  local title="${1:-GitOps Tools}"
  local context="${2:-}"
  local width=70

  echo ""
  echo -e "${BLUE}${BOLD}$(printf '=%.0s' $(seq 1 $width))${NC}"

  # Build title line
  local title_line="$title"
  [[ -n "$context" ]] && title_line="$title_line [$context]"

  # Center the title
  local padding=$(( (width - ${#title_line}) / 2 ))
  printf "${BLUE}${BOLD}%*s%s%*s${NC}\n" $padding "" "$title_line" $padding ""

  echo -e "${CYAN}  Date: $(date)${NC}"
  echo -e "${CYAN}  User: $(whoami)${NC}"
  echo -e "${CYAN}  Repo: $(basename "$REPO_ROOT")${NC}"
  echo -e "${BLUE}${BOLD}$(printf '=%.0s' $(seq 1 $width))${NC}"
  echo ""
}

print_section_header() {
  local title="$1"
  local width=60

  echo "" >&2
  echo -e "${YELLOW}${BOLD}$(printf -- '-%.0s' $(seq 1 $width))${NC}" >&2
  echo -e "${YELLOW}${BOLD}  $title${NC}" >&2
  echo -e "${YELLOW}${BOLD}$(printf -- '-%.0s' $(seq 1 $width))${NC}" >&2
}

# =============================================================================
# Validation Functions
# =============================================================================

validate_file_exists() {
  local file="$1"
  local description="${2:-File}"

  if [[ ! -f "$file" ]]; then
    log_error "$description not found: $file"
    return 1
  fi

  log_debug "$description exists: $file"
  return 0
}

validate_command_exists() {
  local command="$1"
  local install_url="${2:-}"

  if ! command -v "$command" &>/dev/null; then
    log_error "Command '$command' is not installed or not in PATH"
    [[ -n "$install_url" ]] && log_info "Install from: $install_url"
    return 1
  fi

  log_debug "Command '$command' found: $(command -v "$command")"
  return 0
}

# =============================================================================
# Git Utilities
# =============================================================================

# Note: Currently disabled in bootstrap.sh but kept for future use
# Validates git repository state before deployments
check_git_status() {
  log_step "Checking Git repository status"

  # Check if inside a git repository
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_error "Not inside a Git repository"
    return 1
  fi

  # Check Git configuration
  if ! git config user.name &>/dev/null || ! git config user.email &>/dev/null; then
    log_error "Git user.name or user.email is not configured"
    return 1
  fi

  # Fetch latest changes
  log_info "Fetching latest changes from remote..."
  if ! git fetch origin --quiet; then
    log_error "Failed to fetch from remote"
    return 1
  fi

  # Check for uncommitted changes
  if [[ -n "$(git status --porcelain)" ]]; then
    log_error "Working directory is not clean. Please commit or stash changes"
    git status --short
    return 1
  fi

  # Get and validate current branch
  local current_branch
  current_branch=$(git rev-parse --abbrev-ref HEAD)
  log_info "Current branch: $current_branch"

  if [[ "$current_branch" != "main" ]]; then
    log_warning "Bootstrap is recommended from 'main' branch. Current: $current_branch"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && log_error "Aborted by user" && return 1
  fi

  # Check branch status relative to remote
  local LOCAL REMOTE BASE
  LOCAL=$(git rev-parse @)
  REMOTE=$(git rev-parse "@{u}" 2>/dev/null || echo "")
  BASE=$(git merge-base @ "@{u}" 2>/dev/null || echo "")

  if [[ -z "$REMOTE" ]]; then
    log_warning "No upstream branch set. Cannot verify sync status"
  elif [[ "$LOCAL" = "$REMOTE" ]]; then
    log_info "Branch is up to date with remote"
  elif [[ "$LOCAL" = "$BASE" ]]; then
    log_error "Local branch is behind remote. Please pull changes"
    return 1
  elif [[ "$REMOTE" = "$BASE" ]]; then
    log_warning "Local branch has unpushed commits"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && log_error "Aborted by user" && return 1
  else
    log_error "Local and remote have diverged. Please resolve conflicts"
    return 1
  fi

  log_success "Git repository check passed"
}

# =============================================================================
# Service Discovery
# =============================================================================

# Returns list of hostnames for /etc/hosts configuration
# Used by start-dev.sh to configure local DNS
#
# Structure:
#   *.internal.*        - Platform tools (ArgoCD, Grafana, MLflow, etc.)
#   *.dashboard.*       - Model Ray dashboards
#   api.*               - Public API gateway
#   <team>.*            - Team applications
#
get_exposed_services() {
  local base="opencloudhub.org"

cat <<EOF
argocd.internal.${base}
grafana.internal.${base}
mlflow.internal.${base}
argo-workflows.internal.${base}
minio.internal.${base}
minio-api.internal.${base}
pgadmin.internal.${base}
keycloak.internal.${base}
fashion-mnist.dashboard.${base}
wine-classifier.dashboard.${base}
qwen.dashboard.${base}
api.${base}
demo-app.${base}
EOF
}
