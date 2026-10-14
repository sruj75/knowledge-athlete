#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RUNTIME_DIR="$SCRIPT_DIR/../agent"
# Locked, portable storage checks; no desktop launch, capture, or provider calls.
npm --prefix "$RUNTIME_DIR" ci --ignore-scripts
npm --prefix "$RUNTIME_DIR" run build
npm --prefix "$RUNTIME_DIR" test
