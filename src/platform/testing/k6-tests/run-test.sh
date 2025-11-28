#!/bin/bash
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
  echo "⚠️  INGRESS_IP not found in configmap. Getting from service..."
  INGRESS_IP=$(kubectl get svc -n istio-ingress ingress-gateway-istio -o jsonpath='{.spec.clusterIP}')
fi

if [ -z "$INGRESS_IP" ]; then
  echo "❌ Could not determine ingress IP"
  exit 1
fi

echo "🔧 Using ingress IP: $INGRESS_IP"
echo "🧪 Running test: $TEST_NAME"

TEMP_FILE=$(mktemp)
trap "rm -f $TEMP_FILE" EXIT

cat "$TEST_FILE" > "$TEMP_FILE"
cat >> "$TEMP_FILE" << HOSTALIASES
    hostAliases:
      - ip: "$INGRESS_IP"
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
HOSTALIASES

kubectl apply -f "$TEMP_FILE"

echo "⏳ Waiting for test pod..."
sleep 5

echo "📋 Logs:"
kubectl logs -f -l k6_cr=${TEST_NAME} -n k6-testing 2>/dev/null || echo "No logs yet, check: kubectl get pods -n k6-testing"
