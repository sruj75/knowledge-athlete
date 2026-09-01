import asyncio
import json
from types import SimpleNamespace

import httpx
import pytest
from fastapi import HTTPException

from routers import desktop_chat
from utils.observability.langfuse import ChatGeneration
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt

_PROMPT = ResolvedRuntimePrompt(
    text='',
    name='intentive-chat-system',
    version='1',
    source='fallback',
    prompt_client=None,
)


@pytest.fixture(autouse=True)
def _disable_real_langfuse(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'start_chat_generation', lambda **_: ChatGeneration(None, None))


def _native_body() -> dict[str, object]:
    return {
        'contents': [
            {'role': 'user', 'parts': [{'text': 'hello'}, {'inlineData': {'mimeType': 'image/png', 'data': 'AA=='}}]},
            {
                'role': 'model',
                'parts': [
                    {
                        'functionCall': {'name': 'lookup', 'args': {'query': 'one'}},
                        'thoughtSignature': 'c2lnbmF0dXJl',
                    }
                ],
            },
            {
                'role': 'user',
                'parts': [{'functionResponse': {'name': 'lookup', 'response': {'output': 'result'}}}],
            },
        ],
        'tools': [{'functionDeclarations': [{'name': 'lookup', 'parametersJsonSchema': {'type': 'object'}}]}],
        'generationConfig': {'maxOutputTokens': 99_999, 'thinkingConfig': {'thinkingLevel': 'MEDIUM'}},
    }


def test_native_request_preserves_gemini_content_tools_images_and_thought_signature():
    body = _native_body()
    original_contents = json.loads(json.dumps(body['contents']))
    original_tools = json.loads(json.dumps(body['tools']))

    payload = desktop_chat._validate_native_request('gemini-3.7-flash', body, 'sse')

    assert payload['contents'] == original_contents
    assert payload['tools'] == original_tools
    assert payload['generationConfig']['maxOutputTokens'] == 16_384
    assert payload['contents'][1]['parts'][0]['thoughtSignature'] == 'c2lnbmF0dXJl'


@pytest.mark.parametrize('level', ['MINIMAL', 'XHIGH', 'off'])
def test_native_request_rejects_unadvertised_thinking_levels(level):
    body = _native_body()
    body['generationConfig']['thinkingConfig']['thinkingLevel'] = level
    with pytest.raises(ValueError, match='unsupported thinkingLevel'):
        desktop_chat._validate_native_request('gemini-3.7-flash', body, 'sse')


def test_native_request_rejects_aliases_and_non_sse_modes():
    with pytest.raises(ValueError, match='unsupported model'):
        desktop_chat._validate_native_request('omi-sonnet', {'contents': []}, 'sse')
    with pytest.raises(ValueError, match='alt must be sse'):
        desktop_chat._validate_native_request('gemini-3.7-flash', {'contents': []}, 'json')


@pytest.mark.parametrize(
    ('field_path', 'value', 'message'),
    [
        (('cachedContent',), 'cachedContents/client-owned', 'unsupported request field'),
        (('generationConfig', 'responseMimeType'), 'application/json', 'unsupported generationConfig field'),
        (('generationConfig', 'thinkingConfig', 'thinkingBudget'), 100, 'unsupported thinkingConfig field'),
    ],
)
def test_native_request_rejects_fields_outside_the_managed_chat_contract(field_path, value, message):
    body = _native_body()
    target = body
    for key in field_path[:-1]:
        target = target[key]
    target[field_path[-1]] = value

    with pytest.raises(ValueError, match=message):
        desktop_chat._validate_native_request('gemini-3.7-flash', body, 'sse')


class _Response:
    def __init__(self, chunks: list[bytes]):
        self.chunks = chunks

    def raise_for_status(self):
        return None

    def aiter_raw(self):
        async def iterator():
            for chunk in self.chunks:
                yield chunk

        return iterator()


