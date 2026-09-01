import asyncio
import json
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

from routers import desktop_chat
from utils.llm import model_config
from utils.observability import langfuse as langfuse_observability
from utils.observability.langfuse import ChatGeneration
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt


_BLANK_REMOTE_PROMPT = ResolvedRuntimePrompt(
    text='',
    name='intentive-chat-system',
    version='1',
    source='langfuse',
    prompt_client=object(),
)


@pytest.fixture(autouse=True)
def _disable_real_langfuse(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: ChatGeneration(None, None))


def _stream_kwargs() -> dict[str, object]:
    return {
        'request_id': 'request-1',
        'session_id': 'session-1',
        'platform': 'macos',
        'prompt': _BLANK_REMOTE_PROMPT,
    }


def test_anthropic_adapter_uses_managed_client():
    from utils.llm import clients

    managed_messages = object()
    proxy = clients._AnthropicClientProxy(default=SimpleNamespace(messages=managed_messages))
    assert proxy.messages is managed_messages


def test_anthropic_adapter_has_no_retired_gateway_controls():
    from utils.llm import clients

    managed_messages = object()
    proxy = clients._AnthropicClientProxy(default=SimpleNamespace(messages=managed_messages))

    assert proxy.messages is managed_messages
    assert not hasattr(clients, 'get_gateway_anthropic_client')
    assert not hasattr(clients, 'should_route_features_through_gateway')


def test_request_translates_openai_tool_history_and_alias():
    public_model, payload = desktop_chat._request(
        {
            'model': 'omi-sonnet',
            'max_completion_tokens': 20_000,
            'messages': [
                {'role': 'developer', 'content': 'be concise'},
                {
                    'role': 'assistant',
                    'tool_calls': [
                        {
                            'id': 'call_1',
                            'type': 'function',
                            'function': {'name': 'weather', 'arguments': '{"city":"NYC"}'},
                        }
                    ],
                },
                {'role': 'tool', 'tool_call_id': 'call_1', 'content': 'sunny'},
            ],
            'tools': [{'type': 'function', 'function': {'name': 'weather', 'parameters': {'type': 'object'}}}],
            'tool_choice': 'auto',
        }
    )
    assert public_model == 'omi-sonnet'
    assert payload['model'] == model_config.get_model('chat_agent')
    assert payload['max_tokens'] == 16_384
    assert payload['system'] == 'be concise'
    assert payload['messages'][1]['content'][0]['tool_use_id'] == 'call_1'
    assert payload['tool_choice'] == {'type': 'auto'}


@pytest.mark.parametrize(
    'retired_alias',
    [
        'omi-opus',
        'claude-opus-4-6',
        'claude-opus-4-20250514',
        'claude-sonnet-4-6',
        'claude-sonnet-4-20250514',
        'claude-haiku-4-5',
        'claude-haiku-4-5-20251001',
    ],
)
def test_request_rejects_noncanonical_model_aliases(retired_alias):
    with pytest.raises(ValueError, match='unsupported model'):
        desktop_chat._request({'model': retired_alias, 'messages': []})


def test_response_preserves_openai_tool_and_cache_usage():
    message = SimpleNamespace(
        id='msg_1',
        content=[SimpleNamespace(type='tool_use', id='call_1', name='weather', input={'city': 'NYC'})],
        stop_reason='tool_use',
        usage=SimpleNamespace(
            input_tokens=3, cache_creation_input_tokens=2, cache_read_input_tokens=5, output_tokens=7
        ),
    )
    response = desktop_chat._message_response(message, 'omi-sonnet')
    assert response['choices'][0]['finish_reason'] == 'tool_calls'
    assert json.loads(response['choices'][0]['message']['tool_calls'][0]['function']['arguments']) == {'city': 'NYC'}
    assert response['usage'] == {
        'prompt_tokens': 10,
        'completion_tokens': 7,
        'total_tokens': 17,
        'prompt_tokens_details': {'cached_tokens': 5},
    }


