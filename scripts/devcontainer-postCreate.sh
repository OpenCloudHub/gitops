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

install_additional_tools() {
    log_step "Installing additional tools not provided by devcontainer features"

    # Go tools - installed via go install
    local go_tools=(
        "sigs.k8s.io/cloud-provider-kind:cloud-provider-kind"
        "github.com/NVIDIA/nvkind/cmd/nvkind:nvkind"
    )

    for tool_info in "${go_tools[@]}"; do
        local pkg="${tool_info%%:*}"
        local name="${tool_info##*:}"

        log_info "Installing $name via go install..."
        if go install "$pkg@latest"; then
            log_success "$name installed successfully"
        else
            log_error "Failed to install $name"
            return 1
        fi
    done

    # Ensure Go bin is in PATH
    if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
        # shellcheck disable=SC2016
        echo 'export PATH="$HOME/go/bin:$PATH"' >> ~/.bashrc
        export PATH="$HOME/go/bin:$PATH"
        log_info "Added $HOME/go/bin to PATH"
    fi

    # ArgoCD CLI - special case (binary download)
    if ! command -v argocd &> /dev/null; then
        log_info "Installing ArgoCD CLI..."
        if curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 \
            && sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd \
            && rm argocd-linux-amd64; then
            log_success "ArgoCD CLI installed successfully"
        else
            log_error "Failed to install ArgoCD CLI"
            return 1
        fi
    else
        log_info "ArgoCD CLI already installed"
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
        "yq:https://github.com/mikefarah/yq"
        "awk:https://www.gnu.org/software/gawk/"
        "argocd:https://argo-cd.readthedocs.io/en/stable/cli_installation/"
        "nvkind:https://github.com/NVIDIA/nvkind"
        "cloud-provider-kind:https://github.com/kubernetes-sigs/cloud-provider-kind"
        "kustomize:https://kubernetes-sigs.github.io/kustomize/installation/"
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
 ✓ MLOps pipeline with MLflow and Ray
 ✓ Model serving with Ray
 ✓ Observability stack (Prometheus, Grafana, Loki, Tempo)
 ✓ Authentication with Keycloak
 ✓ Security with Istio and External Secrets

Quick start commands:
 🚀 Bootstrap cluster:     bash scripts/bootstrap/start-dev.sh
 🔍 Check cluster status:  kubectl get pods --all-namespaces
 📈 View ArgoCD apps:      https://argocd.internal.opencloudhub.org

Documentation: https://github.com/OpenCloudHub/docs
Happy coding! 🚀

EOF
}

# ==========================
# Main Setup Process
# ==========================

main() {
    print_banner "🚀 OpenCloudHub DevContainer Setup"

    log_info "Starting DevContainer post-create setup..."
    log_info "We will now install additional tools and configure the environment."

    sleep 1

    # Install additional tools
    install_additional_tools

    # Verify basic tools
    verify_development_tools

    # Setup pre-commit hooks
    # setup_precommit_hooks # TODO: enable again

    # Print welcome message
    print_welcome_message

    log_success "DevContainer setup completed successfully!"
}

# Run main function
main "$@"
