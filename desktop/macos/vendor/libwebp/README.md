# Vendored universal libwebp dylibs

`libwebp.7.dylib` and `libsharpyuv.0.dylib` here are **universal (arm64 + x86_64)**
builds of [libwebp](https://chromium.googlesource.com/webm/libwebp) **1.5.0**.

## Why they are committed

These dylibs are protected inputs for the Mac release lane. A universal app needs universal
`libwebp.7.dylib` + `libsharpyuv.0.dylib`; an arm64-only package-manager copy
breaks the x86_64 cross-compile link step.

Previously the "Prepare universal libwebp" step compiled libwebp **from source for
both arches on every release run** (~several minutes each run). These prebuilt
dylibs are vendored so the release step can copy them. The checked-in
`scripts/prepare-release-libwebp.sh` consumer verifies and signs the cache, and
falls back only to `scripts/rebuild-release-libwebp.sh`. Local `run.sh` builds
continue using Homebrew/pkg-config and do not consume this cache.

## Pinned provenance

| Artifact | SHA-256 |
|---|---|
| `libwebp.7.dylib` | `3515af9fc46957cbd3f879ee36b9bbc0283cf6e2bbd51032a943ec8a9e64b2ff` |
| `libsharpyuv.0.dylib` | `5a92b18c7deee56b134d1079712e41e77d151584c20e894a3a9c176e9f9ed119` |
| upstream `libwebp-1.5.0.tar.gz` | `7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c` |

The preparation script also requires exactly `arm64` + `x86_64`, the two exact
`@rpath` install names, a deployment floor no newer than the app's macOS 14
target, and the closed `libSystem`/`libsharpyuv` dependency graph. It copies and
signs `libsharpyuv` before `libwebp`, then verifies both nested signatures and
rechecks the structural contract before the outer app is signed. Release use
also requires `--app-executable`: the script accepts only the known Homebrew
libwebp load paths (or the final `@rpath` form), rewrites them to the bundled
library, and verifies `@executable_path/../Frameworks` for both architectures.
It also fails before rewriting when an executable was linked against a newer,
ABI-incompatible libwebp than the pinned bundle provides; the provider must link
the candidate against this pinned release input.
Ad hoc signing requires the explicit hermetic-test-only flag and cannot be used
by a candidate lane accidentally.

## How to rebuild

The authoritative executable form of this recipe is:

```sh
desktop/macos/scripts/rebuild-release-libwebp.sh --output-dir /path/to/output
```

It verifies the pinned upstream archive checksum before compiling. The expanded
recipe below documents the same inputs and target flags:

```sh
WEBP_VERSION="1.5.0"
SOURCE_SHA256="7d6fab70cf844bf6769077bd5d7a74893f8ffd4dfb42861745750c63c2a5c92c"
TEMP_DIR="$(mktemp -d)"
# version-min flags pin LC_BUILD_VERSION minos to 13.0; CMAKE_OSX_DEPLOYMENT_TARGET
# alone does NOT stick on newer SDKs (they stamp the SDK version, e.g. 26.0, which
# would refuse to load on older macOS). Verify with: otool -l <dylib> | grep -A3 LC_BUILD_VERSION
export MACOSX_DEPLOYMENT_TARGET=13.0
CMAKE_COMMON="-DBUILD_SHARED_LIBS=ON -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
  -DCMAKE_C_FLAGS=-mmacosx-version-min=13.0 \
  -DCMAKE_SHARED_LINKER_FLAGS=-mmacosx-version-min=13.0 \
  -DWEBP_BUILD_EXTRAS=OFF -DWEBP_BUILD_ANIM_UTILS=OFF \
  -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF \
  -DWEBP_BUILD_VWEBP=OFF -DWEBP_BUILD_WEBPINFO=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF"
ARCHIVE="$TEMP_DIR/libwebp-$WEBP_VERSION.tar.gz"
curl -fsSL "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz" -o "$ARCHIVE"
test "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" = "$SOURCE_SHA256"
tar xzf "$ARCHIVE" -C "$TEMP_DIR"
SRC="$TEMP_DIR/libwebp-$WEBP_VERSION"

mkdir "$SRC/build-arm64"  && (cd "$SRC/build-arm64"  && cmake .. -DCMAKE_OSX_ARCHITECTURES=arm64  $CMAKE_COMMON && make -j webp sharpyuv)
mkdir "$SRC/build-x86_64" && (cd "$SRC/build-x86_64" && cmake .. -DCMAKE_OSX_ARCHITECTURES=x86_64 $CMAKE_COMMON && make -j webp sharpyuv)

lipo -create \
  "$(find "$SRC/build-arm64"  -name 'libwebp.7.*.dylib'    -not -type l | head -1)" \
  "$(find "$SRC/build-x86_64" -name 'libwebp.7.*.dylib'    -not -type l | head -1)" \
  -output libwebp.7.dylib
lipo -create \
  "$(find "$SRC/build-arm64"  -name 'libsharpyuv.0.*.dylib' -not -type l | head -1)" \
  "$(find "$SRC/build-x86_64" -name 'libsharpyuv.0.*.dylib' -not -type l | head -1)" \
  -output libsharpyuv.0.dylib
```

Verify with `lipo -info libwebp.7.dylib` (expect `x86_64 arm64`). Both dylibs use
`@rpath` install names, identical to a fresh from-source build.

**When bumping the libwebp version**, rebuild both files, update all three
checksums above and the two release scripts, then run:

```sh
bash desktop/macos/tests/test-release-libwebp.sh
```
