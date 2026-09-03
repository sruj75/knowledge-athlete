#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/source-provenance.sh
source "$SCRIPT_DIR/../scripts/source-provenance.sh"

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/intentive-source-provenance.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

repo="$TMP_ROOT/repo"
bundle="$TMP_ROOT/omi-provenance.app"
mkdir -p "$repo" "$bundle/Contents"
git -C "$repo" init -q
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name 'Source Provenance Test'
printf 'compiled input\n' >"$repo/source.txt"
git -C "$repo" add source.txt
git -C "$repo" commit -qm fixture
/usr/libexec/PlistBuddy -c 'Clear dict' "$bundle/Contents/Info.plist"

intentive_stamp_source_provenance "$repo" "$bundle"
expected_sha="$(git -C "$repo" rev-parse HEAD)"
actual_sha="$(/usr/libexec/PlistBuddy -c 'Print :IntentiveSourceGitSHA' "$bundle/Contents/Info.plist")"
actual_dirty="$(/usr/libexec/PlistBuddy -c 'Print :IntentiveSourceTreeDirty' "$bundle/Contents/Info.plist")"
[[ "$actual_sha" == "$expected_sha" ]] || { echo "source SHA was not stamped" >&2; exit 1; }
[[ "$actual_dirty" == false ]] || { echo "clean source was stamped dirty" >&2; exit 1; }

printf 'uncommitted input\n' >>"$repo/source.txt"
intentive_stamp_source_provenance "$repo" "$bundle"
actual_dirty="$(/usr/libexec/PlistBuddy -c 'Print :IntentiveSourceTreeDirty' "$bundle/Contents/Info.plist")"
[[ "$actual_dirty" == true ]] || { echo "dirty source was stamped clean" >&2; exit 1; }

if intentive_stamp_source_provenance "$TMP_ROOT/not-a-repository" "$bundle" 2>/dev/null; then
  echo "non-repository source unexpectedly produced provenance" >&2
  exit 1
fi

echo "source provenance tests passed"
