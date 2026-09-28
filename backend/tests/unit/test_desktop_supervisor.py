import json

import httpx
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import desktop_supervisor
from services import desktop_inference
from utils.other.endpoints import get_current_participant_uid
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt


@pytest.fixture
def harness(monkeypatch):
    calls = []

    async def provider(request):
        calls.append(json.loads(request.content))
        return httpx.Response(
            200,
            json={
                'candidates': [
                    {
                        'content': {
                            'parts': [{'text': '{"action":"intervene","note":"Ask whether a short break would help."}'}]
                        }
                    }
                ]
            },
        )

    http = httpx.AsyncClient(transport=httpx.MockTransport(provider))
    monkeypatch.setenv('GEMINI_API_KEY', 'synthetic-key')
    monkeypatch.setattr(desktop_supervisor, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(desktop_supervisor, 'get_gemini_client', lambda: http)
    monkeypatch.setattr(
        desktop_supervisor,
        'get_runtime_prompt',
        lambda role: ResolvedRuntimePrompt('managed supervisor', 'intentive-supervisor-system', '9', 'langfuse'),
    )

    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    monkeypatch.setattr(desktop_supervisor, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_supervisor, 'record_supervisor_observation', lambda **kwargs: None)

    async def allowed(_uid):
        return None

    monkeypatch.setattr(desktop_supervisor, 'enforce_desktop_gemini_quota', allowed)
    monkeypatch.setattr(desktop_supervisor, 'enforce_ai_observation_quota', allowed)
    app = FastAPI()
    app.include_router(desktop_supervisor.router)
    app.dependency_overrides[desktop_supervisor.authorized_desktop_user] = lambda: 'synthetic-owner'
    with TestClient(app) as client:
        yield client, calls


def test_supervisor_evaluates_once_with_managed_prompt_and_returns_private_intervention(harness):
    client, calls = harness
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'observation-1',
            'session_id': 'session-1',
            'context_epoch': 3,
            'transcripts': [{'id': 'segment-1', 'source': 'microphone', 'text': 'I have been stuck for an hour.'}],
            'conversation': [],
            'memories': ['Prefers brief suggestions'],
            'profile': 'Synthetic tester',
        },
    )
    assert response.status_code == 200, response.text
    result = response.json()
    assert result['action'] == 'intervene'
    assert result['note'] == 'Ask whether a short break would help.'
    assert result['observation_id'] == 'observation-1'
    assert result['context_epoch'] == 3
    assert result['prompt']['version'] == '9'
    assert len(calls) == 1
    assert calls[0]['systemInstruction']['parts'][0]['text'].startswith('managed supervisor')
    assert 'tools' not in calls[0]


def test_unavailable_supervisor_prompt_waits_without_calling_model(monkeypatch, harness):
    client, calls = harness
    receipts = []
    monkeypatch.setattr(
        desktop_supervisor,
        'get_runtime_prompt',
        lambda role: ResolvedRuntimePrompt('fallback text', 'intentive-supervisor-system', 'fallback', 'fallback'),
    )
    monkeypatch.setattr(desktop_supervisor, 'record_supervisor_observation', lambda **kwargs: receipts.append(kwargs))
    response = client.post(
        '/v1/supervisor/evaluate',
        json={'observation_id': 'missing-prompt', 'session_id': 'session-1', 'context_epoch': 1},
    )
    assert response.status_code == 200
    assert response.json()['action'] == 'wait'
    assert response.json()['note'] is None
    assert response.json()['outcome'] == 'degraded'
    assert response.json()['prompt']['source'] == 'fallback'
    assert calls == []
    assert len(receipts) == 1


