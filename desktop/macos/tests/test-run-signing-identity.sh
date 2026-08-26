#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUN="$ROOT/run.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/omi-run-signing-identity.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin"
cat >"$TMP/bin/security" <<'SH'
#!/usr/bin/env bash
if [ "${IDENTITY_FIXTURE:-development}" = "development" ]; then
    cat <<'EOF'
  1) AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "Apple Development: Omi Developer (TEAM123456)"
  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "Apple Development: Omi Developer (TEAM123456)"
  3) CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC "Developer ID Application: Omi Developer (TEAM123456)"
     3 valid identities found
EOF
else
    cat <<'EOF'
  1) DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD "Developer ID Application: Omi Developer (TEAM123456)"
  2) EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE "Developer ID Application: Omi Developer (TEAM123456)"
     2 valid identities found
EOF
fi
SH
chmod +x "$TMP/bin/security"

FUNCTION_SOURCE="$(sed -n '/^resolve_signing_identity()/,/^}/p' "$RUN")"

SIGN_IDENTITY=""
IS_NAMED_BUNDLE=true
BUNDLE_ID=com.omi.omi-signing-test
OMI_ALLOW_ADHOC_SIGN=0
substep() { :; }
eval "$FUNCTION_SOURCE"

PATH="$TMP/bin:$PATH" resolve_signing_identity
test "$SIGN_IDENTITY" = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

SIGN_IDENTITY=""
IDENTITY_FIXTURE=distribution PATH="$TMP/bin:$PATH" resolve_signing_identity
test "$SIGN_IDENTITY" = "DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD"

echo "test-run-signing-identity.sh: OK"
