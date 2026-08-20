"""Immutable Gemini translation and cache policy."""

from __future__ import annotations

from dataclasses import dataclass
from os import environ as process_environ
from typing import Mapping


@dataclass(frozen=True)
class TranslationProfile:
    """Cache and batching policy for the fixed Gemini translation path."""

    cache_ttl_seconds: int
    negative_cache_ttl_seconds: int
    max_batch_size: int = 100


def resolve_translation_profile(env: Mapping[str, str] | None = None) -> TranslationProfile:
    """Resolve cache policy without consulting a provider control plane."""

    values = process_environ if env is None else env
    cache_ttl = _positive_int(values.get('TRANSLATION_CACHE_TTL', str(60 * 60 * 24 * 14)), 'TRANSLATION_CACHE_TTL')
    negative_ttl = _positive_int(
        values.get('TRANSLATION_NEGATIVE_CACHE_TTL', str(60 * 60 * 24 * 7)),
        'TRANSLATION_NEGATIVE_CACHE_TTL',
    )
    return TranslationProfile(
        cache_ttl_seconds=cache_ttl,
        negative_cache_ttl_seconds=negative_ttl,
    )


def _positive_int(raw: str, name: str) -> int:
    try:
        value = int(raw)
    except (TypeError, ValueError) as error:
        raise ValueError(f'{name} must be an integer') from error
    if value <= 0:
        raise ValueError(f'{name} must be greater than zero')
    return value
