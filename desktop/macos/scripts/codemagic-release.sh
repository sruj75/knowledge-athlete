#!/usr/bin/env bash
# Repository-owned Codemagic boundary for signed Intentive macOS artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/../.." && pwd)"

PREVIEW_MODE="${PREVIEW_MODE:-false}"
BUILD_DIR="${BUILD_DIR:-build}"
BINARY_NAME="${BINARY_NAME:-Omi Computer}"
APP_NAME="${APP_NAME:-Intentive}"
BUNDLE_ID="${BUNDLE_ID:-com.heyintentive.intentive}"
URL_SCHEME="${URL_SCHEME:-heyintentive}"
BETA_APP_NAME="${BETA_APP_NAME:-Intentive Beta}"
BETA_BUNDLE_ID="${BETA_BUNDLE_ID:-com.heyintentive.intentive.beta}"
BETA_URL_SCHEME="${BETA_URL_SCHEME:-heyintentive-beta}"
APPLE_TEAM_ID="${APPLE_TEAM_ID:-24D6NXS6H7}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-sruj75/knowledge-athlete}"
CM_ENV_FILE="${CM_ENV:-$BUILD_DIR/codemagic.env}"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
SOURCE_SHA="${SOURCE_SHA:-}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
STABLE_ZIP="$BUILD_DIR/Intentive.zip"
STABLE_DMG="$BUILD_DIR/intentive.dmg"
BETA_ZIP="$BUILD_DIR/Intentive.Beta.zip"
BETA_DMG="$BUILD_DIR/intentive-beta.dmg"
DSYM_PATH="$BUILD_DIR/Intentive.app.dSYM"
DSYM_ARCHIVE="$BUILD_DIR/Intentive.app.dSYM.zip"
PREVIEW_DMG="$BUILD_DIR/Intentive-Preview.dmg"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_env() {
  local name="$1"
  [[ -n "${!name:-}" ]] || fail "$name is required in the protected Codemagic variable group"
}

append_cm_env() {
  mkdir -p "$(dirname "$CM_ENV_FILE")"
  printf '%s=%s\n' "$1" "$2" >> "$CM_ENV_FILE"
}

plist_set() {
  local plist="$1"
  local key="$2"
  local type="$3"
  local value="$4"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null ||
    /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$plist"
}

validate_url() {
  local name="$1"
  local value="${!name:-}"
  URL_NAME="$name" URL_VALUE="$value" python3 - <<'PY'
import os
from urllib.parse import urlsplit

name = os.environ["URL_NAME"]
value = os.environ["URL_VALUE"]
try:
    parsed = urlsplit(value)
    parsed.port
except ValueError as exc:
    raise SystemExit(f"ERROR: {name} is invalid: {exc}") from exc
host = (parsed.hostname or "").lower().rstrip(".")
if (
    value != value.strip()
    or parsed.scheme.lower() != "https"
    or not host
    or parsed.username is not None
    or parsed.password is not None
    or parsed.fragment
):
    raise SystemExit(f"ERROR: {name} must be one clean absolute HTTPS URL")
for inherited in ("omi.me", "omiapi.com", "basedhardware.com"):
    if host == inherited or host.endswith("." + inherited):
        raise SystemExit(f"ERROR: {name} uses inherited provider host {host}")
PY
}

validate_owned_identity() {
  [[ "$APPLE_TEAM_ID" == "24D6NXS6H7" ]] || fail "unexpected Apple Team ID: $APPLE_TEAM_ID"
  [[ "$GITHUB_REPOSITORY" == "sruj75/knowledge-athlete" ]] ||
    fail "unexpected GitHub release repository: $GITHUB_REPOSITORY"
  [[ "${CODEMAGIC_APP_ID:-}" == "6a8ff0296fc70d39540cb56a" ]] ||
    fail "unexpected Codemagic application ID"
  [[ "${PREVIEW_PUBLICATION_MODE:-}" == "preview-only" ]] ||
    fail "preview publication fence must remain preview-only"

  if [[ "$PREVIEW_MODE" == "true" ]]; then
    [[ "$BUNDLE_ID" == com.heyintentive.intentive.preview.* ]] ||
      fail "preview bundle must use the owned preview namespace"
    [[ "$URL_SCHEME" == heyintentive-preview-* ]] ||
      fail "preview URL scheme must use the owned preview namespace"
  else
    [[ "$APP_NAME" == "Intentive" ]] || fail "release app must be named Intentive"
    [[ "$BUNDLE_ID" == "com.heyintentive.intentive" ]] || fail "unexpected stable bundle ID"
    [[ "$URL_SCHEME" == "heyintentive" ]] || fail "unexpected stable URL scheme"
    [[ "$BETA_APP_NAME" == "Intentive Beta" ]] || fail "unexpected Beta app name"
    [[ "$BETA_BUNDLE_ID" == "com.heyintentive.intentive.beta" ]] || fail "unexpected Beta bundle ID"
    [[ "$BETA_URL_SCHEME" == "heyintentive-beta" ]] || fail "unexpected Beta URL scheme"
  fi
}

validate_common_secrets() {
  for name in \
    MACOS_DEVELOPER_ID_P12 \
    MACOS_DEVELOPER_ID_P12_PASSWORD \
    APP_STORE_CONNECT_KEY_IDENTIFIER \
    APP_STORE_CONNECT_PRIVATE_KEY \
    APP_STORE_CONNECT_ISSUER_ID \
    INTENTIVE_FIREBASE_PLIST_BASE64 \
    INTENTIVE_DESKTOP_APP_ENV_BASE64; do
    require_env "$name"
  done
}

