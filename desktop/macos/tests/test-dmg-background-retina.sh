#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="$SCRIPT_DIR/../dmg-assets"

dimension() {
  sips -g "$2" "$1" | awk -F ': ' -v property="$2" '$1 ~ property { print $2 }'
}

assert_dimensions() {
  local image="$1"
  local expected_width="$2"
  local expected_height="$3"
  local actual_width
  local actual_height
  actual_width="$(dimension "$image" pixelWidth)"
  actual_height="$(dimension "$image" pixelHeight)"

  [[ "$actual_width" == "$expected_width" ]] || {
    echo "Expected $image to be ${expected_width}px wide, got ${actual_width}px" >&2
    exit 1
  }
  [[ "$actual_height" == "$expected_height" ]] || {
    echo "Expected $image to be ${expected_height}px high, got ${actual_height}px" >&2
    exit 1
  }
}

assert_dimensions "$ASSETS_DIR/background.png" 652 381
assert_dimensions "$ASSETS_DIR/background@2x.png" 1304 762

# dmgbuild discovers this exact @2x filename and combines both images into the
# Finder background it places in the DMG.
grep -Fq 'background = bg_path' "$ASSETS_DIR/dmgbuild_settings.py"
grep -Fq 'window_rect = ((200, 120), (652, 381))' "$ASSETS_DIR/dmgbuild_settings.py"
grep -Fq 'icon_size = 112' "$ASSETS_DIR/dmgbuild_settings.py"
grep -Fq 'app_name + ".app": (198, 190)' "$ASSETS_DIR/dmgbuild_settings.py"
grep -Fq '"Applications": (474, 190)' "$ASSETS_DIR/dmgbuild_settings.py"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/omi-dmg-background.XXXXXX")"
compiled_background="$temporary_directory/background.tiff"
trap 'rm -rf "$temporary_directory"' EXIT
tiffutil -cathidpicheck "$ASSETS_DIR/background.png" "$ASSETS_DIR/background@2x.png" -out "$compiled_background"
compiled_info="$(tiffutil -info "$compiled_background")"
grep -Fq 'Image Width: 652 Image Length: 381' <<<"$compiled_info"
grep -Fq 'Image Width: 1304 Image Length: 762' <<<"$compiled_info"

echo "DMG background contains matched 1x and 2x Finder assets"
