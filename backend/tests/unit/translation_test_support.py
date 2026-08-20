from __future__ import annotations

from config.translation import TranslationProfile
from utils.translation import TranslationService
from utils.translation_core.cache import CachedTranslation, PersistentTranslationStore, TranslationCache
from utils.translation_core.metrics import NoopTranslationMetrics
from utils.translation_core.providers import (
    GeminiTranslationExecutor,
    ProviderTranslation,
    TranslationExecutionError,
)


class FakeProvider:
    def __init__(self, responses: list[object]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, object]] = []

    def translate(
        self,
        contents: list[str],
        target_language: str,
        source_language: str,
        profile: TranslationProfile,
    ) -> list[ProviderTranslation]:
        self.calls.append(
            {
                'contents': list(contents),
                'target_language': target_language,
                'source_language': source_language,
                'profile': profile,
            }
        )
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response  # type: ignore[return-value]


class DictTranslationStore(PersistentTranslationStore):
    def __init__(self) -> None:
        self.values: dict[tuple[str, str], CachedTranslation] = {}
        self.negative: set[tuple[str, str]] = set()
        self.puts: list[tuple[str, str, CachedTranslation, int]] = []

    def get(self, fingerprint: str, target_language: str) -> CachedTranslation | None:
        return self.values.get((fingerprint, target_language))

    def put(
        self,
        fingerprint: str,
        target_language: str,
        value: CachedTranslation,
        ttl_seconds: int,
    ) -> None:
        self.puts.append((fingerprint, target_language, value, ttl_seconds))
        self.values[(fingerprint, target_language)] = value

    def is_negative(self, fingerprint: str, target_language: str) -> bool:
        return (fingerprint, target_language) in self.negative

    def put_negative(self, fingerprint: str, target_language: str, ttl_seconds: int) -> None:
        self.negative.add((fingerprint, target_language))


def profile(
    *,
    max_batch_size: int = 100,
) -> TranslationProfile:
    return TranslationProfile(
        cache_ttl_seconds=600,
        negative_cache_ttl_seconds=300,
        max_batch_size=max_batch_size,
    )


def build_service(
    provider: FakeProvider,
    *,
    selected_profile: TranslationProfile | None = None,
    store: PersistentTranslationStore | None = None,
    cache: TranslationCache | None = None,
) -> tuple[TranslationService, TranslationCache]:
    metrics = NoopTranslationMetrics()
    selected_cache = cache or TranslationCache(persistent=store, metrics=metrics)
    translation_executor = GeminiTranslationExecutor(
        adapter=provider,
        metrics=metrics,
    )
    resolved_profile = selected_profile or profile()
    service = TranslationService(
        cache=selected_cache,
        translation_executor=translation_executor,
        profile_resolver=lambda: resolved_profile,
        metrics=metrics,
    )
    return service, selected_cache


def translations(*items: tuple[str, str]) -> list[ProviderTranslation]:
    return [ProviderTranslation(text=text, detected_language=language) for text, language in items]


def translation_error(reason: str = 'other') -> TranslationExecutionError:
    return TranslationExecutionError(reason, 'Gemini translation failed')
