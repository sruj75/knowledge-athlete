import hashlib
import json
from pathlib import Path
import runpy
from types import SimpleNamespace

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from models.desktop_conversation import ConversationPromptReceipt
from routers import desktop_conversation, desktop_realtime
from utils.observability import conversation_prompts
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt


def test_bootstrap_resolves_one_owned_prompt_without_accepting_client_instructions(monkeypatch):
    calls = []
    monkeypatch.setattr(
        conversation_prompts,
        'get_runtime_prompt',
        lambda role: (
            calls.append(role),
            ResolvedRuntimePrompt('Managed A', 'intentive-live-system', '12', 'langfuse'),
        )[1],
    )

    async def immediate(_executor, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_conversation, 'run_blocking', immediate)
    app = FastAPI()
    app.include_router(desktop_conversation.router)
    app.dependency_overrides[desktop_conversation.authorized_desktop_user] = lambda: 'synthetic-owner'
    with TestClient(app) as client:
        response = client.post('/v1/conversation/session', json={'conversation_id': 'conversation-1'})
        rejected = client.post(
            '/v1/conversation/session', json={'conversation_id': 'conversation-1', 'system_instruction': 'untrusted'}
        )

    assert response.status_code == 200, response.text
    body = response.json()
    assert body['conversation_id'] == 'conversation-1'
    assert body['prompt'] == {
        'name': 'intentive-live-system',
        'version': '12',
        'source': 'langfuse',
        'sha256': '332b58745c3dde42e5a301e4fd32401674a78d1966491dd3d84190bc156fc7ae',
        'text': 'Managed A',
    }
    assert calls == ['live']
    assert rejected.status_code == 422


