#!/bin/bash
# Run a k6 TestRun with dynamic hostAliases
set -e

TEST_FILE=${1}
TEST_NAME=$(basename "$TEST_FILE" .yaml)

if [ -z "$TEST_FILE" ] || [ ! -f "$TEST_FILE" ]; then
  echo "Usage: $0 <test-file.yaml>"
  echo "Example: $0 tests/01-smoke/platform/mlops.yaml"
  exit 1
fi

INGRESS_IP=$(kubectl get configmap k6-ingress-config -n k6-testing -o jsonpath='{.data.INGRESS_IP}' 2>/dev/null)

if [ -z "$INGRESS_IP" ]; then
  echo "❌ INGRESS_IP not found. Getting from service..."
  INGRESS_IP=$(kubectl get svc -n istio-ingress ingress-gateway-istio -o jsonpath='{.spec.clusterIP}')
fi

if [ -z "$INGRESS_IP" ]; then
  echo "❌ Could not determine ingress IP"
  exit 1
fi

echo "🔧 Using ingress IP: $INGRESS_IP"

# Read the test file and inject hostAliases
HOSTS=$(cat <<HOSTS
    hostAliases:
      - ip: "${INGRESS_IP}"
        hostnames:
          - api.opencloudhub.org
          - mlflow.internal.opencloudhub.org
          - argo-workflows.internal.opencloudhub.org
          - argocd.internal.opencloudhub.org
          - minio.internal.opencloudhub.org
          - minio-api.internal.opencloudhub.org
          - pgadmin.internal.opencloudhub.org
          - grafana.internal.opencloudhub.org
          - demo-app.opencloudhub.org
          - fashion-mnist-classifier.dashboard.opencloudhub.org
          - wine-classifier.dashboard.opencloudhub.org
          - qwen-0.5b.dashboard.opencloudhub.org
HOSTS
)

# Apply with hostAliases injected after 'runner:' section
awk -v hosts="$HOSTS" '
  /^    resources:/ { in_resources=1 }
  in_resources && /^    [a-z]/ && !/resources/ { print hosts; in_resources=0 }
  { print }
  END { if (in_resources) print hosts }
' "$TEST_FILE" | kubectl apply -f -

echo "⏳ Waiting for test pod..."
sleep 3

echo "📋 Logs for ${TEST_NAME}:"
kubectl logs -f -l app=k6,k6_cr=${TEST_NAME} -n k6-testing 2>/dev/null || \
  kubectl logs -f -l k6_cr=${TEST_NAME} -n k6-testing
