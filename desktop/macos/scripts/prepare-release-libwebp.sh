#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_SOURCE_DIR="$MACOS_ROOT/vendor/libwebp"
SOURCE_DIR="$DEFAULT_SOURCE_DIR"
DESTINATION=""
APP_EXECUTABLE=""
SIGNING_IDENTITY=""
VERIFY_ONLY=false
ALLOW_ADHOC_SIGNING_FOR_TESTS=false
APP_DEPLOYMENT_TARGET="14.0"
REBUILD_DIR=""

readonly WEBP_VERSION="1.5.0"
readonly WEBP_SHA256="3515af9fc46957cbd3f879ee36b9bbc0283cf6e2bbd51032a943ec8a9e64b2ff"
readonly SHARPYUV_SHA256="5a92b18c7deee56b134d1079712e41e77d151584c20e894a3a9c176e9f9ed119"

usage() {
  cat <<'USAGE'
Usage: prepare-release-libwebp.sh [options]

Verify the pinned universal libwebp cache, rebuild it from pinned source only
when the cache is unavailable or invalid, and prepare signed nested dylibs for
a macOS release bundle.

Options:
  --source-dir DIR          Cache to verify (default: vendor/libwebp)
  --destination DIR         Bundle Frameworks directory to receive the dylibs
  --app-executable PATH     Universal candidate executable whose libwebp load path is prepared
  --signing-identity VALUE  Candidate Developer ID codesign identity
  --allow-adhoc-signing-for-tests
                            Permit '-' only in a hermetic test fixture
  --verify-only             Verify cache/fallback without copying or signing
  --app-deployment-target V Maximum permitted dylib deployment target (default: 14.0)
USAGE
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$REBUILD_DIR" ]]; then
    case "$REBUILD_DIR" in
      "${TMPDIR:-/tmp}/knowledge-athlete-libwebp-rebuild."*) rm -rf -- "$REBUILD_DIR" ;;
      *) echo "Refusing unsafe cleanup path: $REBUILD_DIR" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source-dir)
      [[ $# -ge 2 ]] || fail "--source-dir requires a value"
      SOURCE_DIR="$2"
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || fail "--destination requires a value"
      DESTINATION="$2"
      shift 2
      ;;
    --app-executable)
      [[ $# -ge 2 ]] || fail "--app-executable requires a value"
      APP_EXECUTABLE="$2"
      shift 2
      ;;
    --signing-identity)
      [[ $# -ge 2 ]] || fail "--signing-identity requires a value"
      SIGNING_IDENTITY="$2"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY=true
      shift
      ;;
    --allow-adhoc-signing-for-tests)
      ALLOW_ADHOC_SIGNING_FOR_TESTS=true
      shift
      ;;
    --app-deployment-target)
      [[ $# -ge 2 ]] || fail "--app-deployment-target requires a value"
      APP_DEPLOYMENT_TARGET="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

for tool in shasum lipo otool install_name_tool codesign; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool is unavailable: $tool"
done

expected_checksum() {
  case "$1" in
    libwebp.7.dylib) printf '%s\n' "$WEBP_SHA256" ;;
    libsharpyuv.0.dylib) printf '%s\n' "$SHARPYUV_SHA256" ;;
    *) return 1 ;;
  esac
}

validate_architectures() {
  local path="$1"
  local archs
  archs="$(lipo -archs "$path" 2>/dev/null)" || {
    echo "Invalid Mach-O or unreadable architectures: $path" >&2
    return 1
  }
  local count=0
  local saw_arm64=false
  local saw_x86_64=false
  local arch
  for arch in $archs; do
    count=$((count + 1))
    case "$arch" in
      arm64) saw_arm64=true ;;
      x86_64) saw_x86_64=true ;;
      *) echo "Unexpected architecture '$arch' in $path" >&2; return 1 ;;
    esac
  done
  [[ $count -eq 2 && "$saw_arm64" == true && "$saw_x86_64" == true ]] || {
    echo "Expected exactly arm64 and x86_64 in $path; found: $archs" >&2
    return 1
  }
}

validate_install_name() {
  local path="$1"
  local expected
  expected="@rpath/$(basename "$path")"
  local names
  names="$(otool -D "$path" 2>/dev/null | awk '/^[[:space:]]*@rpath\// {print $1}')" || return 1
  local count=0
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    count=$((count + 1))
    [[ "$name" == "$expected" ]] || {
      echo "Unexpected install name '$name' in $path; expected $expected" >&2
      return 1
    }
  done <<<"$names"
  [[ $count -eq 2 ]] || {
    echo "Expected install name $expected for both architectures in $path" >&2
    return 1
  }
}

