#!/bin/bash
# scripts/devcontainer-postCreate.sh
# DevContainer post-create setup script

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/_utils.sh
source "${SCRIPT_DIR}/_utils.sh"

# ==========================
# DevContainer Setup Functions
# ==========================

install_cloud_provider_kind() {
    log_step "Installing cloud-provider-kind"
        
    log_info "Installing cloud-provider-kind via go install..."
    if go install sigs.k8s.io/cloud-provider-kind@latest; then
        log_success "cloud-provider-kind installed successfully"
        # Add GOPATH/bin to PATH if not already there
        if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
            echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
            export PATH="$HOME/go/bin:$PATH"
            log_info "Added $HOME/go/bin to PATH"
        fi
    else
        log_error "Failed to install cloud-provider-kind"
        return 1
    fi
}

setup_precommit_hooks() {
    log_step "Setting up pre-commit hooks"
    
    if [[ ! -f ".pre-commit-config.yaml" ]]; then
        log_warning "No .pre-commit-config.yaml found, skipping pre-commit setup"
        return 0
    fi
    
    log_info "Installing pre-commit hooks..."
    if pre-commit install; then
        log_success "Pre-commit hooks installed"
    else
        log_error "Failed to install pre-commit hooks"
        return 1
    fi
    
    log_info "Running pre-commit hooks on all files..."
    if pre-commit run --all-files; then
        log_success "All pre-commit hooks passed"
    else
        log_warning "Some pre-commit hooks failed - please review and fix"
        log_info "You can run 'pre-commit run --all-files' again after fixing issues"
    fi
}

verify_development_tools() {
    log_step "Verifying development tools"
    
    local tools=(
        "kubectl:https://kubernetes.io/docs/tasks/tools/"
        "helm:https://helm.sh/docs/intro/install/"
        "kind:https://kind.sigs.k8s.io/docs/user/quick-start/"
        "docker:https://docs.docker.com/get-docker/"
        "git:https://git-scm.com/downloads"
        "go:https://golang.org/doc/install"
    )
    
    local missing_tools=()
    
    for tool_info in "${tools[@]}"; do
        local tool="${tool_info%%:*}"
        local url="${tool_info##*:}"
        
        if command -v "$tool" &> /dev/null; then
            log_debug "✓ $tool: $(command -v "$tool")"
        else
            log_warning "✗ $tool: not found"
            missing_tools+=("$tool ($url)")
        fi
    done
    
    if [[ ${#missing_tools[@]} -eq 0 ]]; then
        log_success "All required development tools are available"
    else
        log_warning "Missing tools detected:"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool" >&2
        done
    fi
}

print_welcome_message() {
    cat << 'EOF'

🎉 OpenCloudHub Development Environment Ready!

Available components:
 ✓ GitOps infrastructure with ArgoCD
 ✓ MLOps pipeline with MLflow and Argo Workflows  
 ✓ Model serving with KServe
 ✓ Observability stack (Prometheus, Grafana, Loki, Tempo)
 ✓ Authentication with Keycloak
 ✓ Security with Istio and External Secrets

Quick start commands:
 🚀 Bootstrap cluster:     ./scripts/bootstrap/start-dev.sh
 📊 Access services:       kubectl port-forward -n <namespace> <service> <port>
 🔍 Check cluster status:  kubectl get pods --all-namespaces
 📈 View ArgoCD apps:      kubectl port-forward -n argocd svc/argocd-server 8080:80

Documentation: https://github.com/OpenCloudHub/docs
Happy coding! 🚀

EOF
}

# ==========================
# Main Setup Process
# ==========================

main() {
    print_banner "🚀 OpenCloudHub DevContainer Setup" "Development" "Local Kind"
    
    log_info "Starting DevContainer post-create setup..."
    
    # Verify basic tools
    verify_development_tools
    
    # Install cloud-provider-kind
    install_cloud_provider_kind
    
    # Setup pre-commit hooks
    setup_precommit_hooks
    
    # Print welcome message
    print_welcome_message
    
    log_success "DevContainer setup completed successfully!"
}

# Run main function
main "$@"