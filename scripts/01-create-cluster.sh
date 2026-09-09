#!/usr/bin/env bash
# 01-create-cluster.sh — create the local kind cluster for the labs.
source "$(dirname "$0")/lib.sh"
ROOT="$(repo_root)"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  ok "kind cluster '$CLUSTER_NAME' already exists — skipping."
else
  info "Creating 3-node kind cluster '$CLUSTER_NAME' (this pulls the node image on first run)..."
  kind create cluster --config "$ROOT/scripts/kind-config.yaml"
fi

info "Cluster nodes:"
kubectl get nodes -o wide

ok "Cluster ready. kubectl context: $(kubectl config current-context)"