validate_release_secrets_and_urls() {
  for name in \
    INTENTIVE_BETA_FIREBASE_PLIST_BASE64 \
    INTENTIVE_SPARKLE_PUBLIC_KEY \
    SPARKLE_PRIVATE_KEY \
    SENTRY_AUTH_TOKEN \
    GH_TOKEN \
    INTENTIVE_PRODUCTION_API_URL \
    INTENTIVE_STABLE_FEED_URL \
    INTENTIVE_BETA_FEED_URL \
    INTENTIVE_MANUAL_DOWNLOAD_URL \
    INTENTIVE_PRODUCT_URL \
    INTENTIVE_TERMS_URL \
    INTENTIVE_PRIVACY_URL \
    INTENTIVE_SUPPORT_URL; do
    require_env "$name"
  done
  for name in \
    INTENTIVE_PRODUCTION_API_URL \
    INTENTIVE_STABLE_FEED_URL \
    INTENTIVE_BETA_FEED_URL \
    INTENTIVE_MANUAL_DOWNLOAD_URL \
    INTENTIVE_PRODUCT_URL \
    INTENTIVE_TERMS_URL \
    INTENTIVE_PRIVACY_URL \
    INTENTIVE_SUPPORT_URL; do
    validate_url "$name"
  done
  [[ "${GITHUB_RELEASES_URL:-}" == "https://github.com/sruj75/knowledge-athlete/releases" ]] ||
    fail "unexpected GitHub releases URL"
}

