"""Public translation façade backed by one canonical planner/executor.

Callers keep importing ``utils.translation``. Fixed Gemini execution, cache
policy, planning, strict response validation, and reconstruction live in focused,
injectable modules under ``utils.translation_core``.
"""

from __future__ import annotations

from typing import Callable

from config.translation import TranslationProfile, resolve_translation_profile
from utils.translation_core.cache import (
    CachedTranslation,
    TranslationCache,
    get_default_translation_store,
)
from utils.translation_core.engine import (
    TranslationEngine,
    TranslationOutcome,
    TranslationStatus,
)
from utils.translation_core.metrics import TranslationMetrics, get_translation_metrics
from utils.translation_core.planner import TranslationMode, TranslationUnit
from utils.translation_core.providers import (
    GeminiTranslationExecutor,
    default_translation_executor,
    get_default_translation_executor,
)
from utils.translation_language import (
    CONFIDENCE_FOREIGN_TRANSLATE,
    CONFIDENCE_TARGET_SKIP,
    LANGDETECT_RELIABLE_LANGUAGES,
    MIN_CONFIDENT_CHARS,
    TranslationNeed,
    classify_translation_need,
    detect_language,
    detect_language_with_confidence,
    split_into_sentences,
)


class TranslationService:
    """Compatible outer API over typed translation outcomes."""

    def __init__(
        self,
        *,
        engine: TranslationEngine | None = None,
        cache: TranslationCache | None = None,
        translation_executor: GeminiTranslationExecutor | None = None,
        profile_resolver: Callable[[], TranslationProfile] = resolve_translation_profile,
        metrics: TranslationMetrics | None = None,
    ) -> None:
        self._profile_resolver = profile_resolver
        if engine is not None:
            self._engine = engine
            self.cache = engine.cache
            return

        selected_metrics = metrics or get_translation_metrics()
        self.cache = cache or TranslationCache(
            persistent=get_default_translation_store(),
            metrics=selected_metrics,
        )
        if translation_executor is not None:
            selected_executor = translation_executor
        elif metrics is None:
            selected_executor = get_default_translation_executor()
        else:
            selected_executor = default_translation_executor(selected_metrics)
        self._engine = TranslationEngine(
            cache=self.cache,
            translation_executor=selected_executor,
            profile_resolver=profile_resolver,
        )

    def translate_outcomes(
        self,
        dest_language: str,
        units: list[tuple[str, str]],
        source_language: str = '',
        *,
        mode: TranslationMode = TranslationMode.sentence,
    ) -> list[TranslationOutcome]:
        canonical_units = [
            TranslationUnit(ordinal=ordinal, unit_id=unit_id, text=text)
            for ordinal, (unit_id, text) in enumerate(units)
        ]
        return self._engine.translate(
            canonical_units,
            target_language=dest_language,
            source_language=source_language,
            mode=mode,
        )

    def translate_units_batch(
        self,
        dest_language: str,
        units: list[tuple[str, str]],
        source_language: str = '',
    ) -> list[tuple[str, str, str]]:
        outcomes = self.translate_outcomes(
            dest_language,
            units,
            source_language,
            mode=TranslationMode.sentence,
        )
        return [(outcome.unit_id, outcome.text, outcome.detected_language) for outcome in outcomes]

    def translate_text_by_sentence(
        self,
        dest_language: str,
        text: str,
        source_language: str = '',
    ) -> tuple[str, str]:
        outcome = self.translate_outcomes(
            dest_language,
            [('text', text)],
            source_language,
            mode=TranslationMode.sentence,
        )[0]
        return outcome.text, outcome.detected_language

    def translate_text(self, dest_language: str, text: str, source_language: str = '') -> tuple[str, str]:
        outcome = self.translate_outcomes(
            dest_language,
            [('text', text)],
            source_language,
            mode=TranslationMode.whole_text,
        )[0]
        return outcome.text, outcome.detected_language

    def get_cached_translation(self, fingerprint: str, target_language: str) -> dict[str, str] | None:
        cached = self.cache.get(fingerprint, target_language)
        if cached is None:
            return None
        return {'text': cached.text, 'detected_lang': cached.detected_language}

    def cache_translation(
        self,
        fingerprint: str,
        target_language: str,
        translated_text: str,
        detected_language: str,
    ) -> None:
        self.cache.put(
            fingerprint,
            target_language,
            CachedTranslation(translated_text, detected_language),
            self._profile_resolver(),
        )

    def get_negative_cache(self, fingerprint: str, target_language: str) -> bool:
        return self.cache.is_negative(fingerprint, target_language)

    def set_negative_cache(self, fingerprint: str, target_language: str) -> None:
        self.cache.put_negative(fingerprint, target_language, self._profile_resolver())

    def clear_session_cache(self) -> None:
        """Release per-session translation state while retaining shared Redis data."""
        self.cache.clear_memory()


__all__ = [
    'CONFIDENCE_FOREIGN_TRANSLATE',
    'CONFIDENCE_TARGET_SKIP',
    'LANGDETECT_RELIABLE_LANGUAGES',
    'MIN_CONFIDENT_CHARS',
    'TranslationMode',
    'TranslationNeed',
    'TranslationOutcome',
    'TranslationProfile',
    'TranslationService',
    'TranslationStatus',
    'classify_translation_need',
    'detect_language',
    'detect_language_with_confidence',
    'resolve_translation_profile',
    'split_into_sentences',
]
