import hashlib
import importlib.machinery
import importlib.util
import json
import sys
from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from models.desktop_conversation import ConversationPromptReceipt
from routers import desktop_conversation, desktop_realtime
from utils.observability.langfuse_prompts import ResolvedRuntimePrompt


def _prompt():
    text = "Pinned managed instructions must not appear in probe output"
    return {
        "name": "intentive-live-system",
        "version": "7",
        "source": "langfuse",
        "sha256": hashlib.sha256(text.encode()).hexdigest(),
        "text": text,
    }


def _load_module():
    repo = Path(__file__).resolve().parents[3]
    script_path = repo / "scripts" / "voice-provider-probe.sh"
    loader = importlib.machinery.SourceFileLoader("voice_provider_probe", str(script_path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    loader.exec_module(module)
    return module


class _Response:
    status = 200

    def __init__(self, body):
        self.body = body

    def read(self, _size=-1):
        return self.body

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def test_probe_bootstraps_and_mints_through_current_routes_with_the_same_pinned_prompt(monkeypatch, capsys):
    module = _load_module()
    prompt = _prompt()
    reference = {key: value for key, value in prompt.items() if key != "text"}
    requests = []
    sockets = []

    async def bootstrap(_executor, function, *_args):
        assert function is desktop_conversation.bootstrap_conversation_prompt
        return ConversationPromptReceipt.model_validate(prompt)

    async def mint(_executor, function, *args):
        if function is desktop_realtime.is_trial_paywalled:
            return False
        assert function is desktop_realtime.resolve_conversation_prompt
        assert args[0].model_dump() == reference
        return ResolvedRuntimePrompt(prompt["text"], prompt["name"], prompt["version"], prompt["source"])

    async def provider(*_args):
        return {"name": "auth_tokens/gemini-token-must-not-leak"}, None

    monkeypatch.setattr(desktop_conversation, "run_blocking", bootstrap)

    async def allowed_mint(uid):
        assert uid == "synthetic-owner"

    monkeypatch.setattr(desktop_realtime, "enforce_desktop_gemini_quota", allowed_mint)
    monkeypatch.setattr(desktop_realtime, "run_blocking", mint)
    monkeypatch.setattr(desktop_realtime, "_post_json", provider)
    monkeypatch.setenv("GEMINI_API_KEY", "synthetic-key-never-used")
    app = FastAPI()
    app.include_router(desktop_conversation.router)
    app.include_router(desktop_realtime.router)
    app.dependency_overrides[desktop_conversation.authorized_desktop_user] = lambda: "synthetic-owner"
    app.dependency_overrides[desktop_realtime.get_current_user_uid] = lambda: "synthetic-owner"

    def backend(request, *, timeout):
        assert request.get_header("Authorization") == "Bearer firebase-token-must-not-leak"
        requests.append((request.selector, json.loads(request.data)))
        with TestClient(app) as client:
            response = client.post(request.selector, content=request.data, headers={"Content-Type": "application/json"})
        if response.status_code >= 400:
            raise module.urllib.error.HTTPError(request.full_url, response.status_code, "synthetic", {}, None)
        return _Response(response.content)

    class WebSocket:
        _socket = None

        def __init__(self, *_args):
            self.sent = []
            self.closed = False
            self.events = iter([{"setupComplete": {}}, {"serverContent": {"turnComplete": True}}])
            sockets.append(self)

        def connect(self):
            pass

        def send_json(self, payload):
            self.sent.append(payload)

        def receive_json(self):
            return next(self.events)

        def close(self):
            self.closed = True

    monkeypatch.setattr(module.urllib.request, "urlopen", backend)
    monkeypatch.setattr(module, "ProviderWebSocket", WebSocket)
    result = module.run_probe(module.ProbeConfig("https://candidate.invalid", "firebase-token-must-not-leak", 5))

    assert result == 0
    assert [path for path, _ in requests] == ["/v1/conversation/session", "/v2/realtime/session"]
    assert requests[0][1]["conversation_id"] == requests[1][1]["conversation_id"]
    assert requests[1][1]["prompt_ref"] == reference
    setup = sockets[0].sent[0]["setup"]
    assert setup["systemInstruction"] == {"parts": [{"text": prompt["text"]}]}
    assert setup["realtimeInputConfig"]["automaticActivityDetection"] == {"disabled": False}
    assert setup["realtimeInputConfig"]["activityHandling"] == "START_OF_ACTIVITY_INTERRUPTS"
    assert setup["inputAudioTranscription"] == setup["outputAudioTranscription"] == {}
    assert [tool["name"] for tool in setup["tools"][0]["functionDeclarations"]] == ["end_conversation"]
    assert sockets[0].closed
    output = capsys.readouterr().out
    for secret in (prompt["text"], "firebase-token-must-not-leak", "gemini-token-must-not-leak"):
        assert secret not in output


def test_gemini_probe_commits_text_without_manual_audio_activity_markers(monkeypatch, capsys):
    module = _load_module()
    created = []

    class FakeWebSocket:
        def __init__(self, url, headers, timeout):
            self.url = url
            self.headers = headers
            self.timeout = timeout
            self.events = iter([{"setupComplete": {}}, {"serverContent": {"turnComplete": True}}])
            self.sent = []
            self._socket = None
            self.closed = False
            created.append(self)

        def connect(self):
            return None

        def send_json(self, payload):
            self.sent.append(payload)

        def receive_json(self):
            return next(self.events)

        def close(self):
            self.closed = True

    monkeypatch.setattr(module, "ProviderWebSocket", FakeWebSocket)
    monkeypatch.setattr(
        module,
        "_mint_provider_session",
        lambda _config: module.ProviderSession("auth_tokens/gemini-token-must-not-leak", _prompt()["text"]),
    )

    result = module.run_probe(
        module.ProbeConfig(
            base_url="https://candidate.invalid",
            bearer_token="firebase-token-must-not-leak",
            timeout_seconds=5,
        )
    )

    output = capsys.readouterr().out
    websocket = created[0]
    assert result == 0
    assert websocket.closed is True
    assert websocket.headers == {}
    assert websocket.url.startswith(module.GEMINI_URL_PREFIX)
    assert websocket.sent[0]["setup"]["model"] == "models/gemini-3.1-flash-live-preview"
    # The provider's text-input contract is one realtimeInput.text message.
    # Manual activity markers delimit audio, not a standalone text request:
    # https://ai.google.dev/gemini-api/docs/live-api/capabilities#sending-text
    assert websocket.sent[1:] == [{"realtimeInput": {"text": module.PROBE_INPUT}}]
    assert "provider=gemini step=response status=PASS class=none" in output
    assert "firebase-token-must-not-leak" not in output
    assert "gemini-token-must-not-leak" not in output
    assert module.PROBE_INPUT not in output


def test_mint_rejects_a_2xx_response_with_the_wrong_gemini_token(monkeypatch):
    module = _load_module()
    calls = []

    def fake_urlopen(request, *, timeout):
        calls.append((request, timeout))
        if request.selector == module.SESSION_PATH:
            body = {"conversation_id": json.loads(request.data)["conversation_id"], "prompt": _prompt()}
        else:
            body = {"provider": "gemini", "token": "wrong-prefix", "prompt": _prompt()}
        return _Response(json.dumps(body).encode())

    monkeypatch.setattr(module.urllib.request, "urlopen", fake_urlopen)
    config = module.ProbeConfig(
        base_url="https://candidate.invalid",
        bearer_token="firebase-token-must-not-leak",
        timeout_seconds=5,
    )

    try:
        module._mint_provider_session(config)
    except module.ProbeFailure as error:
        assert error.failure_class == "mint_schema"
    else:
        raise AssertionError("expected typed mint schema rejection")

    request, _ = calls[1]
    assert request.full_url == "https://candidate.invalid/v2/realtime/session"
    assert json.loads(request.data)["prompt_ref"] == {key: value for key, value in _prompt().items() if key != "text"}


def test_timeout_returns_retryable_exit_code_without_exposing_the_token(monkeypatch, capsys):
    module = _load_module()
    monkeypatch.setattr(
        module,
        "_mint_provider_session",
        lambda _config: (_ for _ in ()).throw(module.ProbeFailure("timeout", retryable=True)),
    )

    result = module.run_probe(
        module.ProbeConfig(
            base_url="https://candidate.invalid",
            bearer_token="firebase-token-must-not-leak",
            timeout_seconds=5,
        )
    )

    output = capsys.readouterr().out
    assert result == 75
    assert "provider=gemini step=mint status=FAIL class=timeout" in output
    assert "firebase-token-must-not-leak" not in output


def test_provider_send_timeout_is_reported_once_as_a_retryable_bounded_failure(monkeypatch, capsys):
    module = _load_module()

    class FakeWebSocket:
        _socket = None

        def send_json(self, _payload):
            raise TimeoutError("provider token must not leak")

        def close(self):
            return None

    monkeypatch.setattr(
        module,
        "_mint_provider_session",
        lambda _config: module.ProviderSession("auth_tokens/probe-token-must-not-leak", _prompt()["text"]),
    )
    monkeypatch.setattr(module, "_gemini_websocket", lambda _token, _timeout: FakeWebSocket())

    result = module.run_probe(
        module.ProbeConfig(
            base_url="https://candidate.invalid",
            bearer_token="firebase-token-must-not-leak",
            timeout_seconds=5,
        )
    )

    output = capsys.readouterr().out
    assert result == 75
    assert output.count("status=FAIL") == 1
    assert "provider=gemini step=commit status=FAIL class=timeout" in output
    assert "provider token must not leak" not in output


def test_http_429_is_classified_as_retryable():
    module = _load_module()
    error = module._classify_http_error(429)
    assert error.failure_class == "mint_http_4xx"
    assert error.retryable is True


def test_mint_http_429_returns_retryable_exit_code(monkeypatch, capsys):
    module = _load_module()
    monkeypatch.setattr(
        module,
        "_mint_provider_session",
        lambda _config: (_ for _ in ()).throw(module._classify_http_error(429)),
    )

    result = module.run_probe(
        module.ProbeConfig(
            base_url="https://candidate.invalid",
            bearer_token="firebase-token-must-not-leak",
            timeout_seconds=5,
        )
    )

    output = capsys.readouterr().out
    assert result == 75
    assert "provider=gemini step=mint status=FAIL class=mint_http_4xx" in output


@pytest.mark.parametrize(
    "field,value",
    [
        ("name", "other-prompt"),
        ("version", "0"),
        ("source", "unknown"),
        ("sha256", "0" * 64),
        ("text", ""),
        ("text", "\ud800"),
    ],
)
def test_invalid_bootstrap_receipt_stops_before_mint_without_leaking_prompt(monkeypatch, capsys, field, value):
    module = _load_module()
    calls = []

    def backend(request, *, timeout):
        calls.append(request.selector)
        prompt = {**_prompt(), field: value}
        body = {"conversation_id": json.loads(request.data)["conversation_id"], "prompt": prompt}
        return _Response(json.dumps(body).encode())

    monkeypatch.setattr(module.urllib.request, "urlopen", backend)
    result = module.run_probe(module.ProbeConfig("https://candidate.invalid", "firebase-token-must-not-leak", 5))

    assert result == 1
    assert calls == [module.SESSION_PATH]
    output = capsys.readouterr().out
    assert "class=session_schema" in output
    assert _prompt()["text"] not in output
    assert "firebase-token-must-not-leak" not in output


def test_changed_mint_receipt_stops_before_provider_setup(monkeypatch, capsys):
    module = _load_module()

    def backend(request, *, timeout):
        if request.selector == module.SESSION_PATH:
            body = {"conversation_id": json.loads(request.data)["conversation_id"], "prompt": _prompt()}
        else:
            body = {
                "provider": "gemini",
                "token": "auth_tokens/gemini-token-must-not-leak",
                "prompt": {**_prompt(), "version": "8"},
            }
        return _Response(json.dumps(body).encode())

    monkeypatch.setattr(module.urllib.request, "urlopen", backend)
    monkeypatch.setattr(
        module, "_gemini_websocket", lambda *_args: pytest.fail("changed instructions must not connect")
    )
    result = module.run_probe(module.ProbeConfig("https://candidate.invalid", "firebase-token-must-not-leak", 5))

    assert result == 1
    output = capsys.readouterr().out
    assert "class=mint_schema" in output
    assert _prompt()["text"] not in output
    assert "gemini-token-must-not-leak" not in output


def test_bootstrap_response_for_a_different_conversation_stops_before_mint(monkeypatch):
    module = _load_module()
    body = {"conversation_id": "a-different-conversation", "prompt": _prompt()}
    calls = []

    def backend(request, *, timeout):
        calls.append(request.selector)
        return _Response(json.dumps(body).encode())

    monkeypatch.setattr(module.urllib.request, "urlopen", backend)
    with pytest.raises(module.ProbeFailure, match="session_schema"):
        module._mint_provider_session(module.ProbeConfig("https://candidate.invalid", "synthetic-token", 5))
    assert calls == [module.SESSION_PATH]


def test_pinned_repository_fallback_is_valid_only_with_its_owned_version(monkeypatch):
    module = _load_module()
    prompt = {**_prompt(), "source": "fallback", "version": "conversation-v1"}

    def backend(request, *, timeout):
        if request.selector == module.SESSION_PATH:
            body = {"conversation_id": json.loads(request.data)["conversation_id"], "prompt": prompt}
        else:
            body = {"provider": "gemini", "token": "auth_tokens/synthetic-token", "prompt": prompt}
        return _Response(json.dumps(body).encode())

    monkeypatch.setattr(module.urllib.request, "urlopen", backend)
    session = module._mint_provider_session(module.ProbeConfig("https://candidate.invalid", "synthetic-token", 5))
    assert session.prompt_text == prompt["text"]
    prompt["version"] = "7"
    with pytest.raises(module.ProbeFailure, match="session_schema"):
        module._mint_provider_session(module.ProbeConfig("https://candidate.invalid", "synthetic-token", 5))


@pytest.mark.parametrize("body", [b"not-json", b"[]", b"x" * (128 * 1024 + 1)])
def test_invalid_or_oversized_bootstrap_response_is_a_bounded_typed_failure(monkeypatch, body):
    module = _load_module()
    monkeypatch.setattr(module.urllib.request, "urlopen", lambda *_args, **_kwargs: _Response(body))

    with pytest.raises(module.ProbeFailure, match="session_schema"):
        module._mint_provider_session(module.ProbeConfig("https://candidate.invalid", "synthetic-token", 5))