def test_bundled_conversation_policy_remains_exact_when_managed_prompt_later_changes(monkeypatch):
    monkeypatch.setattr(conversation_prompts, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(
        conversation_prompts,
        'get_runtime_prompt',
        lambda _: ResolvedRuntimePrompt('', 'intentive-live-system', 'fallback', 'fallback'),
    )
    receipt = conversation_prompts.bootstrap_conversation_prompt()
    assert receipt.version == 'conversation-v1'
    assert receipt.source == 'fallback'
    monkeypatch.setattr(
        conversation_prompts, 'get_langfuse_client', lambda: pytest.fail('A pinned fallback must not fetch a new label')
    )
    resolved = conversation_prompts.resolve_conversation_prompt(receipt.reference())
    assert resolved.text == receipt.text
    assert resolved.version == receipt.version


@pytest.mark.asyncio
async def test_live_mint_resolves_exact_reference_instead_of_current_label(monkeypatch):
    calls = []
    prompt = SimpleNamespace(version=99, is_fallback=False, compile=lambda: 'abc')
    monkeypatch.setattr(
        conversation_prompts,
        'get_langfuse_client',
        lambda: SimpleNamespace(get_prompt=lambda *args, **kwargs: (calls.append((args, kwargs)), prompt)[1]),
    )
    monkeypatch.setenv('GEMINI_API_KEY', 'synthetic-key')

    async def immediate(_executor, function, *args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        return function(*args)

    async def mint(*_args, **_kwargs):
        return {'name': 'synthetic-token'}, None

    monkeypatch.setattr(desktop_realtime, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_realtime, '_post_json', mint)
    reference = {
        'name': 'intentive-live-system',
        'version': '99',
        'source': 'langfuse',
        'sha256': 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    }
    request = desktop_realtime.MintRequest(conversation_id='conversation-1', prompt_ref=reference)
    response = await desktop_realtime.mint_session(request, 'synthetic-owner')
    assert response.status_code == 200
    assert json.loads(response.body)['prompt'] == {**reference, 'text': 'abc'}
    assert len(calls) == 1
    assert calls[0][1]['version'] == 99
    assert 'label' not in calls[0][1]

    invalid = desktop_realtime.MintRequest(
        conversation_id='conversation-1', prompt_ref={**reference, 'sha256': '0' * 64}
    )
    rejected = await desktop_realtime.mint_session(invalid, 'synthetic-owner')
    assert rejected.status_code == 409


@pytest.fixture
def conversation_harness(monkeypatch):
    calls = []
    frames = [
        {'candidates': [{'content': {'parts': [{'text': 'Let us start small.'}]}}]},
        {
            'candidates': [
                {
                    'content': {'parts': [{'functionCall': {'name': 'end_conversation', 'args': {}}}]},
                    'finishReason': 'STOP',
                }
            ],
            'modelVersion': 'gemini-3.8-flash',
            'usageMetadata': {
                'promptTokenCount': 100,
                'cachedContentTokenCount': 40,
                'candidatesTokenCount': 8,
                'thoughtsTokenCount': 2,
                'totalTokenCount': 110,
            },
        },
    ]

    class Stream(httpx.AsyncByteStream):
        async def __aiter__(self):
            for frame in frames:
                if isinstance(frame, Exception):
                    raise frame
                yield b'data: ' + json.dumps(frame).encode() + b'\n\n'

    async def provider(request):
        calls.append((str(request.url), json.loads(request.content)))
        return httpx.Response(200, stream=Stream())

    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def allowed(*_args):
        pass

    monkeypatch.setenv('GEMINI_API_KEY', 'synthetic-key')
    monkeypatch.setattr(desktop_conversation, 'run_blocking', immediate)
    monkeypatch.setattr(
        desktop_conversation, 'get_gemini_client', lambda: httpx.AsyncClient(transport=httpx.MockTransport(provider))
    )
    monkeypatch.setattr(desktop_conversation, 'enforce_conversation_quota', allowed)
    monkeypatch.setattr(desktop_conversation, 'record_conversation_usage', allowed)
    monkeypatch.setattr(desktop_conversation, 'remember_chat_prompt', lambda *_: None)
    monkeypatch.setattr(desktop_conversation, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(
        desktop_conversation,
        'resolve_conversation_prompt',
        lambda _: ResolvedRuntimePrompt('Pinned A', 'intentive-live-system', '2', 'langfuse'),
    )
    app = FastAPI()
    app.include_router(desktop_conversation.router)
    app.dependency_overrides[desktop_conversation.authorized_desktop_user] = lambda: 'synthetic-owner'
    body = {
        'conversation_id': 'conversation-1',
        'turn_id': 'turn-1',
        'prompt_ref': {'name': 'intentive-live-system', 'version': '2', 'source': 'langfuse', 'sha256': 'a' * 64},
        'message': 'Help me begin',
        'context': 'Existing local context',
        'guidance': 'Private B cue',
        'image': {'jpeg_base64': '/9j/'},
        'history': [{'role': 'user', 'text': 'Earlier question'}, {'role': 'assistant', 'text': 'Earlier answer'}],
    }
    with TestClient(app) as client:
        yield client, calls, frames, body


def test_direct_a_stream_uses_pinned_policy_fixed_capabilities_and_exclusive_usage(conversation_harness):
    client, calls, _, body = conversation_harness
    response = client.post('/v1/conversation/respond', json=body)
    assert response.status_code == 200, response.text
    assert 'event: text_delta\ndata: {"text":"Let us start small."}' in response.text
    done = json.loads(response.text.split('event: done\ndata: ')[1].strip())
    assert done['end_conversation'] is True
    assert done['prompt_ref'] == body['prompt_ref']
    assert done['usage'] == {
        'input_tokens': 60,
        'cached_input_tokens': 40,
        'output_tokens': 8,
        'thinking_tokens': 2,
        'total_tokens': 110,
    }
    assert len(calls) == 1
    url, payload = calls[0]
    assert '/gemini-3.8-flash:streamGenerateContent' in url
    assert payload['systemInstruction']['parts'][0]['text'] == 'Pinned A'
    assert payload['generationConfig']['thinkingConfig'] == {'thinkingLevel': 'low'}
    assert [fn['name'] for tool in payload['tools'] for fn in tool['functionDeclarations']] == ['end_conversation']
    assert 'Private B cue' in str(payload['contents'])
    assert payload['contents'][-1]['parts'][-1] == {'inlineData': {'mimeType': 'image/jpeg', 'data': '/9j/'}}
    assert payload['contents'][1] == {'role': 'user', 'parts': [{'text': 'Earlier question'}]}
    assert payload['contents'][2] == {'role': 'model', 'parts': [{'text': 'Earlier answer'}]}


def test_release_candidate_probe_bounds_long_history_through_current_request_models(conversation_harness, monkeypatch):
    """Exercise the real probe, request validation, provider adapter and typed SSE."""
    client, calls, frames, _ = conversation_harness
    probe = SimpleNamespace(
        **runpy.run_path(str(Path(__file__).resolve().parents[3] / '.github/scripts/backend_candidate_probe.py'))
    )
    text = 'Pinned A'
    receipt = ConversationPromptReceipt(
        name='intentive-live-system',
        version='2',
        source='langfuse',
        text=text,
        sha256=hashlib.sha256(text.encode()).hexdigest(),
    )
    monkeypatch.setattr(desktop_conversation, 'bootstrap_conversation_prompt', lambda: receipt)
    long_answer = 'a' * 4001
    frames[0]['candidates'][0]['content']['parts'] = [{'text': long_answer}]
    frames[1]['candidates'][0]['content']['parts'] = []
    accepted = []

    class Response:
        def __init__(self, response):
            self.response = response

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def read(self, size=-1):
            return self.response.content[:size] if size >= 0 else self.response.content

        def __iter__(self):
            return iter(self.response.content.splitlines(keepends=True))

    def backend(request, *, timeout):
        response = client.post(request.selector, content=request.data, headers={'Content-Type': 'application/json'})
        assert response.status_code == 200, response.text
        accepted.append((request.selector, json.loads(request.data)))
        return Response(response)

    monkeypatch.setattr(probe.urllib.request, 'urlopen', backend)
    probe.probe_candidate.__globals__['_request_json'] = lambda url: (
        {'status': 'ok'}
        if url.endswith('/v1/health')
        else {'status': 'healthy', 'service': 'backend', 'chat_contract_version': '2'}
    )
    probe.probe_candidate.__globals__['_require_firestore_read'] = lambda _: {'status': 'passed'}
    evidence = probe.probe_candidate(
        base_url='https://candidate.invalid',
        token='synthetic-token',
        expected_contract_version='2',
        source_sha='a' * 40,
        expected_revision='backend-fixture',
        expected_image_digest='sha256:' + 'b' * 64,
        candidate_tag='candidate',
        workflow_run_id='123',
    )
    turns = [body for path, body in accepted if path == '/v1/conversation/respond']
    assert len(turns) == len(calls) == 2
    assert turns[0]['prompt_ref'] == turns[1]['prompt_ref'] == receipt.reference().model_dump()
    assert turns[1]['history'][1]['text'] == long_answer[:4000]
    assert evidence['chat']['initial_turn_chars'] == len(long_answer)
    assert long_answer not in json.dumps(evidence)


@pytest.fixture(scope='module')
def product_route_client():
    import main

    return TestClient(main.app)


def test_general_provider_gateway_and_task_extraction_are_not_product_endpoints(product_route_client):
    client = product_route_client
    assert client.post('/v2/models/gemini-3.7-flash:streamGenerateContent', json={'tools': []}).status_code == 404
    assert client.post('/v1/conversation-compute/action-items', json={}).status_code == 404


def test_partial_provider_failure_preserves_text_without_replay_or_success(conversation_harness):
    client, calls, frames, body = conversation_harness
    frames[1] = httpx.ReadError('PRIVATE_PROVIDER_DETAIL synthetic-key')
    response = client.post('/v1/conversation/respond', json=body)
    assert response.text.count('Let us start small.') == 1
    assert 'event: error' in response.text
    assert 'event: done' not in response.text
    assert 'PRIVATE_PROVIDER_DETAIL' not in response.text
    assert len(calls) == 1


@pytest.mark.parametrize(
    'field,value', [('system_instruction', 'override'), ('tools', []), ('model', 'other'), ('owner', 'other')]
)
def test_direct_a_rejects_client_policy_and_capability_selection(conversation_harness, field, value):
    client, calls, _, body = conversation_harness
    assert client.post('/v1/conversation/respond', json={**body, field: value}).status_code == 422
    assert calls == []


def test_direct_a_enforces_packet_size_before_prompt_or_provider_work(conversation_harness):
    client, calls, _, _ = conversation_harness
    assert (
        client.post(
            '/v1/conversation/respond', content=b' ' * 4_000_001, headers={'content-type': 'application/json'}
        ).status_code
        == 413
    )
    assert calls == []


@pytest.mark.asyncio
async def test_stream_close_cancels_upstream_and_closes_generation(monkeypatch):
    from models.desktop_conversation import ConversationRespondRequest
    from utils.observability.langfuse import ChatGeneration

    closed, finished = [], []

    class Stream(httpx.AsyncByteStream):
        async def __aiter__(self):
            yield b'data: {"candidates":[{"content":{"parts":[{"text":"Hello"}]}}]}\n\n'
            pytest.fail('Cancelled stream must not read another provider frame')

        async def aclose(self):
            closed.append(True)

    class Observation:
        def update(self, **kwargs):
            finished.append(kwargs)

        def end(self):
            finished.append('ended')

    async def provider(_request):
        return httpx.Response(200, stream=Stream())

    monkeypatch.setattr(
        desktop_conversation, 'get_gemini_client', lambda: httpx.AsyncClient(transport=httpx.MockTransport(provider))
    )
    monkeypatch.setattr(
        desktop_conversation, 'start_chat_generation', lambda **_: ChatGeneration(Observation(), 'trace')
    )
    request = ConversationRespondRequest(
        conversation_id='session',
        turn_id='turn',
        message='Hi',
        prompt_ref={'name': 'intentive-live-system', 'version': '2', 'source': 'langfuse', 'sha256': 'a' * 64},
    )
    stream = desktop_conversation._stream_response(
        request, 'owner', ResolvedRuntimePrompt('policy', 'intentive-live-system', '2', 'langfuse'), 'synthetic-key'
    )
    assert b'Hello' in await anext(stream)
    await stream.aclose()
    assert closed == [True]
    assert finished[-1] == 'ended'
    assert finished[-2]['status_message'] == 'cancelled'
    assert finished[-2]['output'] == {'text_chars': 5, 'tool_call_count': 0}


def test_exact_prompt_unavailability_never_advances_to_current_label(monkeypatch, conversation_harness):
    client, calls, _, body = conversation_harness

    def unavailable(_reference):
        raise conversation_prompts.ConversationPromptUnavailableError('private prompt error')

    monkeypatch.setattr(desktop_conversation, 'resolve_conversation_prompt', unavailable)
    response = client.post('/v1/conversation/respond', json=body)
    assert response.status_code == 503
    assert response.json() == {'detail': 'prompt_unavailable'}
    assert calls == []
