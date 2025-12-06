#!/bin/bash
# =============================================================================
# src/tests/run-test.sh
# k6 Test Execution Script
# =============================================================================
#
# Executes k6 performance tests in Kubernetes using the k6-operator.
# Creates a TestRun custom resource and streams logs to the console.
#
# Usage:
#   ./run-test.sh <name> <test_type> <test_target> <script_path> [cpu] [mem]
#
# Arguments:
#   name        - Unique identifier for the test run
#   test_type   - Category: smoke, load, stress, spike
#   test_target - What's being tested: platform-mlops, model-wine, etc.
#   script_path - Path to k6 script (relative to /tests/tests/)
#   cpu         - CPU limit (default: 200m)
#   mem         - Memory limit (default: 256Mi)
#
# Example:
#   ./run-test.sh smoke-mlops smoke platform-mlops 01-smoke/platform/mlops.js
#
# Output:
#   - Console logs from k6 execution
#   - Metrics exported to Prometheus (via k6 experimental-prometheus-rw)
#   - Test ID for Grafana filtering
#
# =============================================================================

set -e

# Usage: ./run-test.sh <name> <test_type> <test_target> <script_path> <cpu> <mem>
NAME=$1
TEST_TYPE=$2
TEST_TARGET=$3
SCRIPT_PATH=$4
CPU=${5:-200m}
MEM=${6:-256Mi}
NAMESPACE=k6-testing
TIMESTAMP=$(date +%Y%m%d-%H%M%S)

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "🧪 ${TEST_TYPE} test: ${TEST_TARGET}"
echo "════════════════════════════════════════════════════════════════"
echo "📋 testid: ${TIMESTAMP}"

kubectl delete testrun ${NAME} -n ${NAMESPACE} --ignore-not-found 2>/dev/null

cat <<EOF | kubectl apply -f -
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: ${NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: k6-tests
    opencloudhub.org/test-type: ${TEST_TYPE}
    opencloudhub.org/test-target: ${TEST_TARGET}
spec:
  parallelism: 1
  script:
    localFile: /tests/tests/${SCRIPT_PATH}
  arguments: --insecure-skip-tls-verify --out experimental-prometheus-rw --tag testid=${TIMESTAMP} --tag test_type=${TEST_TYPE} --tag test_target=${TEST_TARGET}
  cleanup: post
  runner:
    image: docker.io/opencloudhuborg/k6-tests:latest
    env:
      - name: TEST_ENV
        value: "dev"
      - name: K6_PROMETHEUS_RW_SERVER_URL
        value: "http://prometheus-server.observability.svc.cluster.local:80/api/v1/write"
      - name: K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM
        value: "true"
    resources:
      limits:
        cpu: ${CPU}
        memory: ${MEM}
      requests:
        cpu: 100m
        memory: 128Mi
EOF

echo "⏳ Waiting for test..."
while ! kubectl logs -l k6_cr=${NAME} -n ${NAMESPACE} 2>/dev/null | grep -qE "iteration|checks|http_req|level=info"; do
  sleep 2
done

kubectl logs -f -l k6_cr=${NAME} -n ${NAMESPACE} 2>/dev/null || true

echo ""
echo "✅ Complete"
echo "📊 Grafana: testid=${TIMESTAMP}, test_type=${TEST_TYPE}, test_target=${TEST_TARGET}"
