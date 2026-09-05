#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SMOKE="$MACOS_DIR/scripts/smoke-signed-desktop-artifact.sh"

export OMI_SIGNED_ARTIFACT_SMOKE_TEAM_ID="TESTTEAM01"
export OMI_SIGNED_ARTIFACT_SMOKE_PYTHON_API_URL="https://api.heyintentive.com"
export OMI_SIGNED_ARTIFACT_SMOKE_FEED_URL="https://updates.heyintentive.com/v2/desktop/appcast.xml"
export OMI_SIGNED_ARTIFACT_SMOKE_MANUAL_DOWNLOAD_URL="https://updates.heyintentive.com/v2/desktop/download/latest"
export OMI_SIGNED_ARTIFACT_SMOKE_PRODUCT_URL="https://heyintentive.com"
export OMI_SIGNED_ARTIFACT_SMOKE_TERMS_URL="https://heyintentive.com/terms"
export OMI_SIGNED_ARTIFACT_SMOKE_PRIVACY_URL="https://heyintentive.com/privacy"
export OMI_SIGNED_ARTIFACT_SMOKE_SUPPORT_URL="https://heyintentive.com/support"
export OMI_SIGNED_ARTIFACT_SMOKE_POSTHOG_PROJECT_TOKEN="fixture-posthog-project-token"
export OMI_SIGNED_ARTIFACT_SMOKE_POSTHOG_HOST="https://us.i.posthog.com"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

TMP_ROOTS=()
cleanup() {
  for path in "${TMP_ROOTS[@]:-}"; do
    [[ -n "$path" ]] && rm -rf "$path"
  done
}
trap cleanup EXIT

[[ -x "$SMOKE" ]] || fail "signed artifact smoke script must be executable"

if ! "$SMOKE" --help >/tmp/omi-smoke-help.out; then
  fail "--help should succeed"
fi

python3 - "$SMOKE" <<'PY'
import ast
import re
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_text(encoding="utf-8")
match = re.search(r're\.fullmatch\((r"[^"]+")\s*, marker\)', source)
if match is None:
    raise SystemExit("notification callback marker parser is missing")
pattern = ast.literal_eval(match.group(1))
if re.fullmatch(pattern, "main_actor=true authorization_status=0") is None:
    raise SystemExit("notification callback marker parser must accept a numeric authorization status")
PY

for required in \
  "Launch + identity" \
  "Auth persistence" \
  "Signed Keychain canary" \
  "Backend routing" \
  "Sparkle/update metadata" \
  "External-preview isolation" \
  "Native helper/runtime bundle integrity" \
  "Minimal chat path" \
  "Recording permission surface sanity" \
  "Local storage/database"; do
  grep -q "$required" /tmp/omi-smoke-help.out || fail "help is missing smoke path: $required"
done

if "$SMOKE" --tag "bad-tag" >/tmp/omi-smoke-invalid.out 2>/tmp/omi-smoke-invalid.err; then
  fail "missing app should fail"
fi
grep -q -- "--app or --zip is required" /tmp/omi-smoke-invalid.err || fail "missing app failure should be explicit"

if "$SMOKE" --app --zip file.zip >/tmp/omi-smoke-missing-value.out 2>/tmp/omi-smoke-missing-value.err; then
  fail "missing option value should fail"
fi
grep -q -- "--app requires a value" /tmp/omi-smoke-missing-value.err || fail "missing value failure should be explicit"

if "$SMOKE" --expected-bundle-id --preview >/tmp/omi-smoke-preview-missing-value.out 2>/tmp/omi-smoke-preview-missing-value.err; then
  fail "missing external preview identity should fail"
fi
grep -q -- "--expected-bundle-id requires a value" /tmp/omi-smoke-preview-missing-value.err \
  || fail "preview identity failure should be explicit"

tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/omi-smoke-test.XXXXXX")"
TMP_ROOTS+=("$tmp_root")
tmp_app="$tmp_root/Intentive.app"
mkdir -p "$tmp_app/Contents/MacOS" "$tmp_app/Contents/Resources" "$tmp_app/Contents/Frameworks"
cat > "$tmp_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Omi Computer</string>
  <key>CFBundleIdentifier</key><string>com.heyintentive.intentive</string>
  <key>CFBundleShortVersionString</key><string>0.12.34</string>
  <key>CFBundleVersion</key><string>12034</string>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLSchemes</key><array><string>heyintentive</string></array></dict></array>
  <key>SUFeedURL</key><string>https://updates.heyintentive.com/v2/desktop/appcast.xml</string>
  <key>SUPublicEDKey</key><string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
  <key>IntentiveManualDownloadURL</key><string>https://updates.heyintentive.com/v2/desktop/download/latest</string>
  <key>IntentiveReleasesURL</key><string>https://github.com/sruj75/knowledge-athlete/releases</string>
  <key>IntentiveProductionAPIURL</key><string>https://api.heyintentive.com</string>
  <key>IntentiveProductURL</key><string>https://heyintentive.com</string>
  <key>IntentiveTermsURL</key><string>https://heyintentive.com/terms</string>
  <key>IntentivePrivacyURL</key><string>https://heyintentive.com/privacy</string>
  <key>IntentiveSupportURL</key><string>https://heyintentive.com/support</string>
  <key>IntentivePostHogProjectToken</key><string>fixture-posthog-project-token</string>
  <key>IntentivePostHogHost</key><string>https://us.i.posthog.com</string>
</dict>
</plist>
PLIST
touch "$tmp_app/Contents/MacOS/Omi Computer"
chmod +x "$tmp_app/Contents/MacOS/Omi Computer"

if "$SMOKE" --app "$tmp_app" --tag "bad-tag" >/tmp/omi-smoke-badtag.out 2>/tmp/omi-smoke-badtag.err; then
  fail "bad release tag should fail before signing checks"
fi
grep -q "invalid release tag" /tmp/omi-smoke-badtag.err || fail "bad tag failure should be explicit"

# Intentive Beta variant: identity-scoped feed URL is accepted only when passed
# explicitly; the default expectation stays the plain shared feed.
beta_app="$tmp_root/Intentive Beta.app"
mkdir -p "$beta_app/Contents/MacOS" "$beta_app/Contents/Resources" "$beta_app/Contents/Frameworks"
cat > "$beta_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Omi Computer</string>
  <key>CFBundleIdentifier</key><string>com.heyintentive.intentive.beta</string>
  <key>CFBundleShortVersionString</key><string>0.12.34</string>
  <key>CFBundleVersion</key><string>12034</string>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLSchemes</key><array><string>heyintentive-beta</string></array></dict></array>
  <key>SUFeedURL</key><string>https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta</string>
  <key>SUPublicEDKey</key><string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
  <key>IntentiveManualDownloadURL</key><string>https://updates.heyintentive.com/v2/desktop/download/latest</string>
  <key>IntentiveReleasesURL</key><string>https://github.com/sruj75/knowledge-athlete/releases</string>
  <key>IntentiveProductionAPIURL</key><string>https://api.heyintentive.com</string>
  <key>IntentiveProductURL</key><string>https://heyintentive.com</string>
  <key>IntentiveTermsURL</key><string>https://heyintentive.com/terms</string>
  <key>IntentivePrivacyURL</key><string>https://heyintentive.com/privacy</string>
  <key>IntentiveSupportURL</key><string>https://heyintentive.com/support</string>
  <key>IntentivePostHogProjectToken</key><string>fixture-posthog-project-token</string>
  <key>IntentivePostHogHost</key><string>https://us.i.posthog.com</string>
</dict>
</plist>
PLIST
touch "$beta_app/Contents/MacOS/Omi Computer"
chmod +x "$beta_app/Contents/MacOS/Omi Computer"

if "$SMOKE" --app "$beta_app" --tag "v0.12.34+12034-macos" \
  --expected-bundle-id com.heyintentive.intentive.beta \
  --expected-url-scheme heyintentive-beta \
  >/tmp/omi-smoke-beta-default.out 2>/tmp/omi-smoke-beta-default.err; then
  fail "beta feed URL must be rejected without --expected-feed-url"
fi
grep -q "SUFeedURL mismatch" /tmp/omi-smoke-beta-default.err \
  || fail "default feed expectation should reject the identity-scoped feed"

if "$SMOKE" --app "$beta_app" --tag "v0.12.34+12034-macos" \
  --expected-bundle-id com.heyintentive.intentive.beta \
  --expected-url-scheme heyintentive-beta \
  --expected-feed-url "https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta" \
  >/tmp/omi-smoke-beta-feed.out 2>/tmp/omi-smoke-beta-feed.err; then
  fail "unsigned fixture should still fail later (signing), not pass entirely"
