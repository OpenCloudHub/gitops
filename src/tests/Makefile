# =============================================================================
# src/tests/Makefile
# k6 Performance Test Runner
# =============================================================================
#
# Provides make targets for running k6 performance tests against the platform.
# Tests are organized by type (smoke, load, stress, spike) and target.
#
# Usage:
#   make smoke          # Run all smoke tests (quick health checks)
#   make load           # Run load tests (sustained traffic)
#   make stress         # Run stress tests (find limits)
#   make spike          # Run spike tests (sudden bursts)
#   make status         # Show running tests
#   make clean          # Delete all test runs
#
# Test Targets:
#   Platform: mlops, gitops, infra, obs (observability)
#   Models: fashion-mnist, wine, qwen
#   Apps: backend (demo-app)
#
# Results:
#   Metrics are exported to Prometheus and viewable in Grafana
#   using the k6 dashboard.
#
# =============================================================================

# k6 Kubernetes Test Runner

.PHONY: all test
all: help
test: smoke

NAMESPACE := k6-testing
SCRIPT := ./run-test.sh

# Resource defaults
CPU_PLATFORM := 200m
MEM_PLATFORM := 256Mi
CPU_MODEL := 500m
MEM_MODEL := 512Mi

# ============================================================================
# SMOKE TESTS
# ============================================================================

.PHONY: smoke
smoke: smoke-platform  ## Run platform smoke tests

.PHONY: smoke-all
smoke-all: smoke-platform smoke-models smoke-apps

.PHONY: smoke-platform
smoke-platform: smoke-mlops smoke-gitops smoke-infra smoke-obs

.PHONY: smoke-mlops
smoke-mlops:
	@$(SCRIPT) smoke-platform-mlops smoke platform-mlops 01-smoke/platform/mlops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: smoke-gitops
smoke-gitops:
	@$(SCRIPT) smoke-platform-gitops smoke platform-gitops 01-smoke/platform/gitops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: smoke-infra
smoke-infra:
	@$(SCRIPT) smoke-platform-infra smoke platform-infra 01-smoke/platform/infrastructure.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: smoke-obs
smoke-obs:
	@$(SCRIPT) smoke-platform-obs smoke platform-obs 01-smoke/platform/observability.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: smoke-models
smoke-models: smoke-fashion-mnist smoke-wine smoke-qwen

.PHONY: smoke-fashion-mnist
smoke-fashion-mnist:
	@$(SCRIPT) smoke-model-fashion-mnist smoke model-fashion-mnist 01-smoke/models/custom/fashion-mnist.js $(CPU_MODEL) $(MEM_MODEL)

.PHONY: smoke-wine
smoke-wine:
	@$(SCRIPT) smoke-model-wine smoke model-wine 01-smoke/models/custom/wine.js $(CPU_MODEL) $(MEM_MODEL)

.PHONY: smoke-qwen
smoke-qwen:
	@$(SCRIPT) smoke-model-qwen smoke model-qwen 01-smoke/models/base/qwen.js $(CPU_MODEL) $(MEM_MODEL)

.PHONY: smoke-apps
smoke-apps: smoke-backend

.PHONY: smoke-backend
smoke-backend:
	@$(SCRIPT) smoke-app-backend smoke app-backend 01-smoke/apps/demo-backend.js $(CPU_MODEL) $(MEM_MODEL)

# ============================================================================
# LOAD TESTS
# ============================================================================

.PHONY: load
load: load-platform

.PHONY: load-platform
load-platform: load-mlops load-gitops load-infra load-obs

.PHONY: load-mlops
load-mlops:
	@$(SCRIPT) load-platform-mlops load platform-mlops 02-load/platform/mlops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: load-gitops
load-gitops:
	@$(SCRIPT) load-platform-gitops load platform-gitops 02-load/platform/gitops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: load-infra
load-infra:
	@$(SCRIPT) load-platform-infra load platform-infra 02-load/platform/infrastructure.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: load-obs
load-obs:
	@$(SCRIPT) load-platform-obs load platform-obs 02-load/platform/observability.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: load-models
load-models: load-fashion-mnist

.PHONY: load-fashion-mnist
load-fashion-mnist:
	@$(SCRIPT) load-model-fashion-mnist load model-fashion-mnist 02-load/models/custom/fashion-mnist.js $(CPU_MODEL) $(MEM_MODEL)

# ============================================================================
# STRESS TESTS
# ============================================================================

.PHONY: stress
stress: stress-platform

.PHONY: stress-platform
stress-platform: stress-mlops stress-gitops stress-infra stress-obs

.PHONY: stress-mlops
stress-mlops:
	@$(SCRIPT) stress-platform-mlops stress platform-mlops 03-stress/platform/mlops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: stress-gitops
stress-gitops:
	@$(SCRIPT) stress-platform-gitops stress platform-gitops 03-stress/platform/gitops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: stress-infra
stress-infra:
	@$(SCRIPT) stress-platform-infra stress platform-infra 03-stress/platform/infrastructure.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: stress-obs
stress-obs:
	@$(SCRIPT) stress-platform-obs stress platform-obs 03-stress/platform/observability.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: stress-fashion-mnist
stress-fashion-mnist:
	@$(SCRIPT) stress-model-fashion-mnist stress model-fashion-mnist 03-stress/models/custom/fashion-mnist.js $(CPU_MODEL) $(MEM_MODEL)

# ============================================================================
# SPIKE TESTS
# ============================================================================

.PHONY: spike
spike: spike-platform

.PHONY: spike-platform
spike-platform: spike-mlops spike-gitops spike-infra spike-obs

.PHONY: spike-mlops
spike-mlops:
	@$(SCRIPT) spike-platform-mlops spike platform-mlops 04-spike/platform/mlops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: spike-gitops
spike-gitops:
	@$(SCRIPT) spike-platform-gitops spike platform-gitops 04-spike/platform/gitops.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: spike-infra
spike-infra:
	@$(SCRIPT) spike-platform-infra spike platform-infra 04-spike/platform/infrastructure.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: spike-obs
spike-obs:
	@$(SCRIPT) spike-platform-obs spike platform-obs 04-spike/platform/observability.js $(CPU_PLATFORM) $(MEM_PLATFORM)

.PHONY: spike-fashion-mnist
spike-fashion-mnist:
	@$(SCRIPT) spike-model-fashion-mnist spike model-fashion-mnist 04-spike/models/custom/fashion-mnist.js $(CPU_MODEL) $(MEM_MODEL)


# ============================================================================
# UTILITIES
# ============================================================================

.PHONY: status
status:  ## Show running tests
	@kubectl get testruns -n $(NAMESPACE) 2>/dev/null || echo "None"
	@kubectl get pods -n $(NAMESPACE) -l app=k6 2>/dev/null || echo "None"

.PHONY: logs
logs:  ## Tail logs
	@kubectl logs -f -l app=k6 -n $(NAMESPACE)

.PHONY: clean
clean:  ## Delete all testruns
	@kubectl delete testruns --all -n $(NAMESPACE) --ignore-not-found

.PHONY: help
help:  ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
