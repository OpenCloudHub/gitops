# Manual commands to apply everything
export VAULT_TOKEN=1234
export SSH_KEYS_BASE_PATH="${HOME}/.ssh/opencloudhub"

# Create cluster
kind create cluster --config scripts/bootstrap/local-development/kind/basic.yaml

# Setup vault
bash scripts/bootstrap/local-development/setup-vault.sh

# Assign cloud provider kind
cloud-provider-kind

# Create essential namespaces and secrets
echo "Creating essential namespaces..."
kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace istio-ingress --dry-run=client -o yaml | kubectl apply -f -

# Create vault token secret
echo "Creating vault token secret..."
kubectl create secret generic vault-token --from-literal=token="$VAULT_TOKEN" -n external-secrets --dry-run=client -o yaml | kubectl apply -f -

# Install ServiceMonitor CRD
echo "Installing ServiceMonitor CRD..."
kubectl apply -f https://raw.githubusercontent.com/prometheus-operator/prometheus-operator/main/example/prometheus-operator-crd/monitoring.coreos.com_servicemonitors.yaml

# Install Gateway CRDs needed by Cert-Manager
echo "Installing Gateway API CRDs..."
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
kubectl apply --server-side -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.4.0/experimental-install.yaml

# Pre-create ArgoCD repo-server NetworkPolicy for egress
kubectl apply -f "src/apps/core/argocd/base/argocd-repo-server-netpol.yaml"

# Create repository secrets for each repo
echo "Creating ArgoCD repository secrets..."
local repos=(
        "gitops|git@github.com:opencloudhub/gitops.git|argocd_gitops_ed25519"
    )

    for repo_config in "${repos[@]}"; do
        IFS='|' read -r secret_name repo_url key_file <<< "$repo_config"

        if [[ "$DRY_RUN" == "true" ]]; then
            echo "(DRY RUN) Would create repository secret: ${secret_name}"
            continue
        fi

        # Check if key file exists
        if [[ ! -f "${SSH_KEYS_BASE_PATH}/${key_file}" ]]; then
            echo "SSH key file not found: ${SSH_KEYS_BASE_PATH}/${key_file}"
            return 1
        fi

        cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${repo_url}
  sshPrivateKey: |
$(sed 's/^/    /' "${SSH_KEYS_BASE_PATH}/${key_file}")
EOF
        echo "Created repository secret: ${secret_name}"
    done


# Install ArgoCD base and wait for it to be ready
echo "Installing ArgoCD base..."
kustomize build --enable-helm src/apps/core/argocd/base | kubectl apply -f -


# Apply cert-manager base
echo "Installing cert-manager base..."
kustomize build --enable-helm src/apps/core/cert-manager | kubectl apply -f -
rm -rf src/apps/core/cert-manager/charts

# Apply External Secrets Operator base
echo "Installing External Secrets Operator base..."
kustomize build --enable-helm src/apps/core/external-secrets | kubectl apply -f -
rm -rf src/apps/core/external-secrets/charts

# Install Istio base
echo "Installing Istio base..."
kustomize build --enable-helm src/apps/core/istio | kubectl apply -f -
rm -rf src/apps/core/istio/base/charts

# Install Gateway
echo "Installing Gateway base..."
kustomize build --enable-helm src/apps/core/gateway | kubectl apply -f -
rm -rf src/apps/core/gateway/charts

# Install core applications via ArgoCD
echo "Installing core applications via ArgoCD..."
kubectl apply -f "src/app-projects/"
kubectl apply -f "src/application-sets/security/applicationset.yaml"
kubectl apply -f "src/root-app.yaml"
