"""Behavioral checks for the shared fail-open PostHog boundary."""

from types import SimpleNamespace

from utils import posthog_telemetry


def _reset_client(monkeypatch) -> None:
    monkeypatch.setattr(posthog_telemetry, '_posthog_client', None)
    monkeypatch.setattr(posthog_telemetry, '_posthog_disabled', False)


def test_capture_failure_is_fail_open_and_records_fallback(monkeypatch):
    class ExplodingClient:
        def capture(self, **_kwargs):
            raise RuntimeError('offline')

    fallbacks = []
    _reset_client(monkeypatch)
    monkeypatch.setattr(posthog_telemetry, '_posthog_client', ExplodingClient())
    monkeypatch.setattr(posthog_telemetry, 'record_fallback', lambda **fields: fallbacks.append(fields))

    posthog_telemetry.emit_posthog_event('user-1', 'Account Deleted', {'result': 'success'})

    assert fallbacks == [
        {
            'component': 'other',
            'from_mode': 'posthog_capture',
            'to_mode': 'telemetry_skipped',
            'reason': 'other',
            'outcome': 'degraded',
            'log': posthog_telemetry.logger,
        }
    ]


def test_client_construction_failure_is_fail_open_and_records_fallback(monkeypatch):
    class ExplodingPosthog:
        def __init__(self, **_kwargs):
            raise RuntimeError('broken sdk')

    fallbacks = []
    _reset_client(monkeypatch)
    monkeypatch.setenv('POSTHOG_PROJECT_API_KEY', 'configured-test-key')
    monkeypatch.setattr(
        posthog_telemetry.importlib,
        'import_module',
        lambda _name: SimpleNamespace(Posthog=ExplodingPosthog),
    )
    monkeypatch.setattr(posthog_telemetry, 'record_fallback', lambda **fields: fallbacks.append(fields))

    posthog_telemetry.emit_posthog_event('user-1', 'Account Deleted', {'result': 'success'})

    assert posthog_telemetry._posthog_disabled is True
    assert fallbacks == [
        {
            'component': 'other',
            'from_mode': 'posthog_client',
            'to_mode': 'telemetry_skipped',
            'reason': 'config_incomplete',
            'outcome': 'degraded',
            'log': posthog_telemetry.logger,
        }
    ]


def test_client_defaults_to_owned_us_ingestion_host(monkeypatch):
    constructed = []

    class RecordingPosthog:
        def __init__(self, **kwargs):
            constructed.append(kwargs)

    _reset_client(monkeypatch)
    monkeypatch.setenv('POSTHOG_PROJECT_API_KEY', 'configured-test-key')
    monkeypatch.delenv('POSTHOG_HOST', raising=False)
    monkeypatch.setattr(
        posthog_telemetry.importlib,
        'import_module',
        lambda _name: SimpleNamespace(Posthog=RecordingPosthog),
    )

    client = posthog_telemetry._get_posthog_client()

    assert isinstance(client, RecordingPosthog)
    assert constructed == [
        {
            'project_api_key': 'configured-test-key',
            'host': 'https://us.i.posthog.com',
        }
    ]
