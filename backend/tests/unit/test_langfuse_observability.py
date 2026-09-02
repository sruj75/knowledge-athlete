import logging
from contextlib import contextmanager
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest

from utils.observability import langfuse as langfuse_observability


@pytest.fixture(autouse=True)
def _reset_client(monkeypatch):
    langfuse_observability.reset_langfuse_client_for_testing()
    monkeypatch.delenv('LANGFUSE_PUBLIC_KEY', raising=False)
    monkeypatch.delenv('LANGFUSE_SECRET_KEY', raising=False)
    monkeypatch.delenv('LANGFUSE_BASE_URL', raising=False)
    yield
    langfuse_observability.reset_langfuse_client_for_testing()


def test_client_requires_both_credentials_and_is_created_lazily(monkeypatch):
    created = []

    class FakeLangfuse:
        def __init__(self, **kwargs):
            created.append(kwargs)

    monkeypatch.setattr(langfuse_observability, 'Langfuse', FakeLangfuse)
    monkeypatch.setenv('LANGFUSE_PUBLIC_KEY', 'public-key')
    assert langfuse_observability.get_langfuse_client() is None
    assert created == []

    monkeypatch.setenv('LANGFUSE_SECRET_KEY', 'secret-key')
    first = langfuse_observability.get_langfuse_client()
    second = langfuse_observability.get_langfuse_client()

    assert first is second
    assert created == [
        {
            'public_key': 'public-key',
            'secret_key': 'secret-key',
            'base_url': 'https://us.cloud.langfuse.com',
        }
    ]


def test_status_logging_never_exposes_credentials(monkeypatch, caplog):
    monkeypatch.setenv('LANGFUSE_PUBLIC_KEY', 'public-sentinel')
    monkeypatch.setenv('LANGFUSE_SECRET_KEY', 'secret-sentinel')
    monkeypatch.setenv('LANGFUSE_BASE_URL', 'https://url-user:url-secret@us.cloud.langfuse.com')

    with caplog.at_level(logging.INFO):
        langfuse_observability.log_langfuse_status()

    assert 'Langfuse tracing enabled' in caplog.text
    assert 'us.cloud.langfuse.com' in caplog.text
    assert 'public-sentinel' not in caplog.text
    assert 'secret-sentinel' not in caplog.text
    assert 'url-user' not in caplog.text
    assert 'url-secret' not in caplog.text


def test_status_logging_is_fail_open_for_malformed_base_url(monkeypatch, caplog):
    monkeypatch.setenv('LANGFUSE_PUBLIC_KEY', 'public-sentinel')
    monkeypatch.setenv('LANGFUSE_SECRET_KEY', 'secret-sentinel')
    monkeypatch.setenv('LANGFUSE_BASE_URL', 'https://[private-invalid-url')

    with caplog.at_level(logging.INFO):
        langfuse_observability.log_langfuse_status()

    assert 'endpoint_host=invalid' in caplog.text
    assert 'private-invalid-url' not in caplog.text


def test_trace_id_is_deterministic_and_session_id_is_bounded():
    first = langfuse_observability.create_chat_trace_id('user-1', 'request-1')
    second = langfuse_observability.create_chat_trace_id('user-1', 'request-1')

    assert first == second
    assert len(first) == 32
    assert langfuse_observability.normalize_session_id('session_1') == 'session_1'
    assert langfuse_observability.normalize_session_id('has space') is None
    assert langfuse_observability.normalize_session_id('x' * 201) is None


