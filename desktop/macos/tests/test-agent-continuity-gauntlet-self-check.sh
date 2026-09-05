#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../scripts/agent-continuity-gauntlet-self-check.sh"
LIB="$SCRIPT_DIR/../scripts/agent-continuity-gauntlet-lib.py"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

AGENT_DIR="$TEST_ROOT/agent"
BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$AGENT_DIR" "$BIN_DIR"
printf '{}\n' >"$AGENT_DIR/package-lock.json"
printf '# self-check fixture\n' >"$TEST_ROOT/gauntlet.py"

cat >"$BIN_DIR/npm" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${OMI_TEST_NPM_LOG:?}"
mkdir -p "${OMI_TEST_AGENT_DIR:?}/node_modules/.bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$OMI_TEST_AGENT_DIR/node_modules/.bin/vitest"
chmod +x "$OMI_TEST_AGENT_DIR/node_modules/.bin/vitest"
SH

cat >"$BIN_DIR/python3" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${OMI_TEST_PYTHON_LOG:?}"
SH
chmod +x "$BIN_DIR/npm" "$BIN_DIR/python3"

run_fixture() {
  PATH="$BIN_DIR:$PATH" \
    OMI_GAUNTLET_AGENT_DIR="$AGENT_DIR" \
    OMI_GAUNTLET_LIB="$TEST_ROOT/gauntlet.py" \
    OMI_TEST_AGENT_DIR="$AGENT_DIR" \
    OMI_TEST_NPM_LOG="$TEST_ROOT/npm.log" \
    OMI_TEST_PYTHON_LOG="$TEST_ROOT/python.log" \
    "$RUNNER"
}

run_fixture
grep -Fx 'ci --no-fund --no-audit' "$TEST_ROOT/npm.log" >/dev/null
grep -Fx "$TEST_ROOT/gauntlet.py --self-check" "$TEST_ROOT/python.log" >/dev/null

npm_calls_before="$(wc -l <"$TEST_ROOT/npm.log" | tr -d ' ')"
run_fixture
npm_calls_after="$(wc -l <"$TEST_ROOT/npm.log" | tr -d ' ')"
[[ "$npm_calls_after" == "$npm_calls_before" ]] || {
  echo "agent continuity self-check reinstalled an already complete dependency tree" >&2
  exit 1
}

# Regression: required actions may be extracted from DesktopAutomationBridge.swift,
# but deleting one from the authoritative source set must still fail closed.
ACTION_FIXTURE="$TEST_ROOT/action-sources"
mkdir -p "$ACTION_FIXTURE/Desktop/Sources/Automation"
printf 'register(name: "ask")\n' >"$ACTION_FIXTURE/Desktop/Sources/DesktopAutomationBridge.swift"
cat >"$ACTION_FIXTURE/Desktop/Sources/Automation/DesktopAutomationPTTActions.swift" <<'SWIFT'
register(name: "ptt_manager_turn")
register(name: "ptt_turn_snapshot")
SWIFT
python3 - "$LIB" "$ACTION_FIXTURE" <<'PY'
import importlib.util
import sys
from pathlib import Path

library_path = Path(sys.argv[1])
fixture_root = Path(sys.argv[2])
sys.path.insert(0, str(library_path.parent))
spec = importlib.util.spec_from_file_location("agent_continuity_gauntlet_lib", library_path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

required = {"ptt_manager_turn", "ptt_turn_snapshot"}
sources = (
    "Desktop/Sources/DesktopAutomationBridge.swift",
    "Desktop/Sources/Automation/DesktopAutomationPTTActions.swift",
)
assert module.missing_required_automation_actions(
    required,
    desktop_dir=fixture_root,
    source_relative_paths=sources,
) == []

(fixture_root / sources[1]).write_text('register(name: "ptt_manager_turn")\n', encoding="utf-8")
assert module.missing_required_automation_actions(
    required,
    desktop_dir=fixture_root,
    source_relative_paths=sources,
) == ["ptt_turn_snapshot"]
PY

"$RUNNER"

echo "agent continuity gauntlet self-check runner tests passed"
