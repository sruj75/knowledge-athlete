"""
Fake STT (Speech-to-Text) helpers.

For custom-STT mode, the app/client is the STT
boundary: it sends ``suggested_transcript`` events into the real listen
websocket after audio bytes establish the session clock. Those deterministic
events exercise backend transcript handling and persistence without allowing
provider/network access. Managed-STT tests replace the fixed Modulate adapter
at its socket boundary.
"""

from __future__ import annotations

import sys
from typing import Any, Optional, Sequence


class FakeStreamingSTTSocket:
    """Minimal STT socket surface used by routers.transcribe._stream_handler."""

    def __init__(self, callback, *, die_on_first_send=False):
        self.callback = callback
        self.die_on_first_send = die_on_first_send
        self.sent_chunks = []
        self.finish_calls = 0
        self.finalize_calls = 0
        self.drain_calls = 0
        self._dead = False
        self._death_reason = None
        self._emitted = False

    @property
    def is_connection_dead(self) -> bool:
        return self._dead

    @property
    def death_reason(self):
        return self._death_reason

    def send(self, data: bytes) -> bool:
        self.sent_chunks.append(data)
        if self.die_on_first_send:
            self._dead = True
            self._death_reason = "synthetic provider disconnected"
            return False
        if self._emitted:
            return True
        self._emitted = True
        self.callback(
            [
                {
                    "id": "seg-streaming-stt-1",
                    "text": "Hermetic streaming STT transcript from the fake socket.",
                    "speaker": "SPEAKER_00",
                    "is_user": True,
                    "person_id": None,
                    "start": 0.0,
                    "end": 1.25,
                    "stt_provider": "e2e-streaming-stt",
                }
            ]
        )
        return True

    async def drain_and_close(self):
        self.drain_calls += 1
        # Mirror production finalization so teardown observability stays
        # consistent between real and fake sockets.
        self.finish()

    def finish(self) -> None:
        self.finish_calls += 1

    def finalize(self) -> None:
        self.finalize_calls += 1


async def fake_process_audio_modulate(callback, *args, **kwargs):
    """Return the deterministic streaming socket used by the offline app factories."""

    return FakeStreamingSTTSocket(callback)


class FakePrerecordedSTTProvider:
    """Deterministic prerecorded provider with the production adapter surface."""

    def __init__(self, language: Optional[str] = "en") -> None:
        self.language = language

    @staticmethod
    def _words() -> list[dict[str, Any]]:
        return [
            {
                "timestamp": [0.0, 1.25],
                "speaker": "SPEAKER_00",
                "text": "Hermetic prerecorded STT transcript from the fake provider.",
            }
        ]

    def _result(
        self, *, language: Optional[str], return_language: bool
    ) -> list[dict[str, Any]] | tuple[list[dict[str, Any]], str]:
        words = self._words()
        requested = language or self.language or "en"
        normalized_language = requested.split("-")[0].split("_")[0].lower()
        return (words, normalized_language) if return_language else words

    def transcribe_url(
        self,
        audio_url: str,
        speakers_count: Optional[int] = None,
        attempts: int = 0,
        return_language: bool = False,
        diarize: bool = True,
        language: Optional[str] = None,
        keywords: Optional[Sequence[str]] = None,
    ) -> list[dict[str, Any]] | tuple[list[dict[str, Any]], str]:
        return self._result(language=language, return_language=return_language)

    def transcribe_bytes(
        self,
        audio_bytes: bytes,
        sample_rate: int = 16000,
        diarize: bool = True,
        attempts: int = 0,
        encoding: Optional[str] = None,
        channels: int = 1,
        language: Optional[str] = None,
        return_language: bool = False,
        keywords: Optional[Sequence[str]] = None,
    ) -> list[dict[str, Any]] | tuple[list[dict[str, Any]], str]:
        return self._result(language=language, return_language=return_language)


def make_fake_prerecorded_provider(language: Optional[str] = "en") -> FakePrerecordedSTTProvider:
    return FakePrerecordedSTTProvider(language)


def install_offline_managed_stt_fake() -> None:
    """Install fake managed-STT boundaries before an offline ASGI app is imported.

    This installer lives under the test harness and is called only by the
    offline app factories. Production modules retain their normal Modulate
    adapters when imported through their regular entry points.
    """

    from utils import analytics
    from utils.stt import pre_recorded, streaming, vad_gate

    streaming.process_audio_modulate = fake_process_audio_modulate
    pre_recorded.get_prerecorded_provider = make_fake_prerecorded_provider
    vad_gate.is_gate_enabled = lambda: False
    analytics.record_usage = lambda *args, **kwargs: None

    # Keep installation idempotent if a caller imported one of these modules
    # before selecting the offline factory.
    already_loaded = {
        "routers.listen.receiver": {
            "process_audio_modulate": fake_process_audio_modulate,
            "is_gate_enabled": lambda: False,
        },
        "routers.listen.runtime": {"record_usage": lambda *args, **kwargs: None},
        "routers.chat": {"process_audio_modulate": fake_process_audio_modulate},
    }
    for module_name, replacements in already_loaded.items():
        module = sys.modules.get(module_name)
        if module is None:
            continue
        for name, replacement in replacements.items():
            setattr(module, name, replacement)


def install_streaming_stt_fake(monkeypatch, *, die_on_first_send=False):
    """Patch the listen receiver provider boundary and return fake sockets.

    The fake patches the single managed provider entry point.
    """
    from routers.listen import receiver as listen_receiver
    from routers.listen import runtime as listen_runtime

    sockets = []

    async def fake_process_audio_modulate(callback, *args, **kwargs):
        socket = FakeStreamingSTTSocket(callback, die_on_first_send=die_on_first_send)
        sockets.append(socket)
        return socket

    monkeypatch.setattr(listen_receiver, "process_audio_modulate", fake_process_audio_modulate)
    monkeypatch.setattr(listen_receiver, "is_gate_enabled", lambda: False)
    monkeypatch.setattr(listen_runtime, "record_usage", lambda *args, **kwargs: None)
    return sockets


def fake_suggested_transcript_event():
    """Return a deterministic custom-STT event accepted by routers.transcribe."""
    return {
        "type": "suggested_transcript",
        "stt_provider": "e2e-custom-stt",
        "segments": [
            {
                "id": "seg-custom-stt-1",
                "text": "Hermetic custom STT transcript from the listen harness.",
                "speaker": "SPEAKER_00",
                "is_user": True,
                "start": 0.0,
                "end": 1.25,
            }
        ],
    }
