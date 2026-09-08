#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCTION_SCRIPT="$MACOS_DIR/scripts/codemagic-release.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/intentive-codemagic-release-test.XXXXXX")"
OWNED_POSTHOG_TOKEN_SHA256="d30c51741e163c11c7bc34f5661d63c5f691ae6c584663aacfdd735153e9894c"
FIXTURE_POSTHOG_TOKEN="fixture-posthog-project-token"
FIXTURE_POSTHOG_TOKEN_SHA256="$(printf '%s' "$FIXTURE_POSTHOG_TOKEN" | shasum -a 256 | awk '{print $1}')"
SCRIPT=""

cleanup() {
  [[ -z "$SCRIPT" ]] || rm -f -- "$SCRIPT"
  case "$TMP_ROOT" in
    "${TMPDIR:-/tmp}/intentive-codemagic-release-test."*) rm -rf -- "$TMP_ROOT" ;;
    *) echo "Refusing unsafe cleanup path: $TMP_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

SCRIPT="$(mktemp "$MACOS_DIR/scripts/.codemagic-release-test.XXXXXX")"
grep -Fq "OWNED_POSTHOG_PROJECT_TOKEN_SHA256=\"$OWNED_POSTHOG_TOKEN_SHA256\"" "$PRODUCTION_SCRIPT" ||
  fail "production release script does not pin the owned PostHog project fingerprint"
sed "s/$OWNED_POSTHOG_TOKEN_SHA256/$FIXTURE_POSTHOG_TOKEN_SHA256/g" "$PRODUCTION_SCRIPT" > "$SCRIPT"
chmod +x "$SCRIPT"

make_executable() {
  local path="$1"
  shift
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' "$@"
  } > "$path"
  chmod +x "$path"
}

mock_bin="$TMP_ROOT/bin"
mkdir -p "$mock_bin"
preview_sha="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
# The single-quoted lines are intentionally emitted into the fake executables.
make_executable "$mock_bin/git" \
  'case "${1:-}" in' \
  '  fetch|checkout) exit 0 ;;' \
  '  rev-parse) printf "%s\n" "${TEST_PREVIEW_SHA:?}" ;;' \
  '  show) printf "%s\n" 1700000000 ;;' \
  '  *) echo "unexpected git call: $*" >&2; exit 1 ;;' \
  'esac'
make_executable "$mock_bin/gcloud" \
  'if [[ "${1:-} ${2:-}" == "auth activate-service-account" ]]; then exit 0; fi' \
  '[[ "${1:-} ${2:-}" == "storage cp" ]] || { echo "unexpected gcloud call: $*" >&2; exit 1; }' \
  'shift 2' \
  'source_path=""' \
  'destination_path=""' \
  'for argument in "$@"; do' \
  '  [[ "$argument" == --* ]] && continue' \
  '  if [[ -z "$source_path" ]]; then source_path="$argument"; else destination_path="$argument"; fi' \
  'done' \
  'map_path() {' \
  '  case "$1" in' \
  '    gs://*) printf "%s/%s\n" "${TEST_GCS_DIR:?}" "${1#gs://}" ;;' \
  '    *) printf "%s\n" "$1" ;;' \
  '  esac' \
  '}' \
  'mapped_source="$(map_path "$source_path")"' \
  'mapped_destination="$(map_path "$destination_path")"' \
  '[[ -f "$mapped_source" ]] || exit 1' \
  'mkdir -p "$(dirname "$mapped_destination")"' \
  '/bin/cp "$mapped_source" "$mapped_destination"'
