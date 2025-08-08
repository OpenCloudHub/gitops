#!/bin/bash
# scripts/_utils.sh
# Common utilities and functions used across all scripts

set -euo pipefail

# Prevent multiple sourcing
[[ -n "${COMMON_LIB_LOADED:-}" ]] && return 0
readonly COMMON_LIB_LOADED=1

# ==========================
# Terminal Colors & Formatting
# ==========================
declare -gr RED='\033[0;31m'
declare -gr GREEN='\033[0;32m'
declare -gr YELLOW='\033[0;33m'
declare -gr BLUE='\033[0;34m'
declare -gr CYAN='\033[0;36m'
declare -gr BOLD='\033[1m'
declare -gr DIM='\033[2m'
declare -gr NC='\033[0m'

# Icons for better visual feedback
declare -gr ICON_SUCCESS="✅"
declare -gr ICON_ERROR="❌"
declare -gr ICON_WARNING="⚠️"
declare -gr ICON_INFO="ℹ️"
declare -gr ICON_STEP="🔄"
# declare -gr ICON_ROCKET="🚀"

# ==========================
# Configuration & Constants
# ==========================
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
readonly REPO_ROOT
# readonly TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%S+00:00)"
readonly LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Timeouts
readonly DEFAULT_TIMEOUT="5m"
# readonly DEPLOYMENT_TIMEOUT="10m"
# readonly RESOURCE_TIMEOUT="2m"

# ==========================
# Logging Functions
# ==========================

# Get current timestamp for logs
get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Log with level and color
log_with_level() {
    local level="$1"
    local color="$2"
    local icon="$3"
    local message="$4"

    echo -e "${color}${icon} $(get_timestamp) [${level}]${NC} $message" >&2
}

log_info() {
    log_with_level "INFO" "$CYAN" "$ICON_INFO" "$1"
}

log_error() {
    log_with_level "ERROR" "$RED$BOLD" "$ICON_ERROR" "$1"
}

log_warning() {
    log_with_level "WARNING" "$YELLOW$BOLD" "$ICON_WARNING" "$1"
}

log_success() {
    log_with_level "SUCCESS" "$GREEN$BOLD" "$ICON_SUCCESS" "$1"
}

log_step() {
    echo -e "\n${BLUE}${BOLD}${ICON_STEP} $1${NC}" >&2
}

log_debug() {
    log_with_level "DEBUG" "$DIM" "🔍" "$1"
}

# ==========================
# Progress Indicators
# ==========================

# Progress bar for long operations
show_progress() {
    local current="$1"
    local total="$2"
    local msg="${3:-Progress}"
    local width=50

    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "\r%s%s: [" "$CYAN" "$msg"
    printf "%*s" $filled | tr ' ' '█'
    printf "%*s" $empty | tr ' ' '░'
    printf "] %d%% (%d/%d)%s" "$percentage" "$current" "$total" "$NC"

    [[ $current -eq $total ]] && echo
}

# ==========================
# Banner & UI Functions
# ==========================

