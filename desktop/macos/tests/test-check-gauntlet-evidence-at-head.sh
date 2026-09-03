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
  mkdir -p "$(dirname "$EVIDENCE")"
  python3 - "$EVIDENCE" "$sha" "$passed" "$steps_json" "$failures_json" "$assistant_text" <<'PY'
import json
import sys

path, sha, passed, steps, failures, assistant_text = sys.argv[1:]
payload = {
    "run_id": "fixture",
    "started_at": "2026-09-03T00:00:00+00:00",
    "finished_at": "2026-09-03T00:01:00+00:00",
    "git": sha,
    "suites": ["continuity"],
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
VALID_STEPS='[{"id":"continuity","name":"continuity"}]'

write_manifest "$FULL_SHA" true "$VALID_STEPS" '[]'
expect_pass "green evidence at the full HEAD SHA" "$CHECK" block

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
