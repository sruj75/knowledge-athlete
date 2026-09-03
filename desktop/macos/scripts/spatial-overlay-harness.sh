#!/usr/bin/env bash
# Focused, self-driving harness for retained spatial overlay anchoring.
#
# Usage:
#   cd desktop/macos && ./scripts/spatial-overlay-harness.sh
#   ./scripts/spatial-overlay-harness.sh --swift-only
#   ./scripts/spatial-overlay-harness.sh --verbose
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DESKTOP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$DESKTOP_DIR/../.." && pwd)"

RUN_SWIFT=1
VERBOSE=0
INTERNAL_FAILURE_PROBE=0
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_DIR="$DESKTOP_DIR/.harness/spatial-overlay/$RUN_ID"

usage() {
  cat <<'USAGE'
Focused harness for spatial overlay anchoring.

Runs:
  1. Swift unit tests for the retained permission/proactive overlay geometry:
     SpatialOverlay*

Options:
  --swift-only   Run only Swift focused tests
  --verbose      Stream command output instead of saving it quietly
  --help         Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --swift-only)
      RUN_SWIFT=1
      ;;
    --verbose)
      VERBOSE=1
      ;;
    --internal-failure-probe)
      INTERNAL_FAILURE_PROBE=1
      RUN_SWIFT=0
      RUN_VISUAL=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

declare -a STEP_NAMES=()
declare -a STEP_SECONDS=()
declare -a STEP_LOGS=()

now_seconds() {
  python3 - <<'PY'
import time
print(f"{time.monotonic():.6f}")
PY
}

elapsed_seconds() {
  local start="$1"
  python3 - "$start" <<'PY'
import sys, time
start = float(sys.argv[1])
print(f"{time.monotonic() - start:.2f}")
PY
}

run_step() {
  local name="$1"
  shift
  echo
  echo "=== $name ==="
  local start
  local log_path="$RUN_DIR/$(printf '%02d' "$((${#STEP_NAMES[@]} + 1))")-$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9._-').log"
  start="$(now_seconds)"
  local status=0
  if [[ "$VERBOSE" -eq 1 ]]; then
    if "$@" 2>&1 | tee "$log_path"; then
      status=0
    else
      status="${PIPESTATUS[0]}"
      [[ "$status" -eq 0 ]] && status=1
    fi
  else
    if "$@" >"$log_path" 2>&1; then
      status=0
    else
      status=$?
    fi
  fi
  if [[ "$status" -ne 0 ]]; then
    echo "--- $name failed; log: $log_path" >&2
    cat "$log_path" >&2
    exit "$status"
  fi
  local elapsed
  elapsed="$(elapsed_seconds "$start")"
  STEP_NAMES+=("$name")
  STEP_SECONDS+=("$elapsed")
  STEP_LOGS+=("$log_path")
  echo "--- $name passed in ${elapsed}s (log: $log_path)"
}

run_failure_propagation_self_check() {
  echo
  echo "=== harness failure propagation self-check ==="
  local start
  local elapsed
  local log_path="$RUN_DIR/$(printf '%02d' "$((${#STEP_NAMES[@]} + 1))")-harness-failure-propagation-self-check.log"
  start="$(now_seconds)"
  set +e
  "$0" --internal-failure-probe >"$log_path" 2>&1
  local status=$?
  set -e
  elapsed="$(elapsed_seconds "$start")"
  if [[ "$status" -ne 7 ]]; then
    echo "--- harness failure propagation self-check failed; expected exit 7, got $status; log: $log_path" >&2
    cat "$log_path" >&2
    exit 1
  fi
  STEP_NAMES+=("harness failure propagation self-check")
  STEP_SECONDS+=("$elapsed")
  STEP_LOGS+=("$log_path")
  echo "--- harness failure propagation self-check passed in ${elapsed}s (log: $log_path)"
}

run_swift_focus() {
  (
    cd "$DESKTOP_DIR"
    xcrun swift test --package-path Desktop \
      --filter 'SpatialOverlay'
  )
}

total_start="$(now_seconds)"

echo "Intentive desktop spatial overlay harness"
echo "repo: $REPO_ROOT"
echo "desktop: $DESKTOP_DIR"
echo "git: $(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
mkdir -p "$RUN_DIR"
echo "logs: $RUN_DIR"

if [[ "$INTERNAL_FAILURE_PROBE" -eq 1 ]]; then
  run_step "failure propagation probe" bash -c 'exit 7'
  exit 99
fi

run_failure_propagation_self_check

if [[ "$RUN_SWIFT" -eq 1 ]]; then
  run_step "swift spatial overlay tests" run_swift_focus
fi

total_elapsed="$(elapsed_seconds "$total_start")"

echo
echo "=== Timing Summary ==="
for i in "${!STEP_NAMES[@]}"; do
  printf '%7ss  %s  (%s)\n' "${STEP_SECONDS[$i]}" "${STEP_NAMES[$i]}" "${STEP_LOGS[$i]}"
done
printf '%7ss  TOTAL\n' "$total_elapsed"

echo
echo "Harness passed."