validate_preview_secrets_and_urls() {
  for name in \
    PREVIEW_SLUG \
    PREVIEW_ID \
    PREVIEW_SOURCE_REF \
    PREVIEW_SOURCE_SHA \
    PREVIEW_BACKEND_ENVIRONMENT \
    OMI_PYTHON_API_URL \
    GCP_DESKTOP_PREVIEW_SERVICE_ACCOUNT_BASE64 \
    DESKTOP_PREVIEW_PUBLISH_KEY \
    INTENTIVE_PREVIEW_BUCKET \
    INTENTIVE_PREVIEW_PUBLIC_ORIGIN \
    INTENTIVE_PREVIEW_REGISTRY_URL; do
    require_env "$name"
  done
  validate_url OMI_PYTHON_API_URL
  validate_url INTENTIVE_PREVIEW_PUBLIC_ORIGIN
  validate_url INTENTIVE_PREVIEW_REGISTRY_URL
  [[ "$PREVIEW_SLUG" =~ ^[a-z][a-z0-9-]{0,47}$ ]] || fail "invalid preview slug"
  [[ "$PREVIEW_SOURCE_REF" == "preview/$PREVIEW_SLUG" ]] || fail "preview ref and slug do not match"
  [[ "$PREVIEW_SOURCE_SHA" =~ ^[0-9a-f]{40}$ ]] || fail "preview source SHA must be complete"
  local expected_id
  expected_id="p$(printf '%s' "$PREVIEW_SLUG" | shasum -a 256 | cut -c1-10)"
  [[ "$PREVIEW_ID" == "$expected_id" ]] || fail "preview ID does not match its slug"
  [[ "$PREVIEW_BACKEND_ENVIRONMENT" == "production" || "$PREVIEW_BACKEND_ENVIRONMENT" == "preview" ]] ||
    fail "unsupported preview backend environment"
  [[ "$INTENTIVE_PREVIEW_BUCKET" == gs://* ]] || fail "preview bucket must be a gs:// URL"
}

validate_source_and_export_state() {
  mkdir -p "$BUILD_DIR"
  touch "$CM_ENV_FILE"
  local version build_number source_sha
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    git fetch --no-tags origin "$PREVIEW_SOURCE_SHA"
    git checkout --detach "$PREVIEW_SOURCE_SHA"
    source_sha="$(git rev-parse HEAD)"
    [[ "$source_sha" == "$PREVIEW_SOURCE_SHA" ]] || fail "preview checkout does not match approved SHA"
    version="0.0.$(printf '%d' "0x${source_sha:0:6}")"
    build_number="$(git show -s --format=%ct "$source_sha")"
    APP_NAME="Intentive Preview - $PREVIEW_SLUG"
    BUNDLE_ID="com.heyintentive.intentive.preview.$PREVIEW_ID"
    URL_SCHEME="heyintentive-preview-$PREVIEW_ID"
    APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
    APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$BINARY_NAME"
  else
    [[ "${CM_TAG:-}" =~ ^v([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)-macos$ ]] ||
      fail "CM_TAG must be exactly v<version>+<build>-macos"
    version="${BASH_REMATCH[1]}"
    build_number="${BASH_REMATCH[2]}"
    source_sha="$(git rev-parse HEAD)"
    [[ "$(git rev-parse "${CM_TAG}^{commit}")" == "$source_sha" ]] ||
      fail "checked out source does not match the immutable release tag"
    if [[ -n "${CM_COMMIT:-}" ]]; then
      [[ "$CM_COMMIT" == "$source_sha" ]] || fail "Codemagic reported a different source SHA"
    fi
    OMI_PYTHON_API_URL="$INTENTIVE_PRODUCTION_API_URL"
  fi

  append_cm_env VERSION "$version"
  append_cm_env BUILD_NUMBER "$build_number"
  append_cm_env SOURCE_SHA "$source_sha"
  append_cm_env APP_NAME "$APP_NAME"
  append_cm_env BUNDLE_ID "$BUNDLE_ID"
  append_cm_env URL_SCHEME "$URL_SCHEME"
  append_cm_env APP_BUNDLE "$APP_BUNDLE"
  append_cm_env APP_EXECUTABLE "$APP_EXECUTABLE"
  append_cm_env OMI_PYTHON_API_URL "$OMI_PYTHON_API_URL"
  append_cm_env DSYM_PATH "$DSYM_PATH"
  append_cm_env DSYM_ARCHIVE "$DSYM_ARCHIVE"
}

validate() {
  validate_common_secrets
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    validate_preview_secrets_and_urls
    APP_NAME="Intentive Preview - $PREVIEW_SLUG"
    BUNDLE_ID="com.heyintentive.intentive.preview.$PREVIEW_ID"
    URL_SCHEME="heyintentive-preview-$PREVIEW_ID"
  else
    validate_release_secrets_and_urls
  fi
  validate_owned_identity
  validate_source_and_export_state
  echo "Owned Codemagic inputs and exact source are valid."
}

import_signing() {
  require_env MACOS_DEVELOPER_ID_P12
  require_env MACOS_DEVELOPER_ID_P12_PASSWORD
  command -v keychain >/dev/null 2>&1 || fail "Codemagic keychain CLI is unavailable"
  local p12_path keychain_path sign_identity
  p12_path="$(mktemp "${TMPDIR:-/tmp}/intentive-developer-id.p12.XXXXXX")"
  trap '[[ -z "${p12_path:-}" ]] || rm -f -- "$p12_path"' EXIT
  chmod 600 "$p12_path"
  printf '%s' "$MACOS_DEVELOPER_ID_P12" | base64 --decode > "$p12_path"
  keychain initialize
  keychain_path="$(keychain get-default)"
  security import "$p12_path" \
    -k "$keychain_path" \
    -P "$MACOS_DEVELOPER_ID_P12_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$keychain_path" >/dev/null 2>&1 || true
  sign_identity="$(security find-identity -v -p codesigning | awk -F\" '/Developer ID Application/ {print $2; exit}')"
  [[ -n "$sign_identity" ]] || fail "Developer ID Application identity was not imported"
  [[ "$sign_identity" == *"($APPLE_TEAM_ID)"* ]] ||
    fail "Developer ID identity is not owned by Apple Team $APPLE_TEAM_ID"
  rm -f -- "$p12_path"
  p12_path=""
  append_cm_env SIGN_IDENTITY "$sign_identity"
  echo "Imported the owned Developer ID identity for Team $APPLE_TEAM_ID."
}

copy_framework() {
  local name="$1"
  local candidate="Desktop/.build/x86_64-apple-macosx/release/$name.framework"
  if [[ ! -d "$candidate" ]]; then
    candidate="Desktop/.build/arm64-apple-macosx/release/$name.framework"
  fi
  [[ -d "$candidate" ]] || fail "$name.framework is missing from both release build products"
  ditto "$candidate" "$APP_BUNDLE/Contents/Frameworks/$name.framework"
}

prepare_link_time_libwebp() {
  "$SCRIPT_DIR/prepare-release-libwebp.sh" --verify-only
  command -v brew >/dev/null 2>&1 || fail "Homebrew is required for CWebP headers and pkg-config"
  brew list webp >/dev/null 2>&1 || brew install webp
  local lib_dir dylib expected actual
  lib_dir="$(brew --prefix webp)/lib"
  for dylib in libwebp.7.dylib libsharpyuv.0.dylib; do
    [[ -e "$lib_dir/$dylib" ]] || fail "Homebrew link target is missing: $lib_dir/$dylib"
    chmod u+w "$lib_dir/$dylib" 2>/dev/null || true
    cp -f "$MACOS_DIR/vendor/libwebp/$dylib" "$lib_dir/$dylib"
    expected="$(shasum -a 256 "$MACOS_DIR/vendor/libwebp/$dylib" | awk '{print $1}')"
    actual="$(shasum -a 256 "$lib_dir/$dylib" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || fail "link-time $dylib is not the pinned vendored binary"
  done
}

validate_packaged_firebase_plist() {
  local plist="$1"
  local expected_bundle="$2"
  local project_id client_bundle
  project_id="$(/usr/libexec/PlistBuddy -c 'Print :PROJECT_ID' "$plist" 2>/dev/null || true)"
  client_bundle="$(/usr/libexec/PlistBuddy -c 'Print :BUNDLE_ID' "$plist" 2>/dev/null || true)"
  [[ "$project_id" == "knowledge-athlete" ]] || fail "Firebase plist does not belong to knowledge-athlete"
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    plist_set "$plist" BUNDLE_ID string "$expected_bundle"
  else
    [[ "$client_bundle" == "$expected_bundle" ]] ||
      fail "Firebase plist bundle ID '$client_bundle' does not match '$expected_bundle'"
  fi
}

build() {
  require_env VERSION
  require_env BUILD_NUMBER
  require_env SOURCE_SHA
  require_env INTENTIVE_FIREBASE_PLIST_BASE64
  require_env INTENTIVE_DESKTOP_APP_ENV_BASE64
  mkdir -p "$BUILD_DIR"
  case "$APP_BUNDLE" in
    "$BUILD_DIR/Intentive.app"|"$BUILD_DIR/Intentive Preview - "*.app) rm -rf -- "$APP_BUNDLE" ;;
    *) fail "refusing to replace unexpected app path: $APP_BUNDLE" ;;
  esac

  "$SCRIPT_DIR/prepare-agent-runtime.sh" --universal-node
  prepare_link_time_libwebp
  unset TOOLCHAINS
  xcrun swift package resolve --package-path Desktop
  xcrun swift build -c release --package-path Desktop --triple arm64-apple-macosx
  xcrun swift build -c release --package-path Desktop --triple x86_64-apple-macosx

  local arm_binary x86_binary resource_bundle app_plist env_file firebase_plist
  arm_binary="Desktop/.build/arm64-apple-macosx/release/$BINARY_NAME"
  x86_binary="Desktop/.build/x86_64-apple-macosx/release/$BINARY_NAME"
  [[ -f "$arm_binary" && -f "$x86_binary" ]] || fail "both release executable slices are required"
  mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources" "$APP_BUNDLE/Contents/Frameworks"
  lipo -create "$arm_binary" "$x86_binary" -output "$APP_EXECUTABLE"
  [[ "$(lipo -archs "$APP_EXECUTABLE")" == *arm64* && "$(lipo -archs "$APP_EXECUTABLE")" == *x86_64* ]] ||
    fail "release executable is not universal"
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_EXECUTABLE" 2>/dev/null || true

  copy_framework Sparkle
  copy_framework Sentry
  copy_framework onnxruntime

  app_plist="$APP_BUNDLE/Contents/Info.plist"
  cp Desktop/Info.plist "$app_plist"
  plist_set "$app_plist" CFBundleExecutable string "$BINARY_NAME"
  plist_set "$app_plist" CFBundleIdentifier string "$BUNDLE_ID"
  plist_set "$app_plist" CFBundleName string "$APP_NAME"
  plist_set "$app_plist" CFBundleDisplayName string "$APP_NAME"
  plist_set "$app_plist" CFBundleShortVersionString string "$VERSION"
  plist_set "$app_plist" CFBundleVersion string "$BUILD_NUMBER"
  plist_set "$app_plist" CFBundleURLTypes:0:CFBundleURLSchemes:0 string "$URL_SCHEME"
  plist_set "$app_plist" LSMinimumSystemVersion string "14.0"
  plist_set "$app_plist" IntentiveProductionAPIURL string "$OMI_PYTHON_API_URL"
  plist_set "$app_plist" IntentiveReleasesURL string "$GITHUB_RELEASES_URL"

  if [[ "$PREVIEW_MODE" == "true" ]]; then
    plist_set "$app_plist" OMIExternalPreview bool true
    plist_set "$app_plist" OMIExternalPreviewBackend string "$PREVIEW_BACKEND_ENVIRONMENT"
    /usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "$app_plist" 2>/dev/null || true
    plist_set "$app_plist" SUEnableAutomaticChecks bool false
    plist_set "$app_plist" SUAutomaticallyUpdate bool false
  else
    plist_set "$app_plist" OMIExternalPreview bool false
    plist_set "$app_plist" OMIExternalPreviewBackend string production
    plist_set "$app_plist" SUFeedURL string "$INTENTIVE_STABLE_FEED_URL"
    plist_set "$app_plist" SUPublicEDKey string "$INTENTIVE_SPARKLE_PUBLIC_KEY"
    plist_set "$app_plist" SUEnableAutomaticChecks bool true
    plist_set "$app_plist" SUAutomaticallyUpdate bool false
    plist_set "$app_plist" IntentiveManualDownloadURL string "$INTENTIVE_MANUAL_DOWNLOAD_URL"
    plist_set "$app_plist" IntentiveProductURL string "$INTENTIVE_PRODUCT_URL"
    plist_set "$app_plist" IntentiveTermsURL string "$INTENTIVE_TERMS_URL"
    plist_set "$app_plist" IntentivePrivacyURL string "$INTENTIVE_PRIVACY_URL"
    plist_set "$app_plist" IntentiveSupportURL string "$INTENTIVE_SUPPORT_URL"
  fi
  printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

  firebase_plist="$APP_BUNDLE/Contents/Resources/GoogleService-Info.plist"
  printf '%s' "$INTENTIVE_FIREBASE_PLIST_BASE64" | base64 --decode > "$firebase_plist"
  validate_packaged_firebase_plist "$firebase_plist" "$BUNDLE_ID"
  env_file="$APP_BUNDLE/Contents/Resources/.env"
  printf '%s' "$INTENTIVE_DESKTOP_APP_ENV_BASE64" | base64 --decode > "$env_file"
  if grep -Eq '^(OMI_PYTHON_API_URL|OMI_DESKTOP_API_URL)=' "$env_file"; then
    fail "protected desktop app env must contain secrets only, not backend URL overrides"
  fi
  grep -q '^FIREBASE_API_KEY=' "$env_file" || fail "desktop app env is missing FIREBASE_API_KEY"
  printf 'OMI_PYTHON_API_URL=%s\n' "$OMI_PYTHON_API_URL" >> "$env_file"

  resource_bundle="Desktop/.build/x86_64-apple-macosx/release/Omi Computer_Omi Computer.bundle"
  [[ -d "$resource_bundle" ]] || resource_bundle="Desktop/.build/arm64-apple-macosx/release/Omi Computer_Omi Computer.bundle"
  [[ -d "$resource_bundle" ]] || fail "SwiftPM resource bundle is missing"
  local packaged_resource_bundle
  packaged_resource_bundle="$APP_BUNDLE/Contents/Resources/$(basename "$resource_bundle")"
  ditto "$resource_bundle" "$packaged_resource_bundle"
  # SwiftPM still compiles the inherited development-era production plist into
  # its resource bundle. The app reads the owned main-bundle plist above; remove
  # every nested copy so an Omi Firebase credential can never ship as dead data.
  find "$packaged_resource_bundle" -type f -name 'GoogleService-Info.plist' -delete
  [[ -z "$(find "$packaged_resource_bundle" -type f -name 'GoogleService-Info.plist' -print -quit)" ]] ||
    fail "nested inherited Firebase plist remained in the packaged resource bundle"
  [[ -f omi_icon.icns ]] && cp omi_icon.icns "$APP_BUNDLE/Contents/Resources/OmiIcon.icns"

  [[ -d agent/dist && -d .harness/agent-runtime/agent-node_modules ]] || fail "prepared agent runtime is missing"
  mkdir -p "$APP_BUNDLE/Contents/Resources/agent"
  ditto agent/dist "$APP_BUNDLE/Contents/Resources/agent/dist"
  cp agent/package.json "$APP_BUNDLE/Contents/Resources/agent/"
  ditto .harness/agent-runtime/agent-node_modules "$APP_BUNDLE/Contents/Resources/agent/node_modules"
  mkdir -p "$APP_BUNDLE/Contents/Resources/agent/src/runtime"
  cp agent/src/runtime/control-tool-manifest.ts agent/src/runtime/omi-tool-manifest.ts \
    "$APP_BUNDLE/Contents/Resources/agent/src/runtime/"

  [[ -d pi-mono-extension && -d .harness/agent-runtime/pi-mono-extension-node_modules ]] ||
    fail "prepared pi-mono extension runtime is missing"
  mkdir -p "$APP_BUNDLE/Contents/Resources/pi-mono-extension"
  cp pi-mono-extension/index.ts pi-mono-extension/package.json pi-mono-extension/package-lock.json \
    "$APP_BUNDLE/Contents/Resources/pi-mono-extension/"
  ditto .harness/agent-runtime/pi-mono-extension-node_modules \
    "$APP_BUNDLE/Contents/Resources/pi-mono-extension/node_modules"

  echo "Built exact universal source $SOURCE_SHA as $APP_BUNDLE."
}

sign_resource_macho_files() {
  local candidate
  while IFS= read -r -d '' candidate; do
    file "$candidate" 2>/dev/null | grep -q 'Mach-O' || continue
    chmod u+w "$candidate" 2>/dev/null || true
    if [[ "$(basename "$candidate")" == "node" ]]; then
      codesign --force --options runtime --timestamp \
        --entitlements Desktop/Node.entitlements \
        --sign "$SIGN_IDENTITY" "$candidate"
    else
      codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$candidate"
    fi
  done < <(find "$APP_BUNDLE/Contents/Resources" -type f -print0)
}

sign_frameworks() {
  local sparkle="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
  local nested
  for nested in \
    "$sparkle/Versions/B/XPCServices/Downloader.xpc" \
    "$sparkle/Versions/B/XPCServices/Installer.xpc" \
    "$sparkle/Versions/B/Autoupdate" \
    "$sparkle/Versions/B/Updater.app"; do
    [[ -e "$nested" ]] || fail "required Sparkle nested component is missing: $nested"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$nested"
  done
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$sparkle"
  for nested in Sentry onnxruntime; do
    [[ -d "$APP_BUNDLE/Contents/Frameworks/$nested.framework" ]] ||
      fail "$nested.framework is missing from the app"
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" \
      "$APP_BUNDLE/Contents/Frameworks/$nested.framework"
  done
}

sign_nested() {
  require_env SIGN_IDENTITY
  [[ -f "$APP_EXECUTABLE" ]] || fail "release executable is missing"
  chmod -R u+w "$APP_BUNDLE"
  xattr -cr "$APP_BUNDLE"
  "$SCRIPT_DIR/prepare-desktop-bundle-native-deps.sh" "$APP_BUNDLE"
  "$SCRIPT_DIR/prepare-release-libwebp.sh" \
    --destination "$APP_BUNDLE/Contents/Frameworks" \
    --app-executable "$APP_EXECUTABLE" \
    --signing-identity "$SIGN_IDENTITY"
  sign_resource_macho_files
  sign_frameworks
  "$SCRIPT_DIR/prepare-release-libwebp.sh" \
    --destination "$APP_BUNDLE/Contents/Frameworks" \
    --app-executable "$APP_EXECUTABLE" \
    --verify-prepared \
    --expected-team-id "$APPLE_TEAM_ID"
  "$SCRIPT_DIR/publish-desktop-debug-symbols.sh" generate \
    --binary "$APP_EXECUTABLE" \
    --dsym "$DSYM_PATH" \
    --archive "$DSYM_ARCHIVE"
  echo "Prepared and signed all nested release code."
}

sign_outer() {
  require_env SIGN_IDENTITY
  [[ -f "$APP_EXECUTABLE" ]] || fail "release executable is missing"
  codesign --force --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" \
    --entitlements Desktop/Omi-Release.entitlements \
    "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
  local team_id
  team_id="$(codesign -dv "$APP_BUNDLE" 2>&1 | awk -F= '/^TeamIdentifier=/{print $2; exit}')"
  [[ "$team_id" == "$APPLE_TEAM_ID" ]] || fail "signed app Team ID mismatch: $team_id"
  "$SCRIPT_DIR/audit-desktop-bundle-deps.sh" "$APP_BUNDLE"
  echo "Signed the outer Intentive bundle with hardened runtime."
}

notary_key_path=""
notary_cleanup() {
  if [[ -n "$notary_key_path" ]]; then
    rm -f -- "$notary_key_path"
  fi
}

prepare_notary_key() {
  [[ -n "$notary_key_path" ]] && return
  require_env APP_STORE_CONNECT_PRIVATE_KEY
  notary_key_path="$(mktemp "${TMPDIR:-/tmp}/intentive-notary-key.p8.XXXXXX")"
  chmod 600 "$notary_key_path"
  printf '%b' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$notary_key_path"
}

submit_notary_artifact() {
  local submission="$1"
  prepare_notary_key
  local result status submission_id
  result="$(xcrun notarytool submit "$submission" \
    --key "$notary_key_path" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait \
    --output-format json)"
  status="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
  submission_id="$(printf '%s' "$result" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))')"
  if [[ "$status" != "Accepted" ]]; then
    [[ -z "$submission_id" ]] || xcrun notarytool log "$submission_id" \
      --key "$notary_key_path" \
      --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
      --issuer "$APP_STORE_CONNECT_ISSUER_ID" || true
    fail "Apple notarization rejected $submission"
  fi
}

notarize_app() {
  local app="$1"
  local zip_path
  zip_path="$BUILD_DIR/notary-$(basename "$app" .app).zip"
  ditto -c -k --keepParent "$app" "$zip_path"
  submit_notary_artifact "$zip_path"
  rm -f -- "$zip_path"
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
}

create_and_notarize_dmg() {
  local app="$1"
  local volume_name="$2"
  local output="$3"
  local staging
  staging="$(mktemp -d "${TMPDIR:-/tmp}/intentive-dmg-staging.XXXXXX")"
  ditto "$app" "$staging/$(basename "$app")"
  pip3 install --break-system-packages "dmgbuild==${DMGBUILD_VERSION:?}" >/dev/null
  dmgbuild -s "$MACOS_DIR/dmg-assets/dmgbuild_settings.py" \
    -D app_path="$staging/$(basename "$app")" \
    -D app_name="$volume_name" \
    -D assets_dir="$MACOS_DIR/dmg-assets" \
    "$volume_name" "$output"
  case "$staging" in
    "${TMPDIR:-/tmp}/intentive-dmg-staging."*) rm -rf -- "$staging" ;;
    *) fail "refusing unexpected DMG staging cleanup: $staging" ;;
  esac
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$output"
  submit_notary_artifact "$output"
  xcrun stapler staple "$output"
  xcrun stapler validate "$output"
}

