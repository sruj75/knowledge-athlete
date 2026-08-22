"""The voice-message transcribe handler must not block the event loop on STT.

``POST /v2/voice-message/transcribe`` (``routers/chat.py::transcribe_voice_message``) is an
``async def`` handler, so any synchronous call it makes runs directly on the event loop.
The two managed pre-recorded transcription helpers it uses, ``transcribe_pcm_bytes`` and
``transcribe_voice_message_bytes``, are synchronous and perform a blocking multi-second
HTTP round-trip (``httpx.Client().post`` in ``utils/stt/pre_recorded.py``). Calling them
directly froze the loop for the whole transcription, stalling every other connection and
the health checks (the exact "sync requests in async is silent poison" hazard in
``backend/AGENTS.md``).

They must be offloaded with ``await run_blocking(<executor>, fn, ...)``, the same way the
handler already offloads its WAV file write. These AST checks assert the offload stays in
place so the blocking call cannot silently come back.
"""

import ast
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent.parent
CHAT_ROUTER = BACKEND_DIR / "routers" / "chat.py"

# The synchronous, blocking STT helpers that must never be called directly in async code.
_STT_FUNCS = {"transcribe_pcm_bytes"}
_HANDLER = "transcribe_voice_message"
_VOICE_FILE_HELPER = "_transcribe_voice_message_file"


def _async_node(name):
    tree = ast.parse(CHAT_ROUTER.read_text(encoding="utf-8"))
    node = next(
        (n for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef) and n.name == name),
        None,
    )
    assert node is not None, f"async def {name} not found in routers/chat.py"
    return node


def _handler_node():
    return _async_node(_HANDLER)


def _direct_calls(node):
    """Names of functions invoked directly as ``fn(...)`` anywhere under ``node``."""
    return {sub.func.id for sub in ast.walk(node) if isinstance(sub, ast.Call) and isinstance(sub.func, ast.Name)}


def _run_blocking_offloaded(node):
    """Names passed as the function argument to an AWAITED ``run_blocking(executor, fn, ...)``.

    The run_blocking call must be the operand of an ``await``. A bare ``run_blocking(...)``
    without ``await`` returns a coroutine that never runs, so the offload would silently break
    while still passing a looser wrapped-in-run_blocking check. Requiring the await closes that
    regression gap.
    """
    offloaded = set()
    for sub in ast.walk(node):
        if not (isinstance(sub, ast.Await) and isinstance(sub.value, ast.Call)):
            continue
        call = sub.value
        # run_blocking(executor, fn, *args, **kwargs) -> fn is the 2nd positional arg.
        if isinstance(call.func, ast.Name) and call.func.id == "run_blocking" and len(call.args) >= 2:
            if isinstance(call.args[1], ast.Name):
                offloaded.add(call.args[1].id)
    return offloaded


def _run_blocking_pairs(node):
    pairs = set()
    for sub in ast.walk(node):
        if not (isinstance(sub, ast.Await) and isinstance(sub.value, ast.Call)):
            continue
        call = sub.value
        if not (isinstance(call.func, ast.Name) and call.func.id == "run_blocking" and len(call.args) >= 2):
            continue
        executor, function = call.args[:2]
        if isinstance(executor, ast.Name) and isinstance(function, ast.Name):
            pairs.add((executor.id, function.id))
    return pairs


class TestVoiceTranscribeOffloadsSTT:
    def test_stt_helpers_are_not_called_directly_in_the_async_handler(self):
        direct = _direct_calls(_handler_node())
        leaked = _STT_FUNCS & direct
        assert not leaked, (
            f"{_HANDLER} calls blocking STT helpers directly on the event loop: {sorted(leaked)}. "
            f"Offload them with await run_blocking(sync_executor, ...)."
        )

    def test_pcm_stt_helper_is_offloaded_via_run_blocking(self):
        offloaded = _run_blocking_offloaded(_handler_node())
        missing = _STT_FUNCS - offloaded
        assert not missing, f"these STT helpers are not offloaded via run_blocking: {sorted(missing)}"

    def test_handler_is_async(self):
        # If the handler were a plain def it would run in FastAPI's threadpool and the sync
        # calls would be fine; this fix only matters because it is async (it awaits request
        # body/form/file reads). Guard that assumption.
        node = _handler_node()
        assert isinstance(node, ast.AsyncFunctionDef)

    def test_file_bytes_and_provider_work_use_their_owned_executors(self):
        pairs = _run_blocking_pairs(_async_node(_VOICE_FILE_HELPER))
        assert ("storage_executor", "load_voice_message_segment_bytes") in pairs
        assert ("sync_executor", "transcribe_voice_message_bytes") in pairs
