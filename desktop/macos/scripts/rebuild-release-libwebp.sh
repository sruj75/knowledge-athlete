#!/usr/bin/env bash
set -euo pipefail

readonly WEBP_VERSION="1.5.0"
readonly SOURCE_SHA256="7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c"
readonly SOURCE_URL="https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz"
OUTPUT_DIR=""
BUILD_ROOT=""

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

cleanup() {
  if [[ -n "$BUILD_ROOT" ]]; then
    case "$BUILD_ROOT" in
      "${TMPDIR:-/tmp}/knowledge-athlete-libwebp-source."*) rm -rf -- "$BUILD_ROOT" ;;
      *) echo "Refusing unsafe cleanup path: $BUILD_ROOT" >&2 ;;
    esac
  fi
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      [[ $# -ge 2 ]] || fail "--output-dir requires a value"
      OUTPUT_DIR="$2"
      shift 2
      ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$OUTPUT_DIR" ]] || fail "--output-dir is required"
for tool in curl shasum tar cmake lipo find install_name_tool otool; do
  command -v "$tool" >/dev/null 2>&1 || fail "required rebuild tool is unavailable: $tool"
done

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/knowledge-athlete-libwebp-source.XXXXXX")"
ARCHIVE="$BUILD_ROOT/libwebp-$WEBP_VERSION.tar.gz"
curl --fail --location --silent --show-error "$SOURCE_URL" --output "$ARCHIVE"
ACTUAL_SOURCE_SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL_SOURCE_SHA256" == "$SOURCE_SHA256" ]] \
  || fail "libwebp $WEBP_VERSION source archive checksum mismatch"

tar -xzf "$ARCHIVE" -C "$BUILD_ROOT"
SOURCE_ROOT="$BUILD_ROOT/libwebp-$WEBP_VERSION"
[[ -d "$SOURCE_ROOT" ]] || fail "source archive did not contain libwebp-$WEBP_VERSION"

export MACOSX_DEPLOYMENT_TARGET=13.0
for arch in arm64 x86_64; do
  build_dir="$SOURCE_ROOT/build-$arch"
  cmake -S "$SOURCE_ROOT" -B "$build_dir" \
    -DBUILD_SHARED_LIBS=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DCMAKE_C_FLAGS=-mmacosx-version-min=13.0 \
    -DCMAKE_SHARED_LINKER_FLAGS=-mmacosx-version-min=13.0 \
    -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_ANIM_UTILS=OFF \
    -DWEBP_BUILD_CWEBP=OFF \
    -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF \
    -DWEBP_BUILD_IMG2WEBP=OFF \
    -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF \
    -DWEBP_BUILD_WEBPMUX=OFF
  cmake --build "$build_dir" --config Release --target webp sharpyuv --parallel
done

find_library() {
  local arch="$1"
  local pattern="$2"
  local match
  match="$(find "$SOURCE_ROOT/build-$arch" -name "$pattern" -not -type l -print | head -1)"
  [[ -n "$match" ]] || fail "rebuilt library is missing for $arch: $pattern"
  printf '%s\n' "$match"
}

mkdir -p "$OUTPUT_DIR"
lipo -create \
  "$(find_library arm64 'libwebp.7.*.dylib')" \
  "$(find_library x86_64 'libwebp.7.*.dylib')" \
  -output "$OUTPUT_DIR/libwebp.7.dylib"
lipo -create \
  "$(find_library arm64 'libsharpyuv.0.*.dylib')" \
  "$(find_library x86_64 'libsharpyuv.0.*.dylib')" \
  -output "$OUTPUT_DIR/libsharpyuv.0.dylib"

install_name_tool -id @rpath/libwebp.7.dylib "$OUTPUT_DIR/libwebp.7.dylib"
install_name_tool -id @rpath/libsharpyuv.0.dylib "$OUTPUT_DIR/libsharpyuv.0.dylib"
while IFS= read -r dependency; do
  [[ -n "$dependency" ]] || continue
  case "$dependency" in
    @rpath/libsharpyuv.0.dylib) ;;
    *libsharpyuv*.dylib)
      install_name_tool -change "$dependency" @rpath/libsharpyuv.0.dylib \
        "$OUTPUT_DIR/libwebp.7.dylib"
      ;;
  esac
done < <(otool -L "$OUTPUT_DIR/libwebp.7.dylib" | awk '/^[[:space:]]/ {print $1}')

echo "Rebuilt pinned universal libwebp $WEBP_VERSION in $OUTPUT_DIR"
