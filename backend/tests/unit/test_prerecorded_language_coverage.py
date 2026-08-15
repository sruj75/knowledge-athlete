"""Managed pre-recorded STT covers every language accepted by clients."""

import pytest

from config.stt_provider_policy import MODULATE_MODEL, MODULATE_PROVIDER
from utils.stt.pre_recorded import get_prerecorded_service

CLIENT_OFFERED_LANGUAGES = (
    'ar',
    'be',
    'bg',
    'bn',
    'bs',
    'ca',
    'cs',
    'da',
    'de',
    'el',
    'en',
    'es',
    'et',
    'fa',
    'fi',
    'fr',
    'he',
    'hi',
    'hr',
    'hu',
    'id',
    'it',
    'ja',
    'kn',
    'ko',
    'lt',
    'lv',
    'mk',
    'mr',
    'ms',
    'nl',
    'no',
    'pl',
    'pt',
    'ro',
    'ru',
    'sk',
    'sl',
    'sr',
    'sv',
    'ta',
    'te',
    'th',
    'tl',
    'tr',
    'uk',
    'vi',
    'zh',
)


@pytest.mark.parametrize('language', CLIENT_OFFERED_LANGUAGES)
def test_every_client_offered_language_resolves_to_modulate(language):
    assert get_prerecorded_service(language) == (MODULATE_PROVIDER, language, MODULATE_MODEL)


def test_region_qualified_codes_resolve_on_their_base_language():
    assert get_prerecorded_service('pt-BR') == (MODULATE_PROVIDER, 'pt', MODULATE_MODEL)
    assert get_prerecorded_service('zh_Hans') == (MODULATE_PROVIDER, 'zh', MODULATE_MODEL)


def test_missing_language_defaults_to_english():
    assert get_prerecorded_service(None) == (MODULATE_PROVIDER, 'en', MODULATE_MODEL)