@pytest.mark.asyncio
async def test_stream_emits_openai_terminal_event(monkeypatch):
    class Stream:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        def __aiter__(self):
            async def events():
                yield SimpleNamespace(
                    type='content_block_delta', delta=SimpleNamespace(type='text_delta', text='hello')
                )
                yield SimpleNamespace(
                    type='message_delta',
                    delta=SimpleNamespace(stop_reason='end_turn'),
                    usage=SimpleNamespace(
                        input_tokens=1, cache_creation_input_tokens=0, cache_read_input_tokens=0, output_tokens=1
                    ),
                )

            return events()

    monkeypatch.setattr(
        desktop_chat, 'anthropic_client', SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: Stream()))
    )

    async def record_usage(*_):
        return None

    monkeypatch.setattr(desktop_chat, '_record_usage', record_usage)
    events = [
        event
        async for event in desktop_chat._stream(
            {'model': 'claude-sonnet-4-6', 'max_tokens': 1, 'messages': []},
            'omi-sonnet',
            'user',
            **_stream_kwargs(),
        )
    ]
    assert json.loads(events[1][6:])['choices'][0]['delta'] == {'content': 'hello'}
    assert events[-1] == 'data: [DONE]\n\n'


@pytest.mark.asyncio
async def test_stream_reports_managed_provider_failure_without_echoing_detail(monkeypatch):
    sentinel = 'private upstream detail'
    recorded = []
    finished = []

    class Generation:
        def finish(self, **kwargs):
            finished.append(kwargs)

    class FailedStream:
        async def __aenter__(self):
            raise RuntimeError(sentinel)

        async def __aexit__(self, *_):
            return None

    monkeypatch.setattr(
        desktop_chat,
        'anthropic_client',
        SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: FailedStream())),
    )
    monkeypatch.setattr(desktop_chat, 'handle_llm_error', lambda *args, **kwargs: recorded.append((args, kwargs)))
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: Generation())

    events = [
        event
        async for event in desktop_chat._stream(
            {'model': 'claude-sonnet-4-6', 'max_tokens': 1, 'messages': []},
            'omi-sonnet',
            'user',
            **_stream_kwargs(),
        )
    ]

    assert recorded[0][0][1] == 'anthropic'
    assert recorded[0][1] == {'feature': 'chat_agent', 'model': model_config.get_model('chat_agent')}
    assert sentinel not in ''.join(events)
    assert finished[0]['level'] == 'ERROR'
    assert finished[0]['status_message'] == 'RuntimeError'
    assert sentinel not in str(finished)


@pytest.mark.asyncio
async def test_stream_records_cancellation_and_preserves_cancellation(monkeypatch):
    finished = []

    class Generation:
        def finish(self, **kwargs):
            finished.append(kwargs)

    class CancelledStream:
        async def __aenter__(self):
            raise asyncio.CancelledError

        async def __aexit__(self, *_):
            return None

    monkeypatch.setattr(
        desktop_chat,
        'anthropic_client',
        SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: CancelledStream())),
    )
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: Generation())
    stream = desktop_chat._stream(
        {'model': 'claude-sonnet-4-6', 'max_tokens': 1, 'messages': []},
        'omi-sonnet',
        'user',
        **_stream_kwargs(),
    )

    with pytest.raises(asyncio.CancelledError):
        await anext(stream)

    assert finished[0]['level'] == 'WARNING'
    assert finished[0]['status_message'] == 'cancelled'


@pytest.mark.asyncio
async def test_stream_close_records_cancelled_generation(monkeypatch):
    finished = []

    class Generation:
        def mark_completion_started(self, _value):
            return None

        def finish(self, **kwargs):
            finished.append(kwargs)

    class Stream:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        def __aiter__(self):
            async def events():
                yield SimpleNamespace(
                    type='content_block_delta',
                    delta=SimpleNamespace(type='text_delta', text='partial'),
                )

            return events()

    monkeypatch.setattr(
        desktop_chat,
        'anthropic_client',
        SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: Stream())),
    )
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: Generation())
    stream = desktop_chat._stream(
        {'model': 'claude-sonnet-4-6', 'max_tokens': 1, 'messages': []},
        'omi-sonnet',
        'user',
        **_stream_kwargs(),
    )

    await anext(stream)
    await stream.aclose()

    assert finished[0]['level'] == 'WARNING'
    assert finished[0]['status_message'] == 'cancelled'


