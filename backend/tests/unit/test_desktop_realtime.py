import hashlib
import json

import httpx
import pytest
from pydantic import ValidationError

from routers import desktop_realtime
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt


def _mint_request():
    return desktop_realtime.MintRequest(
        conversation_id='conversation-1',
        prompt_ref={
            'name': 'intentive-live-system',
            'version': '7',
            'source': 'langfuse',
            'sha256': hashlib.sha256(b'Live behavior').hexdigest(),
        },
    )


@pytest.fixture
def allowed_mint_quota(monkeypatch):
    async def allowed(uid):
        assert uid == 'user-1'

    monkeypatch.setattr(desktop_realtime, 'enforce_desktop_gemini_quota', allowed)


class _Client:
    def __init__(self, response):
        self.response = response

    async def __aenter__(self):
        return self

    async def __aexit__(self, *_):
        return None

    async def post(self, *_args, **_kwargs):
        return self.response


@pytest.mark.asyncio
async def test_offline_mint_is_unavailable_without_contacting_provider(monkeypatch):
    monkeypatch.setenv('OMI_LLM_STUB', '1')
    monkeypatch.setenv('GEMINI_API_KEY', 'offline-placeholder')
    monkeypatch.setattr(
        desktop_realtime,
        'enforce_desktop_gemini_quota',
        lambda _uid: pytest.fail('offline Live must not consume hosted mint quota'),
    )
    monkeypatch.setattr(
        desktop_realtime.httpx,
        'AsyncClient',
        lambda **_: pytest.fail('offline Live must not contact the provider'),
    )

    async def run(_executor, function, *_args):
        if function is desktop_realtime.resolve_conversation_prompt:
            return ResolvedRuntimePrompt('Live behavior', 'intentive-live-system', '7', 'langfuse')
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, 'run_blocking', run)

    response = await desktop_realtime.mint_session(_mint_request(), 'user-1')

    assert response.status_code == 503
    body = json.loads(response.body)
    assert body['reason'] == 'provider_not_configured'
    assert 'token' not in body


@pytest.mark.asyncio
async def test_gemini_mint_returns_ephemeral_token_without_session_audit_write(monkeypatch, allowed_mint_quota):
    monkeypatch.setenv("GEMINI_API_KEY", "platform-key")
    monkeypatch.setattr(
        desktop_realtime.httpx,
        "AsyncClient",
        lambda **_: _Client(httpx.Response(200, json={"name": "auth-token"})),
    )
    monkeypatch.setattr(
        desktop_realtime,
        "get_firestore_client",
        lambda: pytest.fail("mint must not write a realtime_sessions audit document"),
    )

    async def run(_executor, function, *_args):
        if function is desktop_realtime.resolve_conversation_prompt:
            assert _args == (_mint_request().prompt_ref,)
            return ResolvedRuntimePrompt('Live behavior', 'intentive-live-system', '7', 'langfuse')
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(_mint_request(), "user-1")

    assert response.status_code == 200
    body = json.loads(response.body)
    assert body["provider"] == "gemini"
    assert body["token"] == "auth-token"
    assert body["expires_at"].endswith("Z")
    assert body['prompt'] == {
        'text': 'Live behavior',
        'name': 'intentive-live-system',
        'version': '7',
        'source': 'langfuse',
        'sha256': hashlib.sha256(b'Live behavior').hexdigest(),
    }


@pytest.mark.asyncio
async def test_mint_classifies_provider_quota_error(monkeypatch, allowed_mint_quota):
    monkeypatch.setenv("GEMINI_API_KEY", "platform-key")
    monkeypatch.setattr(
        desktop_realtime.httpx,
        "AsyncClient",
        lambda **_: _Client(
            httpx.Response(429, json={"error": {"status": "RESOURCE_EXHAUSTED", "message": "Quota exhausted"}})
        ),
    )

    async def run(_executor, function, *_args):
        if function is desktop_realtime.resolve_conversation_prompt:
            return ResolvedRuntimePrompt('Live behavior', 'intentive-live-system', '7', 'langfuse')
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(_mint_request(), "user-1")

    assert response.status_code == 429
    assert json.loads(response.body) == {
        "error": "Quota exhausted",
        "reason": "provider_quota_exceeded",
        "backend_route": "/v2/realtime/session",
        "retryable": True,
        "provider": "gemini",
        "code": "RESOURCE_EXHAUSTED",
        "upstream_status_code": 429,
    }


