#!/usr/bin/env bash
# lib.sh — shared helpers for the ztunnel-experiments scripts.
# Source this: `source "$(dirname "$0")/lib.sh"`

set -euo pipefail

# Config (override via environment)
CLUSTER_NAME="${CLUSTER_NAME:-ztunnel-lab}"
ISTIO_NAMESPACE="${ISTIO_NAMESPACE:-istio-system}"

# Colored logging
_c()   { printf '\033[%sm' "$1"; }
info() { printf '%s[info]%s %s\n'  "$(_c '1;34')" "$(_c 0)" "$*"; }
ok()   { printf '%s[ ok ]%s %s\n'  "$(_c '1;32')" "$(_c 0)" "$*"; }
warn() { printf '%s[warn]%s %s\n'  "$(_c '1;33')" "$(_c 0)" "$*" >&2; }
err()  { printf '%s[fail]%s %s\n'  "$(_c '1;31')" "$(_c 0)" "$*" >&2; }
die()  { err "$*"; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

# Absolute path to the repo root, regardless of where a script is invoked from.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}
