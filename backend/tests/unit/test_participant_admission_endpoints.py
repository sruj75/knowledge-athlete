from __future__ import annotations

from collections.abc import Callable

import pytest
from fastapi import Depends, FastAPI, WebSocket
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from config.participant_admission import RELEASE_PROBE_UID
from routers import desktop_chat, transcribe
from utils.other import endpoints as auth


def _hosted_policy(monkeypatch: pytest.MonkeyPatch, participants: str = "firebase-owner-1") -> None:
    monkeypatch.setenv("OMI_ENV_STAGE", "prod")
    monkeypatch.setenv("INTENTIVE_HOSTED_PARTICIPANT_UIDS", participants)
    monkeypatch.delenv("LOCAL_DEVELOPMENT", raising=False)
    monkeypatch.delenv("SERVICE_ACCOUNT_JSON", raising=False)
    monkeypatch.delenv("GOOGLE_APPLICATION_CREDENTIALS", raising=False)


def _app(work: Callable[[], None]) -> FastAPI:
    app = FastAPI()

    @app.post("/compute")
    def compute(uid: str = Depends(auth.get_current_participant_uid)) -> dict[str, str]:
        work()
        return {"uid": uid}

    @app.get("/account")
    def account(uid: str = Depends(auth.get_current_user_uid)) -> dict[str, str]:
        return {"uid": uid}

    @app.websocket("/compute-ws")
    async def compute_ws(websocket: WebSocket, uid: str = Depends(auth.get_current_participant_uid_ws_listen)) -> None:
        work()
        await websocket.accept()
        await websocket.send_json({"uid": uid})

    return app


def test_http_denial_precedes_client_metadata_and_compute_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: calls.append("platform"))
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: calls.append("device"))

    response = TestClient(_app(lambda: calls.append("compute"))).post(
        "/compute",
        headers={"Authorization": "Bearer valid-firebase-token"},
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "participant_not_admitted"}
    assert calls == []


def test_http_admission_records_metadata_only_after_an_exact_uid_match(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "firebase-owner-1")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: calls.append("platform"))
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: calls.append("device"))

    response = TestClient(_app(lambda: calls.append("compute"))).post(
        "/compute",
        headers={"Authorization": "Bearer valid-firebase-token", "X-App-Platform": "macos"},
    )

    assert response.status_code == 200
    assert response.json() == {"uid": "firebase-owner-1"}
    assert calls == ["platform", "device", "compute"]


def test_invalid_hosted_configuration_fails_before_metadata_or_compute_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch, participants="")
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "firebase-owner-1")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: calls.append("platform"))
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: calls.append("device"))

    response = TestClient(_app(lambda: calls.append("compute"))).post(
        "/compute",
        headers={"Authorization": "Bearer valid-firebase-token"},
    )

    assert response.status_code == 503
    assert response.json() == {"detail": "participant_admission_unavailable"}
    assert calls == []


def test_legacy_principal_retains_authenticated_account_surface(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: None)
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: None)

    client = TestClient(_app(lambda: pytest.fail("compute handler must not run")))
    compute = client.post("/compute", headers={"Authorization": "Bearer valid-firebase-token"})
    account = client.get("/account", headers={"Authorization": "Bearer valid-firebase-token"})

    assert compute.status_code == 403
    assert account.status_code == 200
    assert account.json() == {"uid": "legacy-unlisted-user"}


def test_websocket_denial_precedes_handler_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")

    with pytest.raises(WebSocketDisconnect) as caught:
        with TestClient(_app(lambda: calls.append("compute"))).websocket_connect(
            "/compute-ws", headers={"Authorization": "Bearer valid-firebase-token"}
        ):
            pass

    assert caught.value.code == 1008
    assert caught.value.reason == "participant_not_admitted"
    assert calls == []


def test_websocket_admits_an_exact_uid_match(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "firebase-owner-1")

    with TestClient(_app(lambda: calls.append("compute"))).websocket_connect(
        "/compute-ws", headers={"Authorization": "Bearer valid-firebase-token"}
    ) as websocket:
        assert websocket.receive_json() == {"uid": "firebase-owner-1"}

    assert calls == ["compute"]


def test_real_chat_route_denies_before_handler_provider_or_metering_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: calls.append("platform"))
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: calls.append("device"))
    monkeypatch.setattr(desktop_chat, "llm_stub_enabled", lambda: calls.append("provider") or True)
    monkeypatch.setattr(desktop_chat, "_meter_server_request", lambda *_args: calls.append("meter"))
    app = FastAPI()
    app.include_router(desktop_chat.router)

    response = TestClient(app).post(
        "/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse",
        headers={"Authorization": "Bearer valid-firebase-token"},
        json={"contents": [{"role": "user", "parts": [{"text": "hello"}]}]},
    )

    assert response.status_code == 403
    assert response.json() == {"detail": "participant_not_admitted"}
    assert calls == []


def test_real_chat_route_admits_reserved_release_probe_after_human_config_validates(
    monkeypatch: pytest.MonkeyPatch,
):
    _hosted_policy(monkeypatch)
    monkeypatch.setattr(auth, "verify_token", lambda _token: RELEASE_PROBE_UID)
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: None)
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_chat, "llm_stub_enabled", lambda: True)
    app = FastAPI()
    app.include_router(desktop_chat.router)

    response = TestClient(app).post(
        "/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse",
        headers={"Authorization": "Bearer release-probe-firebase-token"},
        json={"contents": [{"role": "user", "parts": [{"text": "hello"}]}]},
    )

    assert response.status_code == 200


def test_real_listen_route_denies_before_session_contract_or_provider_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(transcribe, "run_listen_session", lambda *_args: calls.append("provider"))
    app = FastAPI()
    app.include_router(transcribe.router)

    with pytest.raises(WebSocketDisconnect) as caught:
        with TestClient(app).websocket_connect(
            "/v4/listen?language=en",
            headers={"Authorization": "Bearer valid-firebase-token"},
        ):
            pass

    assert caught.value.code == 1008
    assert caught.value.reason == "participant_not_admitted"
    assert calls == []
