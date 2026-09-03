#!/usr/bin/env bash
# Block continuity-sensitive or S-31 closure branches whose full HEAD SHA lacks
# complete, green, privacy-safe gauntlet evidence.
#
# Usage:
#   ./scripts/check-gauntlet-evidence-at-head.sh          # block (default)
#   ./scripts/check-gauntlet-evidence-at-head.sh warn     # report without blocking
#
# Looks for desktop/macos/.harness/agent-continuity-gauntlet/*/manifest.json with
# matching full git SHA, completed rows, and passed: true.
#
# Applies to branches matching:
#   desktop-agent-* | *continuity* | *chat-timeline* | *floating-viewport*
#   | *kernel-turn* | *agent-pill* | *floating-chat* | *s31* | *s-31*
# (INV-6 Continuity PR DoD — live suite is a PR/RC gate, not CI.)

set -euo pipefail

MODE="${1:-block}"
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
  if python3 - "$manifest" "$HEAD_SHA" "$BRANCH" <<'PY'
import json
from pathlib import Path
import re
import sys

manifest_path, head_sha, branch = sys.argv[1:4]
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

# S-31 is the final all-waves closure lane. A manifest from a smaller live
# suite is useful diagnostic evidence but cannot satisfy that contract. Bind
# the gate to the canonical suite and row identities so a green partial run or
# a producer regression that silently drops one row fails closed.
if re.search(r"(^|[-_/])s-?31($|[-_/])", branch):
    expected_suites = {"agents", "continuity", "owner", "prompts", "resilience"}
    expected_step_ids = {
        "01-typed-turn",
        "02-ptt-turn",
        "02b-ptt-followup",
        "03-typed-followup",
        "04-exact-voice-memory-agent",
        "04-spawn-agent",
        "05-status-query",
        "06-owner-switch-isolation",
        "07a-floating-casual",
        "07b-floating-spawn",
        "07c-spawn-recall-ptt",
        "07d-spawn-recall-typed",
        "p1-over-refusal",
        "p2-tool-selection",
        "p3-register",
        "p4-no-public-web",
        "r1-cold-bridge-launch",
        "r2-warm-reuse-1",
        "r2-warm-reuse-2",
        "r2-warm-reuse-3",
        "r3-already-running-race-policy",
        "r4-subagent-launch",
        "r4-subagent-status",
    }
    if set(data["suites"]) != expected_suites:
        raise SystemExit(1)
    actual_step_ids = {str(step["id"]) for step in data["steps"]}
    if not expected_step_ids.issubset(actual_step_ids):
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
for artifact in Path(manifest_path).parent.rglob("*"):
    if not artifact.is_file():
        continue
    try:
        artifact_text = artifact.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue
    if any(re.search(pattern, artifact_text) for pattern in secret_patterns):
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
