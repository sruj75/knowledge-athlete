from __future__ import annotations

from types import SimpleNamespace

import pytest

from database import desktop_previews
from utils.other import storage


def test_update_storage_requires_owned_bucket_and_retained_prefix(monkeypatch):
    monkeypatch.delenv('BUCKET_DESKTOP_UPDATES', raising=False)
    with pytest.raises(RuntimeError, match='BUCKET_DESKTOP_UPDATES'):
        storage.get_desktop_update_signed_url('updates/stable/app.dmg')

    monkeypatch.setenv('BUCKET_DESKTOP_UPDATES', 'owned-desktop-artifacts')
    with pytest.raises(ValueError, match='updates/ or previews/'):
        storage.get_desktop_update_signed_url('private/conversations/export.zip')


def test_signed_url_uses_injected_client_and_owned_bucket(monkeypatch):
    monkeypatch.setenv('BUCKET_DESKTOP_UPDATES', 'owned-desktop-artifacts')
    blob = SimpleNamespace(name='updates/stable/app.dmg')
    bucket = SimpleNamespace(blob=lambda path: blob if path == blob.name else None)
    client = SimpleNamespace(bucket=lambda name: bucket if name == 'owned-desktop-artifacts' else None)
    monkeypatch.setattr(storage, '_get_storage_client', lambda: client)
    monkeypatch.setattr(storage, '_get_signed_url', lambda selected, minutes, client: f'{selected.name}:{minutes}')

    assert storage.get_desktop_update_signed_url('updates/stable/app.dmg', expiration_hours=2) == (
        'updates/stable/app.dmg:120'
    )


def test_hosted_signed_url_uses_adc_iam_signing(monkeypatch):
    monkeypatch.setenv('OMI_ENV_STAGE', 'prod')
    monkeypatch.setenv('BACKEND_RUNTIME_SERVICE_ACCOUNT', 'backend-runtime@owned-prod.iam.gserviceaccount.com')
    credentials = SimpleNamespace(token=None, valid=False)

    def refresh(_request):
        credentials.token = 'short-lived-access-token'
        credentials.valid = True

    credentials.refresh = refresh
    client = SimpleNamespace(_credentials=credentials)
    calls = []
    blob = SimpleNamespace(
        name='updates/stable/app.dmg',
        generate_signed_url=lambda **kwargs: calls.append(kwargs) or 'https://signed.example/object',
    )
    monkeypatch.setattr(storage, 'get_cached_signed_url', lambda _name: '')
    monkeypatch.setattr(storage, 'cache_signed_url', lambda *_args: None)

    assert storage._get_signed_url(blob, 60, client=client) == 'https://signed.example/object'
    assert calls[0]['credentials'] is credentials
    assert calls[0]['service_account_email'] == 'backend-runtime@owned-prod.iam.gserviceaccount.com'
    assert calls[0]['access_token'] == 'short-lived-access-token'


def test_hosted_signed_url_fails_without_explicit_runtime_identity(monkeypatch):
    monkeypatch.setenv('OMI_ENV_STAGE', 'dev')
    monkeypatch.delenv('BACKEND_RUNTIME_SERVICE_ACCOUNT', raising=False)

    with pytest.raises(RuntimeError, match='BACKEND_RUNTIME_SERVICE_ACCOUNT'):
        storage._hosted_signing_kwargs(SimpleNamespace())


def test_preview_url_uses_same_owned_bucket_coordinate(monkeypatch):
    monkeypatch.setenv('BUCKET_DESKTOP_UPDATES', 'owned-desktop-artifacts')
    slug = 'new-onboarding'
    source_sha = 'a' * 40
    data = {
        'dmg_url': f'https://storage.googleapis.com/owned-desktop-artifacts/previews/{slug}/{source_sha}/Intentive-Preview.dmg'
    }

    assert desktop_previews._preview_dmg_url(data, slug=slug, source_sha=source_sha) == data['dmg_url']