make_executable "$mock_bin/curl" \
  'payload=""' \
  'authorization=""' \
  'url=""' \
  'connect_timeout=""; total_timeout=""' \
  'while [[ "$#" -gt 0 ]]; do' \
  '  case "$1" in' \
  '    --data) payload="$2"; shift 2 ;;' \
  '    -H|--header) [[ "$2" == Authorization:* ]] && authorization="$2"; shift 2 ;;' \
  '    --connect-timeout) connect_timeout="$2"; shift 2 ;;' \
  '    --max-time) total_timeout="$2"; shift 2 ;;' \
  '    http*) url="$1"; shift ;;' \
  '    *) shift ;;' \
  '  esac' \
  'done' \
  'case "$url" in' \
  '  https://api.github.com/app/installations/*/access_tokens)' \
  '    printf "%s\n" mint >> "${TEST_COMMAND_TRACE:?}"' \
  '    printf "%s\n" "$payload" > "${TEST_APP_TOKEN_REQUEST:?}"' \
  '    printf "%s\n" "$authorization" > "${TEST_APP_AUTHORIZATION:?}"' \
  '    printf "%s %s\n" "$connect_timeout" "$total_timeout" > "${TEST_APP_TIMEOUTS:?}"' \
  '    printf "%s" "${TEST_APP_TOKEN_RESPONSE:?}"' \
  '    exit "${TEST_APP_TOKEN_EXIT:-0}"' \
  '    ;;' \
  '  *)' \
  '    printf "%s\n" preview-registry >> "${TEST_COMMAND_TRACE:?}"' \
  '    printf "%s\n" "$payload" > "${TEST_CURL_PAYLOAD:?}"' \
  '    ;;' \
  'esac'
make_executable "$mock_bin/gh" \
  'printf "gh:%s %s\n" "${1:-}" "${2:-}" >> "${TEST_COMMAND_TRACE:?}"' \
  'printf "%s\n" "${GH_TOKEN:-}" >> "${TEST_GH_TOKENS:?}"' \
  'case "${1:-} ${2:-}" in' \
  '  "release view") [[ "${TEST_RELEASE_EXISTS:-false}" == "true" ]] ;;' \
  '  "release create") printf "%s\n" "$*" > "${TEST_GH_CREATE_ARGS:?}" ;;' \
  '  *) echo "unexpected gh call: $*" >&2; exit 1 ;;' \
  'esac'

preview_slug="focus-notes"
preview_id="p$(printf '%s' "$preview_slug" | shasum -a 256 | cut -c1-10)"
preview_notes=$'Try the focus flow.\nCheck the new keyboard shortcut.'
cm_env="$TMP_ROOT/cm.env"
curl_payload="$TMP_ROOT/preview-payload.json"
command_trace="$TMP_ROOT/command-trace.txt"
app_token_request="$TMP_ROOT/app-token-request.json"
app_authorization="$TMP_ROOT/app-authorization.txt"
app_timeouts="$TMP_ROOT/app-timeouts.txt"
gh_tokens="$TMP_ROOT/gh-tokens.txt"
gh_create_args="$TMP_ROOT/gh-create-args.txt"
gcp_key_base64="$(printf '{}\n' | base64)"
common_env=(
  "PATH=$mock_bin:$PATH"
  "TEST_PREVIEW_SHA=$preview_sha"
  "TEST_CURL_PAYLOAD=$curl_payload"
  "TEST_COMMAND_TRACE=$command_trace"
  "TEST_APP_TOKEN_REQUEST=$app_token_request"
  "TEST_APP_AUTHORIZATION=$app_authorization"
  "TEST_APP_TIMEOUTS=$app_timeouts"
  "TEST_GH_TOKENS=$gh_tokens"
  "TEST_GH_CREATE_ARGS=$gh_create_args"
  "PREVIEW_MODE=true"
  "PREVIEW_PUBLICATION_MODE=preview-only"
  "APP_NAME=Intentive Preview"
  "BINARY_NAME=Omi Computer"
  "BUNDLE_ID=com.heyintentive.intentive.preview.pending"
  "URL_SCHEME=heyintentive-preview-pending"
  "APPLE_TEAM_ID=24D6NXS6H7"
  "CODEMAGIC_APP_ID=6a8ff0296fc70d39540cb56a"
  "GITHUB_REPOSITORY=sruj75/knowledge-athlete"
  "GITHUB_RELEASES_URL=https://github.com/sruj75/knowledge-athlete/releases"
  "BUILD_DIR=$TMP_ROOT/build"
  "CM_ENV=$cm_env"
  "MACOS_DEVELOPER_ID_P12=fixture-p12"
  "MACOS_DEVELOPER_ID_P12_PASSWORD=fixture-password"
  "APP_STORE_CONNECT_KEY_IDENTIFIER=fixture-key"
  "APP_STORE_CONNECT_PRIVATE_KEY=fixture-private-key"
  "APP_STORE_CONNECT_ISSUER_ID=fixture-issuer"
  "INTENTIVE_FIREBASE_PLIST_BASE64=fixture-firebase"
  "INTENTIVE_DESKTOP_APP_ENV_BASE64=fixture-app-env"
  "POSTHOG_PROJECT_API_KEY=$FIXTURE_POSTHOG_TOKEN"
  "POSTHOG_HOST=https://us.i.posthog.com"
  "SIGN_IDENTITY=Developer ID Application: Intentive (24D6NXS6H7)"
  "PREVIEW_SLUG=$preview_slug"
  "PREVIEW_ID=$preview_id"
  "PREVIEW_SOURCE_REF=preview/$preview_slug"
  "PREVIEW_SOURCE_SHA=$preview_sha"
  "PREVIEW_NOTES_BASE64=$(printf '%s' "$preview_notes" | base64 | tr -d '\n')"
  "PREVIEW_BACKEND_ENVIRONMENT=development"
  "OMI_PYTHON_API_URL=https://preview-api.heyintentive.com"
  "GCP_DESKTOP_PREVIEW_SERVICE_ACCOUNT_BASE64=$gcp_key_base64"
  "DESKTOP_PREVIEW_PUBLISH_KEY=fixture-publish-key"
  "INTENTIVE_PREVIEW_BUCKET=gs://intentive-previews"
  "INTENTIVE_PREVIEW_PUBLIC_ORIGIN=https://downloads.heyintentive.com"
  "INTENTIVE_PREVIEW_REGISTRY_URL=https://api.heyintentive.com"
  "INTENTIVE_APPROVED_PRODUCTION_API_ORIGIN=https://api.heyintentive.com"
)

