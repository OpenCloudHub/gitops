# #!/bin/bash
# # ==============================================
# # scripts/dev/stop-dev.sh
# # Tear down KIND cluster and clean up dev env
# # ==============================================

# set -euo pipefail

# # ------------------------------
# # Load Common Libraries
# # ------------------------------
# REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
# source "$REPO_ROOT/scripts/bootstrap/_utils.sh"

# # ------------------------------
# # Configuration Inputs  
# # ------------------------------
# ENVIRONMENT="${ENVIRONMENT:-dev}"
# KIND_CONFIG="$REPO_ROOT/scripts/bootstrap/local-development/kind-cluster.yaml"
# SUMMARY_FILE="$REPO_ROOT/_start-dev-summary.txt"
# EXPOSED_SERVICES=($(get_exposed_services "$ENVIRONMENT"))

# # ------------------------------
# # Teardown Steps
# # ------------------------------
# dev_teardown_get_cluster_name() {
#     log_step "Trying to get cluster name"

#     if [[ -f "$SUMMARY_FILE" ]]; then
#         CLUSTER_NAME=$(awk -F': ' '/Cluster:/ {print $2}' "$SUMMARY_FILE")
#         log_info "Cluster name loaded from summary: $CLUSTER_NAME"
#     else
#         if [[ -f "$KIND_CONFIG" ]]; then
#             CLUSTER_NAME=$(yq '.name' "$KIND_CONFIG" 2>/dev/null || awk '/^name:/ { print $2; exit }' "$KIND_CONFIG")
#             log_info "Cluster name loaded from kind config: $CLUSTER_NAME"
#         else
#             # No summary or config - check running clusters
#             RUNNING_CLUSTERS=$(kind get clusters)
#             if [[ -z "$RUNNING_CLUSTERS" ]]; then
#                 log_info "No KIND clusters currently running. Nothing to delete."
#                 CLUSTER_NAME=""
#             else
#                 log_error "No summary or kind config found. Cannot determine cluster name."
#                 echo "Currently running kind clusters:"
#                 echo "$RUNNING_CLUSTERS"
#                 echo "Please manually run:"
#                 echo "  kind delete cluster --name=<your-cluster-name>"
#                 echo "Restart the script after."
#                 exit 1
#             fi
#         fi
#     fi
# }


# dev_teardown_delete_kind_cluster() {
#     log_step "Trying to delete KIND cluster"

#     if kind get clusters | grep -qx "$CLUSTER_NAME"; then
#         log_info "Deleting KIND cluster: $CLUSTER_NAME"
#         kind delete cluster --name="$CLUSTER_NAME"
#         log_success "Deleted KIND cluster: $CLUSTER_NAME"
#     else
#         log_info "KIND cluster '$CLUSTER_NAME' not found"
#     fi
# }

# dev_teardown_kill_cloud_provider_kind() {
#     log_step "Trying to tear down cloud-provider-kind"

#     CLOUD_PIDS=$(pgrep -f "cloud-provider-kind" || true)
#     if [[ -n "$CLOUD_PIDS" ]]; then
#         log_info "Killing cloud-provider-kind processes: $CLOUD_PIDS"
#         echo "$CLOUD_PIDS" | xargs kill
#         log_success "Killed cloud-provider-kind processes"
#     else
#         log_info "No cloud-provider-kind processes running"
#     fi
# }

# # TODO: make platform agnostic
# dev_teardown_cleanup_etc_hosts() {
#     log_step "Trying to clean /etc/hosts"

#     log_info "Cleaning up /etc/hosts entries"
#     for domain in "${EXPOSED_SERVICES[@]}"; do
#         sudo sed -i.bak "/$domain/d" /etc/hosts
#     done
#     log_success "Cleaned up /etc/hosts"
# }

# # TODO: make platform agnostic
# dev_teardown_remove_summary_file() {
#     log_step "Trying to remoev summary file"

#     if [[ -f "$SUMMARY_FILE" ]]; then
#         rm -f "$SUMMARY_FILE"
#         log_success "Removed summary file: $(basename "$SUMMARY_FILE")"
#     fi
# }

# # ------------------------------
# # Cleanup Entry
# # ------------------------------
# main() {
#     print_banner "🧹 Stop KIND Dev Environment" "$ENVIRONMENT"
#     dev_teardown_get_cluster_name
#     dev_teardown_delete_kind_cluster
#     dev_teardown_kill_cloud_provider_kind
#     dev_teardown_cleanup_etc_hosts
#     dev_teardown_remove_summary_file
#     log_success "Dev environment '$ENVIRONMENT' cleaned up 🎉"
# }

# main "$@"

#!/bin/bash
# ==============================================
# scripts/dev/stop-dev.sh
# Tear down KIND cluster and clean up dev env
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
ENVIRONMENT="${ENVIRONMENT:-dev}"
KIND_CONFIG="$REPO_ROOT/scripts/bootstrap/local-development/kind-cluster.yaml"
SUMMARY_FILE="$REPO_ROOT/_start-dev-summary.txt"
EXPOSED_SERVICES=($(get_exposed_services "$ENVIRONMENT"))

# ------------------------------
# Teardown Steps
# ------------------------------

