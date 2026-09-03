#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=_resolve_python.sh
source "$(dirname "$0")/_resolve_python.sh"
cd "$(dirname "$0")/../.."

echo "Intentive local dev harness — one-time setup"

# Environment and hook ownership lives in one place. In particular, do not
# recreate backend/.venv from requirements.txt or write .git/hooks here:
# make setup uses the locked platform pylock and linked-worktree-safe hook
# dispatchers shared by local development and pre-push.
make setup

secrets_file="backend/.env.local-dev"
template="backend/.env.local-dev.template"
if [ ! -f "$secrets_file" ]; then
  cp "$template" "$secrets_file"
  echo "Created $secrets_file from template"
else
  echo "Keeping existing $secrets_file (not overwritten)"
fi

PYTHON_BIN="$(dev_harness_canonical_python || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "make setup completed without creating the canonical backend/.venv interpreter" >&2
  exit 1
fi

PYTHONPATH="scripts/dev-harness" "$PYTHON_BIN" -m dev_harness.synthetic_profiles init >/dev/null
echo "Initialized neutral synthetic desktop profiles"

echo ""
echo "Next: add your provider API keys to backend/.env.local-dev, then run:"
echo "  make dev-desktop"