env "${common_env[@]}" "$SCRIPT" validate >/dev/null
grep -Fxq "SOURCE_SHA=$preview_sha" "$cm_env" || fail "exact preview source was not exported"
grep -Fxq "BUNDLE_ID=com.heyintentive.intentive.preview.$preview_id" "$cm_env" ||
  fail "owned preview bundle identity was not exported"
grep -Fxq "URL_SCHEME=heyintentive-preview-$preview_id" "$cm_env" ||
  fail "owned preview URL scheme was not exported"
if grep -q 'fixture-password\|fixture-private-key\|fixture-publish-key' "$cm_env"; then
  fail "protected provider input leaked into CM_ENV"
fi

if env "${common_env[@]}" POSTHOG_PROJECT_API_KEY= \
  CM_ENV="$TMP_ROOT/rejected-missing-posthog.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-missing-posthog.err"; then
  fail "missing PostHog project token unexpectedly passed"
fi
grep -q 'POSTHOG_PROJECT_API_KEY is required' "$TMP_ROOT/rejected-missing-posthog.err" ||
  fail "missing PostHog project token rejection was not explicit"

if env "${common_env[@]}" POSTHOG_PROJECT_API_KEY=wrong-posthog-project-token \
  CM_ENV="$TMP_ROOT/rejected-wrong-posthog.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-wrong-posthog.err"; then
  fail "wrong PostHog project token unexpectedly passed"
fi
grep -q 'does not match the owned Intentive Desktop project' "$TMP_ROOT/rejected-wrong-posthog.err" ||
  fail "wrong PostHog project token rejection was not explicit"

runtime_build="$TMP_ROOT/runtime-build"
runtime_app="$runtime_build/Intentive.app"
mkdir -p "$runtime_app/Contents/Resources"
cp "$MACOS_DIR/Desktop/Info.plist" "$runtime_app/Contents/Info.plist"
runtime_env_base64="$(printf 'FIREBASE_API_KEY=fixture-firebase-key\nSAFE_VALUE=retained\n' | base64 | tr -d '\n')"
env \
  BUILD_DIR="$runtime_build" \
  APP_NAME=Intentive \
  OMI_PYTHON_API_URL=https://api.heyintentive.com \
  INTENTIVE_DESKTOP_APP_ENV_BASE64="$runtime_env_base64" \
  POSTHOG_PROJECT_API_KEY=fixture-posthog-project-token \
  POSTHOG_HOST=https://us.i.posthog.com \
  "$SCRIPT" configure-owned-runtime >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :IntentivePostHogProjectToken' "$runtime_app/Contents/Info.plist")" == \
  "fixture-posthog-project-token" ]] || fail "owned runtime phase did not stamp the PostHog project token"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :IntentivePostHogHost' "$runtime_app/Contents/Info.plist")" == \
  "https://us.i.posthog.com" ]] || fail "owned runtime phase did not stamp the PostHog host"
