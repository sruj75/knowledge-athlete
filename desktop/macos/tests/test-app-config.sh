#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$MACOS_DIR/scripts/app-config.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" label="$3"
  if [ "$expected" != "$actual" ]; then
    fail "$label: expected '$expected', got '$actual'"
  fi
}

test_home="/tmp/intentive-app-config-home"
HOME="$test_home"
unset XDG_CACHE_HOME
if intentive_should_seed_named_profile true 0; then
  fail "clean named launch unexpectedly enabled profile seeding"
fi
intentive_should_seed_named_profile true 1 || fail "explicit named parity seed was not enabled"
if intentive_should_seed_named_profile false 1; then
  fail "canonical development launch unexpectedly enabled profile seeding"
fi
assert_eq \
  "$test_home/Library/Application Support/Intentive Dev" \
  "$(intentive_dev_profile_root "$test_home" com.heyintentive.intentive.dev)" \
  "canonical development profile"
assert_eq \
  "$test_home/Library/Application Support/Intentive Dev Bundles/com.heyintentive.intentive.dev.omi-wave5-s28" \
  "$(intentive_dev_profile_root "$test_home" com.heyintentive.intentive.dev.omi-wave5-s28)" \
  "named development profile"
if intentive_dev_profile_root "$test_home" com.omi.desktop-dev >/dev/null 2>&1; then
  fail "foreign Omi profile root unexpectedly resolved"
fi
assert_eq "$test_home/Library/Caches/heyintentive-desktop/node-archives" "$(intentive_archive_cache_dir)" "default archive cache"
assert_eq "$test_home/Library/Caches/heyintentive-desktop/qualification-swiftpm-v2" "$(intentive_qualification_cache_dir)" "default qualification cache"
XDG_CACHE_HOME="/tmp/intentive-xdg-cache"
assert_eq "/tmp/intentive-xdg-cache/heyintentive-desktop/node-archives" "$(intentive_archive_cache_dir)" "XDG archive cache"
unset XDG_CACHE_HOME

assert_config() {
  local app_name="$1" expected_is_named="$2" expected_bundle="$3" expected_scheme="$4"
  derive_omi_app_config "$app_name"
  assert_eq "$app_name" "$APP_NAME" "APP_NAME for $app_name"
  assert_eq "$expected_is_named" "$IS_NAMED_BUNDLE" "IS_NAMED_BUNDLE for $app_name"
  assert_eq "$expected_bundle" "$EXPECTED_BUNDLE_ID" "EXPECTED_BUNDLE_ID for $app_name"
  assert_eq "$expected_scheme" "$EXPECTED_URL_SCHEME" "EXPECTED_URL_SCHEME for $app_name"
  assert_eq "$expected_bundle" "$BUNDLE_ID" "BUNDLE_ID for $app_name"
  assert_eq "$expected_scheme" "$URL_SCHEME" "URL_SCHEME for $app_name"
}

assert_plist_value() {
  local plist="$1" key="$2" expected="$3"
  local actual
  actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"
  assert_eq "$expected" "$actual" "$plist $key"
}

assert_config "Intentive Dev" "false" "com.heyintentive.intentive.dev" "heyintentive-dev"
assert_config \
  "omi-wave5-s28" \
  "true" \
  "com.heyintentive.intentive.dev.omi-wave5-s28" \
  "heyintentive-omi-wave5-s28"
assert_config \
  "Omi Subagent Test!!" \
  "true" \
  "com.heyintentive.intentive.dev.omi-subagent-test" \
  "heyintentive-omi-subagent-test"

if derive_omi_app_config "!!!" >/tmp/omi-app-config-invalid.out 2>/tmp/omi-app-config-invalid.err; then
  fail "invalid app name unexpectedly succeeded"
fi
if ! grep -q "OMI_APP_NAME must contain at least one letter or number" /tmp/omi-app-config-invalid.err; then
  fail "invalid app name did not explain the slug requirement"
fi

if derive_omi_app_config "feature-without-prefix" >/tmp/omi-app-config-prefix.out 2>/tmp/omi-app-config-prefix.err; then
  fail "non-omi named app unexpectedly succeeded"
fi
if ! grep -q "must use the omi- prefix" /tmp/omi-app-config-prefix.err; then
  fail "non-omi named app did not explain the required prefix"
fi

if OMI_BUNDLE_ID="com.omi.desktop-dev" derive_omi_app_config "omi-subagent-test" >/tmp/omi-app-config-bundle.out 2>/tmp/omi-app-config-bundle.err; then
  fail "mismatched OMI_BUNDLE_ID unexpectedly succeeded"
fi
if ! grep -q "must use bundle ID 'com.heyintentive.intentive.dev.omi-subagent-test'" /tmp/omi-app-config-bundle.err; then
  fail "mismatched OMI_BUNDLE_ID did not report expected bundle id"
fi

if OMI_URL_SCHEME="omi-wrong" derive_omi_app_config "omi-subagent-test" >/tmp/omi-app-config-scheme.out 2>/tmp/omi-app-config-scheme.err; then
  fail "mismatched OMI_URL_SCHEME unexpectedly succeeded"
fi
if ! grep -q "must use URL scheme 'heyintentive-omi-subagent-test'" /tmp/omi-app-config-scheme.err; then
  fail "mismatched OMI_URL_SCHEME did not report expected URL scheme"
fi

DEV_FIREBASE_PLIST="$MACOS_DIR/Desktop/Sources/GoogleService-Info-Dev.plist"
assert_plist_value "$DEV_FIREBASE_PLIST" "BUNDLE_ID" "com.heyintentive.intentive.dev"
assert_plist_value "$DEV_FIREBASE_PLIST" "PROJECT_ID" "knowledge-athlete"
assert_plist_value "$DEV_FIREBASE_PLIST" "GOOGLE_APP_ID" "1:674306938907:ios:befed665f1aa0cd09b40be"
assert_plist_value "$DEV_FIREBASE_PLIST" "CLIENT_ID" "674306938907-ial5r9hgbbicqem8east4013svkan0lt.apps.googleusercontent.com"
assert_plist_value "$DEV_FIREBASE_PLIST" "REVERSED_CLIENT_ID" "com.googleusercontent.apps.674306938907-ial5r9hgbbicqem8east4013svkan0lt"

LOCAL_FIREBASE_PLIST="$MACOS_DIR/Desktop/Sources/GoogleService-Info-Local.plist"
assert_plist_value "$LOCAL_FIREBASE_PLIST" "BUNDLE_ID" "com.heyintentive.intentive.dev"
assert_plist_value "$LOCAL_FIREBASE_PLIST" "PROJECT_ID" "demo-heyintentive-local"
assert_plist_value "$LOCAL_FIREBASE_PLIST" "CLIENT_ID" "local-heyintentive-dev.apps.localhost"

echo "app-config tests passed"