fi
grep -q "SUFeedURL mismatch" /tmp/omi-smoke-beta-feed.err \
  && fail "--expected-feed-url should accept the identity-scoped feed"

make_signed_smoke_fixture() {
  local app="$1"
  local bundle_id="$2"
  local feed_url="$3"

  mkdir -p \
    "$app/Contents/MacOS" \
    "$app/Contents/Frameworks/Sparkle.framework" \
    "$app/Contents/Resources/agent/dist" \
    "$app/Contents/Resources/agent/node_modules/@earendil-works/pi-coding-agent/dist" \
    "$app/Contents/Resources/agent/src/runtime" \
    "$app/Contents/Resources/pi-mono-extension" \
    "$app/Contents/Resources/Omi Computer_Omi Computer.bundle"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Omi Computer</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleShortVersionString</key><string>0.12.34</string>
  <key>CFBundleVersion</key><string>12034</string>
  <key>CFBundleURLTypes</key>
  <array><dict><key>CFBundleURLSchemes</key><array><string>$(
    [[ "$bundle_id" == "com.heyintentive.intentive.beta" ]] && printf heyintentive-beta || printf heyintentive
  )</string></array></dict></array>
  <key>SUFeedURL</key><string>$feed_url</string>
  <key>SUPublicEDKey</key><string>AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=</string>
  <key>IntentiveManualDownloadURL</key><string>https://updates.heyintentive.com/v2/desktop/download/latest</string>
  <key>IntentiveReleasesURL</key><string>https://github.com/sruj75/knowledge-athlete/releases</string>
  <key>IntentiveProductionAPIURL</key><string>https://api.heyintentive.com</string>
  <key>IntentiveProductURL</key><string>https://heyintentive.com</string>
  <key>IntentiveTermsURL</key><string>https://heyintentive.com/terms</string>
  <key>IntentivePrivacyURL</key><string>https://heyintentive.com/privacy</string>
  <key>IntentiveSupportURL</key><string>https://heyintentive.com/support</string>
  <key>IntentivePostHogProjectToken</key><string>fixture-posthog-project-token</string>
  <key>IntentivePostHogHost</key><string>https://us.i.posthog.com</string>
</dict>
</plist>
PLIST
  cat > "$app/Contents/Resources/.env" <<'ENV'
OMI_PYTHON_API_URL=https://api.heyintentive.com
ENV
  printf '#!/usr/bin/env bash\nexit 0\n' > "$app/Contents/MacOS/Omi Computer"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$app/Contents/Resources/Omi Computer_Omi Computer.bundle/node"
  chmod +x "$app/Contents/MacOS/Omi Computer" "$app/Contents/Resources/Omi Computer_Omi Computer.bundle/node"
  touch \
    "$app/Contents/Frameworks/libwebp.7.dylib" \
    "$app/Contents/Frameworks/libsharpyuv.0.dylib" \
    "$app/Contents/Resources/agent/dist/index.js" \
    "$app/Contents/Resources/agent/node_modules/@earendil-works/pi-coding-agent/dist/cli.js" \
    "$app/Contents/Resources/pi-mono-extension/index.ts" \
    "$app/Contents/Resources/agent/src/runtime/omi-tool-manifest.ts"
}

mock_bin="$tmp_root/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/codesign" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" --entitlements "* ]]; then
  printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict/></plist>'
elif [[ "${1:-}" == "-dv" ]]; then
  printf 'TeamIdentifier=TESTTEAM01\nRuntime Version=15.0.0\n' >&2
fi
SH
cat > "$mock_bin/spctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$mock_bin/xcrun" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$mock_bin/hdiutil" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "attach" ]]; then
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-mountpoint" ]]; then
      mountpoint="$2"
      break
    fi
    shift
  done
  cp -R "$OMI_TEST_DMG_APP_SOURCE" "$mountpoint/"
fi
SH
cat > "$mock_bin/file" <<'SH'
#!/usr/bin/env bash
printf '%s: Mach-O 64-bit executable arm64 x86_64\n' "${1:-fixture}"
SH
cat > "$mock_bin/otool" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat > "$mock_bin/strings" <<'SH'
#!/usr/bin/env bash
printf 'RewindDatabase\n'
SH
cat > "$mock_bin/libwebp-verify" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == "--verify-prepared" ]]
[[ "$2" == "--destination" ]]
test -f "$3/libwebp.7.dylib"
test -f "$3/libsharpyuv.0.dylib"
[[ "$4" == "--app-executable" ]]
test -x "$5"
[[ "$6" == "--expected-team-id" ]]
[[ "$7" == "TESTTEAM01" ]]
SH
cat > "$mock_bin/libwebp-fail" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$mock_bin"/*
export OMI_SIGNED_ARTIFACT_SMOKE_LIBWEBP_VERIFY_SCRIPT="$mock_bin/libwebp-verify"