class _Manager:
    def __init__(self, response: _Response | None = None, error: Exception | None = None):
        self.response = response
        self.error = error

    async def __aenter__(self):
        if self.error is not None:
            raise self.error
        return self.response

    async def __aexit__(self, *_):
        return None


class _Client:
    def __init__(self, manager: _Manager):
        self.manager = manager
        self.calls: list[tuple[tuple[object, ...], dict[str, object]]] = []

    def stream(self, *args, **kwargs):
        self.calls.append((args, kwargs))
        return self.manager


class _Semaphore:
    def __init__(self):
        self.entries = 0

    async def __aenter__(self):
        self.entries += 1

    async def __aexit__(self, *_):
        return None


@pytest.mark.asyncio
async def test_stream_relays_raw_gemini_sse_and_tees_terminal_usage(monkeypatch):
    first = (
        b'data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"lookup",'
        b'"args":{"query":"one"}},"thoughtSignature":"c2ln"}]},"finishReason":"STOP"}]}\n\n'
    )
    terminal = (
        b'data: {"usageMetadata":{"promptTokenCount":7,"cachedContentTokenCount":2,'
        b'"candidatesTokenCount":3,"thoughtsTokenCount":1,"totalTokenCount":11}}\n\n'
    )
    client = _Client(_Manager(_Response([first, terminal])))
    semaphore = _Semaphore()
    recorded: list[tuple[object, ...]] = []
    monkeypatch.setattr(desktop_chat, 'get_gemini_client', lambda: client)
    monkeypatch.setattr(desktop_chat, 'get_gemini_semaphore', lambda: semaphore)

    async def record(*args):
        recorded.append(args)

    monkeypatch.setattr(desktop_chat, '_record_usage', record)
    stream = desktop_chat._stream_native_gemini(
        _native_body(),
        'user-1',
        api_key='server-gemini-secret',
        request_id='request-1',
        session_id='session-1',
        platform='macos',
        prompt=_PROMPT,
    )

    chunks = [chunk async for chunk in stream]

    assert chunks == [first, terminal]
    assert b'c2ln' in chunks[0]
    assert b'server-gemini-secret' not in b''.join(chunks)
    assert semaphore.entries == 1
    assert client.calls[0][1]['headers']['x-goog-api-key'] == 'server-gemini-secret'
    assert recorded == [
        (
            'user-1',
            {
                'promptTokenCount': 7,
                'cachedContentTokenCount': 2,
                'candidatesTokenCount': 3,
                'thoughtsTokenCount': 1,
                'totalTokenCount': 11,
            },
        )
    ]


@pytest.mark.asyncio
async def test_stream_sanitizes_upstream_failure(monkeypatch):
    private_detail = 'private upstream response'
    client = _Client(_Manager(error=RuntimeError(private_detail)))
    recorded = []
    monkeypatch.setattr(desktop_chat, 'get_gemini_client', lambda: client)
    monkeypatch.setattr(desktop_chat, 'handle_llm_error', lambda *args, **kwargs: recorded.append((args, kwargs)))

    chunks = [
        chunk
        async for chunk in desktop_chat._stream_native_gemini(
            {'contents': []},
            'user-1',
            api_key='secret',
            request_id='request-1',
            session_id=None,
            platform='macos',
            prompt=_PROMPT,
        )
    ]

    assert private_detail.encode() not in b''.join(chunks)
    assert json.loads(chunks[-1][6:])['error']['message'] == 'Upstream provider error'
    assert recorded[0][0][1] == 'gemini'


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ('status_code', 'reason', 'status', 'retryable'),
    [
        (401, 'provider_auth_failed', 'UNAUTHENTICATED', False),
        (429, 'provider_quota_exceeded', 'RESOURCE_EXHAUSTED', True),
    ],
)
async def test_stream_types_provider_owned_auth_and_quota_failures(monkeypatch, status_code, reason, status, retryable):
    request = httpx.Request('POST', 'https://generativelanguage.googleapis.com/v1beta/models/test')
    response = httpx.Response(status_code, request=request)
    client = _Client(
        _Manager(error=httpx.HTTPStatusError('sanitized upstream failure', request=request, response=response))
    )
    monkeypatch.setattr(desktop_chat, 'get_gemini_client', lambda: client)
    monkeypatch.setattr(desktop_chat, 'handle_llm_error', lambda *args, **kwargs: None)

    chunks = [
        chunk
        async for chunk in desktop_chat._stream_native_gemini(
            {'contents': []},
            'user-1',
            api_key='secret',
            request_id='request-1',
            session_id=None,
            platform='macos',
            prompt=_PROMPT,
        )
    ]

    payload = json.loads(chunks[-1][6:])
    assert payload['error'] == {
        'code': status_code,
        'message': 'Upstream provider error',
        'status': status,
    }
    assert payload['reason'] == reason
    assert payload['provider'] == 'gemini'
    assert payload['backend_route'] == '/v2/models/gemini-3.7-flash:streamGenerateContent'
    assert payload['upstream_status_code'] == status_code
    assert payload['retryable'] is retryable
    assert b'sanitized upstream failure' not in b''.join(chunks)


