#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/../scripts/agent-continuity-gauntlet-lib.py"

python3 - "$LIB" <<'PY'
import importlib.util
import io
import json
import sys
import tempfile
import urllib.error
from argparse import Namespace
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


def gauntlet_args(root, *, require_live_voice, suite="continuity"):
    return Namespace(
        port=47777,
        bundle_id="com.heyintentive.intentive.dev.omi-voice-evidence",
        run_id="voice-evidence",
        run_dir=str(root / "evidence"),
        log_path=str(root / "app.log"),
        turn_timeout_ms=1_000,
        suite=suite,
        require_live_voice=require_live_voice,
    )


def ptt_response(mode_marker=...):
    detail = {} if mode_marker is ... else {"transport_mode": mode_marker}
    return {"ok": True, "result": {"detail": detail}}


def exercise_transport_manifest(root, *, require_live_voice, mode_marker=..., action_response=...):
    runner = module.GauntletRunner(gauntlet_args(root, require_live_voice=require_live_voice))
    runner.ensure_bridge = lambda: None
    runner.navigate_chat = lambda: None
    runner.clear_kernel_hygiene_if_available = lambda: None
    ptt_calls = []
    response = ptt_response(mode_marker) if action_response is ... else action_response
    runner.bridge_act = lambda name, params=None: (
        ptt_calls.append((name, params)) or response
    )
    runner.run_continuity_suite = lambda: runner.ptt_act(
        "02-ptt-turn",
        {"force_transcript": "private fixture", "text_only": "1"},
    )
    module.finalize_evidence_hygiene = lambda *_args, **_kwargs: None
    exit_code = runner.run()
    manifest = json.loads((Path(runner.run_dir) / "manifest.json").read_text(encoding="utf-8"))
    assert ptt_calls == [
        ("ptt_test_turn", {"force_transcript": "private fixture", "text_only": "1"})
    ]
    return runner, exit_code, manifest


with tempfile.TemporaryDirectory() as raw_root:
    fixture_root = Path(raw_root)

    offline_runner, offline_exit, offline_manifest = exercise_transport_manifest(
        fixture_root / "offline",
        require_live_voice=False,
        mode_marker="hermetic",
    )
    assert offline_exit == 0
    assert offline_runner.failures == []
    assert offline_manifest["passed"] is True
    assert offline_manifest["ptt_config"]["require_live_voice"] is False
    assert offline_manifest["ptt_transport_evidence"] == [
        {"step_id": "02-ptt-turn", "transport_mode": "hermetic"}
    ]

    legacy_runner, legacy_exit, legacy_manifest = exercise_transport_manifest(
        fixture_root / "legacy",
        require_live_voice=True,
        mode_marker=...,
    )
    assert legacy_exit == 1
    assert legacy_runner.failures
    assert legacy_manifest["passed"] is False
    assert legacy_manifest["ptt_transport_evidence"] == [
        {"step_id": "02-ptt-turn", "transport_mode": "unknown"}
    ]

    hermetic_runner, hermetic_exit, hermetic_manifest = exercise_transport_manifest(
        fixture_root / "hermetic",
        require_live_voice=True,
        mode_marker="hermetic",
    )
    assert hermetic_exit == 1
    assert hermetic_runner.failures
    assert hermetic_manifest["passed"] is False

    managed_runner, managed_exit, managed_manifest = exercise_transport_manifest(
        fixture_root / "managed",
        require_live_voice=True,
        mode_marker="managed",
    )
    assert managed_exit == 0
    assert managed_runner.failures == []
    assert managed_manifest["passed"] is True
    assert managed_manifest["ptt_config"]["require_live_voice"] is True
    assert managed_manifest["ptt_transport_evidence"] == [
        {"step_id": "02-ptt-turn", "transport_mode": "managed"}
    ]

    unknown_private = "provider-private-transport alice@example.com"
    unknown_runner, unknown_exit, unknown_manifest = exercise_transport_manifest(
        fixture_root / "unknown",
        require_live_voice=True,
        mode_marker=unknown_private,
    )
    assert unknown_exit == 1
    assert unknown_manifest["ptt_transport_evidence"] == [
        {"step_id": "02-ptt-turn", "transport_mode": "unknown"}
    ]
    assert unknown_private not in json.dumps(unknown_manifest, sort_keys=True)
    assert unknown_private not in "\n".join(unknown_runner.failures)

    malformed_responses = [
        {"ok": True, "result": None},
        {"ok": True, "result": []},
        {"ok": True, "result": {"detail": []}},
        {"ok": True, "result": {"detail": {"transport_mode": []}}},
        {"ok": True, "result": {"detail": {"transport_mode": {"private": "value"}}}},
    ]
    for index, malformed_response in enumerate(malformed_responses):
        malformed_runner, malformed_exit, malformed_manifest = exercise_transport_manifest(
            fixture_root / f"malformed-{index}",
            require_live_voice=True,
            action_response=malformed_response,
        )
        assert malformed_exit == 1
        assert malformed_runner.failures
        assert malformed_manifest["ptt_transport_evidence"] == [
            {"step_id": "02-ptt-turn", "transport_mode": "unknown"}
        ]
        assert "private" not in "\n".join(malformed_runner.failures)
        assert "value" not in "\n".join(malformed_runner.failures)

    try:
        module.GauntletRunner(
            gauntlet_args(
                fixture_root / "no-ptt",
                require_live_voice=True,
                suite="prompts",
            )
        )
    except SystemExit as exc:
        assert "continuity or agents" in str(exc)
    else:
        raise AssertionError("--require-live-voice accepted a suite with no PTT actions")

original_argv = sys.argv
try:
    sys.argv = [str(path), "--require-live-voice", "--suite", "agents"]
    parsed = module.parse_args()
    assert parsed.require_live_voice is True
finally:
    sys.argv = original_argv
PY

echo "agent continuity gauntlet source provenance tests passed"