validate_deployment_target() {
  local path="$1"
  local minos_values
  minos_values="$(otool -l "$path" 2>/dev/null | awk '$1 == "minos" {print $2}')" || return 1
  local count=0
  local minos
  while IFS= read -r minos; do
    [[ -n "$minos" ]] || continue
    count=$((count + 1))
    awk -v actual="$minos" -v maximum="$APP_DEPLOYMENT_TARGET" \
      'BEGIN { exit !((actual + 0) <= (maximum + 0)) }' || {
      echo "Deployment target $minos in $path exceeds app target $APP_DEPLOYMENT_TARGET" >&2
      return 1
    }
  done <<<"$minos_values"
  [[ $count -eq 2 ]] || {
    echo "Expected LC_BUILD_VERSION minos for both architectures in $path" >&2
    return 1
  }
}

validate_dependencies() {
  local path="$1"
  local basename
  basename="$(basename "$path")"
  local dependencies
  dependencies="$(otool -L "$path" 2>/dev/null | awk '/^[[:space:]]/ {print $1}')" || return 1
  local count=0
  local saw_self=false
  local saw_sharpyuv=false
  local saw_libsystem=false
  local dependency
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    count=$((count + 1))
    case "$basename:$dependency" in
      "libwebp.7.dylib:@rpath/libwebp.7.dylib") saw_self=true ;;
      "libwebp.7.dylib:@rpath/libsharpyuv.0.dylib") saw_sharpyuv=true ;;
      "libwebp.7.dylib:/usr/lib/libSystem.B.dylib") saw_libsystem=true ;;
      "libsharpyuv.0.dylib:@rpath/libsharpyuv.0.dylib") saw_self=true ;;
      "libsharpyuv.0.dylib:/usr/lib/libSystem.B.dylib") saw_libsystem=true ;;
      *)
        echo "Unexpected dependency '$dependency' in $path" >&2
        return 1
        ;;
    esac
  done <<<"$dependencies"

  if [[ "$basename" == "libwebp.7.dylib" ]]; then
    [[ $count -eq 6 && "$saw_self" == true && "$saw_sharpyuv" == true && "$saw_libsystem" == true ]] || {
      echo "Incomplete dependency closure in $path" >&2
      return 1
    }
  else
    [[ $count -eq 4 && "$saw_self" == true && "$saw_libsystem" == true ]] || {
      echo "Incomplete dependency closure in $path" >&2
      return 1
    }
  fi
}

validate_directory() {
  local directory="$1"
  local require_cache_checksums="$2"
  local name path expected actual
  for name in libwebp.7.dylib libsharpyuv.0.dylib; do
    path="$directory/$name"
    [[ -f "$path" ]] || {
      echo "Missing release library: $path" >&2
      return 1
    }
    if [[ "$require_cache_checksums" == true ]]; then
      expected="$(expected_checksum "$name")"
      actual="$(shasum -a 256 "$path" | awk '{print $1}')"
      [[ "$actual" == "$expected" ]] || {
        echo "Checksum mismatch for $path (libwebp $WEBP_VERSION)" >&2
        return 1
      }
    fi
    validate_architectures "$path" || return 1
    validate_install_name "$path" || return 1
    validate_deployment_target "$path" || return 1
    validate_dependencies "$path" || return 1
  done
}

app_webp_dependencies() {
  otool -L "$1" 2>/dev/null \
    | awk '/^[[:space:]]/ && $1 ~ /(^|\/)libwebp\.7\.dylib$/ {print $1}'
}

app_framework_rpaths() {
  otool -l "$1" 2>/dev/null \
    | awk '/cmd LC_RPATH/ {inside = 1; next} inside && $1 == "path" {print $2; inside = 0}'
}