grep -Fxq 'OMI_PYTHON_API_URL=https://api.heyintentive.com' "$runtime_app/Contents/Resources/.env" ||
  fail "owned runtime phase did not stamp the backend URL"
if grep -Eq '^POSTHOG_(PROJECT_API_KEY|HOST)=' "$runtime_app/Contents/Resources/.env"; then
  fail "owned PostHog configuration was duplicated into the override-capable bundled env"
fi

runtime_override_base64="$(printf 'FIREBASE_API_KEY=fixture-firebase-key\n  export POSTHOG_PROJECT_API_KEY=inherited-token\nPOSTHOG_HOST = https://attacker.example\n' | base64 | tr -d '\n')"
if env \
  BUILD_DIR="$runtime_build" \
  APP_NAME=Intentive \
  OMI_PYTHON_API_URL=https://api.heyintentive.com \
  INTENTIVE_DESKTOP_APP_ENV_BASE64="$runtime_override_base64" \
  POSTHOG_PROJECT_API_KEY=fixture-posthog-project-token \
  POSTHOG_HOST=https://us.i.posthog.com \
  "$SCRIPT" configure-owned-runtime >/dev/null 2>"$TMP_ROOT/rejected-posthog-override.err"; then
  fail "bundled PostHog override unexpectedly passed"
fi
grep -q 'must not contain PostHog overrides' "$TMP_ROOT/rejected-posthog-override.err" ||
  fail "bundled PostHog override rejection was not explicit"

runtime_backend_override_base64="$(printf 'FIREBASE_API_KEY=fixture-firebase-key\n export OMI_PYTHON_API_URL = https://attacker.example\n' | base64 | tr -d '\n')"
if env \
  BUILD_DIR="$runtime_build" \
  APP_NAME=Intentive \
  OMI_PYTHON_API_URL=https://api.heyintentive.com \
  INTENTIVE_DESKTOP_APP_ENV_BASE64="$runtime_backend_override_base64" \
  POSTHOG_PROJECT_API_KEY="$FIXTURE_POSTHOG_TOKEN" \
  POSTHOG_HOST=https://us.i.posthog.com \
  "$SCRIPT" configure-owned-runtime >/dev/null 2>"$TMP_ROOT/rejected-backend-override.err"; then
  fail "normalized bundled backend override unexpectedly passed"
fi
grep -q 'must not contain backend URL overrides' "$TMP_ROOT/rejected-backend-override.err" ||
  fail "normalized bundled backend override rejection was not explicit"

if env "${common_env[@]}" OMI_PYTHON_API_URL=https://api.omi.me \
  CM_ENV="$TMP_ROOT/rejected-host.env" "$SCRIPT" validate >/dev/null 2>"$TMP_ROOT/rejected-host.err"; then
  fail "inherited Omi preview backend unexpectedly passed"
fi
grep -q 'inherited provider host' "$TMP_ROOT/rejected-host.err" ||
  fail "inherited provider rejection was not explicit"

if env "${common_env[@]}" INTENTIVE_PREVIEW_REGISTRY_URL=https://attacker.example \
  CM_ENV="$TMP_ROOT/rejected-registry-origin.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-registry-origin.err"; then
  fail "unapproved preview registry origin unexpectedly passed"
fi
grep -q 'does not match the separately approved release origin' \
  "$TMP_ROOT/rejected-registry-origin.err" ||
  fail "preview registry origin rejection was not explicit"

if env "${common_env[@]}" PREVIEW_PUBLICATION_MODE=production \
  CM_ENV="$TMP_ROOT/rejected-fence.env" "$SCRIPT" validate >/dev/null 2>"$TMP_ROOT/rejected-fence.err"; then
  fail "preview production-publication mode unexpectedly passed"
fi
grep -q 'preview publication fence must remain preview-only' "$TMP_ROOT/rejected-fence.err" ||
  fail "preview publication-fence rejection was not explicit"

