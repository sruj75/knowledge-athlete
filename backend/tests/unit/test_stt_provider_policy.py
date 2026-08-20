"""Regression coverage for the single source of truth governing STT serving."""

from pathlib import Path

import pytest

from config.stt_provider_policy import (
    MODULATE_MODEL,
    MODULATE_PROVIDER,
    STTServingSurface,
    modulate_supports_language,
    supports_live_multilingual_mode,
)


def test_every_managed_surface_has_one_fixed_modulate_adapter():
    assert MODULATE_PROVIDER == 'modulate'
    assert MODULATE_MODEL == 'modulate-velma-2'
    assert set(STTServingSurface) == {
        STTServingSurface.STREAMING,
        STTServingSurface.PRERECORDED,
        STTServingSurface.PTT,
    }


def test_live_multilingual_policy_normalizes_supported_locales_and_rejects_unknown_languages():
    assert supports_live_multilingual_mode('zh-TW')
    assert supports_live_multilingual_mode('ar')
    assert modulate_supports_language('es-419')
    assert not supports_live_multilingual_mode('xx-unsupported')


# ---------------------------------------------------------------------------
# #10022: user language preference gate must follow the live policy
# ---------------------------------------------------------------------------


def test_user_language_route_gates_multilingual_mode_by_live_policy():
    """Static tripwire (source order, not behavior): the PATCH /v1/users/language
    response derives single_language_mode from the live STT capability policy,
    without reviving cloud transcription-preference persistence (#10022)."""
    users_py = (Path(__file__).resolve().parents[2] / 'routers' / 'users.py').read_text(encoding='utf-8')
    assert 'single_language_mode = not supports_live_multilingual_mode(language)' in users_py
    assert 'set_user_transcription_preferences' not in users_py
    assert 'deepgram_nova3_multi_languages' not in users_py


@pytest.mark.parametrize('language', ['vi', 'vi-VN', 'ko', 'tr', 'ar', 'th', 'pt-BR', 'en'])
def test_live_policy_admits_languages_beyond_the_retired_deepgram_list(language):
    """vi/ko/tr/ar/th were wrongly locked into single-language mode by the old
    19-locale Deepgram list; en/pt-BR keep their existing eligibility."""
    assert supports_live_multilingual_mode(language) is True


@pytest.mark.parametrize('language', ['my', 'am', 'lo'])
def test_live_policy_rejects_languages_outside_modulate_auto_detection(language):
    assert supports_live_multilingual_mode(language) is False
