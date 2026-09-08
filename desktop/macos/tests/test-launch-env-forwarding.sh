#!/usr/bin/env bash
# `open` launches the app from launchd rather than from run.sh's shell, so an
# environment override documented in run.sh reaches the app only if it is
# forwarded with `open --env`. This guard keeps the retained automation token
# overrides working on the normal launch path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/run.sh"
DESKTOP_APP_SCRUB_ENV_FILE="$ROOT/../../scripts/dev-harness/desktop-app-scrub-env.txt"
export DESKTOP_APP_SCRUB_ENV_FILE

BUILD_FUNCTION="$(sed -n '/^build_launch_env_args()/,/^}/p' "$RUN")"

if [[ -z "$BUILD_FUNCTION" ]]; then
  echo "FAIL: build_launch_env_args is missing from $RUN" >&2
  exit 1
fi

# Unset: launchd's ambient provider/admin authority is explicitly cleared,
# while optional automation capabilities remain absent.
(
  unset OMI_AUTOMATION_TOKEN_FILE OMI_AUTOMATION_TOKEN LOCAL_PROFILE
  eval "$BUILD_FUNCTION"
  build_launch_env_args
  rendered="$(printf '%s\n' "${LAUNCH_ENV_ARGS[@]}")"
  direct_rendered="$(printf '%s\n' "${DIRECT_LAUNCH_ENV[@]}")"
  grep -qx 'OPENAI_API_KEY=' <<<"$rendered"
  grep -qx 'LANGFUSE_SECRET_KEY=' <<<"$rendered"
  grep -qx 'ADMIN_KEY=' <<<"$rendered"
  grep -qx 'OMI_HARNESS_OWNERSHIP_TOKEN=' <<<"$rendered"
  ! grep -q '^OMI_AUTOMATION_TOKEN_FILE=' <<<"$rendered"
  ! grep -q '^OMI_AUTOMATION_TOKEN=' <<<"$rendered"
  grep -qx 'OPENAI_API_KEY=' <<<"$direct_rendered"
  grep -qx 'LANGFUSE_SECRET_KEY=' <<<"$direct_rendered"
  grep -qx 'ADMIN_KEY=' <<<"$direct_rendered"
  grep -qx 'OMI_HARNESS_OWNERSHIP_TOKEN=' <<<"$direct_rendered"
)

# Set: retained automation overrides are forwarded verbatim as `open --env`
# pairs.
(
  export OMI_AUTOMATION_TOKEN_FILE=/tmp/omi-test-token
  export OMI_AUTOMATION_TOKEN=test-token
  eval "$BUILD_FUNCTION"
  build_launch_env_args
  rendered="$(printf '%s\n' "${LAUNCH_ENV_ARGS[@]}")"
  direct_rendered="$(printf '%s\n' "${DIRECT_LAUNCH_ENV[@]}")"
  grep -qx 'OPENAI_API_KEY=' <<<"$rendered"
  grep -qx 'OMI_AUTOMATION_TOKEN_FILE=/tmp/omi-test-token' <<<"$rendered"
  grep -qx 'OMI_AUTOMATION_TOKEN=test-token' <<<"$rendered"
  grep -qx 'OMI_AUTOMATION_TOKEN_FILE=/tmp/omi-test-token' <<<"$direct_rendered"
  grep -qx 'OMI_AUTOMATION_TOKEN=test-token' <<<"$direct_rendered"
)

# Every `open` invocation on the launch path must carry the forwarded env, or
# the override works on some launch transports and not others.
OPEN_CALLS="$(grep -cE '^[[:space:]]*if ! open ' "$RUN" || true)"
# FC-shell-unset-array-under-nounset: expand the optional array with the
# `${arr[@]+"${arr[@]}"}` form, never bare `"${arr[@]}"`, so an empty array
# cannot trap `unbound variable` if this path ever runs under `set -u` on the
# bash 3.2 that ships with macOS.
OPEN_CALLS_WITH_ENV="$(grep -cE '^[[:space:]]*if ! open .*\$\{LAUNCH_ENV_ARGS\[@\]\+"\$\{LAUNCH_ENV_ARGS\[@\]\}"\}' "$RUN" || true)"

if [ "$OPEN_CALLS" -eq 0 ]; then
  echo "FAIL: no 'open' launch invocations found in $RUN" >&2
  exit 1
fi

if [ "$OPEN_CALLS" -ne "$OPEN_CALLS_WITH_ENV" ]; then
  echo "FAIL: $OPEN_CALLS 'open' launch invocations but only $OPEN_CALLS_WITH_ENV forward LAUNCH_ENV_ARGS in the nounset-safe form" >&2
  exit 1
fi

if grep -qE '^[[:space:]]*if ! open .*[^+]"\$\{LAUNCH_ENV_ARGS\[@\]\}"' "$RUN"; then
  echo "FAIL: bare \"\${LAUNCH_ENV_ARGS[@]}\" expansion traps under set -u on bash 3.2 (FC-shell-unset-array-under-nounset)" >&2
  exit 1
fi

DIRECT_CALLS="$(grep -cE '^[[:space:]]*env "\$\{DIRECT_LAUNCH_ENV\[@\]\}" "\$APP_PATH/Contents/MacOS/\$BINARY_NAME"' "$RUN" || true)"
if [ "$DIRECT_CALLS" -ne "$OPEN_CALLS" ]; then
  echo "FAIL: $OPEN_CALLS open fallbacks but only $DIRECT_CALLS sanitize the direct executable environment" >&2
  exit 1
fi

echo "PASS: launch env forwarding"
