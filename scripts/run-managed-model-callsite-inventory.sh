#!/usr/bin/env bash
# Run the managed-model inventory with the repository's locked backend dependencies.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=dev-harness/_resolve_python.sh
source "$ROOT_DIR/scripts/dev-harness/_resolve_python.sh"

if ! BACKEND_PYTHON="$(dev_harness_canonical_python)" \
  || ! "$BACKEND_PYTHON" -c "import pytest" >/dev/null 2>&1; then
  "$ROOT_DIR/backend/scripts/sync-python-deps.sh"
  if ! BACKEND_PYTHON="$(dev_harness_canonical_python)"; then
    echo "FAIL: dependency sync did not create the canonical backend/.venv interpreter." >&2
    exit 1
  fi
fi

cd "$ROOT_DIR/backend"
exec "$BACKEND_PYTHON" -m pytest -q -m slow \
  tests/unit/test_managed_model_workloads.py::test_application_model_call_sites_cannot_bypass_the_typed_inventory
