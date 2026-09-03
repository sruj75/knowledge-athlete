#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/../scripts/check-gauntlet-evidence-at-head.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

REPO="$TEST_ROOT/repo"
mkdir -p "$REPO/desktop/macos/scripts"
cp "$CHECKER" "$REPO/desktop/macos/scripts/check-gauntlet-evidence-at-head.sh"
chmod +x "$REPO/desktop/macos/scripts/check-gauntlet-evidence-at-head.sh"

git -C "$REPO" init -q
git -C "$REPO" config user.email test@example.com
git -C "$REPO" config user.name 'Gauntlet Evidence Test'
printf 'fixture\n' >"$REPO/README.md"
git -C "$REPO" add README.md desktop/macos/scripts/check-gauntlet-evidence-at-head.sh
git -C "$REPO" commit -qm fixture

CHECK="$REPO/desktop/macos/scripts/check-gauntlet-evidence-at-head.sh"
EVIDENCE="$REPO/desktop/macos/.harness/agent-continuity-gauntlet/run/manifest.json"

write_manifest() {
  local sha="$1"
  local passed="$2"
  local steps_json="$3"
  local failures_json="$4"
  local assistant_text="${5:-safe synthetic marker}"
  local suites_json="${6:-[\"agents\",\"continuity\",\"owner\",\"prompts\",\"resilience\"]}"
  mkdir -p "$(dirname "$EVIDENCE")"
  python3 - "$EVIDENCE" "$sha" "$passed" "$steps_json" "$failures_json" "$assistant_text" "$suites_json" <<'PY'
import json
import sys

path, sha, passed, steps, failures, assistant_text, suites = sys.argv[1:]
payload = {
    "run_id": "fixture",
    "started_at": "2026-09-03T00:00:00+00:00",
    "finished_at": "2026-09-03T00:01:00+00:00",
    "git": sha,
    "suites": json.loads(suites),
    "steps": json.loads(steps),
    "failures": json.loads(failures),
    "passed": passed == "true",
    "assistant_text": assistant_text,
}
with open(path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle)
PY
}

expect_pass() {
  local label="$1"
  shift
  if ! "$@" >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
    echo "FAIL: $label should pass" >&2
    cat "$TEST_ROOT/err" >&2
    exit 1
  fi
}

expect_fail() {
  local label="$1"
  shift
  if "$@" >"$TEST_ROOT/out" 2>"$TEST_ROOT/err"; then
    echo "FAIL: $label should fail" >&2
    exit 1
  fi
}

git -C "$REPO" checkout -qb unrelated-docs
expect_pass "unrelated branch without live evidence" "$CHECK" block

git -C "$REPO" checkout -qb implement-wave-6-s31-tdd
expect_fail "S-31 branch without evidence" "$CHECK" block

FULL_SHA="$(git -C "$REPO" rev-parse HEAD)"
SHORT_SHA="$(git -C "$REPO" rev-parse --short HEAD)"
VALID_STEPS='[
  {"id":"01-typed-turn","name":"typed turn"},
  {"id":"02-ptt-turn","name":"PTT turn"},
  {"id":"02b-ptt-followup","name":"PTT follow-up"},
  {"id":"03-typed-followup","name":"typed follow-up"},
  {"id":"04-exact-voice-memory-agent","name":"exact voice memory agent"},
  {"id":"04-spawn-agent","name":"spawn agent"},
  {"id":"05-status-query","name":"status query"},
  {"id":"06-owner-switch-isolation","name":"owner switch isolation"},
  {"id":"07a-floating-casual","name":"floating casual"},
  {"id":"07b-floating-spawn","name":"floating spawn"},
  {"id":"07c-spawn-recall-ptt","name":"spawn recall PTT"},
  {"id":"07d-spawn-recall-typed","name":"spawn recall typed"},
  {"id":"p1-over-refusal","name":"prompt over-refusal"},
  {"id":"p2-tool-selection","name":"prompt tool selection"},
  {"id":"p3-register","name":"prompt register"},
  {"id":"p4-no-public-web","name":"prompt public web truth"},
  {"id":"r1-cold-bridge-launch","name":"cold bridge launch"},
  {"id":"r2-warm-reuse-1","name":"warm reuse 1"},
  {"id":"r2-warm-reuse-2","name":"warm reuse 2"},
  {"id":"r2-warm-reuse-3","name":"warm reuse 3"},
  {"id":"r3-already-running-race-policy","name":"already running race"},
  {"id":"r4-subagent-launch","name":"subagent launch"},
  {"id":"r4-subagent-status","name":"subagent status"}
]'

write_manifest "$FULL_SHA" true "$VALID_STEPS" '[]'
expect_pass "green evidence at the full HEAD SHA" "$CHECK" block

write_manifest "$FULL_SHA" true "$VALID_STEPS" '[]' 'safe synthetic marker' '["continuity"]'
expect_fail "partial suite evidence on S-31" "$CHECK" block

MISSING_ROW_STEPS="$(python3 -c 'import json,sys; rows=json.loads(sys.argv[1]); print(json.dumps(rows[:-1]))' "$VALID_STEPS")"
write_manifest "$FULL_SHA" true "$MISSING_ROW_STEPS" '[]'
expect_fail "green manifest missing a canonical row" "$CHECK" block

write_manifest "$SHORT_SHA" true "$VALID_STEPS" '[]'
expect_fail "short SHA evidence" "$CHECK" block

write_manifest "$(printf 'a%.0s' {1..40})" true "$VALID_STEPS" '[]'
expect_fail "stale full SHA evidence" "$CHECK" block

write_manifest "$FULL_SHA" true '[]' '[]'
expect_fail "missing evidence rows" "$CHECK" block

write_manifest "$FULL_SHA" true "$VALID_STEPS" '["terminal failure"]'
expect_fail "red evidence row" "$CHECK" block

printf '{ malformed\n' >"$EVIDENCE"
expect_fail "malformed evidence" "$CHECK" block

write_manifest "$FULL_SHA" true "$VALID_STEPS" '[]' 'Authorization: Bearer secret-fixture'
expect_fail "secret-bearing evidence" "$CHECK" block

echo "gauntlet evidence-at-HEAD tests passed"
