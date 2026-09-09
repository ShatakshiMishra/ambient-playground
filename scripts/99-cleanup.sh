#!/usr/bin/env bash
# 99-cleanup.sh — tear down everything created by these labs.
source "$(dirname "$0")/lib.sh"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  info "Deleting kind cluster '$CLUSTER_NAME'..."
  kind delete cluster --name "$CLUSTER_NAME"
  ok "Cluster deleted."
else
  warn "No kind cluster named '$CLUSTER_NAME' found — nothing to delete."
fi
