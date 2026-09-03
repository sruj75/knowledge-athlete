#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../scripts/agent-continuity-gauntlet-lib.py"

python3 - "$LIB" <<'PY'
import importlib.util
import io
import json
import sys
import urllib.error
from pathlib import Path

path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location("agent_continuity_gauntlet", path)
assert spec is not None and spec.loader is not None
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

expected_sha = "a" * 40
calls = []
real_bridge_request = module.bridge_request


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

private_body = b'{"ok":false,"error":"provider-private-body alice@example.com"}'
module.bridge_request = real_bridge_request
module.automation_token = lambda _port: "fixture-token"


def raise_private_http_error(_request, timeout=60):
    del timeout
    raise urllib.error.HTTPError(
        "http://127.0.0.1:47777/action",
        502,
        "bad gateway",
        {},
        io.BytesIO(private_body),
    )


module.urllib.request.urlopen = raise_private_http_error
failure = module.bridge_request(47777, "POST", "/action", {"name": "ask"})
serialized_failure = json.dumps(failure, sort_keys=True)
assert "provider-private-body" not in serialized_failure
assert "alice@example.com" not in serialized_failure
assert failure["error"] == "bridge_http_error"
assert failure["http_status"] == 502
assert failure["response_body_sha256"] == module.hashlib.sha256(private_body).hexdigest()

raw_success_envelope = {
    "ok": False,
    "error": "provider-private-body alice@example.com",
    "result": {"detail": {"error": "private nested response"}},
}
safe_summary = module.bridge_failure_summary(raw_success_envelope)
assert "provider-private-body" not in safe_summary
assert "alice@example.com" not in safe_summary
assert "private nested response" not in safe_summary
assert "sha256=" in safe_summary
PY

echo "agent continuity gauntlet source provenance tests passed"
