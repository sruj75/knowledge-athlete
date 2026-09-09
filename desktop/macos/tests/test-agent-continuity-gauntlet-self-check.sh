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

# Managed voice can transcribe spoken punctuation as spaces. Accept only that
# rendering of the same exact marker components; typed/wire evidence stays exact.
observed_reply = (
    "GAUNTLET 20260908T135048Z BDD1E7B0 TYPED. I've noted down the new push to talk marker "
    "GAUNTLET 20260908T135048Z 51B01CB1 PTT as requested. Anything else you need help with?"
)
typed_marker = "GAUNTLET-20260908T135048Z-BDD1E7B0-TYPED"
ptt_marker = "GAUNTLET-20260908T135048Z-51B01CB1-PTT"
assert module.spoken_reply_mentions_marker(observed_reply, typed_marker)
assert module.spoken_reply_mentions_marker(observed_reply, ptt_marker)
assert module.spoken_reply_mentions_marker(f"Acknowledged {typed_marker}.", typed_marker)
custom_marker = "GAUNTLET-beta-a-run-BDD1E7B0-TYPED"
assert module.spoken_reply_mentions_marker(
    "Acknowledged GAUNTLET beta-a-run BDD1E7B0 TYPED.",
    custom_marker,
)
assert not module.spoken_reply_mentions_marker(
    "Acknowledged GAUNTLET beta a run BDD1E7B0 TYPED.",
    custom_marker,
)
for rejected in (
    "GAUNTLET 20260908T135048Z BDD1E7B1 TYPED",  # wrong nonce
    "GAUNTLET 20260908T135048Z BDD1E7B TYPED",  # partial nonce
    "GAUNTLET 20260908T135049Z BDD1E7B0 TYPED",  # wrong timestamp
    "GAUNTLET 20260908T135048Z BDD1E7B0 PTT",  # wrong channel
    "gauntlet 20260908T135048Z BDD1E7B0 TYPED",  # wrong case
    "XGAUNTLET 20260908T135048Z BDD1E7B0 TYPED",  # embedded prefix
    "GAUNTLET 20260908T135048Z BDD1E7B0 TYPEDX",  # embedded suffix
):
    assert not module.spoken_reply_mentions_marker(rejected, typed_marker)

# A required chat turn must finish on either its own terminal assistant row or
# its own terminal error. The latter must fail the run immediately, retain only
# privacy-safe evidence, and never burn the outer deadline or add a second
# "no assistant" failure.
def runner_args(run_dir: Path) -> object:
    return type(
        "Args",
        (),
        {
            "port": 47777,
            "bundle_id": "com.heyintentive.intentive.dev.omi-gauntlet-fixture",
            "run_id": "terminal-error-fixture",
            "run_dir": str(run_dir),
            "log_path": str(run_dir / "app.log"),
            "suite": "prompts",
            "require_live_voice": False,
            "turn_timeout_ms": 90_000,
        },
    )()


module.capture_trace_cursor = lambda: "fixture-cursor"
module.read_new_traces = lambda _cursor: [{"model": "fixture-model", "token_count": 2}]
module.time.sleep = lambda _seconds: (_ for _ in ()).throw(AssertionError("turn wait slept"))

query = "fixture current-facts query"
success_calls = []


def success_bridge_action(_port, name, _params=None, **_kwargs):
    success_calls.append(name)
    if name == "ask_main_chat":
        return {"ok": True, "result": {"detail": {"accepted": "true"}}}
    if name == "wait_main_chat_idle":
        return {"ok": True, "result": {"detail": {"idle": "true", "has_error": "false"}}}
    if name == "main_chat_snapshot":
        return {
            "ok": True,
            "result": {
                "detail": {
                    "idle": "true",
                    "has_error": "false",
                    "messages_json": module.json.dumps(
                        [
                            {"role": "user", "text": query, "streaming": "false"},
                            {"role": "assistant", "text": "fixture answer", "streaming": "false"},
                        ]
                    ),
                }
            },
        }
    raise AssertionError(f"unexpected success action: {name}")