release_env=(
  "${common_env[@]}"
  "PREVIEW_MODE=false"
  "APP_NAME=Intentive"
  "BUNDLE_ID=com.heyintentive.intentive"
  "URL_SCHEME=heyintentive"
  "CM_TAG=v1.2.3+1002003-macos"
  "INTENTIVE_BETA_FIREBASE_PLIST_BASE64=fixture-beta-firebase"
  "INTENTIVE_SPARKLE_PUBLIC_KEY=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
  "SPARKLE_PRIVATE_KEY=fixture-sparkle-private-key"
  "SENTRY_AUTH_TOKEN=fixture-sentry-token"
  "GH_TOKEN="
  "INTENTIVE_RELEASE_APP_ID=4838294"
  "INTENTIVE_RELEASE_APP_INSTALLATION_ID=159216850"
  "INTENTIVE_PRODUCTION_API_URL=https://api.heyintentive.com"
  "INTENTIVE_APPROVED_PRODUCTION_API_ORIGIN=https://api.heyintentive.com"
  "INTENTIVE_STABLE_FEED_URL=https://updates.heyintentive.com/v2/desktop/appcast.xml"
  "INTENTIVE_BETA_FEED_URL=https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta"
  "INTENTIVE_MANUAL_DOWNLOAD_URL=https://heyintentive.com/download"
  "INTENTIVE_PRODUCT_URL=https://heyintentive.com"
  "INTENTIVE_TERMS_URL=https://heyintentive.com/terms"
  "INTENTIVE_PRIVACY_URL=https://heyintentive.com/privacy"
  "INTENTIVE_SUPPORT_URL=https://heyintentive.com/support"
)

# Execute the real provider smoke phase against a controlled artifact inspector.
# This proves the producer requests the callbacks its qualification consumer
# requires, and preserves each inspector failure without building a signed app.
smoke_scripts="$TMP_ROOT/smoke-repo/desktop/macos/scripts"
smoke_calls="$TMP_ROOT/smoke-calls.tsv"
mkdir -p "$smoke_scripts"
cp "$PRODUCTION_SCRIPT" "$smoke_scripts/codemagic-release.sh"
make_executable "$smoke_scripts/smoke-signed-desktop-artifact.sh" \
  'bundle=""; auth_canary=false; notification_canary=false' \
  'while [[ "$#" -gt 0 ]]; do' \
  '  case "$1" in' \
  '    --expected-bundle-id) bundle="$2"; shift 2 ;;' \
  '    --auth-storage-canary) auth_canary=true; shift ;;' \
  '    --notification-callback-canary) notification_canary=true; shift ;;' \
  '    *) shift ;;' \
  '  esac' \
  'done' \
  'printf "%s\t%s\t%s\n" "$bundle" "$auth_canary" "$notification_canary" >> "${TEST_SMOKE_CALLS:?}"' \
  'if [[ "$bundle" == "${TEST_SMOKE_REJECT_BUNDLE:-}" ]]; then exit 23; fi'
env "${release_env[@]}" SOURCE_SHA="$preview_sha" TEST_SMOKE_CALLS="$smoke_calls" \
  bash "$smoke_scripts/codemagic-release.sh" smoke
[[ "$(wc -l < "$smoke_calls" | tr -d ' ')" == "2" ]] || fail "provider did not inspect exactly both release identities"
grep -Fxq $'com.heyintentive.intentive\ttrue\ttrue' "$smoke_calls" ||
  fail "Stable provider smoke omitted an admission-required canary"
grep -Fxq $'com.heyintentive.intentive.beta\ttrue\ttrue' "$smoke_calls" ||
  fail "Beta provider smoke omitted an admission-required canary"

for rejected_bundle in com.heyintentive.intentive com.heyintentive.intentive.beta; do
  rejected_smoke_calls="$TMP_ROOT/smoke-rejected-$rejected_bundle.tsv"
  if env "${release_env[@]}" SOURCE_SHA="$preview_sha" TEST_SMOKE_CALLS="$rejected_smoke_calls" \
    TEST_SMOKE_REJECT_BUNDLE="$rejected_bundle" bash "$smoke_scripts/codemagic-release.sh" smoke; then
    fail "provider ignored a failed artifact inspector for $rejected_bundle"
  else
    smoke_exit=$?
  fi
  [[ "$smoke_exit" == "23" ]] || fail "provider masked artifact inspector failure"
  expected_calls=1
  [[ "$rejected_bundle" != com.heyintentive.intentive.beta ]] || expected_calls=2
  [[ "$(wc -l < "$rejected_smoke_calls" | tr -d ' ')" == "$expected_calls" ]] ||
    fail "provider continued inspecting after an artifact failure"
