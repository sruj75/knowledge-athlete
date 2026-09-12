#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUALIFIER="$SCRIPT_DIR/../scripts/qualify-desktop-beta.sh"
CORE_HARNESS="$SCRIPT_DIR/../scripts/desktop-core-harness.sh"
PROFILE_PREP="$SCRIPT_DIR/../scripts/prepare-qualification-profile.sh"
SWIFT_CACHE="$SCRIPT_DIR/../scripts/qualification-swift-cache.sh"
LEASE_COMMAND="$SCRIPT_DIR/../scripts/qualification-lease-command.sh"
SELF_CLEAN="$SCRIPT_DIR/../scripts/qualification-runner-self-clean.py"
WATCHDOG="$SCRIPT_DIR/../scripts/qualification-watchdog.py"
APP_CONFIG="$SCRIPT_DIR/../scripts/app-config.sh"
RUN_SH="$SCRIPT_DIR/../run.sh"
WORKFLOW="$SCRIPT_DIR/../../../.github/workflows/desktop_qualify_beta.yml"
COLLECTOR="$SCRIPT_DIR/../scripts/collect-owner-manual-beta-qualification.sh"

require_text() {
  local pattern="$1"
  local file="${2:-$QUALIFIER}"
  grep -Fq -- "$pattern" "$file" || {
    echo "FAIL: qualification bootstrap missing: $pattern" >&2
    exit 1
  }
}

require_order() {
  local file="$1"
  shift
  python3 - "$file" "$@" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
needles = sys.argv[2:]
text = path.read_text(encoding="utf-8")
position = -1
for needle in needles:
    next_position = text.find(needle, position + 1)
    if next_position < 0:
        raise SystemExit(f"FAIL: {path} missing ordered launch-phase fragment: {needle}")
    position = next_position
PY
}

require_text 'defaults delete "$BUNDLE_ID"' "$PROFILE_PREP"
require_text '^omi-qualification-' "$PROFILE_PREP"
require_text 'Application Support/$BUNDLE_NAME' "$PROFILE_PREP"
require_text 'defaults write "$BUNDLE_ID" hasCompletedOnboarding -bool true' "$PROFILE_PREP"
require_text 'defaults write "$BUNDLE_ID" devLazyPermissionsEnabled -bool true' "$PROFILE_PREP"
require_text 'defaults write "$BUNDLE_ID" screenAnalysisEnabled -bool false' "$PROFILE_PREP"
require_text 'defaults write "$BUNDLE_ID" transcriptionEnabled -bool false' "$PROFILE_PREP"
require_text '"$SCRIPT_DIR/prepare-qualification-profile.sh" "$BUNDLE"' "$QUALIFIER"
require_text 'OMI_SEED_FROM_CANONICAL_DEV=0'
require_text 'make desktop-run-local DESKTOP_APP_NAME="$BUNDLE" DESKTOP_USER=alice'
# omi-test-quality: source-inspection -- wiring tripwire for incident #107.
# Behavioral owner/foreign-process checks live in dev-harness lifecycle tests;
# qualification must use that owner, not create a competing signal/capability.
require_text 'qualification-desktop-command.py'
require_text '"${OMI_QUALIFICATION_PYTHON:-$WORKTREE/backend/.venv/bin/python}"'
require_text 'qualification_desktop_command inspect'
require_text 'qualification_desktop_command stop'
require_text 'lsof -nP -iTCP:"$AUTOMATION_PORT" -sTCP:LISTEN'
require_text 'qualification automation port remains bound after owned app cleanup'
require_text 'canonical desktop launcher has not settled; preserving lease'
if grep -Eq 'DESKTOP_LAUNCH_TOKEN|LAUNCH_SIGNAL_FILE|DESKTOP_LAUNCH_RECORD|kill -[A-Z]+' "$QUALIFIER"; then
  echo "FAIL: qualification must delegate app ownership to the canonical Dev launcher" >&2
  exit 1
