# =============================================================================
# Makefile
# OpenCloudHub GitOps - Root Makefile
# =============================================================================
#
# Entry point for common development tasks. Provides a simple interface
# to the various scripts and sub-Makefiles in the repository.
#
# Quick Start:
#   make dev      # Start complete local development environment
#   make test     # Run smoke tests
#   make status   # Show cluster and test status
#   make info     # Show all environment summaries (credentials, IPs, etc.)
#
# Development Workflow:
#   1. make dev           - Sets up Minikube + Vault + ArgoCD
#   2. (wait for sync)    - ArgoCD syncs all applications
#   3. make test          - Verify everything is working
#   4. make status        - Check cluster state
#
# For detailed help: make help
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
