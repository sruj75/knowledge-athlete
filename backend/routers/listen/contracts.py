"""Typed public contract for the transient ``/v4/listen`` session."""

from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from typing import Any, Iterable

from config.stt_provider_policy import modulate_supports_language, normalized_stt_language


ALLOWED_LISTEN_QUERY_FIELDS = frozenset({"language", "translation_target", "vocabulary"})
MAX_VOCABULARY_TERMS = 100
MAX_VOCABULARY_TERM_CHARACTERS = 256
MAX_VOCABULARY_SERIALIZED_CHARACTERS = 8_000


class ListenContractError(ValueError):
    """A client supplied an unsupported or malformed immutable session field."""


@dataclass(frozen=True)
class ListenAudioContract:
    sample_rate: int = 16_000
    channels: int = 1
    codec: str = "s16le"


@dataclass(frozen=True)
class ListenSessionConfig:
    language: str
    translation_target: str | None = None
    vocabulary: tuple[str, ...] = ()

    @property
    def modulate_language(self) -> str:
        """Provider language hint; empty means documented automatic detection."""
        if self.language in {"auto", "multi"}:
            return ""
        return normalized_stt_language(self.language)

    @classmethod
    def from_query(cls, items: Iterable[tuple[str, str]]) -> "ListenSessionConfig":
        values: dict[str, list[str]] = {}
        for key, raw_value in items:
            if key not in ALLOWED_LISTEN_QUERY_FIELDS:
                raise ListenContractError("unsupported listen query field")
            values.setdefault(key, []).append(raw_value)

        language_values = values.get("language", [])
        if len(language_values) != 1:
            raise ListenContractError("language must be supplied exactly once")
        language = language_values[0].strip()
        if not language:
            raise ListenContractError("language must not be empty")
        normalized_language = normalized_stt_language(language)
        if language.lower() not in {"auto", "multi"} and not modulate_supports_language(normalized_language):
            raise ListenContractError("unsupported transcription language")
        language = language.lower() if language.lower() in {"auto", "multi"} else normalized_language

        translation_values = values.get("translation_target", [])
        if len(translation_values) > 1:
            raise ListenContractError("translation_target may be supplied at most once")
        translation_target: str | None = None
        if translation_values:
            raw_target = translation_values[0].strip()
            target = normalized_stt_language(raw_target)
            if not raw_target or raw_target.lower() in {"auto", "multi"} or not modulate_supports_language(target):
                raise ListenContractError("unsupported translation target")
            translation_target = target

        raw_vocabulary = values.get("vocabulary", [])
        if len(raw_vocabulary) > MAX_VOCABULARY_TERMS:
            raise ListenContractError(f"vocabulary may contain at most {MAX_VOCABULARY_TERMS} terms")
        vocabulary: list[str] = []
        seen: set[str] = set()
        for raw_term in raw_vocabulary:
            term = raw_term.strip()
            if not term:
                raise ListenContractError("vocabulary terms must not be empty")
            if len(term) > MAX_VOCABULARY_TERM_CHARACTERS:
                raise ListenContractError(
                    f"vocabulary terms may contain at most {MAX_VOCABULARY_TERM_CHARACTERS} characters"
                )
            identity = term.casefold()
            if identity not in seen:
                seen.add(identity)
                vocabulary.append(term)
        if sum(len(term) for term in vocabulary) > MAX_VOCABULARY_SERIALIZED_CHARACTERS:
            raise ListenContractError(
                f"vocabulary may contain at most {MAX_VOCABULARY_SERIALIZED_CHARACTERS} serialized characters"
            )

        return cls(language=language, translation_target=translation_target, vocabulary=tuple(vocabulary))


@dataclass(frozen=True)
class ListenRequest:
    websocket: Any
    uid: str
    config: ListenSessionConfig
    platform: str
    audio: ListenAudioContract = ListenAudioContract()


@dataclass
class ListenSessionState:
    active: bool = True
    close_code: int = 1001
    stt_terminal_failure: bool = False
    shutdown_event: asyncio.Event = field(default_factory=asyncio.Event)
    first_audio_byte_timestamp: float | None = None
    live_transcription_attempt: Any = None
    live_transcription_failed: bool = False
    last_usage_record_timestamp: float | None = None
    words_transcribed_since_last_record: int = 0
    last_transcript_time: float | None = None
    freemium_threshold_sent: bool = False
    remaining_seconds_cache: int | None = None
    remaining_seconds_cache_ts: float = 0.0
    remaining_seconds_cache_initialized: bool = False
    fair_use_last_check_ts: float = 0.0
    fair_use_managed_stt_budget_exhausted: bool = False
    fair_use_track_managed_stt_usage: bool = False
    fair_use_entitlement_policy: Any = None
    managed_stt_usage_ms_pending: int = 0
    last_audio_received_time: float | None = None
    last_activity_time: float | None = None


@dataclass(frozen=True)
class ListenLimits:
    credits_refresh_seconds: int = 900
    ws_receive_timeout: float = 300.0
    bg_drain_timeout: float = 30.0
