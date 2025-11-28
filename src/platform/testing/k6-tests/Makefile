# k6-tests Kubernetes Makefile
# Runs k6 tests via TestRun CRDs in cluster

NAMESPACE := k6-testing
BASE_PATH := /home/lukas/Development/projects/opencloudhub/dev/teams/platform/gitops/src/platform/testing/k6-tests/tests
TIMESTAMP := $(shell date +%Y%m%d-%H%M%S)

# Run test with dynamic testid
define run_test
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"
	@echo "🧪 Running: $(1) [testid=$(1)-$(TIMESTAMP)]"
	@echo "════════════════════════════════════════════════════════════════"
	@kubectl delete testrun $(1) -n $(NAMESPACE) --ignore-not-found 2>/dev/null
	@sed 's/--out experimental-prometheus-rw/--out experimental-prometheus-rw --tag testid=$(1)-$(TIMESTAMP)/' $(2) | kubectl apply -f -
	@echo "⏳ Waiting for test to start..."
	@while ! kubectl logs -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null | grep -q "iteration\|checks\|http_req"; do sleep 2; done
	@kubectl logs -f -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null || true
	@echo ""
	@echo "📊 Grafana filter: testid = $(1)-$(TIMESTAMP)"
	@echo "✅ Done: $(1)"
	@echo ""
endef

# ============================================================================
# SMOKE TESTS
# ============================================================================

.PHONY: smoke
smoke: smoke-platform  ## Run all platform smoke tests (models/apps need services running)

.PHONY: smoke-all
smoke-all: smoke-platform smoke-models smoke-apps  ## Run ALL smoke tests

.PHONY: smoke-platform
smoke-platform: smoke-platform-mlops smoke-platform-gitops smoke-platform-infra smoke-platform-obs  ## All platform smoke tests

.PHONY: smoke-platform-mlops
smoke-platform-mlops:
	$(call run_test,smoke-platform-mlops,$(BASE_PATH)/01-smoke/platform/mlops.yaml)

.PHONY: smoke-platform-gitops
smoke-platform-gitops:
	$(call run_test,smoke-platform-gitops,$(BASE_PATH)/01-smoke/platform/gitops.yaml)

.PHONY: smoke-platform-infra
smoke-platform-infra:
	$(call run_test,smoke-platform-infrastructure,$(BASE_PATH)/01-smoke/platform/infrastructure.yaml)

.PHONY: smoke-platform-obs
smoke-platform-obs:
	$(call run_test,smoke-platform-observability,$(BASE_PATH)/01-smoke/platform/observability.yaml)

.PHONY: smoke-models
smoke-models: smoke-fashion-mnist smoke-wine smoke-qwen  ## All model smoke tests

.PHONY: smoke-fashion-mnist
smoke-fashion-mnist:
	$(call run_test,smoke-model-fashion-mnist,$(BASE_PATH)/01-smoke/models/custom/fashion-mnist.yaml)

.PHONY: smoke-wine
smoke-wine:
	$(call run_test,smoke-model-wine,$(BASE_PATH)/01-smoke/models/custom/wine.yaml)

.PHONY: smoke-qwen
smoke-qwen:
	$(call run_test,smoke-model-qwen,$(BASE_PATH)/01-smoke/models/base/qwen.yaml)

.PHONY: smoke-apps
smoke-apps: smoke-demo-backend  ## All app smoke tests

.PHONY: smoke-demo-backend
smoke-demo-backend:
	$(call run_test,smoke-app-demo-backend,$(BASE_PATH)/01-smoke/apps/demo-backend.yaml)

# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: status
status:  ## Show running tests
	@kubectl get testruns -n $(NAMESPACE)
	@echo ""
	@kubectl get pods -n $(NAMESPACE) -l app=k6

.PHONY: logs
logs:  ## Show logs from running test
	@kubectl logs -f -l app=k6 -n $(NAMESPACE)

.PHONY: clean
clean:  ## Delete all testruns
	@kubectl delete testruns --all -n $(NAMESPACE) --ignore-not-found
	@echo "✅ Cleaned up all testruns"

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
