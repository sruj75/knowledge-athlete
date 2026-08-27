#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT="$MACOS_DIR/scripts/cleanup-omi-tcc.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

home="$TMPDIR/home"
apps="$TMPDIR/apps"
prefs="$home/Library/Preferences"
tcc_dir="$home/Library/Application Support/com.apple.TCC"
bin="$TMPDIR/bin"
mkdir -p "$apps" "$prefs" "$tcc_dir" "$bin"

make_app() {
  local app_name="$1" bundle_id="$2" display_name="$3"
  local contents="$apps/$app_name.app/Contents"
  mkdir -p "$contents"
  python3 - "$contents/Info.plist" "$bundle_id" "$display_name" <<'PY'
import plistlib
import sys

path, bundle_id, display_name = sys.argv[1:]
with open(path, "wb") as handle:
    plistlib.dump(
        {
            "CFBundleIdentifier": bundle_id,
            "CFBundleDisplayName": display_name,
            "CFBundleName": display_name,
        },
        handle,
    )
PY
}

make_pref() {
  local domain="$1"
  python3 - "$prefs/$domain.plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "wb") as handle:
    plistlib.dump({"fixture": True}, handle)
PY
}

make_app "Intentive" "com.heyintentive.intentive" "Intentive"
make_app "Intentive Beta" "com.heyintentive.intentive.beta" "Intentive Beta"
make_app "Intentive Dev" "com.heyintentive.intentive.dev" "Intentive Dev"
make_app "omi-test-one" "com.heyintentive.intentive.dev.omi-test-one" "omi-test-one"
make_app "preview-review" "com.heyintentive.intentive.preview.review-build" "Intentive Preview"
make_app "Omi Foreign" "com.omi.computer-macos" "Omi"
make_app "Other" "com.example.other" "Other"
make_pref "com.heyintentive.intentive.dev.omi-pref-only"
make_pref "com.heyintentive.intentive.preview.review-pref"
make_pref "com.omi.omi-foreign"

python3 - "$tcc_dir/TCC.db" <<'PY'
import sqlite3
import sys

conn = sqlite3.connect(sys.argv[1])
conn.execute(
    "CREATE TABLE access (service TEXT, client TEXT, client_type INTEGER, auth_value INTEGER, last_modified INTEGER)"
)
conn.executemany(
    "INSERT INTO access VALUES (?, ?, ?, ?, ?)",
    [
        ("kTCCServiceMicrophone", "com.heyintentive.intentive.dev.omi-test-one", 0, 2, 1),
        ("kTCCServiceScreenCapture", "com.heyintentive.intentive.dev.omi-pref-only", 0, 2, 1),
        ("kTCCServiceMicrophone", "com.heyintentive.intentive.dev", 0, 2, 1),
        ("kTCCServiceMicrophone", "com.heyintentive.intentive", 0, 2, 1),
        ("kTCCServiceMicrophone", "com.heyintentive.intentive.preview.review-build", 0, 2, 1),
        ("kTCCServiceMicrophone", "com.omi.omi-foreign", 0, 2, 1),
        ("kTCCServiceMicrophone", "/Applications/omi-path-only.app/Contents/MacOS/Omi", 1, 2, 1),
    ],
)
conn.commit()
conn.close()
PY

summary_out="$TMPDIR/summary.json"
OMI_TCC_HOME="$home" OMI_TCC_APP_ROOTS="$apps" "$SCRIPT" --json >"$summary_out"

python3 - "$summary_out" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["detail_mode"] == "summary", data
assert data["details_available"] is True, data
assert data["candidate_bundle_ids_count"] == 2, data
assert data["tccutil_bundle_ids_count"] == 1, data
assert data["tcc"]["row_count"] == 5, data
assert "apps" not in data, data
assert "preferences" not in data, data
PY

json_out="$TMPDIR/inventory.json"
OMI_TCC_HOME="$home" OMI_TCC_APP_ROOTS="$apps" "$SCRIPT" --json --verbose >"$json_out"

