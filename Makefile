# Minimal Makefile for Kagent ArgoCD Demo
.PHONY: help setup teardown status install-tools create-cluster clean env-template

# Default target
help: ## Show this help message
	@echo "Kagent ArgoCD Demo - Available Commands:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Prerequisites: Copy .env.template to .env and set OPENAI_API_KEY"

install-tools: ## Install required tools (macOS with Homebrew)
	@echo "📦 Installing required tools..."
	@command -v brew >/dev/null 2>&1 || { echo "❌ Homebrew not found. Please install it first."; exit 1; }
	brew install kubectl argocd helm kind podman
	@echo "✅ Tools installed successfully!"

create-cluster: ## Create a new Kind cluster
	@echo "🏗️ Creating Kind cluster..."
	kind create cluster --name kagent-demo
	kubectl cluster-info --context kind-kagent-demo

setup: ## Deploy Kagent to Kind cluster with ArgoCD
	@echo "🚀 Setting up Kagent with ArgoCD..."
	./setup-kagent.sh

teardown: ## Remove all Kagent resources (keeps ArgoCD and Kind cluster)
	@echo "🧹 Tearing down Kagent resources..."
	./setup-kagent.sh --teardown

status: ## Show port-forward status and access info
	@echo "� Checking service status..."
	./setup-kagent.sh --status

clean: ## Clean up everything (delete cluster, kill port-forwards)
	@echo "🧽 Complete cleanup..."
	-pkill -f "port-forward.*808" 2>/dev/null || true
	-rm -f /tmp/*-port-forward.pid /tmp/kagent-ui-pf.log
	kind delete cluster --name kagent-demo
	@echo "✅ Cleanup complete!"

env-template: ## Copy .env.template to .env for editing
	@if [ ! -f .env ]; then \
		cp .env.template .env; \
		echo "📝 Created .env file from template. Please edit it with your OPENAI_API_KEY."; \
	else \
		echo "⚠️  .env file already exists."; \
	fi