#!/usr/bin/env bash
# Warn when pushing continuity-sensitive or S-31 closure branches whose full
# HEAD SHA lacks complete, green, privacy-safe gauntlet evidence.
#
# Usage:
#   ./scripts/check-gauntlet-evidence-at-head.sh          # warn (default)
#   ./scripts/check-gauntlet-evidence-at-head.sh block    # exit 1 when missing
#
# Looks for desktop/macos/.harness/agent-continuity-gauntlet/*/manifest.json with
# matching full git SHA, completed rows, and passed: true.
#
# Applies to branches matching:
#   desktop-agent-* | *continuity* | *chat-timeline* | *floating-viewport*
#   | *kernel-turn* | *agent-pill* | *floating-chat* | *s31* | *s-31*
# (INV-6 Continuity PR DoD — live suite is a PR/RC gate, not CI.)

set -euo pipefail

MODE="${1:-warn}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DESKTOP_DIR/../.." && pwd)"
HARNESS_ROOT="$DESKTOP_DIR/.harness/agent-continuity-gauntlet"

cd "$REPO_ROOT"
HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"

if [[ ! "$BRANCH" =~ (^desktop-agent-|continuity|chat-timeline|floating-viewport|kernel-turn|agent-pill|floating-chat|(^|[-_/])s-?31($|[-_/])) ]]; then
  exit 0
fi

if [[ ! -d "$HARNESS_ROOT" ]]; then
  echo "WARN: branch $BRANCH at $HEAD_SHA has no gauntlet evidence directory ($HARNESS_ROOT)." >&2
  echo "WARN: run: cd desktop/macos && ./scripts/agent-continuity-gauntlet.sh" >&2
  if [[ "$MODE" == "block" ]]; then
    exit 1
  fi
  exit 0
fi

FOUND=false
for manifest in "$HARNESS_ROOT"/*/manifest.json; do
  [[ -f "$manifest" ]] || continue
  if python3 - "$manifest" "$HEAD_SHA" <<'PY'
import json
import re
import sys

manifest_path, head_sha = sys.argv[1], sys.argv[2]
try:
    with open(manifest_path, encoding="utf-8") as handle:
        raw = handle.read()
    data = json.loads(raw)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
    raise SystemExit(1)
if data.get("git") != head_sha:
    raise SystemExit(1)
if data.get("passed") is not True:
    raise SystemExit(1)
if not isinstance(data.get("suites"), list) or not data["suites"]:
    raise SystemExit(1)
if not isinstance(data.get("steps"), list) or not data["steps"]:
    raise SystemExit(1)
if not all(isinstance(step, dict) and step.get("id") and step.get("name") for step in data["steps"]):
    raise SystemExit(1)
if data.get("failures") != []:
    raise SystemExit(1)
if not isinstance(data.get("started_at"), str) or not isinstance(data.get("finished_at"), str):
    raise SystemExit(1)

secret_patterns = (
    r"(?i)authorization\s*[:=]\s*bearer\s+[a-z0-9._~+/=-]{8,}",
    r"\bAIza[0-9A-Za-z_-]{20,}\b",
    r"\bsk-[0-9A-Za-z_-]{20,}\b",
)
if any(re.search(pattern, raw) for pattern in secret_patterns):
    raise SystemExit(1)
PY
  then
    FOUND=true
    break
  fi
done

if [[ "$FOUND" != true ]]; then
  echo "WARN: pushing $BRANCH at $HEAD_SHA with no green gauntlet bundle at HEAD." >&2
  echo "WARN: run: cd desktop/macos && OMI_APP_NAME=omi-gauntlet ./scripts/agent-continuity-gauntlet.sh" >&2
  if [[ "$MODE" == "block" ]]; then
    exit 1
  fi
fi