notarize() {
  require_env SIGN_IDENTITY
  require_env APP_STORE_CONNECT_KEY_IDENTIFIER
  require_env APP_STORE_CONNECT_PRIVATE_KEY
  require_env APP_STORE_CONNECT_ISSUER_ID
  trap notary_cleanup EXIT
  notarize_app "$APP_BUNDLE"
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    create_and_notarize_dmg "$APP_BUNDLE" "$APP_NAME" "$PREVIEW_DMG"
  else
    create_and_notarize_dmg "$APP_BUNDLE" "Intentive" "$STABLE_DMG"
    local beta_firebase_plist="$BUILD_DIR/GoogleService-Info-Beta.plist"
    printf '%s' "$INTENTIVE_BETA_FIREBASE_PLIST_BASE64" | base64 --decode > "$beta_firebase_plist"
    "$SCRIPT_DIR/create-intentive-beta-variant.sh" \
      --source-app "$APP_BUNDLE" \
      --build-dir "$BUILD_DIR" \
      --beta-feed-url "$INTENTIVE_BETA_FEED_URL" \
      --beta-firebase-plist "$beta_firebase_plist" \
      --sparkle-zip-out "$BETA_ZIP" \
      --dmg-out "$BETA_DMG" \
      --cm-env "$CM_ENV_FILE"
  fi
  echo "Notarization and stapling completed."
}

