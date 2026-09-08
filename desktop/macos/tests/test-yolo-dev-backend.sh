#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/run.sh"
BACKEND_MAIN="$ROOT/../../backend/main.py"
DESKTOP_APP_SCRUB_ENV_FILE="$ROOT/../../scripts/dev-harness/desktop-app-scrub-env.txt"
export DESKTOP_APP_SCRUB_ENV_FILE

YOLO_FUNCTION="$(sed -n '/^apply_yolo_env()/,/^}/p' "$RUN")"
ROUTE_FUNCTION="$(sed -n '/^apply_requested_backend_mode()/,/^}/p' "$RUN")"
FIREBASE_FUNCTION="$(sed -n '/^load_owned_dev_firebase_api_key()/,/^}/p' "$RUN")"
LAUNCH_ENV_FUNCTION="$(sed -n '/^build_launch_env_args()/,/^}/p' "$RUN")"
BACKEND_ENV_FUNCTION="$(sed -n '/^load_backend_launch_env()/,/^}/p' "$RUN")"

if [[ -z "$YOLO_FUNCTION" ]]; then
  echo "FAIL: apply_yolo_env is missing from $RUN" >&2
  exit 1
fi

if [[ -z "$ROUTE_FUNCTION" ]]; then
  echo "FAIL: apply_requested_backend_mode is missing from $RUN" >&2
  exit 1
fi

if [[ -z "$FIREBASE_FUNCTION" ]]; then
  echo "FAIL: load_owned_dev_firebase_api_key is missing from $RUN" >&2
  exit 1
fi

if [[ -z "$LAUNCH_ENV_FUNCTION" ]]; then
  echo "FAIL: build_launch_env_args is missing from $RUN" >&2
  exit 1
fi

if [[ -z "$BACKEND_ENV_FUNCTION" ]]; then
  echo "FAIL: load_backend_launch_env is missing from $RUN" >&2
  exit 1
fi

(
  unset OMI_SKIP_BACKEND OMI_SKIP_TUNNEL OMI_PYTHON_API_URL FIREBASE_API_KEY
  SCRIPT_DIR="$ROOT"
  eval "$FIREBASE_FUNCTION"
  eval "$YOLO_FUNCTION"
  apply_yolo_env

  expected_key="$(/usr/libexec/PlistBuddy -c 'Print :API_KEY' "$ROOT/Desktop/Sources/GoogleService-Info-Dev.plist")"
  test -n "$expected_key"
  test "$FIREBASE_API_KEY" = "$expected_key"
)

# A local-profile launch must not reload backend-only credentials after the
# Python launcher has scrubbed its child environment.
(
  fixture_backend="$(mktemp -d)"
  trap 'rm -rf "$fixture_backend"' EXIT
  printf 'POSTHOG_PROJECT_API_KEY=must-not-reach-app\nDODO_PAYMENTS_API_KEY=must-not-reach-app\n' \
    > "$fixture_backend/.env"
  unset POSTHOG_PROJECT_API_KEY DODO_PAYMENTS_API_KEY
  export BACKEND_DIR="$fixture_backend"
  export LOCAL_PROFILE=true
  export YOLO_MODE=0
  eval "$FIREBASE_FUNCTION"
  eval "$YOLO_FUNCTION"
  eval "$ROUTE_FUNCTION"
  eval "$BACKEND_ENV_FUNCTION"
  load_backend_launch_env

  test -z "${POSTHOG_PROJECT_API_KEY+x}"
  test -z "${DODO_PAYMENTS_API_KEY+x}"
)

# Behavioral route contract: named bundles remain on their explicitly supplied
# local backend unless the caller deliberately selects --yolo.
(
  export YOLO_MODE=0
  export IS_NAMED_BUNDLE=true
  export OMI_SKIP_BACKEND=1
  export OMI_SKIP_TUNNEL=1
  export OMI_PYTHON_API_URL="http://127.0.0.1:55000"
  eval "$FIREBASE_FUNCTION"
  eval "$YOLO_FUNCTION"
  eval "$ROUTE_FUNCTION"
  apply_requested_backend_mode

  test "$OMI_SKIP_BACKEND" = "1"
  test "$OMI_SKIP_TUNNEL" = "1"
  test "$OMI_PYTHON_API_URL" = "http://127.0.0.1:55000"
)

(
  unset OMI_SKIP_BACKEND OMI_SKIP_TUNNEL OMI_PYTHON_API_URL
  export FIREBASE_API_KEY="fixture-owned-firebase-key"
  SCRIPT_DIR="$ROOT"
  eval "$FIREBASE_FUNCTION"
  eval "$YOLO_FUNCTION"
  apply_yolo_env

  test "$OMI_SKIP_BACKEND" = "1"
  test "$OMI_SKIP_TUNNEL" = "1"
  test "$OMI_PYTHON_API_URL" = "https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app"
  test "$FIREBASE_API_KEY" = "fixture-owned-firebase-key"
)

