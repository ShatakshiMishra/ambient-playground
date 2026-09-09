#!/usr/bin/env bash
# 03-deploy-sample-apps.sh — deploy httpbin + curl client into ambient-demo.
source "$(dirname "$0")/lib.sh"
ROOT="$(repo_root)"

info "Deploying sample apps into namespace 'ambient-demo'..."
kubectl apply -f "$ROOT/manifests/sample-apps.yaml"

info "Waiting for workloads to be ready..."
kubectl -n ambient-demo rollout status deploy/httpbin --timeout=120s
kubectl -n ambient-demo rollout status deploy/curl    --timeout=120s

info "Pods (note the nodes — httpbin and curl may land on different nodes):"
kubectl -n ambient-demo get pods -o wide

echo
info "Smoke test (traffic is NOT in the mesh yet):"
kubectl -n ambient-demo exec deploy/curl -- \
  curl -s -o /dev/null -w "curl -> httpbin: HTTP %{http_code}\n" http://httpbin:8000/get

ok "Sample apps ready. Continue with experiments/01-enroll-and-verify."