fi
require_text 'cleanup failed (non-gating after behavioral pass); continuing to evidence registration'
require_text 'cleanup failed (non-gating on EXIT); preserving residual lease for later reclaim'
if grep -Eq 'osascript|pkill|kill_process_tree|quit app id' "$QUALIFIER"; then
  echo "FAIL: qualification cleanup must not use broad app-name or bundle-id termination" >&2
  exit 1
fi
require_order "$QUALIFIER" \
  'if ! wait_for_desktop_launch; then' \
  './scripts/desktop-core-harness.sh --tier 2' \
  'if ! run_qualification_cleanup; then' \
  'if [[ "$GITHUB_ACTIONS_ARTIFACT" -eq 1 ]]'
require_order "$QUALIFIER" \
  'qualification_desktop_command stop || return 1' \
  'wait "$DESKTOP_LAUNCH_PID"' \
  'if ! "$LEASE_COMMAND" release'
require_text 'automation bridge healthy on port $port (authenticated; token=$token_file)'
require_text 'automation_token_lib'
require_text 'OMI_AUTOMATION_TOKEN_FILE' "$RUN_SH"
require_text 'OMI_AUTOMATION_TOKEN_FILE="$OMI_AUTOMATION_TOKEN_FILE"'
require_text 'omi_automation_token_file'
require_text '--json tagName,isDraft,isPrerelease,publishedAt,assets,body'
require_text '"$SCRIPT_DIR/qualification-swift-cache.sh" prepare'
require_text 'QUALIFICATION_CACHE_LEASE_ID'
require_text 'QUALIFICATION_CACHE_LEASE_TOKEN'
require_text '"$SCRIPT_DIR/qualification-swift-cache.sh" release'
require_text 'qualification-cache-reclaim.py' "$SWIFT_CACHE"
require_text 'qualification-lease "$action"' "$LEASE_COMMAND"
require_text 'acquire)' "$LEASE_COMMAND"
require_text 'preflight-fault-cleanup)' "$LEASE_COMMAND"
require_text 'release)' "$LEASE_COMMAND"
require_text 'qualification-lease-command.sh' "$QUALIFIER"
require_text 'OMI_HARNESS_PORT_OFFSET="$QUALIFICATION_PORT_OFFSET"'
require_text 'OMI_AUTOMATION_PORT="$((47777 + QUALIFICATION_PORT_OFFSET))"'
require_text 'QUALIFICATION_RETAINED_RUNS="${OMI_QUALIFICATION_RETAINED_RUNS:-3}"'
if grep -Fq 'worktree add' "$QUALIFIER" || grep -Fq 'rm -rf "$WORKTREE"' "$QUALIFIER"; then
  echo "FAIL: qualification must use the persistent exact-SHA source directly" >&2
  exit 1
fi
require_text "for-each-ref --count=1 --sort=-v:refname"
require_text "--format='%(refname:strip=2)' 'refs/tags/v*-macos'"

# Acceleration changes bootstrap only. The signed-artifact, static self-check,
# Tier-2, fault-suite, evidence, and newest-candidate gates remain mandatory.
# Runner-hygiene final-cleanup is best-effort after those behavioral gates
# (must not fence a green T2+fault solely on lease-lineage cleanup).
require_text 'non-gating after behavioral pass'
require_text 'python3 "$KEYVALUE_PY" preflight-release'
require_text './scripts/desktop-core-harness.sh --self-check'
require_text './scripts/desktop-core-harness.sh --tier 2 --bundle "$BUNDLE" --port "$AUTOMATION_PORT" --keep-stack'
require_text 'python3 "$KEYVALUE_PY" check-manifest "$EVIDENCE/manifest.json"'
require_text './scripts/desktop-core-harness.sh --fault-suite --port "$((AUTOMATION_PORT + 1))"'
require_text 'python3 "$KEYVALUE_PY" check-fault-manifest "$FAULT_EVIDENCE/manifest.json"'
require_text 'evidence["automatic_gates"] = ["signed-artifact", "static-self-check", "tier-2", "fault-suite"]'
require_text 'if [[ "$LATEST_TAG" != "$RELEASE_TAG" ]]'
require_text 'python3 "$KEYVALUE_PY" update-qualified-beta'
require_text 'derive_omi_app_config "$BUNDLE"' "$CORE_HARNESS"
require_text 'wrong bundle on port' "$CORE_HARNESS"

