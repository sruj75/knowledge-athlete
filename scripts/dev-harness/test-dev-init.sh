#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/intentive-dev-init.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

fixture="$TMP_ROOT/repo"
bin_dir="$TMP_ROOT/bin"
mkdir -p \
  "$fixture/scripts/dev-harness" \
  "$fixture/backend/.venv/bin" \
  "$fixture/backend" \
  "$fixture/.git/hooks" \
  "$bin_dir"
cp "$ROOT/scripts/dev-harness/dev-init.sh" "$fixture/scripts/dev-harness/dev-init.sh"
cp "$ROOT/scripts/dev-harness/_resolve_python.sh" "$fixture/scripts/dev-harness/_resolve_python.sh"
cp "$ROOT/scripts/dev-instance.sh" "$fixture/scripts/dev-instance.sh"
chmod +x "$fixture/scripts/dev-harness/dev-init.sh"
printf 'PROVIDER_KEY=replace-me\n' >"$fixture/backend/.env.local-dev.template"

cat >"$bin_dir/make" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == "setup" ]] || { echo "unexpected make invocation: $*" >&2; exit 91; }
printf 'make setup\n' >>"${DEV_INIT_LOG:?}"
SH
chmod +x "$bin_dir/make"

cat >"$fixture/backend/.venv/bin/python" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == "-m dev_harness.synthetic_profiles init" ]]; then
  printf 'profiles init instance=%s backend=%s\n' \
    "${OMI_LOCAL_INSTANCE:-missing}" "${OMI_HARNESS_BACKEND_PORT:-missing}" >>"${DEV_INIT_LOG:?}"
  exit 0
fi
printf 'legacy python %s\n' "$*" >>"${DEV_INIT_LOG:?}"
exit 0
SH
chmod +x "$fixture/backend/.venv/bin/python"

: >"$TMP_ROOT/dev-init.log"
(
  cd "$fixture"
  CONDUCTOR_IS_LOCAL=1 CONDUCTOR_PORT=55000 OMI_INSTANCE=workspace-alpha \
    DEV_INIT_LOG="$TMP_ROOT/dev-init.log" PATH="$bin_dir:$PATH" scripts/dev-harness/dev-init.sh >/dev/null
) || fail "dev-init failed in the hermetic fixture"

expected=$'make setup\nprofiles init instance=workspace-alpha backend=55000'
actual="$(cat "$TMP_ROOT/dev-init.log")"
[[ "$actual" == "$expected" ]] || {
  printf 'FAIL: dev-init must delegate environment and hook ownership to make setup.\nExpected:\n%s\nActual:\n%s\n' \
    "$expected" "$actual" >&2
  exit 1
}

[[ -f "$fixture/backend/.env.local-dev" ]] || fail "dev-init did not create the local secrets file"
[[ ! -e "$fixture/.git/hooks/pre-commit" ]] || fail "dev-init wrote a Git hook instead of delegating to make setup"

echo "dev-init setup ownership test passed"
