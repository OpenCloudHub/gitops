# =============================================================================
# OpenCloudHub GitOps - Root Makefile
# =============================================================================
#
# Entry point for common development tasks. Delegates to specialized scripts
# and Makefiles in subdirectories.
#
# =============================================================================

.PHONY: all help
all: help

# Paths
LOCAL_DEV_DIR := local-development
TESTS_DIR := src/tests
SCRIPTS_DIR := scripts

# =============================================================================
# DEVELOPMENT ENVIRONMENT
# =============================================================================

.PHONY: dev vault

dev:  ## Start local development environment (Minikube + Vault + GitOps)
	@$(LOCAL_DEV_DIR)/start-dev.sh

vault:  ## Setup local Vault only (for standalone use)
	@$(LOCAL_DEV_DIR)/setup-vault.sh

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test test-%

test:  ## Run smoke tests
	@$(MAKE) -C $(TESTS_DIR) smoke

test-%:  ## Run specific test target (e.g., make test-load, make test-smoke-models)
	@$(MAKE) -C $(TESTS_DIR) $*

# =============================================================================
# STATUS & SUMMARIES
# =============================================================================

.PHONY: status info info-vault info-bootstrap info-dev

status:  ## Show cluster and running tests status
	@$(SCRIPTS_DIR)/show-status.sh

info:  ## Show all environment summaries
	@$(SCRIPTS_DIR)/show-info.sh all

info-vault:  ## Show Vault summary
	@$(SCRIPTS_DIR)/show-info.sh vault

info-bootstrap:  ## Show ArgoCD bootstrap summary
	@$(SCRIPTS_DIR)/show-info.sh bootstrap

info-dev:  ## Show dev environment summary
	@$(SCRIPTS_DIR)/show-info.sh dev

# =============================================================================
# CLEANUP
# =============================================================================

.PHONY: clean clean-tests

clean-tests:  ## Delete all k6 test runs
	@$(MAKE) -C $(TESTS_DIR) clean

# =============================================================================
# HELP
# =============================================================================

help:  ## Show this help
	@$(SCRIPTS_DIR)/show-help.sh $(MAKEFILE_LIST)

.DEFAULT_GOAL := help
