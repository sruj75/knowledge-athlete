#!/usr/bin/env bash
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$MACOS_DIR/scripts/create-intentive-beta-variant.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/heyintentive-beta-variant-test.XXXXXX")"

cleanup() {
  case "$TMP_ROOT" in
    "${TMPDIR:-/tmp}/heyintentive-beta-variant-test."*) rm -rf -- "$TMP_ROOT" ;;
    *) echo "Refusing unsafe cleanup path: $TMP_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

make_source_app() {
  local app="$1"
  local bundle_id="$2"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$app/Contents/Info.plist"
  plutil -insert CFBundleExecutable -string "Omi Computer" "$app/Contents/Info.plist"
  plutil -insert CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
  plutil -insert CFBundleName -string Intentive "$app/Contents/Info.plist"
  plutil -insert CFBundleDisplayName -string Intentive "$app/Contents/Info.plist"
  plutil -insert CFBundleURLTypes -xml '<array><dict><key>CFBundleURLSchemes</key><array><string>heyintentive</string></array></dict></array>' "$app/Contents/Info.plist"
  plutil -insert SUFeedURL -string "https://updates.heyintentive.com/v2/desktop/appcast.xml" "$app/Contents/Info.plist"
  plutil -insert SUPublicEDKey -string "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" "$app/Contents/Info.plist"
  plutil -insert IntentiveManualDownloadURL -string "https://updates.heyintentive.com/v2/desktop/download/latest" "$app/Contents/Info.plist"
  plutil -insert IntentiveReleasesURL -string "https://github.com/sruj75/knowledge-athlete/releases" "$app/Contents/Info.plist"
  : >"$app/Contents/MacOS/Omi Computer"
  chmod +x "$app/Contents/MacOS/Omi Computer"
}

make_executable() {
  local path="$1"
  shift
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' "$@"
  } >"$path"
  chmod +x "$path"
}

[[ -x "$SCRIPT" ]] || fail "Intentive Beta packaging script must be executable"

source_app="$TMP_ROOT/Intentive.app"
make_source_app "$source_app" com.heyintentive.intentive

mock_bin="$TMP_ROOT/mock-bin"
sparkle_bin="$TMP_ROOT/sparkle-bin"
mkdir -p "$mock_bin" "$sparkle_bin"
make_executable "$mock_bin/ditto" \
  'if [[ "${1:-}" == "-c" ]]; then : > "${@: -1}"; else cp -R "$1" "$2"; fi'
make_executable "$mock_bin/codesign" 'exit 0'
make_executable "$mock_bin/pip3" 'exit 0'
make_executable "$mock_bin/xcrun" \
  'if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then printf "%s\n" "{\"status\":\"Accepted\",\"id\":\"fixture\"}"; fi'
make_executable "$mock_bin/dmgbuild" ': > "${@: -1}"'
make_executable "$sparkle_bin/sign_update" \
  'printf "%s\n" "sparkle:edSignature=\"fixture-signature\""'

common_env=(
  "PATH=$mock_bin:$PATH"
  "SIGN_IDENTITY=Developer ID Application: Fixture (TESTTEAM01)"
  "APP_STORE_CONNECT_KEY_IDENTIFIER=FIXTUREKEY"
  "APP_STORE_CONNECT_PRIVATE_KEY=fixture-private-key"
  "APP_STORE_CONNECT_ISSUER_ID=fixture-issuer"
  "SPARKLE_PRIVATE_KEY=fixture-sparkle-private-key"
  "DMGBUILD_VERSION=1.0"
  "INTENTIVE_SPARKLE_BIN=$sparkle_bin"
)

build_dir="$TMP_ROOT/build"
cm_env="$TMP_ROOT/cm-env"
env "${common_env[@]}" "$SCRIPT" \
  --source-app "$source_app" \
  --build-dir "$build_dir" \
  --beta-feed-url "https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta" \
  --sparkle-zip-out "$TMP_ROOT/Intentive.Beta.zip" \
  --dmg-out "$TMP_ROOT/intentive-beta.dmg" \
  --cm-env "$cm_env" >/dev/null

beta_plist="$build_dir/Intentive Beta.app/Contents/Info.plist"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$beta_plist")" == "com.heyintentive.intentive.beta" ]] \
  || fail "Beta bundle ID was not re-owned"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' "$beta_plist")" == "heyintentive-beta" ]] \
  || fail "Beta URL scheme was not re-owned"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$beta_plist")" == "https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta" ]] \
  || fail "Beta feed was not stamped from the explicit owned input"
[[ -f "$TMP_ROOT/Intentive.Beta.zip" && -f "$TMP_ROOT/intentive-beta.dmg" ]] \
  || fail "Beta artifacts were not produced"
grep -Fxq 'BETA_ED_SIGNATURE=fixture-signature' "$cm_env" \
  || fail "Beta Sparkle signature was not exported"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$source_app/Contents/Info.plist")" == "com.heyintentive.intentive" ]] \
  || fail "stable source identity was mutated"

if env "${common_env[@]}" "$SCRIPT" \
  --source-app "$source_app" \
  --build-dir "$TMP_ROOT/rejected-build" \
  --beta-feed-url "https://api.omi.me/v2/desktop/appcast.xml?identity=beta" \
  --sparkle-zip-out "$TMP_ROOT/rejected.zip" \
  --dmg-out "$TMP_ROOT/rejected.dmg" >/dev/null 2>"$TMP_ROOT/rejected.err"; then
  fail "inherited Omi Beta feed unexpectedly passed"
fi
grep -q 'inherited Omi beta feeds are forbidden' "$TMP_ROOT/rejected.err" \
  || fail "inherited feed rejection was not explicit"
[[ ! -e "$TMP_ROOT/rejected-build/Intentive Beta.app" ]] \
  || fail "rejected feed mutated the Beta output"

foreign_app="$TMP_ROOT/Foreign.app"
make_source_app "$foreign_app" com.omi.computer-macos
if env "${common_env[@]}" "$SCRIPT" \
  --source-app "$foreign_app" \
  --build-dir "$TMP_ROOT/foreign-build" \
  --beta-feed-url "https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta" \
  --sparkle-zip-out "$TMP_ROOT/foreign.zip" \
  --dmg-out "$TMP_ROOT/foreign.dmg" >/dev/null 2>"$TMP_ROOT/foreign.err"; then
  fail "foreign stable source identity unexpectedly passed"
fi
grep -q 'source app must use stable Intentive identity' "$TMP_ROOT/foreign.err" \
  || fail "foreign source rejection was not explicit"

echo "PASS: Intentive Beta packaging identity and provider inputs"