# Static timing contract: cold preparation has its own bounded phase (env-
# overridable via OMI_QUALIFY_PREPARE_WAIT_SECS). Canonical source-bound launch
# admission completes before the separate 900-second authenticated bridge readiness
# phase starts. Default preparation budget 5400s; combined bound 6300s.
# History: 1800s (compiling stalled at 1107/1182, run 29904736566) → 3600s,
# which STILL expired at 1139/1190 on a cold M1 self-hosted build (run
# 29965341760), timing out every fresh tag (v0.12.99–v0.12.113) and leaving no
# reusable .build for the warm retry. 5400s covers the observed ~75-min cold path.
require_text 'DESKTOP_PREPARE_WAIT_SECS="${OMI_QUALIFY_PREPARE_WAIT_SECS:-5400}"'
require_text 'BRIDGE_WAIT_SECS=900'
prepare_wait_secs="$(sed -n 's/.*OMI_QUALIFY_PREPARE_WAIT_SECS:-\([0-9]*\)}.*/\1/p' "$QUALIFIER")"
bridge_wait_secs="$(sed -n 's/^BRIDGE_WAIT_SECS=//p' "$QUALIFIER")"
if [[ "$prepare_wait_secs" -ne 5400 || "$bridge_wait_secs" -ne 900 \
  || $((prepare_wait_secs + bridge_wait_secs)) -ne 6300 ]]; then
  echo "FAIL: qualification timing bounds must remain 5400s preparation + 900s bridge = 6300s total" >&2
  exit 1
fi
require_text 'signal_desktop_launch' "$RUN_SH"
require_order "$QUALIFIER" \
  'DESKTOP_LAUNCH_PID=$!' \
  'if ! wait_for_desktop_launch; then' \
  'SECONDS=0' \
  'wait_for_bridge "$AUTOMATION_PORT"'
# The middle needle carries the env-forwarding expansion added by 4a68e31c83,
# which is what broke the previous literal `open "$APP_PATH"`. The contract is
# unchanged and still exact: run.sh dispatches an `open` of the built bundle
# between announcing the start and signalling that the launch went out.
require_order "$RUN_SH" \
  'step "Starting app..."' \
  'open ${LAUNCH_ENV_ARGS[@]+"${LAUNCH_ENV_ARGS[@]}"} "$APP_PATH"' \
  'signal_desktop_launch'

# Runner-only listener cleanup must prove its exact token/PID/port lineage before
# the expensive app build or any user-flow suite. Unknown listeners still fail
# closed, and phase timings make the 20-minute target measurable without
# weakening artifact, Tier-2, or fault evidence.
require_order "$QUALIFIER" \
  'phase_begin "fault-listener-preflight" "runner-hygiene-cleanup"' \
  '"$LEASE_COMMAND" preflight-fault-cleanup' \
  'phase_begin "desktop-preparation" "runner-hygiene-cleanup"' \
  'phase_begin "tier-2-user-flows" "user-visible-behavioral-fault"' \
  'phase_begin "fault-user-flow" "user-visible-behavioral-fault"' \
  'phase_begin "final-cleanup" "runner-hygiene-cleanup"'