sparkle() {
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    echo "Preview artifacts are isolated from Sparkle."
    return
  fi
  require_env SPARKLE_PRIVATE_KEY
  local sparkle_bin signature
  sparkle_bin="Desktop/.build/artifacts/sparkle/Sparkle/bin/sign_update"
  [[ -x "$sparkle_bin" ]] || fail "Sparkle sign_update is missing"
  ditto -c -k --keepParent "$APP_BUNDLE" "$STABLE_ZIP"
  signature="$(printf '%s' "$SPARKLE_PRIVATE_KEY" | \
    "$sparkle_bin" "$STABLE_ZIP" --ed-key-file - 2>/dev/null | \
    sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  [[ -n "$signature" ]] || fail "could not sign the stable Sparkle archive"
  append_cm_env ED_SIGNATURE "$signature"
  [[ -s "$BETA_ZIP" ]] || fail "Beta Sparkle archive is missing"
  grep -q '^BETA_ED_SIGNATURE=' "$CM_ENV_FILE" || fail "Beta Sparkle signature is missing"
  echo "Created and signed stable and Beta Sparkle archives."
}

symbols() {
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    echo "Preview symbol publication is intentionally isolated from the release project."
    return
  fi
  require_env SENTRY_AUTH_TOKEN
  "$SCRIPT_DIR/publish-desktop-debug-symbols.sh" upload \
    --binary "$APP_EXECUTABLE" \
    --dsym "$DSYM_PATH"
}