module.bridge_action = success_bridge_action
success_runner = module.GauntletRunner(runner_args(fixture_root / "success-run"))
_send, success_snapshot, success_traces = success_runner.send_and_wait(query, 90_000)
assert module.current_turn_assistant_text(success_snapshot, query) == "fixture answer"
assert success_traces == [{"model": "fixture-model", "token_count": 2}]
assert success_runner.failures == []
assert success_calls == ["ask_main_chat", "wait_main_chat_idle", "main_chat_snapshot", "main_chat_snapshot"]

superseded_snapshot = {
    "has_error": "true",
    "messages_json": module.json.dumps(
        [
            {"role": "user", "text": query, "streaming": "false"},
            {"role": "user", "text": "later fixture query", "streaming": "false"},
        ]
    ),
}
assert not module.current_turn_has_terminal_error(superseded_snapshot, query)

denial_calls = []
private_error = "fixture provider detail that must not survive evidence hygiene"


def denial_bridge_action(_port, name, _params=None, **_kwargs):
    denial_calls.append(name)
    if name == "ask_main_chat":
        return {"ok": True, "result": {"detail": {"accepted": "true"}}}
    if name == "wait_main_chat_idle":
        return {"ok": True, "result": {"detail": {"idle": "true", "has_error": "true"}}}
    if name == "main_chat_snapshot":
        return {
            "ok": True,
            "result": {
                "detail": {
                    "idle": "true",
                    "is_sending": "false",
                    "is_streaming": "false",
                    "has_error": "true",
                    "current_error": "quota",
                    "error_message": private_error,
                    "messages_json": module.json.dumps(
                        [{"role": "user", "text": query, "streaming": "false"}]
                    ),
                }
            },
        }
    raise AssertionError(f"unexpected denial action: {name}")


module.bridge_action = denial_bridge_action
module.git_sha = lambda: "a" * 40
module.sine_pcm16k = lambda: b""
module.finalize_evidence_hygiene = lambda *_args, **_kwargs: None
denial_run_dir = fixture_root / "denial-run"
denial_runner = module.GauntletRunner(runner_args(denial_run_dir))
denial_runner.suites = {"prompts"}
denial_runner.ensure_bridge = lambda: None
denial_runner.navigate_chat = lambda: None
denial_runner.clear_kernel_hygiene_if_available = lambda: None
denial_runner.run_prompts_suite = lambda: denial_runner.send_and_wait(query, 90_000)

assert denial_runner.run() == 1
assert denial_calls == ["ask_main_chat", "wait_main_chat_idle", "main_chat_snapshot"]
assert len(denial_runner.failures) == 1
assert "timed out waiting" not in denial_runner.failures[0]
assert "no terminal assistant" not in denial_runner.failures[0]
terminal_evidence = denial_run_dir / "terminal-main-chat-error.json"
assert terminal_evidence.is_file()
serialized_terminal_evidence = terminal_evidence.read_text(encoding="utf-8")
assert private_error not in serialized_terminal_evidence
assert query not in serialized_terminal_evidence
assert module.json.loads(serialized_terminal_evidence)["privacy_class"] == "hashed-summary"
manifest = module.json.loads((denial_run_dir / "manifest.json").read_text(encoding="utf-8"))
assert manifest["passed"] is False
assert len(manifest["failures"]) == 1

denial_calls.clear()
resilience_runner = module.GauntletRunner(runner_args(fixture_root / "resilience-denial"))
resilience_runner.suites = {"resilience"}
send, snapshot, traces = resilience_runner.send_and_wait_resilience(query, 90_000)
assert denial_calls == ["ask_main_chat", "wait_main_chat_idle", "main_chat_snapshot", "main_chat_snapshot"]
terminal_reason = resilience_runner.classify_resilience_turn(
    scenario="fixture-resilience",
    iteration=1,
    query=query,
    send=send,
    snapshot=snapshot,
    traces=traces,
    require_trace=False,
)
assert terminal_reason == "generic_chat_error"
assert len(resilience_runner.failures) == 1
assert "timed out waiting" not in resilience_runner.failures[0]
PY

"$RUNNER"

echo "agent continuity gauntlet self-check runner tests passed"