dev_teardown_get_cluster_name() {
    log_step "Trying to get cluster name"
    if [[ -f "$SUMMARY_FILE" ]]; then
        CLUSTER_NAME=$(awk -F': ' '/Cluster:/ {print $2}' "$SUMMARY_FILE")
        log_info "Cluster name loaded from summary: $CLUSTER_NAME"
    else
        if [[ -f "$KIND_CONFIG" ]]; then
            CLUSTER_NAME=$(yq '.name' "$KIND_CONFIG" 2>/dev/null || awk '/^name:/ { print $2; exit }' "$KIND_CONFIG")
            log_info "Cluster name loaded from kind config: $CLUSTER_NAME"
        else
            # No summary or config - check running clusters
            RUNNING_CLUSTERS=$(kind get clusters)
            if [[ -z "$RUNNING_CLUSTERS" ]]; then
                log_info "No KIND clusters currently running. Nothing to delete."
                CLUSTER_NAME=""
            else
                log_error "No summary or kind config found. Cannot determine cluster name."
                echo "Currently running kind clusters:"
                echo "$RUNNING_CLUSTERS"
                echo "Please manually run:"
                echo "  kind delete cluster --name=<your-cluster-name>"
                echo "Restart the script after."
                exit 1
            fi
        fi
    fi
}

dev_teardown_kill_cloud_provider_kind() {
    log_step "Trying to tear down cloud-provider-kind"
    
    # Get process info with user details
    CLOUD_PROCESSES=$(ps aux | grep "cloud-provider-kind" | grep -v grep || true)
    
    if [[ -n "$CLOUD_PROCESSES" ]]; then
        log_info "Found cloud-provider-kind processes:"
        echo "$CLOUD_PROCESSES"
        
        # Get PIDs
        CLOUD_PIDS=$(pgrep -f "cloud-provider-kind" || true)
        
        if [[ -n "$CLOUD_PIDS" ]]; then
            log_info "Attempting to terminate cloud-provider-kind processes: $CLOUD_PIDS"
            
            # Try with sudo for graceful termination
            for pid in $CLOUD_PIDS; do
                log_info "Terminating process $pid"
                sudo kill -TERM "$pid" 2>/dev/null || {
                    log_info "Could not terminate $pid gracefully, trying force kill"
                    sudo kill -KILL "$pid" 2>/dev/null || log_info "Process $pid may have already exited"
                }
            done
            
            # Wait for processes to exit
            log_info "Waiting for processes to exit..."
            for i in {1..10}; do
                REMAINING_PIDS=$(pgrep -f "cloud-provider-kind" || true)
                if [[ -z "$REMAINING_PIDS" ]]; then
                    log_success "All cloud-provider-kind processes terminated"
                    return 0
                fi
                log_info "Still waiting for processes to exit... ($i/10)"
                sleep 1
            done
            
            # Final check and force kill any remaining
            REMAINING_PIDS=$(pgrep -f "cloud-provider-kind" || true)
            if [[ -n "$REMAINING_PIDS" ]]; then
                log_info "Force killing remaining processes: $REMAINING_PIDS"
                for pid in $REMAINING_PIDS; do
                    sudo kill -KILL "$pid" 2>/dev/null || true
                done
                sleep 2
                log_success "Force killed remaining cloud-provider-kind processes"
            fi
        fi
    else
        log_info "No cloud-provider-kind processes running"
    fi
}

dev_teardown_delete_kind_cluster() {
    log_step "Trying to delete KIND cluster"
    if [[ -n "$CLUSTER_NAME" ]] && kind get clusters | grep -qx "$CLUSTER_NAME"; then
        log_info "Deleting KIND cluster: $CLUSTER_NAME"
        kind delete cluster --name="$CLUSTER_NAME"
        log_success "Deleted KIND cluster: $CLUSTER_NAME"
        
        # Wait a moment for processes to clean up
        log_info "Waiting for cluster cleanup to complete..."
        sleep 3
    else
        log_info "KIND cluster '$CLUSTER_NAME' not found or already deleted"
    fi
}

# TODO: make platform agnostic
dev_teardown_cleanup_etc_hosts() {
    log_step "Trying to clean /etc/hosts"
    log_info "Cleaning up /etc/hosts entries"
    for domain in "${EXPOSED_SERVICES[@]}"; do
        sudo sed -i.bak "/$domain/d" /etc/hosts || true
    done
    log_success "Cleaned up /etc/hosts"
}

# TODO: make platform agnostic
dev_teardown_remove_summary_file() {
    log_step "Trying to remove summary file"
    if [[ -f "$SUMMARY_FILE" ]]; then
        rm -f "$SUMMARY_FILE"
        log_success "Removed summary file: $(basename "$SUMMARY_FILE")"
    fi
}

# ------------------------------
# Cleanup Entry
# ------------------------------

main() {
    print_banner "🧹 Stop KIND Dev Environment" "$ENVIRONMENT"
    
    # Get cluster name first
    dev_teardown_get_cluster_name
    
    # Kill cloud-provider-kind BEFORE deleting cluster to avoid race conditions
    dev_teardown_kill_cloud_provider_kind
    
    # Now delete the cluster
    dev_teardown_delete_kind_cluster
    
    # Clean up remaining items
    dev_teardown_cleanup_etc_hosts
    dev_teardown_remove_summary_file
    
    log_success "Dev environment '$ENVIRONMENT' cleaned up 🎉"
}

main "$@"