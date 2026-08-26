"""
Fake STT (Speech-to-Text) helpers.

Managed-STT tests replace the fixed Modulate adapter at its socket boundary;
prerecorded and PTT callers continue to share the same offline fake.
"""

from __future__ import annotations

import uuid
from typing import Any, Optional, Sequence


class FakeStreamingSTTSocket:
    """Minimal socket surface used by retained managed-STT callers."""

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
                    "segmentId": str(uuid.UUID("00000000-0000-4000-8000-000000000001")),
                    "text": "Hermetic streaming STT transcript from the fake socket.",
                    "speakerId": 0,
                    "start": 0.0,
                    "end": 1.25,
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
