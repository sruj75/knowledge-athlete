#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENT_DIR="${OMI_GAUNTLET_AGENT_DIR:-$MACOS_DIR/agent}"
GAUNTLET_LIB="${OMI_GAUNTLET_LIB:-$SCRIPT_DIR/agent-continuity-gauntlet-lib.py}"

if [[ ! -x "$AGENT_DIR/node_modules/.bin/vitest" ]]; then
  [[ -f "$AGENT_DIR/package-lock.json" ]] || {
    echo "agent continuity self-check: missing $AGENT_DIR/package-lock.json" >&2
    exit 1
  }
  (
    cd "$AGENT_DIR"
    npm ci --no-fund --no-audit
  )
fi

exec "${PYTHON_BIN:-python3}" "$GAUNTLET_LIB" --self-check
