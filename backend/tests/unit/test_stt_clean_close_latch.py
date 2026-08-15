"""Regression (#10028): a clean upstream close must latch the provider socket dead.

When the Modulate live upstream WebSocket ends *cleanly* — the
``async for`` over the socket exhausts without raising ``ConnectionClosed`` — the
wrapper previously fell through with ``_dead`` still ``False``. ``live_stt_socket_is_dead``
then read that stale ``False``, so the listen loop kept the mobile socket in a
"Listening" zombie state (up to the 300s ``ws_receive_timeout``) instead of
terminating via the ``stt_failed`` / WebSocket 1011 path.

An explicit local drain (``_closed``) or an expected provider ``done`` frame is
finalization, not death, and must NOT latch dead.
"""

import asyncio
import json

from utils.stt.streaming import SafeModulateSocket


class _FakeUpstreamWS:
    """Async-iterable stand-in for a provider WebSocket that yields `messages`
    then closes cleanly (StopAsyncIteration) — exactly a graceful upstream close."""

    def __init__(self, messages):
        self._messages = list(messages)

    def __aiter__(self):
        return self

    async def __anext__(self):
        if self._messages:
            return self._messages.pop(0)
        raise StopAsyncIteration

    async def send(self, _data):
        return None

    async def close(self):
        return None


# --------------------------------------------------------------------------
# Modulate
# --------------------------------------------------------------------------


def _run_modulate_recv(messages):
    loop = asyncio.new_event_loop()

    async def run():
        ws = _FakeUpstreamWS(messages)
        sock = SafeModulateSocket(ws, lambda _segments: None, loop, preseconds=0)
        sock.set_wav_header(b'')
        sock._send_task.cancel()
        await asyncio.wait_for(sock._recv_task, timeout=2)
        return sock

    try:
        return loop.run_until_complete(run())
    finally:
        loop.close()


def test_modulate_clean_upstream_close_latches_dead():
    sock = _run_modulate_recv([])  # provider closes without any terminal frame
    assert sock.is_connection_dead is True


def test_modulate_done_frame_is_not_death():
    sock = _run_modulate_recv([json.dumps({'type': 'done', 'duration_ms': 100})])
    assert sock.is_connection_dead is False
