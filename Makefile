# Convenience targets for the ztunnel-experiments labs.
# Scripts do the real work; these just chain them.

SHELL := /bin/bash
S     := ./scripts

.PHONY: help all prereqs cluster install apps enroll clean logs status

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

all: prereqs cluster install apps ## Full setup: prereqs -> cluster -> ambient -> apps

prereqs: ## Check required tools
	$(S)/00-prereqs.sh

cluster: ## Create the 3-node kind cluster
	$(S)/01-create-cluster.sh

install: ## Install Istio (ambient profile)
	$(S)/02-install-istio-ambient.sh

apps: ## Deploy sample apps (httpbin + curl)
	$(S)/03-deploy-sample-apps.sh

enroll: ## Enroll the ambient-demo namespace (shortcut for experiment 01)
	kubectl label namespace ambient-demo istio.io/dataplane-mode=ambient --overwrite

status: ## Show mesh + workload status at a glance
	@echo "== namespaces ==";        kubectl get ns -L istio.io/dataplane-mode
	@echo "== istio-system ==";      kubectl -n istio-system get pods -o wide
	@echo "== ztunnel workloads =="; istioctl ztunnel-config workloads || true

logs: ## Follow ztunnel logs
	kubectl -n istio-system logs ds/ztunnel -f

clean: ## Delete the kind cluster and everything in it
	$(S)/99-cleanup.sh
