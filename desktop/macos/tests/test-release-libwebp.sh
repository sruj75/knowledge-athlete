#!/usr/bin/env bash
# Mutation snippets are single-quoted so generated helpers expand their variables.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/prepare-release-libwebp.sh"
VENDOR="$ROOT/vendor/libwebp"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-athlete-release-libwebp.XXXXXX")"

cleanup() {
  case "$TMP_ROOT" in
    "${TMPDIR:-/tmp}/knowledge-athlete-release-libwebp."*) rm -rf -- "$TMP_ROOT" ;;
    *) echo "Refusing unsafe cleanup path: $TMP_ROOT" >&2 ;;
  esac
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$TMP_ROOT/$label.stdout" 2>"$TMP_ROOT/$label.stderr"; then
    fail "$label unexpectedly passed"
  fi
}

make_helper() {
  local name="$1"
  local mutation="$2"
  local helper="$TMP_ROOT/$name.sh"
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf '%s\n' 'test "$1" = "--output-dir"' 'output_dir="$2"' 'mkdir -p "$output_dir"'
    printf 'cp %q/libwebp.7.dylib "$output_dir/libwebp.7.dylib"\n' "$VENDOR"
    printf 'cp %q/libsharpyuv.0.dylib "$output_dir/libsharpyuv.0.dylib"\n' "$VENDOR"
    printf '%s\n' 'test -z "${TEST_FALLBACK_MARKER:-}" || : > "$TEST_FALLBACK_MARKER"'
    printf '%s\n' "$mutation"
  } >"$helper"
  chmod +x "$helper"
  printf '%s\n' "$helper"
}

make_universal_app_fixture() {
  local output="$1"
  local compatibility_version="$2"
  local fixture_dir="$TMP_ROOT/app-fixture-$compatibility_version"
  mkdir -p "$fixture_dir"
  printf '%s\n' \
    'extern int WebPGetEncoderVersion(void);' \
    'int main(void) { return WebPGetEncoderVersion() == 0; }' \
    >"$fixture_dir/main.c"
  printf '%s\n' 'int WebPGetEncoderVersion(void) { return 1; }' >"$fixture_dir/webp.c"

  local arch thin_webp absolute_webp
  for arch in arm64 x86_64; do
    thin_webp="$fixture_dir/libwebp-$arch.dylib"
    absolute_webp="/opt/homebrew/opt/webp/lib/libwebp.7.dylib"
    clang -dynamiclib -arch "$arch" -mmacosx-version-min=14.0 \
      -install_name "$absolute_webp" \
      -compatibility_version "$compatibility_version" \
      -current_version "$compatibility_version" \
      "$fixture_dir/webp.c" -o "$thin_webp"
    clang -arch "$arch" -mmacosx-version-min=14.0 \
      "$fixture_dir/main.c" "$thin_webp" \
      -o "$fixture_dir/app-$arch"
  done
  lipo -create "$fixture_dir/app-arm64" "$fixture_dir/app-x86_64" -output "$output"
}

test -x "$SCRIPT" || fail "release libwebp preparation script is missing or not executable"

"$SCRIPT" --verify-only

corrupt_cache="$TMP_ROOT/corrupt-cache"
mkdir -p "$corrupt_cache"
cp "$VENDOR/libwebp.7.dylib" "$corrupt_cache/libwebp.7.dylib"
cp "$VENDOR/libsharpyuv.0.dylib" "$corrupt_cache/libsharpyuv.0.dylib"
printf 'corrupt' >>"$corrupt_cache/libwebp.7.dylib"
expect_failure corrupt-cache env LIBWEBP_REBUILD_HELPER="$TMP_ROOT/missing-helper" \
  "$SCRIPT" --source-dir "$corrupt_cache" --verify-only