@pytest.mark.asyncio
async def test_stream_records_generation_output_first_token_usage_and_prompt(monkeypatch):
    started = []
    first_tokens = []
    finished = []
    provider_events = []

    class Generation:
        def mark_completion_started(self, value):
            first_tokens.append((value, list(provider_events)))

        def finish(self, **kwargs):
            finished.append(kwargs)

    class Stream:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        def __aiter__(self):
            async def events():
                provider_events.append('message_start')
                yield SimpleNamespace(type='message_start')
                provider_events.append('empty_text_start')
                yield SimpleNamespace(
                    type='content_block_start',
                    index=0,
                    content_block=SimpleNamespace(type='text', text=''),
                )
                provider_events.append('tool_use_start')
                yield SimpleNamespace(
                    type='content_block_start',
                    index=0,
                    content_block=SimpleNamespace(type='tool_use', id='call-1', name='lookup'),
                )
                yield SimpleNamespace(
                    type='content_block_delta',
                    index=0,
                    delta=SimpleNamespace(type='input_json_delta', partial_json='{"query":"one"}'),
                )
                yield SimpleNamespace(
                    type='content_block_delta',
                    index=1,
                    delta=SimpleNamespace(type='text_delta', text='done'),
                )
                yield SimpleNamespace(
                    type='message_delta',
                    delta=SimpleNamespace(stop_reason='tool_use'),
                    usage=SimpleNamespace(
                        input_tokens=3,
                        output_tokens=4,
                        cache_read_input_tokens=5,
                        cache_creation_input_tokens=6,
                    ),
                )

            return events()

    monkeypatch.setattr(
        desktop_chat, 'anthropic_client', SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: Stream()))
    )
    monkeypatch.setattr(
        desktop_chat,
        'start_chat_generation',
        lambda **kwargs: (started.append(kwargs), Generation())[1],
    )

    async def record_usage(*_):
        return None

    monkeypatch.setattr(desktop_chat, '_record_usage', record_usage)
    payload = {'model': 'claude-sonnet-4-6', 'max_tokens': 1, 'messages': []}

    events = [event async for event in desktop_chat._stream(payload, 'omi-sonnet', 'user', **_stream_kwargs())]

    assert events[-1] == 'data: [DONE]\n\n'
    assert len(first_tokens) == 1
    assert first_tokens[0][1] == ['message_start', 'empty_text_start', 'tool_use_start']
    assert started[0]['provider_input'] is payload
    assert started[0]['prompt_client'] is _BLANK_REMOTE_PROMPT.prompt_client
    assert finished == [
        {
            'output': {
                'text': 'done',
                'stop_reason': 'tool_use',
                'tool_calls': [{'id': 'call-1', 'name': 'lookup', 'arguments': '{"query":"one"}'}],
            },
            'usage_details': {
                'input': 3,
                'output': 4,
                'cache_read_input_tokens': 5,
                'cache_creation_input_tokens': 6,
            },
            'level': None,
            'status_message': None,
        }
    ]


