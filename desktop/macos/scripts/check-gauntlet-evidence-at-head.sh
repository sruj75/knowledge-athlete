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
EVIDENCE_SCANNER="$SCRIPT_DIR/omi-hardening-smoke.sh"

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

if [[ ! -x "$EVIDENCE_SCANNER" ]]; then
  echo "WARN: gauntlet evidence scanner is missing or not executable: $EVIDENCE_SCANNER" >&2
  exit 1
fi

FOUND=false
for manifest in "$HARNESS_ROOT"/*/manifest.json; do
  [[ -f "$manifest" ]] || continue
  if python3 - "$manifest" "$HEAD_SHA" "$BRANCH" <<'PY'
import json
import re
import sys
from pathlib import Path

manifest_path, head_sha, branch = sys.argv[1:4]
manifest_file = Path(manifest_path)
try:
    with manifest_file.open(encoding="utf-8") as handle:
        raw = handle.read()
    data = json.loads(raw)
except (OSError, json.JSONDecodeError):
    raise SystemExit(1)

if not re.fullmatch(r"[0-9a-f]{40}", head_sha):
    raise SystemExit(1)
if data.get("git") != head_sha:
    raise SystemExit(1)
if data.get("source_git_sha") != data.get("git"):
    raise SystemExit(1)
if data.get("source_tree_dirty") is not False:
    raise SystemExit(1)
if data.get("passed") is not True:
    raise SystemExit(1)
if not isinstance(data.get("suites"), list) or not data["suites"]:
    raise SystemExit(1)
if not isinstance(data.get("steps"), list) or not data["steps"]:
    raise SystemExit(1)
if not all(isinstance(step, dict) and step.get("id") and step.get("name") for step in data["steps"]):
    raise SystemExit(1)
forbidden_top_level_fields = {"markers", "trace_log", "app_log"}
if forbidden_top_level_fields.intersection(data):
    raise SystemExit(1)
if re.search(r"/Users/|GAUNTLET-|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}", raw):
    raise SystemExit(1)
forbidden_manifest_fields = {"user_text", "assistant_text", "identity", "trace_ids"}
if any(forbidden_manifest_fields.intersection(step) for step in data["steps"] if isinstance(step, dict)):
    raise SystemExit(1)


def valid_text_summary(value):
    return (
        isinstance(value, dict)
        and set(value) == {"sha256", "utf8_bytes"}
        and isinstance(value["sha256"], str)
        and re.fullmatch(r"[0-9a-f]{64}", value["sha256"])
        and isinstance(value["utf8_bytes"], int)
        and value["utf8_bytes"] >= 0
    )


marker_digests = data.get("marker_digests", {})
if not isinstance(marker_digests, dict) or not all(valid_text_summary(value) for value in marker_digests.values()):
    raise SystemExit(1)
for field in ("failures", "warnings"):
    values = data.get(field, [])
    if not isinstance(values, list) or not all(valid_text_summary(value) for value in values):
        raise SystemExit(1)


def valid_privacy_node(node):
    if not isinstance(node, dict) or not isinstance(node.get("kind"), str):
        return False
    kind = node["kind"]
    if kind == "null":
        return set(node) == {"kind"}
    if kind == "boolean":
        return set(node) == {"kind", "value"} and isinstance(node["value"], bool)
    if kind == "number":
        if set(node) == {"kind", "value"}:
            return isinstance(node["value"], (int, float)) and not isinstance(node["value"], bool)
        return set(node) == {"kind", "sha256", "utf8_bytes"} and valid_text_summary(
            {"sha256": node.get("sha256"), "utf8_bytes": node.get("utf8_bytes")}
        )
    if kind == "string":
        return set(node) == {"kind", "sha256", "utf8_bytes"} and valid_text_summary(
            {"sha256": node.get("sha256"), "utf8_bytes": node.get("utf8_bytes")}
        )
    if kind == "bytes":
        return (
            set(node) == {"kind", "sha256", "bytes"}
            and isinstance(node["sha256"], str)
            and re.fullmatch(r"[0-9a-f]{64}", node["sha256"])
            and isinstance(node["bytes"], int)
            and node["bytes"] >= 0
        )
    if kind == "array":
        return set(node) == {"kind", "items"} and isinstance(node["items"], list) and all(
            valid_privacy_node(item) for item in node["items"]
        )
    if kind == "object":
        if set(node) != {"kind", "entries"} or not isinstance(node["entries"], list):
            return False
        return all(
            isinstance(entry, dict)
            and set(entry) == {"key", "value"}
            and isinstance(entry["key"], dict)
            and entry["key"].get("kind") == "string"
            and valid_privacy_node(entry["key"])
            and valid_privacy_node(entry["value"])
            for entry in node["entries"]
        )
    return False


def valid_privacy_envelope(value):
    return (
        isinstance(value, dict)
        and set(value) == {"schema_version", "privacy_class", "payload"}
        and value["schema_version"] == 1
        and value["privacy_class"] == "hashed-summary"
        and valid_privacy_node(value["payload"])
    )


for artifact in manifest_file.parent.rglob("*"):
    if artifact.is_symlink():
        raise SystemExit(1)
    if not artifact.is_file() or artifact == manifest_file:
        continue
    if artifact.suffix not in {".json", ".jsonl"}:
        raise SystemExit(1)
    try:
        artifact_raw = artifact.read_text(encoding="utf-8")
        if artifact.suffix == ".json":
            payloads = [json.loads(artifact_raw)]
        else:
            rows = [line for line in artifact_raw.splitlines() if line.strip()]
            if not rows:
                raise SystemExit(1)
            payloads = [json.loads(line) for line in rows]
    except (OSError, UnicodeDecodeError, json.JSONDecodeError):
        raise SystemExit(1)
    if not all(valid_privacy_envelope(payload) for payload in payloads):
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

PY
  then
    if "$EVIDENCE_SCANNER" scan "$(dirname "$manifest")"; then
      FOUND=true
      break
    fi
  fi
done

if [[ "$FOUND" != true ]]; then
  echo "WARN: pushing $BRANCH at $HEAD_SHA with no green gauntlet bundle at HEAD." >&2
  echo "WARN: run: cd desktop/macos && OMI_APP_NAME=omi-gauntlet ./scripts/agent-continuity-gauntlet.sh" >&2
  if [[ "$MODE" == "block" ]]; then
    exit 1
  fi
fi