@pytest.mark.parametrize(
    'provider_result',
    [
        {'candidates': [{'content': {'parts': [42]}}]},
        {'candidates': [{'content': {'parts': [{'text': '{"action":"intervene","note":""}'}]}}]},
        {'candidates': [{'content': {'parts': [{'text': 'not JSON private-upstream-body synthetic-key'}]}}]},
        {'candidates': []},
    ],
)
def test_malformed_provider_result_returns_wait_without_guidance(monkeypatch, harness, caplog, provider_result):
    client, _ = harness
    requests = []
    receipts = []

    async def provider(request):
        requests.append(request)
        return httpx.Response(200, json=provider_result)

    monkeypatch.setattr(
        desktop_supervisor, 'get_gemini_client', lambda: httpx.AsyncClient(transport=httpx.MockTransport(provider))
    )
    monkeypatch.setattr(desktop_supervisor, 'record_supervisor_observation', lambda **kwargs: receipts.append(kwargs))
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'observation-2',
            'session_id': 'session-1',
            'context_epoch': 3,
        },
    )
    assert response.status_code == 200
    assert response.json()['action'] == 'wait'
    assert response.json()['note'] is None
    assert response.json()['outcome'] == 'degraded'
    assert len(requests) == 1
    assert len(receipts) == 1
    assert receipts[0]['response'].observation_id == 'observation-2'
    assert receipts[0]['response'].prompt.version == '9'
    assert 'from=supervisor to=wait reason=malformed_doc outcome=degraded' in caplog.text
    assert 'private-upstream-body' not in response.text + caplog.text
    assert 'synthetic-key' not in response.text + caplog.text


@pytest.mark.parametrize(
    ('upstream_status', 'client_status', 'reason'),
    [
        (402, 503, 'quota'),
        (429, 429, 'provider_429'),
        (401, 503, 'auth'),
        (403, 503, 'auth'),
        (400, 502, 'other'),
        (404, 502, 'other'),
        (500, 503, 'provider_5xx'),
        (503, 503, 'provider_5xx'),
    ],
)
def test_provider_rejection_triggers_backoff_without_account_error_or_private_data(
    monkeypatch, harness, caplog, upstream_status, client_status, reason
):
    client, _ = harness
    requests = []
    receipts = []

    async def provider(request):
        requests.append(request)
        return httpx.Response(
            upstream_status,
            json={'error': {'message': 'private-upstream-body synthetic-key'}},
        )

    monkeypatch.setattr(
        desktop_supervisor, 'get_gemini_client', lambda: httpx.AsyncClient(transport=httpx.MockTransport(provider))
    )
    monkeypatch.setattr(desktop_supervisor, 'record_supervisor_observation', lambda **kwargs: receipts.append(kwargs))
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'provider-rejection-1',
            'session_id': 'session-1',
            'context_epoch': 3,
            'profile': 'private-local-profile',
        },
    )

    assert response.status_code == client_status
    assert response.json() == {'detail': 'Managed Gemini is temporarily unavailable'}
    assert len(requests) == 1
    assert len(receipts) == 1
    receipt = receipts[0]
    assert receipt['uid'] == 'synthetic-owner'
    assert receipt['request'].observation_id == 'provider-rejection-1'
    assert receipt['response'].observation_id == 'provider-rejection-1'
    assert receipt['response'].session_id == 'session-1'
    assert receipt['response'].decision_id
    assert receipt['response'].action == 'wait'
    assert receipt['response'].note is None
    assert receipt['response'].outcome == 'degraded'
    assert receipt['response'].prompt.model_dump(include={'name', 'version', 'source'}) == {
        'name': 'intentive-supervisor-system',
        'version': '9',
        'source': 'langfuse',
    }
    assert receipt['duration_ms'] >= 0
    assert f'from=supervisor to=wait reason={reason} outcome=degraded' in caplog.text
    for private_value in ('private-upstream-body', 'synthetic-key', 'private-local-profile'):
        assert private_value not in response.text + caplog.text


@pytest.mark.parametrize(
    ('error_type', 'reason'),
    [(httpx.ReadTimeout, 'timeout'), (httpx.ConnectTimeout, 'timeout'), (httpx.ConnectError, 'other')],
)
def test_provider_transport_failure_pauses_with_safe_error_and_correlated_trace(
    monkeypatch, harness, caplog, error_type, reason
):
    client, _ = harness
    requests = []
    receipts = []

    async def timeout(request):
        requests.append(request)
        raise error_type('private-provider-detail synthetic-key', request=request)

    monkeypatch.setattr(
        desktop_supervisor, 'get_gemini_client', lambda: httpx.AsyncClient(transport=httpx.MockTransport(timeout))
    )
    monkeypatch.setattr(desktop_supervisor, 'record_supervisor_observation', lambda **kwargs: receipts.append(kwargs))
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'timeout-1',
            'session_id': 'session-1',
            'context_epoch': 3,
        },
    )
    assert response.status_code == 503
    assert response.json() == {'detail': 'Managed Gemini is temporarily unavailable'}
    assert len(requests) == 1
    assert len(receipts) == 1
    result = receipts[0]['response']
    assert result.observation_id == 'timeout-1'
    assert result.session_id == 'session-1'
    assert result.context_epoch == 3
    assert result.action == 'wait'
    assert result.note is None
    assert result.outcome == 'degraded'
    assert result.prompt.name == 'intentive-supervisor-system'
    assert result.prompt.version == '9'
    assert f'from=supervisor to=wait reason={reason} outcome=degraded' in caplog.text
    assert 'private-provider-detail' not in response.text + caplog.text
    assert 'synthetic-key' not in response.text + caplog.text