canonical_dmg_app="$tmp_root/Intentive.app"
signed_beta_app="$tmp_root/signed/Intentive Beta.app"
renamed_canonical_app="$tmp_root/Anything.app"
renamed_beta_app="$tmp_root/signed/Anything Beta.app"
make_signed_smoke_fixture "$canonical_dmg_app" \
  com.heyintentive.intentive \
  https://updates.heyintentive.com/v2/desktop/appcast.xml
make_signed_smoke_fixture "$signed_beta_app" \
  com.heyintentive.intentive.beta \
  'https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta'
make_signed_smoke_fixture "$renamed_canonical_app" \
  com.heyintentive.intentive \
  https://updates.heyintentive.com/v2/desktop/appcast.xml
make_signed_smoke_fixture "$renamed_beta_app" \
  com.heyintentive.intentive.beta \
  'https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta'
dummy_dmg="$tmp_root/fixture.dmg"
touch "$dummy_dmg"

mkdir -p "$canonical_dmg_app/Contents/Resources/agent/dist/adapters"
touch "$canonical_dmg_app/Contents/Resources/agent/dist/adapters/acp.js"
if PATH="$mock_bin:$PATH" \
  "$SMOKE" --app "$canonical_dmg_app" --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-retired-runtime.out 2>/tmp/omi-smoke-retired-runtime.err; then
  fail "signed smoke must reject retired agent runtime assets"
fi
grep -q "retired agent runtime asset present" /tmp/omi-smoke-retired-runtime.err \
  || fail "retired runtime rejection should identify the package boundary"
rm "$canonical_dmg_app/Contents/Resources/agent/dist/adapters/acp.js"
rmdir "$canonical_dmg_app/Contents/Resources/agent/dist/adapters"

PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$canonical_dmg_app" \
  "$SMOKE" --app "$canonical_dmg_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-canonical-dmg.out 2>/tmp/omi-smoke-canonical-dmg.err \
  || fail "canonical Intentive.app DMG should pass: $(cat /tmp/omi-smoke-canonical-dmg.err)"

wrong_posthog_dmg_app="$tmp_root/wrong-posthog/Intentive.app"
make_signed_smoke_fixture "$wrong_posthog_dmg_app" \
  com.heyintentive.intentive \
  https://updates.heyintentive.com/v2/desktop/appcast.xml
/usr/libexec/PlistBuddy -c 'Set :IntentivePostHogProjectToken wrong-project-token' \
  "$wrong_posthog_dmg_app/Contents/Info.plist"
if PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$wrong_posthog_dmg_app" \
  "$SMOKE" --app "$canonical_dmg_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-wrong-posthog-dmg.out 2>/tmp/omi-smoke-wrong-posthog-dmg.err; then
  fail "signed smoke unexpectedly accepted a DMG with the wrong PostHog project token"
fi
grep -q "DMG-contained Intentive.app PostHog project token mismatch" /tmp/omi-smoke-wrong-posthog-dmg.err ||
  fail "wrong DMG PostHog token rejection should identify the cross-artifact boundary"

/usr/libexec/PlistBuddy -c 'Set :IntentivePostHogProjectToken wrong-project-token' \
  "$canonical_dmg_app/Contents/Info.plist"
if PATH="$mock_bin:$PATH" \
  "$SMOKE" --app "$canonical_dmg_app" --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-wrong-posthog.out 2>/tmp/omi-smoke-wrong-posthog.err; then
  fail "signed smoke unexpectedly accepted the wrong PostHog project token"
fi
grep -q "IntentivePostHogProjectToken mismatch" /tmp/omi-smoke-wrong-posthog.err ||
  fail "wrong PostHog token rejection should name IntentivePostHogProjectToken"
/usr/libexec/PlistBuddy -c 'Set :IntentivePostHogProjectToken fixture-posthog-project-token' \
  "$canonical_dmg_app/Contents/Info.plist"

/usr/libexec/PlistBuddy -c 'Set :IntentiveProductURL https://example.com' \
  "$canonical_dmg_app/Contents/Info.plist"
