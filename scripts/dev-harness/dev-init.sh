#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=_resolve_python.sh
source "$(dirname "$0")/_resolve_python.sh"
cd "$(dirname "$0")/../.."

echo "Intentive local dev harness — one-time setup"

secrets_file="backend/.env.local-dev"
template="backend/.env.local-dev.template"
if [ ! -f "$secrets_file" ]; then
  cp "$template" "$secrets_file"
  echo "Created $secrets_file from template"
else
  echo "Keeping existing $secrets_file (not overwritten)"
fi

PYTHON_BIN="$(dev_harness_python)"
if [ "$PYTHON_BIN" = "python3" ]; then
  python3 -m venv backend/.venv
  PYTHON_BIN="$(dev_harness_python)"
  echo "Created backend/.venv"
fi

if ! "$PYTHON_BIN" -m pip --version >/dev/null; then
  echo "${PYTHON_BIN%/bin/python} is incomplete; recreate it with: python3 -m venv backend/.venv" >&2
  exit 1
fi

"$PYTHON_BIN" -m pip install -q -r backend/requirements.txt
echo "Backend Python dependencies installed"

PYTHONPATH="scripts/dev-harness" "$PYTHON_BIN" -m dev_harness.synthetic_profiles init >/dev/null
echo "Initialized neutral synthetic desktop profiles"

hook=".git/hooks/pre-commit"
if [ ! -f "$hook" ]; then
  ln -s -f ../../scripts/pre-commit "$hook"
  echo "Installed pre-commit hook"
else
  echo "Pre-commit hook already present"
fi

echo ""
echo "Next: add your provider API keys to backend/.env.local-dev, then run:"
echo "  make dev-desktop"