smoke() {
  require_env SOURCE_SHA
  export OMI_SIGNED_ARTIFACT_SMOKE_TEAM_ID="$APPLE_TEAM_ID"
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    "$SCRIPT_DIR/smoke-signed-desktop-artifact.sh" \
      --app "$APP_BUNDLE" \
      --dmg "$PREVIEW_DMG" \
      --source-sha "$SOURCE_SHA" \
      --expected-channel preview \
      --expected-bundle-id "$BUNDLE_ID" \
      --expected-url-scheme "$URL_SCHEME" \
      --expected-python-api-url "$OMI_PYTHON_API_URL" \
      --preview \
      --result-json "$BUILD_DIR/desktop-smoke-result.json"
    return
  fi

  OMI_SIGNED_ARTIFACT_SMOKE_ALLOW_PRODUCTION_LAUNCH=1 \
    "$SCRIPT_DIR/smoke-signed-desktop-artifact.sh" \
      --app "$APP_BUNDLE" \
      --zip "$STABLE_ZIP" \
      --dmg "$STABLE_DMG" \
      --tag "$CM_TAG" \
      --source-sha "$SOURCE_SHA" \
      --expected-channel beta \
      --expected-bundle-id "com.heyintentive.intentive" \
      --expected-url-scheme heyintentive \
      --expected-feed-url "$INTENTIVE_STABLE_FEED_URL" \
      --expected-manual-download-url "$INTENTIVE_MANUAL_DOWNLOAD_URL" \
      --expected-releases-url "$GITHUB_RELEASES_URL" \
      --expected-python-api-url "$INTENTIVE_PRODUCTION_API_URL" \
      --launch \
      --auth-storage-canary \
      --timeout 90 \
      --result-json "$BUILD_DIR/desktop-smoke-result.json"

  OMI_SIGNED_ARTIFACT_SMOKE_ALLOW_PRODUCTION_LAUNCH=1 \
    "$SCRIPT_DIR/smoke-signed-desktop-artifact.sh" \
      --app "$BUILD_DIR/$BETA_APP_NAME.app" \
      --zip "$BETA_ZIP" \
      --dmg "$BETA_DMG" \
      --tag "$CM_TAG" \
      --source-sha "$SOURCE_SHA" \
      --expected-channel beta \
      --expected-bundle-id "$BETA_BUNDLE_ID" \
      --expected-url-scheme "$BETA_URL_SCHEME" \
      --expected-feed-url "$INTENTIVE_BETA_FEED_URL" \
      --expected-manual-download-url "$INTENTIVE_MANUAL_DOWNLOAD_URL" \
      --expected-releases-url "$GITHUB_RELEASES_URL" \
      --expected-python-api-url "$INTENTIVE_PRODUCTION_API_URL" \
      --launch \
      --auth-storage-canary \
      --timeout 90 \
      --result-json "$BUILD_DIR/desktop-smoke-result-beta.json"
}

