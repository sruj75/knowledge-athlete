#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=_source_local_dev_env.sh
source "$(dirname "$0")/_source_local_dev_env.sh"
cd "$(dirname "$0")/../.."

BACKEND_URL="${OMI_PYTHON_API_URL:-http://127.0.0.1:${OMI_HARNESS_BACKEND_PORT}}"
STATE_ROOT="${OMI_LOCAL_STATE_ROOT:-.local/dev-harness}/${OMI_LOCAL_INSTANCE}"
BACKEND_LOG="${STATE_ROOT}/logs/backend.log"
OMI_CTL="./desktop/macos/scripts/omi-ctl"

failures=0

echo "Intentive local dev harness verification"

if [ -x "$OMI_CTL" ]; then
  deadline=$((SECONDS + 30))
  signed_in=false
  while [ "$SECONDS" -lt "$deadline" ]; do
    if state_json="$("$OMI_CTL" state 2>/dev/null)"; then
      if echo "$state_json" | grep -q '"isSignedIn"[[:space:]]*:[[:space:]]*true'; then
        signed_in=true
        echo "omi-ctl state: isSignedIn=true"
        break
      fi
    fi
    sleep 2
  done
  if [ "$signed_in" != true ]; then
    echo "omi-ctl state: isSignedIn not true within 30s (is Intentive Dev running?)" >&2
    failures=$((failures + 1))
  fi
else
  echo "warning: $OMI_CTL not found; skipping omi-ctl state check"
fi

chat_status="$(curl --connect-timeout 3 --max-time 5 -s -o /dev/null -w '%{http_code}' -X POST "${BACKEND_URL}/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse" \
  -H 'Content-Type: application/json' \
  -H 'X-Intentive-Chat-Contract-Version: 2' \
  -d '{"contents":[{"role":"user","parts":[{"text":"ping"}]}],"generationConfig":{"maxOutputTokens":1}}' || true)"
# No Firebase token is sent: prove the route rejects anonymous inference, not
# model success. Connection errors and arbitrary non-404 responses are not proof.
case "$chat_status" in
  401|403) echo "chat smoke: anonymous inference rejected (HTTP $chat_status)" ;;
  *)
    echo "chat smoke: expected authentication rejection, got HTTP ${chat_status:-unknown}" >&2
    failures=$((failures + 1))
    ;;
esac

if [ -f "$BACKEND_LOG" ]; then
  aud_count="$(grep -c 'incorrect "aud"' "$BACKEND_LOG" 2>/dev/null || true)"
  if [ "${aud_count:-0}" -gt 0 ]; then
    echo "backend log: found ${aud_count} incorrect \"aud\" errors in $BACKEND_LOG" >&2
    failures=$((failures + 1))
  else
    echo "backend log: no incorrect \"aud\" errors"
  fi
else
  echo "warning: backend log not found at $BACKEND_LOG"
fi

if [ "$failures" -gt 0 ]; then
  echo "dev-verify failed ($failures check(s))" >&2
  exit 1
fi

echo "dev-verify passed"