done

fixture_release_app_private_key_path="$TMP_ROOT/release-app-private-key.pem"
openssl genrsa 2048 > "$fixture_release_app_private_key_path" 2>/dev/null
chmod 600 "$fixture_release_app_private_key_path"
fixture_release_app_private_key="$(<"$fixture_release_app_private_key_path")"
release_env+=("INTENTIVE_RELEASE_APP_PRIVATE_KEY=$fixture_release_app_private_key")

: > "$command_trace"
release_cm_env="$TMP_ROOT/release.env"
env "${release_env[@]}" CM_ENV="$release_cm_env" "$SCRIPT" validate >/dev/null
[[ ! -s "$command_trace" ]] || fail "initial release validation minted a pre-aged installation token"
if grep -q 'fixture-github-token\|BEGIN .*PRIVATE KEY\|INTENTIVE_RELEASE_APP_PRIVATE_KEY' "$release_cm_env"; then
  fail "GitHub publication credential leaked into CM_ENV"
fi

if env "${release_env[@]}" INTENTIVE_RELEASE_APP_INSTALLATION_ID=42 \
  CM_ENV="$TMP_ROOT/rejected-release-app.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-release-app.err"; then
  fail "wrong GitHub Release App installation unexpectedly passed"
fi
grep -q 'unexpected GitHub Release App installation ID' "$TMP_ROOT/rejected-release-app.err" ||
  fail "wrong GitHub Release App installation rejection was not explicit"

if env "${release_env[@]}" INTENTIVE_RELEASE_APP_PRIVATE_KEY=not-a-private-key \
  CM_ENV="$TMP_ROOT/rejected-release-key.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-release-key.err"; then
  fail "malformed GitHub Release App private key unexpectedly passed"
fi
grep -q 'GitHub Release App private key is invalid' "$TMP_ROOT/rejected-release-key.err" ||
  fail "malformed GitHub Release App private-key rejection was not explicit"
if env "${release_env[@]}" \
  INTENTIVE_PRODUCTION_API_URL=https://attacker.example \
  CM_ENV="$TMP_ROOT/rejected-production-origin.env" "$SCRIPT" validate \
  >/dev/null 2>"$TMP_ROOT/rejected-production-origin.err"; then
  fail "unapproved production API origin unexpectedly passed"
fi
grep -q 'does not match the separately approved release origin' \
  "$TMP_ROOT/rejected-production-origin.err" ||
  fail "production API origin rejection was not explicit"

for public_destination in \
  INTENTIVE_PRODUCT_URL \
  INTENTIVE_TERMS_URL \
  INTENTIVE_PRIVACY_URL \
  INTENTIVE_SUPPORT_URL; do
  if env "${release_env[@]}" "$public_destination=https://example.com/retired" \
    CM_ENV="$TMP_ROOT/rejected-$public_destination.env" "$SCRIPT" validate \
    >/dev/null 2>"$TMP_ROOT/rejected-$public_destination.err"; then
    fail "$public_destination unexpectedly accepted a non-owned host"
  fi
  grep -q 'must use heyintentive.com or one of its subdomains' \
    "$TMP_ROOT/rejected-$public_destination.err" ||
    fail "$public_destination rejection did not explain the owned-host requirement"
done

preview_build="$TMP_ROOT/build"
gcs_root="$TMP_ROOT/gcs"
mkdir -p "$preview_build"
printf 'signed preview fixture\n' > "$preview_build/Intentive-Preview.dmg"
printf '{"status":"passed"}\n' > "$preview_build/desktop-smoke-result.json"
env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish >/dev/null
jq -e \
  --arg notes "$preview_notes" \
  --arg signer "Developer ID Application: Intentive (24D6NXS6H7)" \
  --arg dmg_url "https://storage.googleapis.com/intentive-previews/previews/$preview_slug/$preview_sha/Intentive-Preview.dmg" \
  '.notes == $notes and .signer == $signer and .dmg_url == $dmg_url' \
  "$curl_payload" >/dev/null || fail "preview registry payload lost notes, signer, or canonical GCS URL"