good_helper="$(make_helper good ':')"
fallback_marker="$TMP_ROOT/fallback-invoked"
TEST_FALLBACK_MARKER="$fallback_marker" LIBWEBP_REBUILD_HELPER="$good_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-cache" --verify-only
test -f "$fallback_marker" || fail "missing cache did not invoke the pinned rebuild helper"

wrong_arch_helper="$(make_helper wrong-arch \
  'lipo "$output_dir/libwebp.7.dylib" -thin arm64 -output "$output_dir/libwebp-thin.dylib" && mv "$output_dir/libwebp-thin.dylib" "$output_dir/libwebp.7.dylib"')"
expect_failure wrong-arch env LIBWEBP_REBUILD_HELPER="$wrong_arch_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-arch-cache" --verify-only

wrong_id_helper="$(make_helper wrong-id \
  'install_name_tool -id /tmp/libwebp.7.dylib "$output_dir/libwebp.7.dylib"')"
expect_failure wrong-install-name env LIBWEBP_REBUILD_HELPER="$wrong_id_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-id-cache" --verify-only

wrong_minos_helper="$(make_helper wrong-minos \
  'vtool -set-build-version macos 26.0 26.0 -replace -output "$output_dir/libwebp-new.dylib" "$output_dir/libwebp.7.dylib" && mv "$output_dir/libwebp-new.dylib" "$output_dir/libwebp.7.dylib"')"
expect_failure wrong-minos env LIBWEBP_REBUILD_HELPER="$wrong_minos_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-minos-cache" --verify-only

wrong_dependency_helper="$(make_helper wrong-dependency \
  'install_name_tool -change /usr/lib/libSystem.B.dylib @rpath/libmissing.dylib "$output_dir/libwebp.7.dylib"')"
expect_failure wrong-dependency env LIBWEBP_REBUILD_HELPER="$wrong_dependency_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-dependency-cache" --verify-only

missing_dependency_helper="$(make_helper missing-dependency \
  'install_name_tool -change @rpath/libsharpyuv.0.dylib /usr/lib/libSystem.B.dylib "$output_dir/libwebp.7.dylib"')"
expect_failure missing-dependency env LIBWEBP_REBUILD_HELPER="$missing_dependency_helper" \
  "$SCRIPT" --source-dir "$TMP_ROOT/missing-dependency-closure-cache" --verify-only

destination="$TMP_ROOT/Frameworks"
app_executable="$TMP_ROOT/TestApp"
make_universal_app_fixture "$app_executable" 9.0.0
incompatible_app_executable="$TMP_ROOT/IncompatibleTestApp"
make_universal_app_fixture "$incompatible_app_executable" 10.0.0
expect_failure incompatible-app-libwebp \
  "$SCRIPT" --destination "$TMP_ROOT/incompatible-frameworks" \
  --app-executable "$incompatible_app_executable" --signing-identity - \
  --allow-adhoc-signing-for-tests
expect_failure unguarded-adhoc-signing \
  "$SCRIPT" --destination "$destination" --app-executable "$app_executable" --signing-identity -
"$SCRIPT" --destination "$destination" --app-executable "$app_executable" \
  --signing-identity - --allow-adhoc-signing-for-tests
for name in libwebp.7.dylib libsharpyuv.0.dylib; do
  test -f "$destination/$name" || fail "prepared destination is missing $name"
  codesign --verify --strict "$destination/$name"
done
test "$(otool -L "$app_executable" | awk '$1 == "@rpath/libwebp.7.dylib" {count += 1} END {print count + 0}')" -eq 2 \
  || fail "prepared app executable does not use the bundled libwebp for both architectures"
test "$(otool -l "$app_executable" | awk '/cmd LC_RPATH/ {inside = 1; next} inside && $1 == "path" && $2 == "@executable_path/../Frameworks" {count += 1; inside = 0} END {print count + 0}')" -eq 2 \
  || fail "prepared app executable is missing the bundle Frameworks rpath"

echo "PASS: release libwebp cache, fallback, app linkage, copy, and signing contracts"
