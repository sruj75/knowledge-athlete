from unittest.mock import MagicMock

import httpx
import pytest

from routers import desktop_tts_updates
from routers.desktop_tts_updates import ReleaseInfo, _appcast_xml, _is_allowed_openai_voice, _manual_download_url


@pytest.mark.asyncio
async def test_tts_uses_managed_key_and_metering_when_legacy_customer_key_exists(monkeypatch):
    from utils.byok import set_byok_keys

    captured = {}

    class FakeClient:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_args):
            return None

        async def post(self, url, *, headers, json):
            captured.update(url=url, headers=headers, json=json)
            return httpx.Response(200, content=b'mp3')

    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    meter = MagicMock(return_value=(0, 1))
    monkeypatch.setenv('OPENAI_API_KEY', 'managed-openai-key')
    monkeypatch.setattr(desktop_tts_updates, 'is_trial_paywalled', lambda _uid, _source: False)
    monkeypatch.setattr(desktop_tts_updates, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_tts_updates.redis_db, 'check_tts_rate_limit', meter)
    monkeypatch.setattr(desktop_tts_updates.httpx, 'AsyncClient', lambda **_kwargs: FakeClient())

    set_byok_keys({'openai': 'legacy-customer-key'})
    try:
        response = await desktop_tts_updates.tts_synthesize(
            desktop_tts_updates.TtsSynthesizeRequest(text='hello', voice_id='marin'), uid='managed-user'
        )
    finally:
        set_byok_keys({})

    assert response.body == b'mp3'
    assert captured['headers']['Authorization'] == 'Bearer managed-openai-key'
    meter.assert_called_once()


def _release(**overrides):
    values = {
        "version": "1.0.0",
        "build_number": 1,
        "download_url": "https://example.com/Omi.zip",
        "ed_signature": "signature",
        "published_at": "2026-07-26T00:00:00Z",
        "is_live": True,
    }
    values.update(overrides)
    return ReleaseInfo(**values)


def test_openai_tts_voices_match_rust_contract():
    assert _is_allowed_openai_voice("marin")
    assert _is_allowed_openai_voice("cedar")
    assert not _is_allowed_openai_voice("BAMYoBHLZM7lJgJAmFz0")


def test_appcast_deduplicates_staging_and_preserves_stable_default_channel():
    xml = _appcast_xml(
        [
            _release(version="2.0.0"),
            _release(version="1.0.0", channel="staging"),
            _release(version="3.0.0", channel="stable"),
        ],
        "macos",
    )
    assert "Omi 2.0.0" in xml
    assert "Omi 1.0.0" not in xml
    assert "Omi 3.0.0" in xml
    assert xml.count("<sparkle:channel>") == 1


def test_manual_download_prefers_explicit_dmg_then_github_zip_derivation():
    assert (
        _manual_download_url(_release(manual_download_url="https://example.com/custom.dmg"))
        == "https://example.com/custom.dmg"
    )
    assert _manual_download_url(_release()) == "https://example.com/Omi.dmg"