prepare_app_executable() {
  local executable="$1"
  local bundled_webp="$2"
  [[ -f "$executable" ]] || fail "candidate app executable is missing: $executable"
  validate_architectures "$executable" \
    || fail "candidate app executable is not exactly arm64 + x86_64: $executable"

  local dependencies dependency count=0
  dependencies="$(app_webp_dependencies "$executable")" \
    || fail "could not inspect candidate app libwebp dependencies: $executable"
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    count=$((count + 1))
    case "$dependency" in
      @rpath/libwebp.7.dylib) ;;
      /opt/homebrew/opt/webp/lib/libwebp.7.dylib|/usr/local/opt/webp/lib/libwebp.7.dylib) ;;
      *) fail "unexpected candidate app libwebp dependency: $dependency" ;;
    esac
  done <<<"$dependencies"
  [[ $count -eq 2 ]] \
    || fail "candidate app must link libwebp.7.dylib exactly once per architecture"

  local arch required_line provided_line required_version provided_version
  for arch in arm64 x86_64; do
    required_line="$(otool -arch "$arch" -L "$executable" \
      | awk '$1 ~ /(^|\/)libwebp\.7\.dylib$/ {print; exit}')"
    provided_line="$(otool -arch "$arch" -L "$bundled_webp" \
      | awk '$1 ~ /(^|\/)libwebp\.7\.dylib$/ {print; exit}')"
    required_version="$(printf '%s\n' "$required_line" \
      | sed -E -n 's/.*compatibility version ([0-9.]+),.*/\1/p')"
    provided_version="$(printf '%s\n' "$provided_line" \
      | sed -E -n 's/.*compatibility version ([0-9.]+),.*/\1/p')"
    [[ -n "$required_version" && -n "$provided_version" ]] \
      || fail "could not inspect libwebp compatibility for candidate architecture $arch"
    awk -v required="$required_version" -v provided="$provided_version" '
      BEGIN {
        split(required, r, ".")
        split(provided, p, ".")
        for (i = 1; i <= 4; i += 1) {
          rv = r[i] + 0
          pv = p[i] + 0
          if (rv < pv) exit 0
          if (rv > pv) exit 1
        }
        exit 0
      }
    ' || fail "candidate $arch requires libwebp compatibility $required_version, but the pinned bundle provides $provided_version"
  done

  while IFS= read -r dependency; do
    [[ -n "$dependency" && "$dependency" != "@rpath/libwebp.7.dylib" ]] || continue
    install_name_tool -change "$dependency" @rpath/libwebp.7.dylib "$executable"
  done < <(printf '%s\n' "$dependencies" | sort -u)

  local framework_rpath_count
  framework_rpath_count="$(app_framework_rpaths "$executable" \
    | awk '$1 == "@executable_path/../Frameworks" {count += 1} END {print count + 0}')"
  case "$framework_rpath_count" in
    0) install_name_tool -add_rpath @executable_path/../Frameworks "$executable" ;;
    2) ;;
    *) fail "candidate app has an inconsistent Frameworks rpath across architectures" ;;
  esac

  dependencies="$(app_webp_dependencies "$executable")"
  count="$(printf '%s\n' "$dependencies" \
    | awk '$1 == "@rpath/libwebp.7.dylib" {count += 1} END {print count + 0}')"
  [[ "$count" -eq 2 ]] \
    || fail "candidate app libwebp dependency was not rewritten for both architectures"
  framework_rpath_count="$(app_framework_rpaths "$executable" \
    | awk '$1 == "@executable_path/../Frameworks" {count += 1} END {print count + 0}')"
  [[ "$framework_rpath_count" -eq 2 ]] \
    || fail "candidate app Frameworks rpath is missing from one or more architectures"
}

if [[ "$VERIFY_ONLY" != true ]]; then
  [[ -n "$DESTINATION" ]] || fail "--destination is required unless --verify-only is used"
  [[ -n "$APP_EXECUTABLE" ]] || fail "--app-executable is required unless --verify-only is used"
  [[ -n "$SIGNING_IDENTITY" ]] \
    || fail "--signing-identity is required for prepared release libraries"
  if [[ "$SIGNING_IDENTITY" == "-" && "$ALLOW_ADHOC_SIGNING_FOR_TESTS" != true ]]; then
    fail "ad hoc signing is test-only; supply the candidate Developer ID identity"
  fi
fi

SELECTED_SOURCE="$SOURCE_DIR"
if validate_directory "$SOURCE_DIR" true; then
  echo "Verified pinned libwebp $WEBP_VERSION release cache: $SOURCE_DIR"
else
  echo "Pinned libwebp cache is unavailable or invalid; invoking the pinned source rebuild" >&2
  REBUILD_HELPER="${LIBWEBP_REBUILD_HELPER:-$SCRIPT_DIR/rebuild-release-libwebp.sh}"
  [[ -x "$REBUILD_HELPER" ]] || fail "pinned rebuild helper is unavailable: $REBUILD_HELPER"
  REBUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-athlete-libwebp-rebuild.XXXXXX")"
  "$REBUILD_HELPER" --output-dir "$REBUILD_DIR"
  validate_directory "$REBUILD_DIR" false \
    || fail "pinned libwebp rebuild did not satisfy the release library contract"
  SELECTED_SOURCE="$REBUILD_DIR"
  echo "Verified pinned libwebp $WEBP_VERSION source rebuild"
fi

if [[ "$VERIFY_ONLY" == true ]]; then
  exit 0
fi

prepare_app_executable "$APP_EXECUTABLE" "$SELECTED_SOURCE/libwebp.7.dylib"
mkdir -p "$DESTINATION"

for name in libsharpyuv.0.dylib libwebp.7.dylib; do
  cp "$SELECTED_SOURCE/$name" "$DESTINATION/$name"
  chmod 755 "$DESTINATION/$name"
  if [[ "$SIGNING_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$DESTINATION/$name"
  else
    codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$DESTINATION/$name"
  fi
  codesign --verify --strict --verbose=2 "$DESTINATION/$name"
done

validate_directory "$DESTINATION" false \
  || fail "signed release libraries no longer satisfy the structural contract"
echo "Prepared and signed libwebp $WEBP_VERSION release libraries in $DESTINATION"
