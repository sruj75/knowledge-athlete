import json

import httpx
import pytest
from pydantic import ValidationError

from routers import desktop_realtime


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
async def test_openai_mint_returns_ephemeral_token_without_session_audit_write(monkeypatch):
    monkeypatch.setenv("OPENAI_API_KEY", "platform-key")
    monkeypatch.setattr(
        desktop_realtime.httpx,
        "AsyncClient",
        lambda **_: _Client(httpx.Response(200, json={"value": "ek_secret", "expires_at": 123})),
    )
    monkeypatch.setattr(
        desktop_realtime,
        "get_firestore_client",
        lambda: pytest.fail("mint must not write a realtime_sessions audit document"),
    )

    async def run(_executor, function, *_args):
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(desktop_realtime.MintRequest(provider="openai"), "user-1")

    assert response.status_code == 200
    assert json.loads(response.body) == {"provider": "openai", "token": "ek_secret", "expires_at": "123"}


@pytest.mark.asyncio
async def test_gemini_mint_returns_ephemeral_token_without_session_audit_write(monkeypatch):
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
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(desktop_realtime.MintRequest(provider="gemini"), "user-1")

    assert response.status_code == 200
    body = json.loads(response.body)
    assert body["provider"] == "gemini"
    assert body["token"] == "auth-token"
    assert body["expires_at"].endswith("Z")


@pytest.mark.asyncio
async def test_mint_classifies_provider_quota_error(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "platform-key")
    monkeypatch.setattr(
        desktop_realtime.httpx,
        "AsyncClient",
        lambda **_: _Client(
            httpx.Response(429, json={"error": {"status": "RESOURCE_EXHAUSTED", "message": "Quota exhausted"}})
        ),
    )

    async def run(_executor, function, *_args):
        assert function is desktop_realtime.is_trial_paywalled
        return False

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(desktop_realtime.MintRequest(provider="gemini"), "user-1")

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
        provider="openai",
        input_text_tokens=-1,
        input_audio_tokens=10,
        input_cached_tokens=-2,
        output_text_tokens=5,
        output_audio_tokens=-3,
    )

    response = await desktop_realtime.report_usage(report, "user-1")

    assert response.status_code == 204
    _, args = calls[0]
    assert args[0] == "user-1"
    assert args[2:] == (10, 5, 0, 15, 0.00044)


@pytest.mark.asyncio
async def test_usage_with_no_positive_tokens_skips_firestore(monkeypatch):
    async def fail(_executor, function, *_args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        raise AssertionError("usage write should not run")

    monkeypatch.setattr(desktop_realtime, "run_blocking", fail)

    response = await desktop_realtime.report_usage(
        desktop_realtime.UsageReport(provider="gemini", input_text_tokens=-1), "user-1"
    )

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
        desktop_realtime.UsageReport(provider="openai", **{retired_field: value})


@pytest.mark.asyncio
async def test_trial_expiry_copy_offers_managed_recovery_not_customer_keys(monkeypatch):
    async def run(_executor, function, *_args):
        assert function is desktop_realtime.is_trial_paywalled
        return True

    monkeypatch.setattr(desktop_realtime, "run_blocking", run)

    response = await desktop_realtime.mint_session(desktop_realtime.MintRequest(provider="openai"), "user-1")

    assert response.status_code == 402
    body = json.loads(response.body)
    assert body == {
        "error": "trial_expired",
        "message": "Desktop trial expired. Upgrade to continue managed voice.",
    }
    assert "key" not in body["message"].lower()
