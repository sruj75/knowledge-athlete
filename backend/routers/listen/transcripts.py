"""Conversation-free transcript delivery and transient translation."""

from __future__ import annotations

import asyncio
import logging
import uuid
from typing import Any

from utils.async_tasks import gather_safe
from utils.executors import llm_executor, run_blocking
from utils.translation import TranslationService
from utils.translation_cache import should_emit_translation

logger = logging.getLogger(__name__)


def validate_transient_segment(raw: dict[str, Any]) -> dict[str, Any]:
    """Return the exact public segment DTO or fail the managed adapter boundary."""
    if set(raw) != {"segmentId", "speakerId", "text", "start", "end"}:
        raise ValueError("transient segment has unexpected fields")
    segment_id = raw["segmentId"]
    if not isinstance(segment_id, str):
        raise ValueError("segmentId must be a UUID string")
    try:
        segment_id = str(uuid.UUID(segment_id))
    except ValueError as error:
        raise ValueError("segmentId must be a UUID string") from error
    speaker_id = raw["speakerId"]
    if not isinstance(speaker_id, int) or isinstance(speaker_id, bool) or speaker_id < 0:
        raise ValueError("speakerId must be a zero-based integer")
    text = raw["text"]
    start = raw["start"]
    end = raw["end"]
    if not isinstance(text, str) or not text.strip():
        raise ValueError("segment text must not be empty")
    if not isinstance(start, (int, float)) or not isinstance(end, (int, float)) or start < 0 or end < start:
        raise ValueError("segment timing is invalid")
    return {
        "segmentId": segment_id,
        "speakerId": speaker_id,
        "text": text.strip(),
        "start": float(start),
        "end": float(end),
    }


class TransientTranscriptProcessor:
    """Deliver provider-final segments and optional translations without product storage."""

    def __init__(self, host: Any, translation_service: TranslationService | None = None):
        self.host = host
        self.queue: asyncio.Queue[list[dict[str, Any]]] = asyncio.Queue(maxsize=1_000)
        self.translation_service = translation_service or TranslationService()
        self.translation_tasks: set[asyncio.Task[Any]] = set()
        self.translation_ids: set[str] = set()

    def enqueue(self, segments: list[dict[str, Any]]) -> None:
        canonical = [validate_transient_segment(segment) for segment in segments]
        if not canonical:
            return
        try:
            self.queue.put_nowait(canonical)
        except asyncio.QueueFull as error:
            raise RuntimeError("transient transcript queue is full") from error

    async def process_loop(self) -> None:
        while self.host.state.active or not self.queue.empty():
            try:
                segments = await asyncio.wait_for(self.queue.get(), timeout=0.25)
            except asyncio.TimeoutError:
                continue
            try:
                if await self.host.send_json({"type": "segments", "segments": segments}):
                    self.host.complete_live_transcription()
                    self.host.state.last_transcript_time = self.host.now()
                    self.host.state.words_transcribed_since_last_record += sum(
                        len(segment["text"].split()) for segment in segments
                    )
                target = self.host.request.config.translation_target
                pending = [segment for segment in segments if segment["segmentId"] not in self.translation_ids]
                if target and pending:
                    self.translation_ids.update(segment["segmentId"] for segment in pending)
                    task = self.host.spawn(self._translate(pending, target), name="translate_segments")
                    self.translation_tasks.add(task)
                    task.add_done_callback(self.translation_tasks.discard)
            finally:
                self.queue.task_done()

    async def _translate(self, segments: list[dict[str, Any]], target: str) -> None:
        units = [(segment["segmentId"], segment["text"]) for segment in segments]
        try:
            outcomes = await run_blocking(
                llm_executor,
                self.translation_service.translate_units_batch,
                target,
                units,
            )
        except Exception as error:
            logger.warning("Transient translation failed type=%s", type(error).__name__)
            return
        if len(outcomes) != len(units):
            logger.warning("Transient translation cardinality mismatch")
            return

        source_by_id = {segment["segmentId"]: segment["text"] for segment in segments}
        for segment_id, translated_text, detected_language in outcomes:
            source_text = source_by_id.get(segment_id)
            if source_text is None or not should_emit_translation(
                source_text, translated_text, detected_language, target
            ):
                continue
            await self.host.send_json(
                {
                    "type": "translation",
                    "segmentId": segment_id,
                    "language": target,
                    "text": translated_text,
                }
            )

    async def flush(self) -> None:
        await self.queue.join()
        if self.translation_tasks:
            await gather_safe(
                *tuple(self.translation_tasks),
                label="listen_translation_flush",
                max_concurrency=10,
            )

    def clear(self) -> None:
        self.translation_service.clear_session_cache()
        self.translation_ids.clear()