publish_release() {
  require_env GH_TOKEN
  require_env ED_SIGNATURE
  require_env BETA_ED_SIGNATURE
  for artifact in \
    "$STABLE_ZIP" \
    "$STABLE_DMG" \
    "$BETA_ZIP" \
    "$BETA_DMG" \
    "$DSYM_ARCHIVE" \
    "$BUILD_DIR/desktop-smoke-result.json" \
    "$BUILD_DIR/desktop-smoke-result-beta.json"; do
    [[ -s "$artifact" ]] || fail "publication artifact is missing or empty: $artifact"
  done
  if gh release view "$CM_TAG" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    fail "immutable candidate $CM_TAG already exists; refusing to replace its artifacts"
  fi

  local changelog release_notes
  changelog="$(python3 "$REPO_ROOT/.github/scripts/desktop-changelog.py" latest-release --format markdown)"
  release_notes=$(cat <<EOF
## Intentive ${VERSION} candidate

### What's new
${changelog}

<!-- KEY_VALUE_START
isLive: false
channel: candidate
sourceSha: ${SOURCE_SHA}
edSignature: ${ED_SIGNATURE}
betaEdSignature: ${BETA_ED_SIGNATURE}
KEY_VALUE_END -->
EOF
)
  gh release create "$CM_TAG" \
    --repo "$GITHUB_REPOSITORY" \
    --verify-tag \
    --target "$SOURCE_SHA" \
    --title "Intentive ${VERSION} candidate" \
    --notes "$release_notes" \
    "$STABLE_ZIP" \
    "$STABLE_DMG" \
    "$BETA_ZIP" \
    "$BETA_DMG" \
    "$DSYM_ARCHIVE" \
    "$BUILD_DIR/desktop-smoke-result.json" \
    "$BUILD_DIR/desktop-smoke-result-beta.json"
  echo "Published immutable non-live candidate $CM_TAG."
}

preview_key_path=""
preview_key_cleanup() {
  [[ -z "$preview_key_path" ]] || rm -f -- "$preview_key_path"
}

