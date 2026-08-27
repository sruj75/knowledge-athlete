#!/usr/bin/env bash
# Create the separately-installable "Intentive Beta" variant from the signed stable app.
#
# The variant is the same binary re-identified (CFBundleIdentifier
# com.heyintentive.intentive.beta + "Intentive Beta" name) so it runs beside stable with its
# own UserDefaults, TCC grants, Keychain ACL, storage root, and single-instance
# lock. Only the outer bundle signature covers Info.plist, so nested component
# signatures from the stable signing pass remain valid; the outer bundle is
# re-signed, then the variant is independently notarized, stapled, packaged as a
# Sparkle ZIP + DMG, and EdDSA-signed for the appcast.
#
# Required env (provided by the Codemagic release workflow):
#   SIGN_IDENTITY, APP_STORE_CONNECT_KEY_IDENTIFIER, APP_STORE_CONNECT_PRIVATE_KEY,
#   APP_STORE_CONNECT_ISSUER_ID, SPARKLE_PRIVATE_KEY, DMGBUILD_VERSION
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_APP=""
BUILD_DIR=""
BETA_APP_NAME="Intentive Beta"
BETA_BUNDLE_ID="com.heyintentive.intentive.beta"
BETA_URL_SCHEME="heyintentive-beta"
BETA_FEED_URL="${INTENTIVE_BETA_FEED_URL:-}"
SPARKLE_ZIP_OUT=""
DMG_OUT=""
CM_ENV_OUT=""
NOTARY_KEY_PATH=""
STAGING_DIR=""

cleanup() {
  [[ -z "$NOTARY_KEY_PATH" ]] || rm -f -- "$NOTARY_KEY_PATH"
  if [[ -n "$STAGING_DIR" ]]; then
    case "$STAGING_DIR" in
      "${TMPDIR:-/tmp}/heyintentive-beta-dmg-staging."*) rm -rf -- "$STAGING_DIR" ;;
      *) echo "Refusing unsafe cleanup path: $STAGING_DIR" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage: scripts/create-intentive-beta-variant.sh \
  --source-app build/Intentive.app --build-dir build \
  --beta-feed-url https://OWNED_HOST/v2/desktop/appcast.xml?identity=beta \
  --sparkle-zip-out build/Intentive.Beta.zip \
  --dmg-out build/intentive-beta.dmg [--cm-env "$CM_ENV"]
EOF
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-app) SOURCE_APP="$2"; shift 2 ;;
    --build-dir) BUILD_DIR="$2"; shift 2 ;;
    --beta-feed-url) BETA_FEED_URL="$2"; shift 2 ;;
    --sparkle-zip-out) SPARKLE_ZIP_OUT="$2"; shift 2 ;;
    --dmg-out) DMG_OUT="$2"; shift 2 ;;
    --cm-env) CM_ENV_OUT="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$SOURCE_APP" && -n "$BUILD_DIR" && -n "$SPARKLE_ZIP_OUT" && -n "$DMG_OUT" ]] || usage
[[ -d "$SOURCE_APP" ]] || { echo "ERROR: source app not found: $SOURCE_APP" >&2; exit 1; }
: "${BETA_FEED_URL:?--beta-feed-url or INTENTIVE_BETA_FEED_URL is required}"
: "${SIGN_IDENTITY:?SIGN_IDENTITY is required}"
: "${APP_STORE_CONNECT_KEY_IDENTIFIER:?notary key id required}"
: "${APP_STORE_CONNECT_PRIVATE_KEY:?notary private key required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?notary issuer required}"
: "${SPARKLE_PRIVATE_KEY:?Sparkle EdDSA key required}"

BUILD_DIR="$(mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR" && pwd)"
SOURCE_APP="$(cd "$SOURCE_APP" && pwd)"
BETA_APP="$BUILD_DIR/$BETA_APP_NAME.app"
PLIST="$BETA_APP/Contents/Info.plist"

SOURCE_PLIST="$SOURCE_APP/Contents/Info.plist"
SOURCE_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_PLIST" 2>/dev/null || true)"
[[ "$SOURCE_BUNDLE_ID" == "com.heyintentive.intentive" ]] \
  || { echo "ERROR: source app must use stable Intentive identity" >&2; exit 1; }
[[ "$(basename "$SOURCE_APP")" == "Intentive.app" ]] \
  || { echo "ERROR: stable source app must be named Intentive.app" >&2; exit 1; }
python3 - "$BETA_FEED_URL" <<'PY'
import sys
from urllib.parse import urlparse

url = urlparse(sys.argv[1])
host = (url.hostname or "").lower()
if url.scheme != "https" or not host or url.username or url.password or url.fragment:
    raise SystemExit("ERROR: beta feed must be a clean HTTPS URL")
if host == "omi.me" or host.endswith(".omi.me"):
    raise SystemExit("ERROR: inherited Omi beta feeds are forbidden")
if host == "basedhardware.com" or host.endswith(".basedhardware.com"):
    raise SystemExit("ERROR: inherited BasedHardware beta feeds are forbidden")
PY

