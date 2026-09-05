#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/run-swift-ci.sh"
PACKAGE_PATH="$SCRIPT_DIR/../Desktop"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

mkdir -p "$TMPDIR/macos/scripts" "$TMPDIR/Xcode_16.4.app/Contents/Developer/usr/bin" "$TMPDIR/bin"
cp "$RUNNER" "$TMPDIR/macos/scripts/run-swift-ci.sh"
chmod +x "$TMPDIR/macos/scripts/run-swift-ci.sh"

cat >"$TMPDIR/Xcode_16.4.app/Contents/Developer/usr/bin/xcodebuild" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "Xcode ${FAKE_XCODE_VERSION:-16.4}"
echo "Build version ${FAKE_XCODE_BUILD:-16F6}"
SH
chmod +x "$TMPDIR/Xcode_16.4.app/Contents/Developer/usr/bin/xcodebuild"

cat >"$TMPDIR/bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$DEVELOPER_DIR" "$*" >> "$FAKE_XCRUN_LOG"
printf '%s|%s\n' "${OMI_NOTIFICATION_RELEASE_TESTS_ONLY:-unset}" "$*" >> "$FAKE_RELEASE_LOG"
if [ "${1:-}" = "swift" ] && [ "${2:-}" = "--version" ]; then
  echo "Swift version fake"
fi
if [ "${1:-}" = "swift" ] && [ "${2:-}" = "test" ]; then
  exit "${FAKE_TEST_EXIT_CODE:-0}"
fi
SH
chmod +x "$TMPDIR/bin/xcrun"

cat >"$TMPDIR/macos/scripts/swift-test-suites.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$DEVELOPER_DIR" "$OMI_SWIFT_TEST_SUITE_WORKERS" >> "$FAKE_SUITE_LOG"
SH
chmod +x "$TMPDIR/macos/scripts/swift-test-suites.sh"

export PATH="$TMPDIR/bin:$PATH"
export OMI_SWIFT_CI_XCODE_APP="$TMPDIR/Xcode_16.4.app"
export FAKE_XCRUN_LOG="$TMPDIR/xcrun.log"
export FAKE_RELEASE_LOG="$TMPDIR/release.log"
export FAKE_SUITE_LOG="$TMPDIR/suite.log"
export GITHUB_ENV="$TMPDIR/github-env"

"$TMPDIR/macos/scripts/run-swift-ci.sh" --select-toolchain
if ! grep -qx "DEVELOPER_DIR=$TMPDIR/Xcode_16.4.app/Contents/Developer" "$GITHUB_ENV"; then
  fail "toolchain selection did not export DEVELOPER_DIR for subsequent CI steps"
fi

"$TMPDIR/macos/scripts/run-swift-ci.sh" --test
if ! grep -qx "$TMPDIR/Xcode_16.4.app/Contents/Developer|4" "$FAKE_SUITE_LOG"; then
  fail "Swift suite did not inherit the selected toolchain and four worker default"
fi

"$TMPDIR/macos/scripts/run-swift-ci.sh" --release-compile
if ! grep -q -- 'swift build -c release --package-path Desktop --triple arm64-apple-macosx' "$FAKE_XCRUN_LOG"; then
  fail "release compile did not use the CI release command"
fi

"$TMPDIR/macos/scripts/run-swift-ci.sh" --release-notification-regression
if ! grep -qx '1|swift test -c release --package-path Desktop --filter UserNotificationCallbackBridgeTests/' "$FAKE_RELEASE_LOG"; then
  fail "release notification check did not select its isolated release test graph"
fi
if FAKE_TEST_EXIT_CODE=42 "$TMPDIR/macos/scripts/run-swift-ci.sh" --release-notification-regression; then
  fail "release notification check hid a failed Swift test"
else
  status=$?
  [ "$status" -eq 42 ] || fail "release notification check lost the Swift failure status: $status"
fi

if FAKE_XCODE_VERSION=16.5 "$TMPDIR/macos/scripts/run-swift-ci.sh" --select-toolchain >"$TMPDIR/wrong-version.out" 2>&1; then
  fail "runner accepted an Xcode version other than the pinned CI version"
fi
if ! grep -q 'expected Xcode 16.4' "$TMPDIR/wrong-version.out"; then
  fail "wrong Xcode version did not produce an actionable error"
fi

# Exercise SwiftPM's actual manifest, not source-string matching. This runs in
# the existing macOS launcher lane; Linux can still exercise the runner above.
# Incident: PR #71 job 101276183481 compiled debug-only suites for a release filter.
if [ "$(uname -s)" = Darwin ]; then
  env -u OMI_NOTIFICATION_RELEASE_TESTS_ONLY /usr/bin/xcrun swift package --package-path "$PACKAGE_PATH" dump-package >"$TMPDIR/default-package.json"
  OMI_NOTIFICATION_RELEASE_TESTS_ONLY=1 /usr/bin/xcrun swift package --package-path "$PACKAGE_PATH" dump-package >"$TMPDIR/release-package.json"
  env -u OMI_NOTIFICATION_RELEASE_TESTS_ONLY /usr/bin/xcrun swift package --package-path "$PACKAGE_PATH" dump-package >"$TMPDIR/restored-package.json"
  python3 - "$TMPDIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
normal = json.loads((root / "default-package.json").read_text())
release = json.loads((root / "release-package.json").read_text())
restored = json.loads((root / "restored-package.json").read_text())
normal_tests = {t["name"]: t for t in normal["targets"] if t["type"] == "test"}
release_tests = {t["name"]: t for t in release["targets"] if t["type"] == "test"}
assert set(normal_tests) == {
    "Omi ComputerTests", "OmiSupportTests", "VoiceTurnDomainTests",
    "SemanticFeatureSentinels", "UserNotificationCallbackTests",
}, normal_tests.keys()
assert set(release_tests) == {"UserNotificationCallbackTests"}, release_tests.keys()
assert release_tests["UserNotificationCallbackTests"] == normal_tests["UserNotificationCallbackTests"]
normal["targets"] = [t for t in normal["targets"] if t["type"] != "test"]
release["targets"] = [t for t in release["targets"] if t["type"] != "test"]
assert normal == release, "release test selection must not change production targets, dependencies, or compiler flags"
assert restored == json.loads((root / "default-package.json").read_text()), "release selection leaked into normal testing"
print("release notification package isolation passed")
PY
fi

echo "run-swift-ci tests passed"