require_text '"target_seconds": 1200'
require_text 'OMI_QUALIFICATION_TIMINGS_FILE' "$QUALIFIER"
require_text 'OMI_QUALIFICATION_FAULT_PREFLIGHT_REPORT' "$QUALIFIER"
# The everyday owner Mac is an explicit local evidence source, never an Actions
# runner. GitHub-hosted admission rechecks the exact content-addressed bundle.
require_text 'runs-on: ubuntu-latest' "$WORKFLOW"
require_text 'owner_evidence_asset:' "$WORKFLOW"
require_text 'owner_manual_desktop_qualification.py verify' "$WORKFLOW"
require_text 'desktop-qualification-evidence-${{ inputs.release_tag }}' "$WORKFLOW"
if grep -Eq 'self-hosted|intentive-qual-m1-studio|qualify-m1-studio' "$WORKFLOW"; then
  echo "FAIL: owner-manual qualification must not register or target a Mac runner" >&2
  exit 1
fi
require_text '--local-evidence-directory DIR' "$QUALIFIER"
require_text 'source-t2-manifest.json' "$QUALIFIER"
require_text 'fault-manifest.json' "$QUALIFIER"
require_text '--qualification-mode owner-manual' "$COLLECTOR"
require_text 'Intentive.Beta.zip' "$COLLECTOR"
require_text 'intentive-beta.dmg' "$COLLECTOR"
require_text '--auth-storage-canary' "$COLLECTOR"
require_text 'pre-tag-readiness.sh' "$COLLECTOR"
require_text 'owner_manual_desktop_qualification.py' "$COLLECTOR"
if grep -Eq 'gh release upload|gh workflow run' "$COLLECTOR"; then
  echo "FAIL: local owner evidence collection must not upload or dispatch" >&2
  exit 1
fi

if [[ ! -x "$PROFILE_PREP" ]]; then
  echo "FAIL: missing executable qualification profile preparation helper" >&2
  exit 1
fi
if [[ ! -x "$SWIFT_CACHE" ]]; then
  echo "FAIL: missing executable exact-source qualification Swift cache helper" >&2
  exit 1
fi
if [[ ! -x "$LEASE_COMMAND" ]]; then
  echo "FAIL: missing executable qualification lease command helper" >&2
  exit 1
fi
if [[ ! -x "$SELF_CLEAN" || ! -x "$WATCHDOG" ]]; then
  echo "FAIL: missing executable qualification self-clean/watchdog helper" >&2
  exit 1
fi
if [[ ! -x "$COLLECTOR" ]]; then
  echo "FAIL: missing executable owner-manual qualification collector" >&2
  exit 1
fi

# Profile preparation is shared by release qualification and direct local retries.
# Exercise it with an isolated preferences home so this contract never reads or
# changes a developer's real qualification profile.
prefs_home="$(mktemp -d "${TMPDIR:-/tmp}/omi-qualification-profile.XXXXXX")"
trap 'rm -rf "$prefs_home"' EXIT
bundle_name="omi-qualification-contract-$$"
source "$APP_CONFIG"
derive_omi_app_config "$bundle_name"
HOME="$prefs_home" "$PROFILE_PREP" "$bundle_name"
if [[ "$(HOME="$prefs_home" defaults read "$BUNDLE_ID" hasCompletedOnboarding)" != "1" ]]; then
  echo "FAIL: prepared qualification profile must complete onboarding" >&2
  exit 1
fi
if [[ "$(HOME="$prefs_home" defaults read "$BUNDLE_ID" devLazyPermissionsEnabled)" != "1" ]]; then
  echo "FAIL: prepared qualification profile must enable lazy dev permissions" >&2
  exit 1
fi
if HOME="$prefs_home" "$PROFILE_PREP" 'omi-not-a-qualification' >/dev/null 2>&1; then
  echo "FAIL: profile preparation accepted a non-qualification bundle" >&2
  exit 1
fi

# Release qualification names contain SemVer punctuation; the preflight must
# compare against the same slugged identity run.sh installs.
source "$APP_CONFIG"
derive_omi_app_config 'omi-qualification-0.12.69+12069'
if [[ "$BUNDLE_ID" != 'com.heyintentive.intentive.dev.omi-qualification-0-12-69-12069' ]]; then
  echo "FAIL: qualification bundle ID was not canonically slugged: $BUNDLE_ID" >&2
  exit 1
fi

echo "desktop beta qualification bootstrap contract tests passed"