@pytest.mark.asyncio
async def test_usage_clamps_negative_tokens_and_records_realtime_breakdown(monkeypatch):
    calls = []

    async def run(_executor, function, *args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        calls.append((function, args))

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)
    report = desktop_realtime.UsageReport(
        input_text_tokens=-1,
        input_audio_tokens=10,
        input_cached_tokens=-2,
        output_text_tokens=5,
        output_audio_tokens=-3,
        thinking_tokens=-4,
    )

    response = await desktop_realtime.report_usage(report, "user-1")

    assert response.status_code == 204
    _, args = calls[0]
    assert args[0] == "user-1"
    assert args[1:] == (10, 5, 0, 0, 15, 0.0000525)


@pytest.mark.asyncio
async def test_usage_with_no_positive_tokens_skips_firestore(monkeypatch):
    async def fail(_executor, function, *_args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        raise AssertionError("usage write should not run")

    monkeypatch.setattr(desktop_realtime, "run_blocking", fail)

    response = await desktop_realtime.report_usage(desktop_realtime.UsageReport(input_text_tokens=-1), "user-1")

    assert response.status_code == 204


@pytest.mark.parametrize(
    "retired_field,value",
    [
        ("context_plan_id", "plan"),
        ("stable_cache_identity", "stable"),
        ("dynamic_context_identity", "dynamic"),
        ("context_cache_replaced", True),
    ],
)
def test_usage_report_rejects_retired_context_fields(retired_field, value):
    with pytest.raises(ValidationError, match="Extra inputs are not permitted"):
        desktop_realtime.UsageReport(**{retired_field: value})


@pytest.mark.parametrize("retired_field", ["provider", "model"])
def test_usage_report_rejects_client_provider_attribution(retired_field):
    with pytest.raises(ValidationError, match="Extra inputs are not permitted"):
        desktop_realtime.UsageReport(**{retired_field: "client-controlled"})


def test_mint_request_rejects_provider_choice():
    with pytest.raises(ValidationError, match="Extra inputs are not permitted"):
        desktop_realtime.MintRequest(provider="openai")


@pytest.mark.asyncio
async def test_trial_expiry_copy_offers_managed_recovery_not_customer_keys(monkeypatch):
    async def run(_executor, function, *_args):
        assert function is desktop_realtime.is_trial_paywalled
        return True

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(_mint_request(), "user-1")

    assert response.status_code == 402
    body = json.loads(response.body)
    assert body == {
        "error": "trial_expired",
        "message": "Desktop trial expired. Upgrade to continue managed voice.",
    }
    assert "key" not in body["message"].lower()


@pytest.mark.asyncio
async def test_live_usage_keeps_thinking_exclusive_in_ledger_total_and_cost(monkeypatch):
    writes = []

    class Ledger:
        def collection(self, _name):
            return self

        def document(self, _name):
            return self

        def set(self, updates, *, merge):
            assert merge is True
            writes.append(updates)

    async def run(_executor, function, *args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        return function(*args)

    monkeypatch.setattr(desktop_realtime, 'run_blocking', run)
    monkeypatch.setattr(desktop_realtime, 'get_firestore_client', Ledger)
    monkeypatch.setattr(desktop_realtime.firestore, 'Increment', lambda value: value)
    response = await desktop_realtime.report_usage(
        desktop_realtime.UsageReport(
            input_text_tokens=40,
            input_cached_tokens=60,
            output_text_tokens=10,
            thinking_tokens=7,
        ),
        'owner',
    )
    assert response.status_code == 204
    assert len(writes) == 1
    for prefix in ['desktop_chat', 'desktop_chat_realtime']:
        assert writes[0][f'{prefix}.input_tokens'] == 40
        assert writes[0][f'{prefix}.cache_read_tokens'] == 60
        assert writes[0][f'{prefix}.output_tokens'] == 10
        assert writes[0][f'{prefix}.thinking_tokens'] == 7
        assert writes[0][f'{prefix}.total_tokens'] == 117
        assert writes[0][f'{prefix}.cost_usd'] == pytest.approx((40 * 0.75 + 60 * 0.075 + 17 * 4.5) / 1_000_000)