publish_preview() {
  require_env GCP_DESKTOP_PREVIEW_SERVICE_ACCOUNT_BASE64
  require_env DESKTOP_PREVIEW_PUBLISH_KEY
  [[ -s "$PREVIEW_DMG" && -s "$BUILD_DIR/desktop-smoke-result.json" ]] ||
    fail "preview artifact or signed-smoke evidence is missing"
  [[ "$INTENTIVE_PREVIEW_BUCKET" != *omi* && "$INTENTIVE_PREVIEW_BUCKET" != *basedhardware* ]] ||
    fail "preview bucket uses an inherited provider identity"

  local object_root dmg_object smoke_object dmg_sha public_dmg_url payload
  preview_key_path="$(mktemp "${TMPDIR:-/tmp}/intentive-preview-gcp.json.XXXXXX")"
  trap preview_key_cleanup EXIT
  chmod 600 "$preview_key_path"
  printf '%s' "$GCP_DESKTOP_PREVIEW_SERVICE_ACCOUNT_BASE64" | base64 --decode > "$preview_key_path"
  gcloud auth activate-service-account --key-file="$preview_key_path" >/dev/null
  rm -f -- "$preview_key_path"
  preview_key_path=""

  object_root="${INTENTIVE_PREVIEW_BUCKET%/}/previews/$PREVIEW_SLUG/$PREVIEW_SOURCE_SHA"
  dmg_object="$object_root/Intentive-Preview.dmg"
  smoke_object="$object_root/desktop-smoke-result.json"
  dmg_sha="$(shasum -a 256 "$PREVIEW_DMG" | awk '{print $1}')"
  publish_immutable_preview_object "$PREVIEW_DMG" "$dmg_object"
  publish_immutable_preview_object "$BUILD_DIR/desktop-smoke-result.json" "$smoke_object"

  public_dmg_url="${INTENTIVE_PREVIEW_PUBLIC_ORIGIN%/}/previews/$PREVIEW_SLUG/$PREVIEW_SOURCE_SHA/Intentive-Preview.dmg"
  payload="$(jq -n \
    --arg slug "$PREVIEW_SLUG" \
    --arg source_sha "$PREVIEW_SOURCE_SHA" \
    --arg dmg_url "$public_dmg_url" \
    --arg dmg_sha256 "$dmg_sha" \
    --arg app_name "$APP_NAME" \
    --arg bundle_id "$BUNDLE_ID" \
    --arg url_scheme "$URL_SCHEME" \
    --arg built_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg backend_url "$OMI_PYTHON_API_URL" \
    '{slug: $slug, source_sha: $source_sha, dmg_url: $dmg_url, dmg_sha256: $dmg_sha256, app_name: $app_name, bundle_id: $bundle_id, url_scheme: $url_scheme, built_at: $built_at, notarization: "stapled", backend_url: $backend_url}')"
  curl --fail-with-body --silent --show-error \
    --retry 3 \
    -H 'Content-Type: application/json' \
    -H "secret-key: $DESKTOP_PREVIEW_PUBLISH_KEY" \
    --data "$payload" \
    "${INTENTIVE_PREVIEW_REGISTRY_URL%/}/v2/desktop/previews/publish"
  echo "Published immutable preview $PREVIEW_SLUG at exact source $PREVIEW_SOURCE_SHA."
}

publish_immutable_preview_object() {
  local source="$1"
  local object="$2"
  local expected_sha existing_path
  expected_sha="$(shasum -a 256 "$source" | awk '{print $1}')"
  existing_path="$(mktemp "${TMPDIR:-/tmp}/intentive-preview-existing.XXXXXX")"

  if gcloud storage cp "$object" "$existing_path" >/dev/null 2>&1; then
    if [[ "$(shasum -a 256 "$existing_path" | awk '{print $1}')" != "$expected_sha" ]]; then
      rm -f -- "$existing_path"
      fail "immutable preview object already exists with a different digest: $object"
    fi
    rm -f -- "$existing_path"
    return
  fi

  if gcloud storage cp --if-generation-match=0 \
    --cache-control='public,max-age=31536000,immutable' \
    "$source" "$object"; then
    rm -f -- "$existing_path"
    return
  fi

  # Another retry may have won the create-only race. Accept only the exact
  # bytes this run intended to publish; any different object remains fatal.
  gcloud storage cp "$object" "$existing_path" >/dev/null 2>&1 || {
    rm -f -- "$existing_path"
    fail "immutable preview object could not be created or verified: $object"
  }
  if [[ "$(shasum -a 256 "$existing_path" | awk '{print $1}')" != "$expected_sha" ]]; then
    rm -f -- "$existing_path"
    fail "immutable preview object raced with a different digest: $object"
  fi
  rm -f -- "$existing_path"
}

publish() {
  if [[ "$PREVIEW_MODE" == "true" ]]; then
    publish_preview
  else
    publish_release
  fi
}

usage() {
  cat >&2 <<'EOF'
Usage: scripts/codemagic-release.sh <phase>

Phases: validate, import-signing, build, sign-nested, sign-outer,
        notarize, sparkle, symbols, smoke, publish
EOF
  exit 2
}

phase="${1:-}"
case "$phase" in
  validate) validate ;;
  import-signing) import_signing ;;
  build) build ;;
  sign-nested) sign_nested ;;
  sign-outer) sign_outer ;;
  notarize) notarize ;;
  sparkle) sparkle ;;
  symbols) symbols ;;
  smoke) smoke ;;
  publish) publish ;;
  *) usage ;;
esac