(
  export OMI_PYTHON_API_URL="https://canonical-override.test"
  export FIREBASE_API_KEY="fixture-owned-firebase-key"
  SCRIPT_DIR="$ROOT"
  eval "$FIREBASE_FUNCTION"
  eval "$YOLO_FUNCTION"
  apply_yolo_env

  test "$OMI_SKIP_BACKEND" = "1"
  test "$OMI_SKIP_TUNNEL" = "1"
  test "$OMI_PYTHON_API_URL" = "https://canonical-override.test"
)

bash "$RUN" --help | grep -q 'Quick start: use dev backend, no local services'

# Static forbidden-pattern tripwires complement the behavior test above: the
# retired implicit-owner names and broad process matcher must not return.
if grep -q 'NAMED_BUNDLE_DEFAULT_DEV_BACKEND\|should_default_named_bundle_to_dev_backend' "$RUN"; then
  echo "FAIL: named bundles must not silently select the hosted development backend" >&2
  exit 1
fi

if grep -q 'pkill -f "\$APP_NAME.app"' "$RUN"; then
  echo "FAIL: run.sh must not stop apps by broad process-name matching" >&2
  exit 1
fi

(
  export LOCAL_PROFILE=true
  export OMI_PYTHON_API_URL="http://127.0.0.1:8000"
  export FIREBASE_API_KEY="local-api-key"
  export FIREBASE_PROJECT_ID="demo-heyintentive-local"
  export FIREBASE_AUTH_PROJECT_ID="demo-heyintentive-local"
  export FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"
  export FIRESTORE_DATABASE_ID="(default)"
  export OMI_LOCAL_PROVIDER_MODE="real"
  eval "$LAUNCH_ENV_FUNCTION"
  build_launch_env_args
  rendered="$(printf '%s\n' "${LAUNCH_ENV_ARGS[@]}")"
  direct_rendered="$(printf '%s\n' "${DIRECT_LAUNCH_ENV[@]}")"
  grep -qx 'LANGFUSE_SECRET_KEY=' <<<"$rendered"
  grep -qx 'ADMIN_KEY=' <<<"$rendered"
  grep -qx 'PROVIDER_MODE=' <<<"$rendered"
  grep -qx 'OMI_LLM_STUB=' <<<"$rendered"
  grep -qx 'FIREBASE_API_KEY=local-api-key' <<<"$rendered"
  grep -qx 'OMI_PYTHON_API_URL=http://127.0.0.1:8000' <<<"$rendered"
  grep -qx 'OMI_LOCAL_PROVIDER_MODE=real' <<<"$rendered"
  grep -qx 'PROVIDER_MODE=' <<<"$direct_rendered"
  grep -qx 'OMI_LLM_STUB=' <<<"$direct_rendered"
  grep -qx 'OMI_LOCAL_PROVIDER_MODE=real' <<<"$direct_rendered"
)

# Static tripwire: app and backend diagnostics must never converge on a
# machine-global developer log. The launcher's private per-launch directory
# is the ownership boundary for a local backend started by run.sh.
if grep -qE '/private/tmp/omi-dev\.log|/tmp/omi-dev\.log' "$RUN" "$BACKEND_MAIN"; then
  echo "FAIL: named-bundle launcher or Python backend still uses the shared developer log" >&2
  exit 1
fi
grep -q 'BACKEND_LOG_FILE' "$RUN"
grep -q 'mktemp -d' "$RUN"
grep -q '>>"$BACKEND_LOG_FILE" 2>&1' "$RUN"
grep -q 'main:app --host 127.0.0.1' "$RUN"
grep -q 'http://127.0.0.1:$port/v1/health' "$ROOT/scripts/python-backend-dev.sh"

# backend/.env may carry the canonical default PORT=8080. The launcher
# must reassert its worktree-derived port after loading it so child/backend
# ownership state cannot diverge.
ENV_LOAD_LINE="$(grep -n 'source "\$BACKEND_DIR/.env"' "$RUN" | tail -1 | cut -d: -f1)"
PORT_REASSERT_LINE="$(grep -n 'export PORT="\$BACKEND_PORT"' "$RUN" | tail -1 | cut -d: -f1)"
if [[ -z "$ENV_LOAD_LINE" || -z "$PORT_REASSERT_LINE" || "$PORT_REASSERT_LINE" -le "$ENV_LOAD_LINE" ]]; then
  echo "FAIL: run.sh must reassert its derived backend PORT after sourcing .env" >&2
  exit 1
fi

echo "PASS: only explicit --yolo targets the canonical hosted development backend"