def test_generation_uses_real_trace_attributes_prompt_and_usage(monkeypatch):
    propagated = []
    started = []
    updates = []
    ended = []

    class Observation:
        def update(self, **kwargs):
            updates.append(kwargs)

        def end(self):
            ended.append(True)

    class Client:
        def start_observation(self, **kwargs):
            started.append(kwargs)
            return Observation()

    @contextmanager
    def fake_propagate_attributes(**kwargs):
        propagated.append(kwargs)
        yield

    monkeypatch.setattr(langfuse_observability, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(langfuse_observability, 'propagate_attributes', fake_propagate_attributes)
    monkeypatch.setattr(langfuse_observability, 'create_chat_trace_id', lambda *_: 'a' * 32)
    prompt = object()
    payload = {'model': 'claude', 'messages': [{'role': 'user', 'content': 'hello'}]}

    generation = langfuse_observability.start_chat_generation(
        uid='usér-1',
        request_id='request-1',
        session_id='session-1',
        platform='macos',
        model='claude',
        provider_input=payload,
        prompt_version='1',
        prompt_source='langfuse',
        prompt_client=prompt,
        streaming=True,
    )
    started_at = datetime.now(timezone.utc)
    generation.mark_completion_started(started_at)
    generation.finish(output={'text': 'done'}, usage_details={'input': 2, 'output': 1})

    assert propagated == [
        {
            'user_id': 'usér-1',
            'session_id': 'session-1',
            'tags': ['desktop', 'chat', 'streaming'],
            'metadata': {
                'request_id': 'request-1',
                'platform': 'macos',
                'prompt_source': 'langfuse',
                'prompt_version': '1',
            },
            'trace_name': 'desktop-chat-completion',
        }
    ]
    assert started == [
        {
            'trace_context': {'trace_id': 'a' * 32},
            'name': 'desktop-chat-completion',
            'as_type': 'generation',
            'input': payload,
            'model': 'claude',
            'prompt': prompt,
        }
    ]
    assert updates == [
        {'completion_start_time': started_at},
        {
            'output': {'text': 'done'},
            'usage_details': {'input': 2, 'output': 1},
            'level': None,
            'status_message': None,
        },
    ]
    assert ended == [True]


def test_generation_start_failure_is_fail_open(monkeypatch):
    fallbacks = []
    monkeypatch.setattr(
        langfuse_observability,
        'get_langfuse_client',
        lambda: (_ for _ in ()).throw(RuntimeError('private detail')),
    )
    monkeypatch.setattr(langfuse_observability, 'record_fallback', lambda **kwargs: fallbacks.append(kwargs))

    generation = langfuse_observability.start_chat_generation(
        uid='user',
        request_id='request',
        session_id=None,
        platform=None,
        model='claude',
        provider_input={'messages': []},
        prompt_version='fallback',
        prompt_source='fallback',
        prompt_client=None,
        streaming=False,
    )

    generation.finish(output={'text': 'still works'})
    assert generation.observation is None
    assert fallbacks[0]['from_mode'] == 'langfuse_tracing'


def test_trace_id_failure_is_fail_open(monkeypatch):
    fallbacks = []
    monkeypatch.setattr(langfuse_observability, 'get_langfuse_client', lambda: object())
    monkeypatch.setattr(
        langfuse_observability,
        'create_chat_trace_id',
        lambda *_: (_ for _ in ()).throw(RuntimeError('private detail')),
    )
    monkeypatch.setattr(langfuse_observability, 'record_fallback', lambda **kwargs: fallbacks.append(kwargs))

    generation = langfuse_observability.start_chat_generation(
        uid='user',
        request_id='request',
        session_id='session',
        platform='macos',
        model='claude',
        provider_input={'messages': []},
        prompt_version='1',
        prompt_source='langfuse',
        prompt_client=object(),
        streaming=True,
    )

    assert generation.observation is None
    assert generation.trace_id is None
    assert fallbacks[0]['from_mode'] == 'langfuse_tracing'


def test_shutdown_flushes_the_existing_client_once():
    client = SimpleNamespace(shutdown=lambda: setattr(client, 'shutdown_called', True), shutdown_called=False)
    langfuse_observability._client = client
    langfuse_observability._client_configuration = ('public', 'secret', 'host')

    langfuse_observability.shutdown_langfuse()
    langfuse_observability.shutdown_langfuse()

    assert client.shutdown_called is True
    assert langfuse_observability._client is None
