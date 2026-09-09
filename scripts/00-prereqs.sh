#!/usr/bin/env bash
# 00-prereqs.sh — verify the tools and versions needed for the labs.
source "$(dirname "$0")/lib.sh"

info "Checking required tools..."
need docker
need kind
need kubectl
need istioctl

# jq is optional but used by several experiments.
if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found — install it for the JSON-parsing steps (brew install jq)"
fi

info "Versions:"
docker --version   || true
kind --version     || true
kubectl version --client --output=yaml 2>/dev/null | grep -E 'gitVersion' | head -1 || true
istioctl version --remote=false 2>/dev/null || istioctl version 2>/dev/null || true

# Verify istioctl is new enough for ambient (>= 1.24 recommended).
ver="$(istioctl version --remote=false 2>/dev/null | head -1 | tr -dc '0-9.' || true)"
if [[ -n "$ver" ]]; then
  major="${ver%%.*}"; rest="${ver#*.}"; minor="${rest%%.*}"
  if (( major == 1 && minor < 24 )); then
    warn "istioctl $ver detected; ambient is GA in 1.24+. Some flags may differ."
  fi
fi

# Docker must be running.
docker info >/dev/null 2>&1 || die "Docker does not appear to be running."

ok "Prerequisites look good."
