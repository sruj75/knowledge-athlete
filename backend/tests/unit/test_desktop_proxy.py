import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock

import httpx
import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

BACKEND_DIR = Path(__file__).resolve().parents[2]
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))

from routers import desktop_proxy


def test_gemini_proxy_routes_legacy_customer_input_to_managed_external_adapter(monkeypatch):
    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    outbound: dict[str, Any] = {}

    class FakeAsyncClient:
        def __init__(self, **_kwargs):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, _exc_type, _exc, _traceback):
            return None

        async def post(self, url, *, params, content, headers):
            outbound.update(url=url, params=params, content=content, headers=headers)
            return httpx.Response(200, content=b'{"managed":true}', headers={'content-type': 'application/json'})

    meter = MagicMock(side_effect=[(True, 1, 60), (True, 1, 86_400)])
    monkeypatch.setenv('GEMINI_API_KEY', 'managed-gemini-key')
    monkeypatch.setattr(desktop_proxy, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_proxy.redis_db, 'check_rate_limit', meter)
    monkeypatch.setattr(desktop_proxy, 'llm_stub_enabled', lambda: False)
    monkeypatch.setattr(desktop_proxy.httpx, 'AsyncClient', FakeAsyncClient)

    app = FastAPI()
    app.include_router(desktop_proxy.router)
    app.dependency_overrides[desktop_proxy._authorized_desktop_user] = lambda: 'managed-user'
    try:
        with TestClient(app) as client:
            response = client.post(
                '/v1/proxy/gemini/models/gemini-2.5-flash:generateContent?key=legacy-customer-key',
                headers={'X-BYOK-Gemini': 'legacy-customer-key'},
                json={'contents': [{'role': 'user', 'parts': [{'text': 'hello'}]}]},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {'managed': True}
    assert outbound['url'] == (
        'https://generativelanguage.googleapis.com/v1beta/' 'models/gemini-2.5-flash:generateContent'
    )
    assert 'key' not in outbound['params']
    assert outbound['headers']['x-goog-api-key'] == 'managed-gemini-key'
    assert 'legacy-customer-key' not in outbound['headers'].values()
    assert json.loads(outbound['content']) == {
        'contents': [{'role': 'user', 'parts': [{'text': 'hello'}]}],
        'generationConfig': {'thinkingConfig': {'thinkingBudget': 1024}},
    }
    assert meter.call_count == 2


def test_sanitize_caps_generation_and_normalizes_system_content():
    body = desktop_proxy._sanitize(
        json.dumps(
            {
                "safetySettings": [{"category": "x"}],
                "contents": [{"role": "system", "parts": [{"text": "system"}]}, {"parts": [{"text": "user"}]}],
                "generation_config": {"maxOutputTokens": "9000"},
            }
        ).encode(),
        "generateContent",
    )
    payload = json.loads(body)
    assert "safetySettings" not in payload
    assert payload["contents"] == [{"role": "user", "parts": [{"text": "user"}]}]
    assert payload["systemInstruction"] == {"parts": [{"text": "system"}]}
    assert payload["generation_config"] == {"maxOutputTokens": 8192, "thinkingConfig": {"thinkingBudget": 1024}}


def test_sanitize_rejects_multiple_candidates_and_path_is_allowlisted():
    with pytest.raises(HTTPException, match="candidate_count"):
        desktop_proxy._sanitize(b'{"candidateCount": 2}', "generateContent")
    assert desktop_proxy._path_parts("models/gemini-3-flash-preview:generateContent") == (
        "models/gemini-2.5-flash:generateContent",
        "gemini-2.5-flash",
        "generateContent",
    )
    with pytest.raises(HTTPException):
        desktop_proxy._path_parts("models/gemini-2.5-pro:deleteModel")


def test_proxy_rejects_product_dead_pro_and_streaming_actions():
    with pytest.raises(HTTPException) as pro_error:
        desktop_proxy._path_parts("models/gemini-2.5-pro:generateContent")
    assert pro_error.value.status_code == 403

    with pytest.raises(HTTPException) as streaming_error:
        desktop_proxy._path_parts("models/gemini-2.5-flash:streamGenerateContent")
    assert streaming_error.value.status_code == 403


def test_streaming_proxy_route_is_absent():
    app = FastAPI()
    app.include_router(desktop_proxy.router)
    app.dependency_overrides[desktop_proxy._authorized_desktop_user] = lambda: 'managed-user'
    try:
        with TestClient(app) as client:
            response = client.post(
                '/v1/proxy/gemini-stream/models/gemini-2.5-flash:generateContent',
                json={'contents': [{'role': 'user', 'parts': [{'text': 'hello'}]}]},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 404


def test_desktop_live_suggestions_model_is_allowed_on_the_developer_api():
    """Desktop live suggestions run on Flash-Lite (ModelQoS.suggestions), so the proxy must forward it."""
    assert desktop_proxy._path_parts("models/gemini-2.5-flash-lite:generateContent") == (
        "models/gemini-2.5-flash-lite:generateContent",
        "gemini-2.5-flash-lite",
        "generateContent",
    )


def test_every_proxy_model_the_desktop_client_ships_is_proxy_allowlisted():
    """Static checker: ModelQoS.swift picks the models the desktop sends to this proxy.

    Not behavioral coverage — it reads the client's model table so a tier change there
    cannot ship a proxy-routed model the proxy answers with 403. Normal Chat is excluded
    because it uses the native versioned streaming boundary instead of this legacy proxy.
    """
    qos = BACKEND_DIR.parent / "desktop/macos/Desktop/Sources/ModelQoS.swift"
    if not qos.exists():  # partial checkouts (backend-only forks) have no desktop tree
        pytest.skip("desktop sources are not present in this checkout")
    proxy_models = set(
        re.findall(
            r'static let (?:proactive|taskExtraction|insight|suggestions|embedding) = "(gemini-[^"]+)"',
            qos.read_text(),
        )
    )
    assert proxy_models
    assert proxy_models <= desktop_proxy._ALLOWED_MODELS
    assert "gemini-3.7-flash" not in desktop_proxy._ALLOWED_MODELS


@pytest.mark.asyncio
async def test_gemini_proxy_rejects_paywalled_desktop_user(monkeypatch):
    async def run_blocking(_, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_proxy, "run_blocking", run_blocking)
    monkeypatch.setattr(desktop_proxy, "is_trial_paywalled", lambda uid, platform: True)

    with pytest.raises(HTTPException) as error:
        await desktop_proxy._authorized_desktop_user("user")

    assert error.value.status_code == 402
    assert error.value.detail == "trial_expired"


@pytest.mark.asyncio
async def test_server_gemini_meter_preserves_the_explicit_flash_route(monkeypatch):
    async def run_blocking(_, function, *args, **kwargs):
        if function is desktop_proxy.redis_db.check_rate_limit:
            if args[1] == "desktop_gemini_daily":
                return True, 31, 86_400
            return True, 1, 60
        return 31, 86_400

    monkeypatch.setattr(desktop_proxy, "run_blocking", run_blocking)
    monkeypatch.setenv("OMI_MODEL_TIER", "max")

    assert (
        await desktop_proxy._meter_server_request(
            "user", "models/gemini-2.5-flash:generateContent", "gemini-2.5-flash", "generateContent"
        )
        == "models/gemini-2.5-flash:generateContent"
    )
