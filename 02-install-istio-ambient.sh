#!/usr/bin/env bash
# 02-install-istio-ambient.sh — install Istio with the ambient profile.
# The ambient profile installs istiod, the istio-cni node agent, and ztunnel.
source "$(dirname "$0")/lib.sh"

info "Installing Istio (ambient profile)..."
# --set profile=ambient pulls in istiod + istio-cni + ztunnel.
istioctl install --set profile=ambient -y

info "Waiting for control plane and data plane to be ready..."
kubectl -n "$ISTIO_NAMESPACE" rollout status deploy/istiod --timeout=180s
kubectl -n "$ISTIO_NAMESPACE" rollout status ds/ztunnel   --timeout=180s || \
  warn "ztunnel DaemonSet not fully ready yet; re-check with: kubectl -n $ISTIO_NAMESPACE get pods"

# istio-cni is a DaemonSet in recent releases; name can vary, so best-effort.
kubectl -n "$ISTIO_NAMESPACE" rollout status ds/istio-cni-node --timeout=120s 2>/dev/null || true

info "Istio system pods:"
kubectl -n "$ISTIO_NAMESPACE" get pods -o wide

echo
info "ztunnel runs one pod per node:"
kubectl -n "$ISTIO_NAMESPACE" get pods -l app=ztunnel -o wide

ok "Ambient mesh installed. Nothing is enrolled yet — see experiment 01."
