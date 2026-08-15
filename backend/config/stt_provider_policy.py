"""Language and capability policy for the fixed managed STT adapter."""

from __future__ import annotations

from enum import Enum
from typing import Final


class STTServingSurface(str, Enum):
    STREAMING = 'streaming'
    PRERECORDED = 'prerecorded'
    PTT = 'ptt'


MODULATE_PROVIDER: Final = 'modulate'
MODULATE_MODEL: Final = 'modulate-velma-2'

# Velma-2 is the live fallback for every language we can safely send to its
# automatic-detection mode. Keep this capability at the policy boundary rather
# than beside one caller: a user may choose multi-language mode independently
# of their primary language.
MODULATE_SUPPORTED_LANGUAGES: Final[frozenset[str]] = frozenset(
    {
        'multi',
        'en',
        'af',
        'sq',
        'ar',
        'az',
        'eu',
        'be',
        'bn',
        'bs',
        'bg',
        'ca',
        'zh',
        'hr',
        'cs',
        'da',
        'nl',
        'et',
        'fi',
        'fr',
        'gl',
        'de',
        'el',
        'gu',
        'he',
        'hi',
        'hu',
        'id',
        'it',
        'ja',
        'kn',
        'kk',
        'ko',
        'lv',
        'lt',
        'mk',
        'ms',
        'ml',
        'mr',
        'no',
        'fa',
        'pl',
        'pt',
        'pa',
        'ro',
        'ru',
        'sr',
        'sk',
        'sl',
        'es',
        'sw',
        'sv',
        'tl',
        'ta',
        'te',
        'th',
        'tr',
        'uk',
        'ur',
        'vi',
        'cy',
    }
)


def normalized_stt_language(language: str | None) -> str:
    """Return the base language code accepted by provider capability maps."""
    if not language:
        return ''
    return language.split('-')[0].split('_')[0].lower()


def modulate_supports_language(language: str | None) -> bool:
    """Return whether Velma-2 accepts a language code on a serving surface."""
    return normalized_stt_language(language) in MODULATE_SUPPORTED_LANGUAGES


def supports_live_multilingual_mode(language: str | None) -> bool:
    """Return whether a live user language can enter Modulate auto-detection."""
    return modulate_supports_language(language)