@pytest.mark.asyncio
async def test_blank_remote_prompt_keeps_kernel_policy_and_nonstream_trace(monkeypatch):
    started = []
    finished = []

    class Generation:
        def finish(self, **kwargs):
            finished.append(kwargs)

    async def run_blocking(_, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def meter(*_):
        return None

    async def record_usage(*_):
        return None

    message = SimpleNamespace(
        id='message-1',
        content=[SimpleNamespace(type='text', text='hello')],
        stop_reason='end_turn',
        usage=SimpleNamespace(
            input_tokens=2,
            output_tokens=1,
            cache_read_input_tokens=0,
            cache_creation_input_tokens=0,
        ),
    )
    provider_payloads = []

    async def create_message(_messages, payload):
        provider_payloads.append(payload)
        return message

    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(desktop_chat, 'enforce_chat_quota', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, '_meter_server_request', meter)
    monkeypatch.setattr(desktop_chat, 'run_blocking', run_blocking)
    monkeypatch.setattr(desktop_chat.llm_usage_db, 'record_chat_quota_question', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, 'get_runtime_prompt', lambda: _BLANK_REMOTE_PROMPT)
    monkeypatch.setattr(desktop_chat, 'create_managed_anthropic_message', create_message)
    monkeypatch.setattr(desktop_chat, '_record_usage', record_usage)
    monkeypatch.setattr(
        desktop_chat,
        'start_chat_generation',
        lambda **kwargs: (started.append(kwargs), Generation())[1],
    )

    response = await desktop_chat.chat_completions(
        {'model': 'omi-sonnet', 'messages': [{'role': 'developer', 'content': 'kernel policy'}]},
        uid='user-1',
        x_app_platform='macos',
        x_omi_chat_contract_version='1',
        x_omi_request_id='request-1',
        x_omi_session_id='session-1',
    )

    assert response.status_code == 200
    assert provider_payloads[0]['system'] == 'kernel policy'
    assert started[0]['session_id'] == 'session-1'
    assert started[0]['provider_input'] is provider_payloads[0]
    assert finished[0]['output'] == {'text': 'hello', 'stop_reason': 'end_turn'}
    assert finished[0]['usage_details'] == {
        'input': 2,
        'output': 1,
        'cache_read_input_tokens': 0,
        'cache_creation_input_tokens': 0,
    }


@pytest.mark.asyncio
@pytest.mark.parametrize('streaming', [False, True])
async def test_endpoint_is_fail_open_when_prompt_and_tracing_are_unavailable(monkeypatch, streaming):
    async def run_blocking(_, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def meter(*_):
        return None

    async def record_usage(*_):
        return None

    usage = SimpleNamespace(
        input_tokens=2,
        output_tokens=1,
        cache_read_input_tokens=0,
        cache_creation_input_tokens=0,
    )
    message = SimpleNamespace(
        id='message-1',
        content=[SimpleNamespace(type='text', text='hello')],
        stop_reason='end_turn',
        usage=usage,
    )

    class Stream:
        async def __aenter__(self):
            return self

        async def __aexit__(self, *_):
            return None

        def __aiter__(self):
            async def events():
                yield SimpleNamespace(
                    type='content_block_delta',
                    delta=SimpleNamespace(type='text_delta', text='hello'),
                )
                yield SimpleNamespace(
                    type='message_delta',
                    delta=SimpleNamespace(stop_reason='end_turn'),
                    usage=usage,
                )

            return events()

    async def create_message(_messages, _payload):
        return message

    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(desktop_chat, 'enforce_chat_quota', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, '_meter_server_request', meter)
    monkeypatch.setattr(desktop_chat, 'run_blocking', run_blocking)
    monkeypatch.setattr(desktop_chat.llm_usage_db, 'record_chat_quota_question', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(
        desktop_chat,
        'get_runtime_prompt',
        lambda: (_ for _ in ()).throw(RuntimeError('prompt unavailable')),
    )
    monkeypatch.setattr(
        langfuse_observability,
        'get_langfuse_client',
        lambda: (_ for _ in ()).throw(RuntimeError('tracing unavailable')),
    )
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', langfuse_observability.start_chat_generation)
    monkeypatch.setattr(desktop_chat, 'create_managed_anthropic_message', create_message)
    monkeypatch.setattr(desktop_chat, '_record_usage', record_usage)
    monkeypatch.setattr(
        desktop_chat,
        'anthropic_client',
        SimpleNamespace(messages=SimpleNamespace(stream=lambda **_: Stream())),
    )

    response = await desktop_chat.chat_completions(
        {
            'model': 'omi-sonnet',
            'messages': [{'role': 'developer', 'content': 'kernel policy'}],
            'stream': streaming,
        },
        uid='user-1',
        x_app_platform='macos',
        x_omi_chat_contract_version='1',
        x_omi_request_id='request-1',
        x_omi_session_id='session-1',
    )

    if streaming:
        chunks = [chunk async for chunk in response.body_iterator]
        assert chunks[-1] == 'data: [DONE]\n\n'
        assert any('hello' in chunk for chunk in chunks)
    else:
        assert response.status_code == 200
        assert json.loads(response.body)['choices'][0]['message']['content'] == 'hello'


@pytest.mark.asyncio
async def test_nonstream_records_cancellation_and_preserves_cancellation(monkeypatch):
    finished = []

    class Generation:
        def finish(self, **kwargs):
            finished.append(kwargs)

    async def run_blocking(_, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def meter(*_):
        return None

    async def cancel_message(*_):
        raise asyncio.CancelledError

    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(desktop_chat, 'enforce_chat_quota', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, '_meter_server_request', meter)
    monkeypatch.setattr(desktop_chat, 'run_blocking', run_blocking)
    monkeypatch.setattr(desktop_chat.llm_usage_db, 'record_chat_quota_question', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, 'get_runtime_prompt', lambda: _BLANK_REMOTE_PROMPT)
    monkeypatch.setattr(desktop_chat, 'create_managed_anthropic_message', cancel_message)
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: Generation())

    with pytest.raises(asyncio.CancelledError):
        await desktop_chat.chat_completions(
            {'model': 'omi-sonnet', 'messages': []},
            uid='user-1',
            x_app_platform='macos',
            x_omi_chat_contract_version='1',
            x_omi_request_id='request-1',
            x_omi_session_id='session-1',
        )

    assert finished == [
        {
            'output': {'cancelled': True},
            'level': 'WARNING',
            'status_message': 'cancelled',
        }
    ]


@pytest.mark.asyncio
async def test_offline_stub_never_touches_prompt_or_tracing(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: True)
    monkeypatch.setattr(
        desktop_chat,
        'get_runtime_prompt',
        lambda: (_ for _ in ()).throw(AssertionError('prompt lookup must stay offline')),
    )
    monkeypatch.setattr(
        desktop_chat,
        'start_chat_generation',
        lambda **_: (_ for _ in ()).throw(AssertionError('tracing must stay offline')),
    )
    monkeypatch.setattr(desktop_chat, 'stub_chat_completions_json', lambda _body: {'stub': True})

    response = await desktop_chat.chat_completions(
        {'model': 'omi-sonnet', 'messages': []},
        uid='offline-user',
        x_app_platform='macos',
        x_omi_chat_contract_version='1',
        x_omi_request_id='offline-request',
        x_omi_session_id='offline-session',
    )

    assert json.loads(response.body) == {'stub': True}


@pytest.mark.asyncio
async def test_server_metering_fails_closed_when_rate_limit_storage_fails(monkeypatch):
    async def run_blocking(_, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_chat, 'run_blocking', run_blocking)
    monkeypatch.setattr(desktop_chat.redis_db, 'check_rate_limit', lambda *_: (_ for _ in ()).throw(RuntimeError()))

    with pytest.raises(desktop_chat.HTTPException) as error:
        await desktop_chat._meter_server_request('user')
    assert error.value.status_code == 503


@pytest.mark.asyncio
async def test_server_metering_rejects_exhausted_user(monkeypatch):
    async def run_blocking(_, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_chat, 'run_blocking', run_blocking)
    monkeypatch.setattr(desktop_chat.redis_db, 'check_rate_limit', lambda *_: (False, 0, 37))

    with pytest.raises(desktop_chat.HTTPException) as error:
        await desktop_chat._meter_server_request('user')
    assert error.value.status_code == 429
    assert error.value.headers == {'Retry-After': '37'}