if PATH="$mock_bin:$PATH" \
  "$SMOKE" --app "$canonical_dmg_app" --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-unowned-product.out 2>/tmp/omi-smoke-unowned-product.err; then
  fail "signed smoke unexpectedly accepted an unowned stamped product URL"
fi
grep -q "IntentiveProductURL mismatch" /tmp/omi-smoke-unowned-product.err \
  || fail "unowned stamped product URL rejection should name IntentiveProductURL"
/usr/libexec/PlistBuddy -c 'Set :IntentiveProductURL https://heyintentive.com' \
  "$canonical_dmg_app/Contents/Info.plist"

PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$signed_beta_app" \
  "$SMOKE" --app "$signed_beta_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  --expected-bundle-id com.heyintentive.intentive.beta \
  --expected-url-scheme heyintentive-beta \
  --expected-feed-url 'https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta' \
  >/tmp/omi-smoke-beta-dmg.out 2>/tmp/omi-smoke-beta-dmg.err \
  || fail "Intentive Beta.app DMG should pass: $(cat /tmp/omi-smoke-beta-dmg.err)"

if PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$canonical_dmg_app" \
  "$SMOKE" --app "$signed_beta_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  --expected-bundle-id com.heyintentive.intentive.beta \
  --expected-url-scheme heyintentive-beta \
  --expected-feed-url 'https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta' \
  >/tmp/omi-smoke-beta-wrong-dmg.out 2>/tmp/omi-smoke-beta-wrong-dmg.err; then
  fail "beta smoke must reject a DMG containing only Intentive.app"
fi
grep -q "DMG must contain exact Intentive Beta.app" /tmp/omi-smoke-beta-wrong-dmg.err \
  || fail "wrong-name DMG rejection should name the exact expected bundle"

if PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$renamed_canonical_app" \
  "$SMOKE" --app "$renamed_canonical_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-renamed-canonical.out 2>/tmp/omi-smoke-renamed-canonical.err; then
  fail "canonical identity must reject a renamed app and matching DMG"
fi
grep -q "app bundle name for com.heyintentive.intentive must be Intentive.app, got Anything.app" \
  /tmp/omi-smoke-renamed-canonical.err \
  || fail "renamed canonical rejection should bind Intentive.app to its bundle identity"

if PATH="$mock_bin:$PATH" OMI_TEST_DMG_APP_SOURCE="$renamed_beta_app" \
  "$SMOKE" --app "$renamed_beta_app" --dmg "$dummy_dmg" \
  --tag v0.12.34+12034-macos \
  --expected-bundle-id com.heyintentive.intentive.beta \
  --expected-url-scheme heyintentive-beta \
  --expected-feed-url 'https://updates.heyintentive.com/v2/desktop/appcast.xml?identity=beta' \
  >/tmp/omi-smoke-renamed-beta.out 2>/tmp/omi-smoke-renamed-beta.err; then
  fail "beta identity must reject a renamed app and matching DMG"
fi
grep -q "app bundle name for com.heyintentive.intentive.beta must be Intentive Beta.app, got Anything Beta.app" \
  /tmp/omi-smoke-renamed-beta.err \
  || fail "renamed beta rejection should bind Intentive Beta.app to its bundle identity"

if PATH="$mock_bin:$PATH" OMI_SIGNED_ARTIFACT_SMOKE_LIBWEBP_VERIFY_SCRIPT="$mock_bin/libwebp-fail" \
  "$SMOKE" --app "$canonical_dmg_app" --tag v0.12.34+12034-macos \
  >/tmp/omi-smoke-libwebp-failure.out 2>/tmp/omi-smoke-libwebp-failure.err; then
  fail "signed smoke must fail closed when bundled libwebp verification fails"
fi
grep -q "bundled libwebp/libsharpyuv provenance, linkage, or signing verification failed" \
  /tmp/omi-smoke-libwebp-failure.err \
  || fail "libwebp rejection should identify the nested release boundary"

# Regression (v0.12.91 build failure): macOS mktemp creates the LITERAL template
# file when characters follow the final XXXXXX, so the second smoke invocation
# in one build (stable then Omi Beta) dies with "File exists". Every template
# must end with XXXXXX.
if grep -nE 'mktemp (-d )?"[^"]*XXXXXX[^"]+"' "$SMOKE"; then
  fail "mktemp template with a suffix after XXXXXX breaks repeat smoke invocations"
fi

echo "signed artifact smoke tests passed"