print_banner() {
    local title="${1:-GitOps Tools}"
    local environment="${2:-}"
    local target="${3:-}"
    local width=80

    echo
    echo -e "${BLUE}${BOLD}$(printf "%${width}s" "" | tr ' ' '=')${NC}"

    # Center the title
    local title_line="$title"
    [[ -n "$environment" ]] && title_line="$title_line - Environment: $environment"
    [[ -n "$target" ]] && title_line="$title_line - Target: $target"

    local padding=$(( (width - ${#title_line}) / 2 ))
    printf "${BLUE}${BOLD}%*s%s%*s${NC}\n" $padding "" "$title_line" $padding ""

    echo -e "${CYAN}Date: $(date)${NC}"
    echo -e "${CYAN}User: $(whoami)${NC}"
    echo -e "${CYAN}Repository: $(basename "$REPO_ROOT")${NC}"

    echo -e "${BLUE}${BOLD}$(printf "%${width}s" "" | tr ' ' '=')${NC}"
    echo
}

print_section_header() {
    local title="$1"
    local width=60

    echo -e "\n${YELLOW}${BOLD}$(printf "%${width}s" "" | tr ' ' '-')${NC}"
    echo -e "${YELLOW}${BOLD} $title${NC}"
    echo -e "${YELLOW}${BOLD}$(printf "%${width}s" "" | tr ' ' '-')${NC}"
}

# ==========================
# Utility Functions
# ==========================

# Check if array contains element
array_contains() {
    if [[ $# -lt 1 ]]; then
        echo "array_contains: missing search element" >&2
        return 2
    fi

    local element="$1"
    shift

    local item
    for item in "$@"; do
        [[ "$item" == "$element" ]] && return 0
    done
    return 1
}


# Retry function with exponential backoff
retry_with_backoff() {
    local max_attempts="$1"
    local delay="$2"
    shift 2
    local cmd=("$@")

    local attempt=1
    local current_delay="$delay"

    while [[ $attempt -le $max_attempts ]]; do
        log_debug "Attempt $attempt/$max_attempts: ${cmd[*]}"

        if "${cmd[@]}"; then
            return 0
        fi

        if [[ $attempt -lt $max_attempts ]]; then
            log_warning "Command failed. Retrying in ${current_delay}s... ($attempt/$max_attempts)"
            sleep "$current_delay"
            current_delay=$((current_delay * 2))  # Exponential backoff
        fi

        ((attempt++))
    done

    log_error "Command failed after $max_attempts attempts: ${cmd[*]}"
    return 1
}

# Wait for condition with timeout
wait_for_condition() {
    local condition_cmd="$1"
    local timeout="${2:-$DEFAULT_TIMEOUT}"
    local description="${3:-condition}"

    log_info "Waiting for $description (timeout: $timeout)"

    local timeout_seconds
    if [[ "$timeout" =~ ^([0-9]+)([smh])$ ]]; then
        local number="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[2]}"
        case "$unit" in
            s) timeout_seconds="$number" ;;
            m) timeout_seconds=$((number * 60)) ;;
            h) timeout_seconds=$((number * 3600)) ;;
        esac
    else
        timeout_seconds=300  # Default 5 minutes
    fi

    local elapsed=0
    local interval=5

    while [[ $elapsed -lt $timeout_seconds ]]; do
        if eval "$condition_cmd" >/dev/null 2>&1; then
            log_success "$description met after ${elapsed}s"
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))

        # Show progress every 30 seconds
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            log_info "Still waiting for $description... (${elapsed}s/${timeout_seconds}s)"
        fi
    done

    log_error "Timeout waiting for $description after $timeout"
    return 1
}


# Validation functions
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

    if ! command -v "$command" &> /dev/null; then
        log_error "Command '$command' is not installed or not in PATH"
        if [[ -n "$install_url" ]]; then
            log_info "Install it from: $install_url"
        fi
        exit 1
    fi
    log_debug "Command '$command' found: $(command -v "$command")"
}

# Environment variable helpers
require_env_var() {
    local var_name="$1"
    local description="${2:-$var_name}"

    if [[ -z "${!var_name:-}" ]]; then
        log_error "Required environment variable not set: $var_name ($description)"
        return 1
    fi

    log_debug "Environment variable set: $var_name"
    return 0
}

check_git_status() {

    log_step "Checking Git repository status"

    # Check if inside a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Not inside a Git repository"
        log_info "If you want to proceed anyway, run with FORCE=true"
        return 1
    fi

    # Check Git configuration
    if ! git config user.name &> /dev/null || ! git config user.email &> /dev/null; then
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
    if [ -n "$(git status --porcelain)" ]; then
        log_error "Working directory is not clean. Please commit or stash changes"
        git status --short
        return 1
    fi

    # Get and validate current branch
    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    log_info "Current branch: $current_branch"

    if [ "$current_branch" != "main" ]; then
        log_warning "Bootstrap is recommended to be run from the 'main' branch. Current branch: $current_branch"
        read -p "Do you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborted by user"
            return 1
        fi
    fi

    # Check branch status
    local LOCAL REMOTE BASE
    LOCAL=$(git rev-parse @)
    REMOTE=$(git rev-parse "@{u}" 2>/dev/null || echo "")
    BASE=$(git merge-base @ "@{u}" 2>/dev/null || echo "")

    if [ -z "$REMOTE" ]; then
        log_warning "No upstream branch set. Cannot check if branch is up-to-date"
    elif [ "$LOCAL" = "$REMOTE" ]; then
        log_info "Git repository is up to date"
    elif [ "$LOCAL" = "$BASE" ]; then
        log_error "Local branch is behind remote. Please pull changes"
        return 1
    elif [ "$REMOTE" = "$BASE" ]; then
        log_warning "Local branch has unpushed commits"
        read -p "Do you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Aborted by user"
            return 1
        fi
    else
        log_error "Local and remote have diverged. Please resolve conflicts"
        return 1
    fi

    log_success "Git repository check completed"
}

get_exposed_services() {
    local base="opencloudhub.org"

    echo "argocd.core.internal.${base}"
    echo "keycloak.auth.internal.${base}"
    echo "grafana.observability.internal.${base}"
    echo "pgadmin.storage.internal.${base}"
    echo "minio.storage.internal.${base}"
    echo "mlflow.mlops.internal.${base}"
    echo "argo.mlops.internal.${base}"
    echo "sklearn-v2-iris.models.internal.${base}"
}