@pytest.mark.asyncio
async def test_stream_preserves_cancellation(monkeypatch):
    client = _Client(_Manager(error=asyncio.CancelledError()))
    monkeypatch.setattr(desktop_chat, 'get_gemini_client', lambda: client)
    stream = desktop_chat._stream_native_gemini(
        {'contents': []},
        'user-1',
        api_key='secret',
        request_id='request-1',
        session_id=None,
        platform='macos',
        prompt=_PROMPT,
    )
    with pytest.raises(asyncio.CancelledError):
        await anext(stream)


@pytest.mark.asyncio
async def test_offline_endpoint_returns_native_gemini_sse_without_provider_key(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: True)
    monkeypatch.delenv('GEMINI_API_KEY', raising=False)

    response = await desktop_chat.stream_generate_content(
        model='gemini-3.7-flash',
        body={'contents': [{'role': 'user', 'parts': [{'text': 'Reply with exactly PROBE'}]}]},
        alt='sse',
        uid='user-1',
        x_app_platform='macos',
        x_omi_chat_contract_version='2',
        x_omi_request_id='request-1',
        x_omi_session_id='session-1',
    )

    chunks = [chunk async for chunk in response.body_iterator]
    payload = json.loads(chunks[0][6:])
    assert payload['candidates'][0]['content']['parts'][0]['text'] == 'PROBE'
    assert response.headers['x-omi-chat-contract-version'] == '2'
    assert 'server-gemini-secret' not in str(payload)


@pytest.mark.asyncio
async def test_endpoint_rejects_client_gemini_key_before_offline_dispatch(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: True)
    with pytest.raises(HTTPException) as caught:
        await desktop_chat.stream_generate_content(
            model='gemini-3.7-flash',
            body={'contents': []},
            alt='sse',
            uid='user-1',
            x_app_platform='macos',
            x_omi_chat_contract_version='2',
            x_omi_request_id='request-1',
            x_omi_session_id=None,
            x_goog_api_key='must-not-cross-managed-boundary',
        )

    assert caught.value.status_code == 400
    assert caught.value.detail == 'Client provider keys are not accepted'


@pytest.mark.asyncio
async def test_endpoint_requires_server_managed_gemini_key_outside_stub(monkeypatch):
    monkeypatch.setattr(desktop_chat, 'llm_stub_enabled', lambda: False)
    monkeypatch.delenv('GEMINI_API_KEY', raising=False)
    with pytest.raises(Exception) as caught:
        await desktop_chat.stream_generate_content(
            model='gemini-3.7-flash',
            body={'contents': []},
            alt='sse',
            uid='user-1',
            x_app_platform='macos',
            x_omi_chat_contract_version='2',
            x_omi_request_id='request-1',
            x_omi_session_id=None,
        )
    assert getattr(caught.value, 'status_code', None) == 503
