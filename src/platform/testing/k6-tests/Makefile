# k6 Kubernetes Test Runner
# Runs tests via k6-operator TestRun CRDs

NAMESPACE := k6-testing
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# Resource defaults
CPU_PLATFORM := 200m
MEM_PLATFORM := 256Mi
CPU_MODEL := 500m
MEM_MODEL := 512Mi

# Colors
GREEN := \033[0;32m
CYAN := \033[0;36m
YELLOW := \033[0;33m
NC := \033[0m

# Run k6 test in cluster
# Usage: $(call run_k8s,<name>,<test_type>,<test_target>,<script_path>,<cpu>,<mem>)
define run_k8s
	@echo ""
	@echo "$(CYAN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "$(GREEN)🧪 $(2) test: $(3)$(NC)"
	@echo "$(CYAN)════════════════════════════════════════════════════════════════$(NC)"
	@echo "📋 testid: $(TIMESTAMP)"
	@kubectl delete testrun $(1) -n $(NAMESPACE) --ignore-not-found 2>/dev/null
	@cat <<EOF | kubectl apply -f -
apiVersion: k6.io/v1alpha1
kind: TestRun
metadata:
  name: $(1)
  namespace: $(NAMESPACE)
  labels:
    app.kubernetes.io/name: k6-tests
    opencloudhub.org/test-type: $(2)
    opencloudhub.org/test-target: $(3)
spec:
  parallelism: 1
  script:
    localFile: /tests/tests/$(4)
  arguments: --insecure-skip-tls-verify --out experimental-prometheus-rw --tag testid=$(TIMESTAMP) --tag test_type=$(2) --tag test_target=$(3)
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
        cpu: $(5)
        memory: $(6)
      requests:
        cpu: 100m
        memory: 128Mi
EOF
	@echo "⏳ Waiting for test..."
	@while ! kubectl logs -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null | grep -qE "iteration|checks|http_req|level=info"; do sleep 2; done
	@kubectl logs -f -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null || true
	@echo ""
	@echo "$(GREEN)✅ Complete$(NC)"
	@echo "$(YELLOW)📊 Grafana: testid=$(TIMESTAMP), test_type=$(2), test_target=$(3)$(NC)"
endef

# ============================================================================
# SMOKE TESTS
# ============================================================================

.PHONY: smoke
smoke: smoke-platform  ## Run platform smoke tests

.PHONY: smoke-all
smoke-all: smoke-platform smoke-models smoke-apps  ## Run ALL smoke tests

.PHONY: smoke-platform
smoke-platform: smoke-mlops smoke-gitops smoke-infra smoke-obs

.PHONY: smoke-mlops
smoke-mlops:
	$(call run_k8s,smoke-platform-mlops,smoke,platform-mlops,01-smoke/platform/mlops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: smoke-gitops
smoke-gitops:
	$(call run_k8s,smoke-platform-gitops,smoke,platform-gitops,01-smoke/platform/gitops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: smoke-infra
smoke-infra:
	$(call run_k8s,smoke-platform-infra,smoke,platform-infra,01-smoke/platform/infrastructure.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: smoke-obs
smoke-obs:
	$(call run_k8s,smoke-platform-obs,smoke,platform-obs,01-smoke/platform/observability.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: smoke-models
smoke-models: smoke-fashion-mnist smoke-wine smoke-qwen

.PHONY: smoke-fashion-mnist
smoke-fashion-mnist:
	$(call run_k8s,smoke-model-fashion-mnist,smoke,model-fashion-mnist,01-smoke/models/custom/fashion-mnist.js,$(CPU_MODEL),$(MEM_MODEL))

.PHONY: smoke-wine
smoke-wine:
	$(call run_k8s,smoke-model-wine,smoke,model-wine,01-smoke/models/custom/wine.js,$(CPU_MODEL),$(MEM_MODEL))

.PHONY: smoke-qwen
smoke-qwen:
	$(call run_k8s,smoke-model-qwen,smoke,model-qwen,01-smoke/models/base/qwen.js,$(CPU_MODEL),$(MEM_MODEL))

.PHONY: smoke-apps
smoke-apps: smoke-backend

.PHONY: smoke-backend
smoke-backend:
	$(call run_k8s,smoke-app-backend,smoke,app-backend,01-smoke/apps/demo-backend.js,$(CPU_MODEL),$(MEM_MODEL))

# ============================================================================
# LOAD TESTS
# ============================================================================

.PHONY: load
load: load-platform  ## Run platform load tests

.PHONY: load-platform
load-platform: load-mlops load-gitops load-infra load-obs

.PHONY: load-mlops
load-mlops:
	$(call run_k8s,load-platform-mlops,load,platform-mlops,02-load/platform/mlops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: load-gitops
load-gitops:
	$(call run_k8s,load-platform-gitops,load,platform-gitops,02-load/platform/gitops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: load-infra
load-infra:
	$(call run_k8s,load-platform-infra,load,platform-infra,02-load/platform/infrastructure.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: load-obs
load-obs:
	$(call run_k8s,load-platform-obs,load,platform-obs,02-load/platform/observability.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

# ============================================================================
# STRESS TESTS
# ============================================================================

.PHONY: stress
stress: stress-platform  ## Run platform stress tests

.PHONY: stress-platform
stress-platform: stress-mlops stress-gitops stress-infra stress-obs

.PHONY: stress-mlops
stress-mlops:
	$(call run_k8s,stress-platform-mlops,stress,platform-mlops,03-stress/platform/mlops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: stress-gitops
stress-gitops:
	$(call run_k8s,stress-platform-gitops,stress,platform-gitops,03-stress/platform/gitops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: stress-infra
stress-infra:
	$(call run_k8s,stress-platform-infra,stress,platform-infra,03-stress/platform/infrastructure.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: stress-obs
stress-obs:
	$(call run_k8s,stress-platform-obs,stress,platform-obs,03-stress/platform/observability.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

# ============================================================================
# SPIKE TESTS
# ============================================================================

.PHONY: spike
spike: spike-platform  ## Run platform spike tests

.PHONY: spike-platform
spike-platform: spike-mlops spike-gitops spike-infra spike-obs

.PHONY: spike-mlops
spike-mlops:
	$(call run_k8s,spike-platform-mlops,spike,platform-mlops,04-spike/platform/mlops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: spike-gitops
spike-gitops:
	$(call run_k8s,spike-platform-gitops,spike,platform-gitops,04-spike/platform/gitops.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: spike-infra
spike-infra:
	$(call run_k8s,spike-platform-infra,spike,platform-infra,04-spike/platform/infrastructure.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

.PHONY: spike-obs
spike-obs:
	$(call run_k8s,spike-platform-obs,spike,platform-obs,04-spike/platform/observability.js,$(CPU_PLATFORM),$(MEM_PLATFORM))

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: status
status:  ## Show running tests
	@echo "$(CYAN)TestRuns:$(NC)"
	@kubectl get testruns -n $(NAMESPACE) 2>/dev/null || echo "None"
	@echo ""
	@echo "$(CYAN)Pods:$(NC)"
	@kubectl get pods -n $(NAMESPACE) -l app=k6 2>/dev/null || echo "None"

.PHONY: logs
logs:  ## Tail logs from running test
	@kubectl logs -f -l app=k6 -n $(NAMESPACE)

.PHONY: clean
clean:  ## Delete all testruns
	@kubectl delete testruns --all -n $(NAMESPACE) --ignore-not-found
	@echo "$(GREEN)✅ Cleaned$(NC)"

.PHONY: help
help:  ## Show this help
	@echo "$(CYAN)k6 Kubernetes Test Runner$(NC)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-20s$(NC) %s\n", $$1, $$2}'

.DEFAULT_GOAL := help