env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish >/dev/null

printf '{"status":"different"}\n' > "$preview_build/desktop-smoke-result.json"
if env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish \
  >/dev/null 2>"$TMP_ROOT/rejected-immutable.err"; then
  fail "different bytes unexpectedly replaced immutable preview evidence"
fi
grep -q 'already exists with a different digest' "$TMP_ROOT/rejected-immutable.err" ||
  fail "immutable preview conflict was not explicit"

if grep -Fxq mint "$command_trace"; then
  fail "preview publication unexpectedly requested a production release token"
fi

release_build="$TMP_ROOT/release-build"
mkdir -p "$release_build"
for artifact in \
  Intentive.zip \
  intentive.dmg \
  Intentive.Beta.zip \
  intentive-beta.dmg \
  Intentive.app.dSYM.zip \
  desktop-smoke-result.json \
  desktop-smoke-result-beta.json; do
  printf 'signed release fixture: %s\n' "$artifact" > "$release_build/$artifact"
done
token_expires_at="$(python3 - <<'PY'
from datetime import datetime, timedelta, timezone

print((datetime.now(timezone.utc) + timedelta(minutes=55)).isoformat().replace("+00:00", "Z"))
PY
)"
installation_token="ghs_fixture_installation_token"
token_response="$(jq -cn \
  --arg token "$installation_token" \
  --arg expires_at "$token_expires_at" \
  '{token: $token, expires_at: $expires_at, permissions: {contents: "write", metadata: "read"}, repository_selection: "selected", repositories: [{full_name: "sruj75/knowledge-athlete"}]}')"
publish_env=(
  "${release_env[@]}"
  "BUILD_DIR=$release_build"
  "VERSION=1.2.3"
  "SOURCE_SHA=$preview_sha"
  "ED_SIGNATURE=stable-signature"
  "BETA_ED_SIGNATURE=beta-signature"
  "TEST_APP_TOKEN_RESPONSE=$token_response"
  "TEST_RELEASE_EXISTS=false"
)

: > "$command_trace"
: > "$gh_tokens"
env "${publish_env[@]}" "$SCRIPT" publish >/dev/null
[[ "$(sed -n '1p' "$command_trace")" == mint ]] || fail "release publication did not mint just in time"
[[ "$(sed -n '2p' "$command_trace")" == "gh:release view" ]] || fail "release lookup did not follow token mint"
[[ "$(sed -n '3p' "$command_trace")" == "gh:release create" ]] || fail "release creation did not follow lookup"
[[ "$(wc -l < "$command_trace" | tr -d ' ')" == 3 ]] || fail "release publication ran unexpected commands"
jq -e \
  '.repositories == ["knowledge-athlete"] and .permissions == {"contents": "write"}' \
  "$app_token_request" >/dev/null || fail "installation token request exceeded the exact repository/permission scope"
while IFS= read -r observed_token; do
  [[ "$observed_token" == "$installation_token" ]] || fail "gh did not receive only the minted installation token"
done < "$gh_tokens"
grep -Fq -- '--verify-tag' "$gh_create_args" || fail "create-only publication lost tag verification"
grep -Fq -- '--target aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$gh_create_args" ||
  fail "create-only publication lost exact source binding"

jwt="$(sed 's/^Authorization: Bearer //' "$app_authorization")"
IFS=. read -r jwt_header jwt_payload jwt_signature <<< "$jwt"
python3 - "$jwt_header" "$jwt_payload" <<'PY'
import base64
import json
import sys
import time


def decode(segment: str) -> dict:
    padded = segment + "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(padded))


header = decode(sys.argv[1])
payload = decode(sys.argv[2])
assert header == {"alg": "RS256", "typ": "JWT"}
assert payload["iss"] == "4838294"
assert payload["exp"] - payload["iat"] == 600
assert payload["iat"] <= int(time.time()) <= payload["exp"]
PY
printf '%s' "$jwt_header.$jwt_payload" > "$TMP_ROOT/jwt-message"
python3 - "$jwt_signature" "$TMP_ROOT/jwt-signature" <<'PY'
import base64
from pathlib import Path
import sys

