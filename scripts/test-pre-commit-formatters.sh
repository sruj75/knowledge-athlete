#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/intentive-pre-commit.XXXXXX")"
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

fixture="$TMP_ROOT/repo"
bin_dir="$TMP_ROOT/bin"
mkdir -p "$fixture/scripts" "$fixture/backend/scripts" "$bin_dir"
git init -q "$fixture"
cp "$ROOT/scripts/pre-commit" "$fixture/scripts/pre-commit"
chmod +x "$fixture/scripts/pre-commit"

cat >"$fixture/backend/scripts/black-wrapper.sh" <<'SH'
#!/usr/bin/env bash
printf 'repo-wrapper %s\n' "$*" >>"${FORMATTER_LOG:?}"
if [[ "${FORMATTER_FAIL:-0}" == "1" ]]; then
  exit 94
fi
SH
chmod +x "$fixture/backend/scripts/black-wrapper.sh"

cat >"$bin_dir/black" <<'SH'
#!/usr/bin/env bash
printf 'ambient-black %s\n' "$*" >>"${FORMATTER_LOG:?}"
exit 93
SH
chmod +x "$bin_dir/black"

printf 'x=  1\n' >"$fixture/backend/example.py"
git -C "$fixture" add backend/example.py
: >"$TMP_ROOT/formatter.log"
(
  cd "$fixture"
  FORMATTER_LOG="$TMP_ROOT/formatter.log" PATH="$bin_dir:$PATH" scripts/pre-commit
) || fail "pre-commit did not use the repository formatter wrapper"

grep -Fq 'repo-wrapper --line-length 120 --skip-string-normalization backend/example.py' \
  "$TMP_ROOT/formatter.log" || fail "repository formatter wrapper did not receive the staged backend file"
if grep -Fq 'ambient-black' "$TMP_ROOT/formatter.log"; then
  fail "pre-commit invoked ambient Black"
fi

if (
  cd "$fixture"
  FORMATTER_FAIL=1 FORMATTER_LOG="$TMP_ROOT/formatter.log" PATH="$bin_dir:$PATH" scripts/pre-commit >/dev/null 2>&1
); then
  fail "pre-commit ignored a repository formatter failure"
fi

test -x "$ROOT/backend/scripts/black-wrapper.sh" || fail "checked-in Black wrapper is missing"
test -s "$ROOT/backend/.black-version" || fail "checked-in Black version is missing"

cat >"$bin_dir/uvx" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >"${UVX_LOG:?}"
SH
chmod +x "$bin_dir/uvx"
UVX_LOG="$TMP_ROOT/uvx.log" PATH="$bin_dir:$PATH" \
  "$ROOT/backend/scripts/black-wrapper.sh" --check backend/example.py
expected="--from black==$(tr -d '[:space:]' <"$ROOT/backend/.black-version") black --check backend/example.py"
actual="$(cat "$TMP_ROOT/uvx.log")"
[[ "$actual" == "$expected" ]] || fail "Black wrapper invocation drifted: $actual"

grep -Fq 'entry: backend/scripts/black-wrapper.sh --line-length=120 --skip-string-normalization' \
  "$ROOT/.pre-commit-config.yaml" || fail "optional lint suite does not use the repository Black wrapper"
if grep -Fq 'repo: https://github.com/psf/black' "$ROOT/.pre-commit-config.yaml"; then
  fail "optional lint suite maintains a second Black installation/version owner"
fi
if grep -Fq 'pre-commit install' "$ROOT/.pre-commit-config.yaml" "$ROOT/.github/scripts/run-lint.sh"; then
  fail "optional lint documentation can overwrite the repository Git-hook dispatcher"
fi
if grep -Eq '(^|[[:space:]])black[[:space:]]+--' "$ROOT/.github/scripts/run-lint.sh"; then
  fail "manual lint runner invokes ambient Black"
fi
grep -Fq 'scripts/black-wrapper.sh --version' "$ROOT/backend/test-preflight.sh" \
  || fail "backend preflight still probes ambient Black instead of the repository wrapper"

echo "pre-commit formatter ownership tests passed"