def test_oversized_request_is_rejected_before_model_call(harness):
    client, calls = harness
    response = client.post(
        '/v1/supervisor/evaluate', content=b' ' * 3_100_000, headers={'content-type': 'application/json'}
    )
    assert response.status_code == 413
    assert calls == []


def test_observation_intake_rejects_images_and_arbitrary_feedback_text(harness):
    client, calls = harness
    response = client.post(
        '/v1/ai/observations',
        json={
            'kind': 'score',
            'session_id': 'session-1',
            'turn_id': 'turn-1',
            'value': 1,
            'jpeg_base64': '/9j/',
            'comment': 'private content',
        },
    )
    assert response.status_code == 422
    assert calls == []


def test_participant_auth_and_paywall_still_guard_supervisor(monkeypatch, harness):
    client, calls = harness
    client.app.dependency_overrides.clear()
    body = {'observation_id': 'observation-1', 'session_id': 'session-1', 'context_epoch': 0}
    assert client.post('/v1/supervisor/evaluate', json=body).status_code == 401
    client.app.dependency_overrides[get_current_participant_uid] = lambda: 'synthetic-owner'

    async def immediate(_executor, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_inference, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_inference, 'is_trial_paywalled', lambda *_: True)
    assert client.post('/v1/supervisor/evaluate', json=body).status_code == 402
    assert calls == []


def test_shared_daily_quota_denial_stops_supervisor_before_provider(monkeypatch, harness):
    client, calls = harness
    policies = []

    def quota(_uid, policy, _limit, _window):
        policies.append(policy)
        return policy != 'desktop_gemini_daily', 0, 60

    async def immediate(_executor, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_inference, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_inference.redis_db, 'check_rate_limit', quota)
    monkeypatch.setattr(
        desktop_supervisor, 'enforce_desktop_gemini_quota', desktop_inference.enforce_desktop_gemini_quota
    )
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'observation-1',
            'session_id': 'session-1',
            'context_epoch': 0,
        },
    )
    assert response.status_code == 429
    assert response.json()['detail'] == 'Daily Gemini request limit exceeded'
    assert policies == ['desktop_gemini_burst', 'desktop_gemini_daily']
    assert calls == []


def test_intake_authenticates_and_delivers_typed_examples(monkeypatch, harness):
    client, calls = harness
    events = []
    monkeypatch.setattr(desktop_supervisor, 'record_client_observation', lambda **kwargs: events.append(kwargs))
    response = client.post(
        '/v1/ai/observations',
        json={
            'kind': 'supervisor_decision',
            'session_id': 'session-1',
            'decision_id': 'decision-1',
            'observation_id': 'observation-1',
            'evaluation_sharing': True,
            'note': 'A private note.',
            'prompt': {'name': 'intentive-supervisor-system', 'version': '2', 'source': 'langfuse'},
        },
    )
    assert response.status_code == 204, response.text
    assert events[0]['uid'] == 'synthetic-owner'
    assert events[0]['event'].note == 'A private note.'
    assert calls == []


def test_hermetic_stub_never_opens_provider_or_prompt_service(monkeypatch, harness):
    client, calls = harness
    monkeypatch.setattr(desktop_supervisor, 'llm_stub_enabled', lambda: True)
    monkeypatch.setattr(desktop_supervisor, 'get_runtime_prompt', lambda *_: pytest.fail('remote prompt opened'))
    monkeypatch.delenv('GEMINI_API_KEY', raising=False)
    response = client.post(
        '/v1/supervisor/evaluate',
        json={
            'observation_id': 'observation-1',
            'session_id': 'session-1',
            'context_epoch': 0,
        },
    )
    assert response.status_code == 200
    assert response.json()['action'] == 'wait'
    assert calls == []