notarize_and_staple() {
  local artifact="$1"
  if [[ -z "$NOTARY_KEY_PATH" ]]; then
    NOTARY_KEY_PATH="$(mktemp "${TMPDIR:-/tmp}/heyintentive-notary-key.XXXXXX")"
    chmod 600 "$NOTARY_KEY_PATH"
    printf '%b' "$APP_STORE_CONNECT_PRIVATE_KEY" > "$NOTARY_KEY_PATH"
  fi

  local result status submission_id
  result=$(xcrun notarytool submit "$artifact" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
    --wait \
    --output-format json)
  status=$(echo "$result" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('status',''))" 2>/dev/null || echo "")
  submission_id=$(echo "$result" | python3 -c \
    "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
  if [[ "$status" != "Accepted" ]]; then
    echo "ERROR: notarization failed for $artifact: $status" >&2
    [[ -n "$submission_id" ]] && xcrun notarytool log "$submission_id" \
      --key "$NOTARY_KEY_PATH" \
      --key-id "$APP_STORE_CONNECT_KEY_IDENTIFIER" \
      --issuer "$APP_STORE_CONNECT_ISSUER_ID" || true
    exit 1
  fi
}

echo "== Duplicating $SOURCE_APP -> $BETA_APP"
case "$BETA_APP" in
  "$BUILD_DIR/Intentive Beta.app") rm -rf -- "$BETA_APP" ;;
  *) echo "ERROR: refusing unsafe beta app replacement path: $BETA_APP" >&2; exit 1 ;;
esac
ditto "$SOURCE_APP" "$BETA_APP"

echo "== Patching identity"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BETA_BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $BETA_APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $BETA_APP_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c \
  "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 $BETA_URL_SCHEME" "$PLIST"
# Identity-aware feed: beta enclosures are requested only by the Beta identity.
# The exact owned provider URL is required; this script has no inherited fallback.
/usr/libexec/PlistBuddy -c \
  "Set :SUFeedURL $BETA_FEED_URL" "$PLIST"

echo "== Re-signing outer bundle (nested signatures unchanged)"
codesign --force --options runtime --timestamp \
  --sign "$SIGN_IDENTITY" \
  --entitlements "$MACOS_DIR/Desktop/Omi-Release.entitlements" \
  "$BETA_APP"
codesign --verify --deep --strict --verbose=2 "$BETA_APP"

echo "== Notarizing beta app"
TEMP_ZIP="$BUILD_DIR/notarize-beta-temp.zip"
ditto -c -k --keepParent "$BETA_APP" "$TEMP_ZIP"
notarize_and_staple "$TEMP_ZIP"
rm -f "$TEMP_ZIP"
xcrun stapler staple "$BETA_APP"

echo "== Creating beta DMG"
pip3 install --break-system-packages "dmgbuild==${DMGBUILD_VERSION:?}" >/dev/null
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heyintentive-beta-dmg-staging.XXXXXX")"
ditto "$BETA_APP" "$STAGING_DIR/$BETA_APP_NAME.app"
xcrun stapler validate "$STAGING_DIR/$BETA_APP_NAME.app" 2>/dev/null || \
  xcrun stapler staple "$STAGING_DIR/$BETA_APP_NAME.app"
dmgbuild -s "$MACOS_DIR/dmg-assets/dmgbuild_settings.py" \
  -D app_path="$STAGING_DIR/$BETA_APP_NAME.app" \
  -D app_name="$BETA_APP_NAME" \
  -D assets_dir="$(pwd)/dmg-assets" \
  "$BETA_APP_NAME" \
  "$DMG_OUT"
rm -rf -- "$STAGING_DIR"
STAGING_DIR=""

codesign --force --sign "$SIGN_IDENTITY" "$DMG_OUT"
echo "== Notarizing beta DMG"
notarize_and_staple "$DMG_OUT"
xcrun stapler staple "$DMG_OUT"

echo "== Creating beta Sparkle ZIP"
ditto -c -k --keepParent "$BETA_APP" "$SPARKLE_ZIP_OUT"
SPARKLE_BIN="${INTENTIVE_SPARKLE_BIN:-$MACOS_DIR/Desktop/.build/artifacts/sparkle/Sparkle/bin}"
BETA_ED_SIGNATURE=""
if [[ -f "$SPARKLE_BIN/sign_update" ]]; then
  BETA_ED_SIGNATURE=$(echo "$SPARKLE_PRIVATE_KEY" | \
    "$SPARKLE_BIN/sign_update" "$SPARKLE_ZIP_OUT" --ed-key-file - 2>/dev/null | \
    grep "sparkle:edSignature" | \
    sed 's/.*edSignature="\([^"]*\)".*/\1/')
fi
if [[ -z "$BETA_ED_SIGNATURE" ]]; then
  echo "ERROR: could not generate EdDSA signature for the beta Sparkle ZIP" >&2
  exit 1
fi
echo "Beta EdDSA signature: $BETA_ED_SIGNATURE"
if [[ -n "$CM_ENV_OUT" ]]; then
  echo "BETA_ED_SIGNATURE=$BETA_ED_SIGNATURE" >> "$CM_ENV_OUT"
fi

echo "== Beta variant ready"
shasum -a 256 "$SPARKLE_ZIP_OUT" "$DMG_OUT"
