#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../scripts/agent-continuity-gauntlet-lib.py"

python3 - "$LIB" <<'PY'
import importlib.util
import sys
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("agent_continuity_gauntlet", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

expected_sha = "a" * 40
calls = []


def fake_bridge_request(port, method, route, body=None, *, timeout_sec=60, authenticate=True):
    calls.append((port, method, route, authenticate))
    return {
        "ok": True,
        "sourceGitSHA": expected_sha,
        "sourceTreeDirty": False,
    }


module.bridge_request = fake_bridge_request
module.git_sha = lambda: expected_sha
module.bridge_state = lambda _port: {"ok": True}
module.classify_restarted_bundle_state = lambda _state, _bundle, _port: ("ready", "fixture")

runner = module.GauntletRunner.__new__(module.GauntletRunner)
runner.port = 47777
runner.bundle_id = "com.heyintentive.intentive.dev.omi-wave6-s31"
runner.manifest = {}
runner.ensure_bridge()

assert calls == [(47777, "GET", "/health", False)], calls
assert runner.manifest["source_git_sha"] == expected_sha
assert runner.manifest["source_tree_dirty"] is False
PY

echo "agent continuity gauntlet source provenance tests passed"