python3 - "$json_out" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
assert data["tcc"]["readable"] is True
assert data["candidate_prefixes"] == ["com.heyintentive.intentive.dev.omi-"]
assert data["tccutil_bundle_ids"] == ["com.heyintentive.intentive.dev.omi-test-one"], data["tccutil_bundle_ids"]
assert set(data["candidate_bundle_ids"]) == {
    "com.heyintentive.intentive.dev.omi-test-one",
    "com.heyintentive.intentive.dev.omi-pref-only",
}
assert set(data["keep_bundle_ids"]) == {
    "com.heyintentive.intentive",
    "com.heyintentive.intentive.beta",
    "com.heyintentive.intentive.dev",
}
assert data["summary"]["apps"].get("keep") == 3, data["summary"]
assert data["summary"]["apps"].get("candidate") == 1, data["summary"]
assert data["summary"]["apps"].get("review") == 1, data["summary"]
tcc_classes = {row["client"]: row["classification"] for row in data["tcc"]["rows"]}
assert tcc_classes["com.heyintentive.intentive"] == "keep", tcc_classes
assert tcc_classes["com.heyintentive.intentive.dev"] == "keep", tcc_classes
assert tcc_classes["com.heyintentive.intentive.preview.review-build"] == "review", tcc_classes
serialized = json.dumps(data)
assert "com.omi" not in serialized, serialized
assert "/Applications/omi-path-only.app" not in serialized, serialized
PY

cat >"$bin/tccutil" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TCCUTIL_LOG"
exit 0
SH
chmod +x "$bin/tccutil"
apply_json="$TMPDIR/apply.json"
TCCUTIL_LOG="$TMPDIR/tccutil.log" \
PATH="$bin:$PATH" \
OMI_TCC_HOME="$home" \
OMI_TCC_APP_ROOTS="$apps" \
  "$SCRIPT" --apply-tccutil --json >"$apply_json"

python3 - "$apply_json" "$TMPDIR/tccutil.log" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
log = open(sys.argv[2]).read().splitlines()
assert log == ["reset All com.heyintentive.intentive.dev.omi-test-one"], log
assert data["detail_mode"] == "summary", data
assert data["details_available"] is True, data
assert data["apply"]["summary"] == {"ok": 1}, data["apply"]
assert "results" not in data["apply"], data["apply"]
PY

apply_verbose_json="$TMPDIR/apply-verbose.json"
TCCUTIL_LOG="$TMPDIR/tccutil-verbose.log" \
PATH="$bin:$PATH" \
OMI_TCC_HOME="$home" \
OMI_TCC_APP_ROOTS="$apps" \
  "$SCRIPT" --apply-tccutil --json --verbose >"$apply_verbose_json"

python3 - "$apply_verbose_json" "$TMPDIR/tccutil-verbose.log" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
log = open(sys.argv[2]).read().splitlines()
assert log == ["reset All com.heyintentive.intentive.dev.omi-test-one"], log
assert data["detail_mode"] == "full", data
assert len(data["apply"]["results"]) == 1, data["apply"]
assert data["apply"]["summary"] == {"ok": 1}, data["apply"]
PY

custom_json="$TMPDIR/custom.json"
OMI_TCC_HOME="$home" OMI_TCC_APP_ROOTS="$apps" \
  "$SCRIPT" --json --verbose \
    --candidate-prefix com.heyintentive.intentive.dev.omi-review- \
    --keep-bundle-id com.heyintentive.intentive.dev.omi-review-build >"$custom_json"
python3 - "$custom_json" <<'PY'
import json
import sys

data = json.load(open(sys.argv[1]))
# Explicit keep wins over a broader candidate prefix.
assert "com.heyintentive.intentive.dev.omi-review-build" in data["keep_bundle_ids"]
assert data["tccutil_bundle_ids"] == ["com.heyintentive.intentive.dev.omi-test-one"], data["tccutil_bundle_ids"]
PY

if "$SCRIPT" --candidate-prefix com.omi. >/tmp/cleanup-omi-tcc-invalid.out 2>/tmp/cleanup-omi-tcc-invalid.err; then
  fail "foreign Omi candidate prefix unexpectedly succeeded"
fi
if ! grep -q "expected an Intentive named-development prefix" /tmp/cleanup-omi-tcc-invalid.err; then
  fail "invalid candidate prefix did not explain the owned target requirement"
fi

echo "cleanup-omi-tcc tests passed"
