# k6-tests Kubernetes Makefile
# Runs k6 tests via TestRun CRDs in cluster

.PHONY: all test
all: help
test: smoke

NAMESPACE := k6-testing
BASE_PATH := /home/lukas/Development/projects/opencloudhub/dev/teams/platform/gitops/src/platform/testing/k6-tests/tests

# Wait for test and show logs
define run_test
	@echo ""
	@echo "════════════════════════════════════════════════════════════════"
	@echo "🧪 Running: $(1)"
	@echo "════════════════════════════════════════════════════════════════"
	@kubectl delete testrun $(1) -n $(NAMESPACE) --ignore-not-found 2>/dev/null
	@kubectl apply -f $(2)
	@while ! kubectl logs -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null | grep -q "iteration\|checks"; do sleep 2; done
	@kubectl logs -f -l k6_cr=$(1) -n $(NAMESPACE) 2>/dev/null || true
	@echo "✅ Done: $(1)"
	@echo ""
endef

# ============================================================================
# SMOKE TESTS
# ============================================================================

.PHONY: smoke
smoke: smoke-platform smoke-models smoke-apps  ## Run all smoke tests

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
smoke-models: smoke-models-custom smoke-models-base  ## All model smoke tests

.PHONY: smoke-models-custom
smoke-models-custom: smoke-fashion-mnist smoke-wine

.PHONY: smoke-models-base
smoke-models-base: smoke-qwen

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
	@kubectl get pods -n $(NAMESPACE)

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
