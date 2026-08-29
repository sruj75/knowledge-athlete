#!/usr/bin/env bash
# shellcheck disable=SC2016
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$MACOS_DIR/scripts/codemagic-release.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/intentive-codemagic-release-test.XXXXXX")"

cleanup() {
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
make_executable "$mock_bin/curl" 'exit 0'

preview_slug="focus-notes"
preview_id="p$(printf '%s' "$preview_slug" | shasum -a 256 | cut -c1-10)"
cm_env="$TMP_ROOT/cm.env"
gcp_key_base64="$(printf '{}\n' | base64)"
common_env=(
  "PATH=$mock_bin:$PATH"
  "TEST_PREVIEW_SHA=$preview_sha"
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
  "PREVIEW_SLUG=$preview_slug"
  "PREVIEW_ID=$preview_id"
  "PREVIEW_SOURCE_REF=preview/$preview_slug"
  "PREVIEW_SOURCE_SHA=$preview_sha"
  "PREVIEW_BACKEND_ENVIRONMENT=preview"
  "OMI_PYTHON_API_URL=https://preview-api.heyintentive.com"
  "GCP_DESKTOP_PREVIEW_SERVICE_ACCOUNT_BASE64=$gcp_key_base64"
  "DESKTOP_PREVIEW_PUBLISH_KEY=fixture-publish-key"
  "INTENTIVE_PREVIEW_BUCKET=gs://intentive-previews"
  "INTENTIVE_PREVIEW_PUBLIC_ORIGIN=https://downloads.heyintentive.com"
  "INTENTIVE_PREVIEW_REGISTRY_URL=https://api.heyintentive.com"
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

if env "${common_env[@]}" OMI_PYTHON_API_URL=https://api.omi.me \
  CM_ENV="$TMP_ROOT/rejected-host.env" "$SCRIPT" validate >/dev/null 2>"$TMP_ROOT/rejected-host.err"; then
  fail "inherited Omi preview backend unexpectedly passed"
fi
grep -q 'inherited provider host' "$TMP_ROOT/rejected-host.err" ||
  fail "inherited provider rejection was not explicit"

if env "${common_env[@]}" PREVIEW_PUBLICATION_MODE=production \
  CM_ENV="$TMP_ROOT/rejected-fence.env" "$SCRIPT" validate >/dev/null 2>"$TMP_ROOT/rejected-fence.err"; then
  fail "preview production-publication mode unexpectedly passed"
fi
grep -q 'preview publication fence must remain preview-only' "$TMP_ROOT/rejected-fence.err" ||
  fail "preview publication-fence rejection was not explicit"

preview_build="$TMP_ROOT/build"
gcs_root="$TMP_ROOT/gcs"
mkdir -p "$preview_build"
printf 'signed preview fixture\n' > "$preview_build/Intentive-Preview.dmg"
printf '{"status":"passed"}\n' > "$preview_build/desktop-smoke-result.json"
env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish >/dev/null
env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish >/dev/null

printf '{"status":"different"}\n' > "$preview_build/desktop-smoke-result.json"
if env "${common_env[@]}" TEST_GCS_DIR="$gcs_root" "$SCRIPT" publish \
  >/dev/null 2>"$TMP_ROOT/rejected-immutable.err"; then
  fail "different bytes unexpectedly replaced immutable preview evidence"
fi
grep -q 'already exists with a different digest' "$TMP_ROOT/rejected-immutable.err" ||
  fail "immutable preview conflict was not explicit"

echo "PASS: Codemagic release source, identity, secret boundary, and immutable retry contracts"