segment = sys.argv[1]
Path(sys.argv[2]).write_bytes(base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4)))
PY
openssl pkey -in "$fixture_release_app_private_key_path" -pubout -out "$TMP_ROOT/release-app-public-key.pem" 2>/dev/null
openssl dgst -sha256 \
  -verify "$TMP_ROOT/release-app-public-key.pem" \
  -signature "$TMP_ROOT/jwt-signature" \
  "$TMP_ROOT/jwt-message" >/dev/null || fail "GitHub App JWT signature does not match the protected private key"

: > "$command_trace"
bad_token_response="$(jq '.token = "private-response-token" | .repositories = [{full_name: "attacker/other"}]' <<< "$token_response")"
if env "${publish_env[@]}" TEST_APP_TOKEN_RESPONSE="$bad_token_response" "$SCRIPT" publish \
  >/dev/null 2>"$TMP_ROOT/rejected-token-response.err"; then
  fail "wrong-repository installation token response unexpectedly passed"
fi
grep -q 'installation token response failed validation' "$TMP_ROOT/rejected-token-response.err" ||
  fail "wrong-repository token response rejection was not explicit"
if grep -q 'private-response-token\|attacker/other' "$TMP_ROOT/rejected-token-response.err"; then
  fail "installation token response body leaked into error output"
fi
[[ "$(cat "$command_trace")" == mint ]] || fail "invalid installation token response reached gh"

# Execute the actual response parser with one changed authority/lifetime field.
# GitHub's installation-token contract is one hour with requested permissions:
# https://docs.github.com/en/rest/apps/apps#create-an-installation-access-token-for-an-app
for invalid_response in \
  '.permissions.actions = "read"' \
  '.expires_at = "2099-01-01T00:00:00Z"' \
  '.repository_selection = "all"'; do
  : > "$command_trace"
  bad_token_response="$(jq "$invalid_response" <<< "$token_response")"
  if env "${publish_env[@]}" TEST_APP_TOKEN_RESPONSE="$bad_token_response" "$SCRIPT" publish \
    >"$TMP_ROOT/rejected-token-contract.out" 2>"$TMP_ROOT/rejected-token-contract.err"; then
    fail "out-of-contract installation token response unexpectedly passed: $invalid_response"
  fi
  [[ "$(cat "$command_trace")" == mint ]] || fail "out-of-contract token reached gh"
  grep -q 'installation token response failed validation' "$TMP_ROOT/rejected-token-contract.err" ||
    fail "token contract rejection was not explicit"
  if grep -Fq "$installation_token" "$TMP_ROOT/rejected-token-contract.out" "$TMP_ROOT/rejected-token-contract.err"; then
    fail "rejected token leaked into diagnostics"
  fi
done

: > "$command_trace"
if env "${publish_env[@]}" TEST_APP_TOKEN_EXIT=28 "$SCRIPT" publish \
  >"$TMP_ROOT/rejected-token-transport.out" 2>"$TMP_ROOT/rejected-token-transport.err"; then
  fail "failed token transport unexpectedly reached publication"
fi
[[ "$(cat "$command_trace")" == mint ]] || fail "failed token transport reached gh"
[[ "$(cat "$app_timeouts")" == '10 30' ]] || fail "token transport is not bounded to 10s connect and 30s total"
if grep -Fq "$installation_token" "$TMP_ROOT/rejected-token-transport.out" "$TMP_ROOT/rejected-token-transport.err"; then
  fail "failed token transport leaked response credentials"
fi

: > "$command_trace"
if env "${publish_env[@]}" TEST_RELEASE_EXISTS=true "$SCRIPT" publish \
  >/dev/null 2>"$TMP_ROOT/rejected-existing-release.err"; then
  fail "existing immutable candidate unexpectedly passed"
fi
grep -q 'already exists; refusing to replace' "$TMP_ROOT/rejected-existing-release.err" ||
  fail "existing immutable candidate rejection was not explicit"
[[ "$(sed -n '1p' "$command_trace")" == mint ]] || fail "existing-release check did not use a fresh token"
[[ "$(sed -n '2p' "$command_trace")" == "gh:release view" ]] || fail "existing-release check did not query GitHub"
[[ "$(wc -l < "$command_trace" | tr -d ' ')" == 2 ]] || fail "existing release reached candidate creation"

echo "PASS: Codemagic release source, identity, secret boundary, and immutable retry contracts"
