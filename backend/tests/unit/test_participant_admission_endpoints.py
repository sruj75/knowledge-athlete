from __future__ import annotations

from collections.abc import Callable
import logging

import pytest
from fastapi import Depends, FastAPI, WebSocket
from fastapi.testclient import TestClient
from redis.exceptions import RedisError
from starlette.websockets import WebSocketDisconnect

import main
from config.participant_admission import RELEASE_PROBE_UID
from database import users as database_users
from routers import chat as voice_chat
from routers import chat_sessions, desktop_chat, transcribe
from services.users import account_deletion, data_export
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


def test_legacy_principal_can_export_delete_real_account_but_not_use_managed_compute(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: None)
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: None)

    monkeypatch.setattr(data_export, "get_user_profile", lambda _uid: {"language": "en"})
    monkeypatch.setattr(data_export, "get_existing_user_subscription", lambda _uid: None)
    monkeypatch.setattr(data_export, "get_monthly_usage_for_subscription", lambda _uid: {})
    monkeypatch.setattr(data_export.llm_usage_db, "get_total_llm_cost", lambda _uid: 0)
    deletion_intents: list[str] = []

    def persisted_intent(uid: str) -> dict:
        deletion_intents.append(uid)
        return {"wipe_job_id": "existing-account-wipe", "dispatch_claimed": False}

    monkeypatch.setattr(account_deletion.users_db, "mark_user_deletion_wipe_intent", persisted_intent)

    client = TestClient(main.app)
    headers = {"Authorization": "Bearer valid-firebase-token"}
    compute = client.post(
        "/v2/models/gemini-3.7-flash:streamGenerateContent?alt=sse",
        headers=headers,
        json={"contents": [{"role": "user", "parts": [{"text": "hello"}]}]},
    )
    account = client.get("/v1/users/export", headers=headers)
    deletion = client.delete("/v1/users/delete-account", headers=headers)

    assert compute.status_code == 403
    assert account.status_code == 200
    assert account.json()["account"] == {"uid": "legacy-unlisted-user", "language": "en"}
    assert account.json()["schema_version"] == 1
    assert deletion.status_code == 200
    assert deletion.json() == {"status": "ok", "message": "Account deletion started"}
    assert deletion_intents == ["legacy-unlisted-user"]


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


def test_real_rate_limited_route_denies_before_redis_or_provider_work(monkeypatch: pytest.MonkeyPatch):
    _hosted_policy(monkeypatch)
    calls: list[str] = []
    monkeypatch.setattr(auth, "verify_token", lambda _token: "legacy-unlisted-user")
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: calls.append("platform"))
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: calls.append("device"))
    monkeypatch.setattr(auth, "_enforce_rate_limit", lambda *_args: calls.append("redis"))
    monkeypatch.setattr(chat_sessions, "get_workload_client", lambda *_args: calls.append("provider"))
    app = FastAPI()
    app.include_router(chat_sessions.router)

    response = TestClient(app).post(
        "/v2/chat/initial-message",
        headers={"Authorization": "Bearer valid-firebase-token"},
        json={},
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


def test_rejected_admin_impersonation_log_does_not_disclose_participant_uid(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
):
    _hosted_policy(monkeypatch)
    admin_key = "admin-key-longer-than-sixteen"
    rejected_uid = "private-rejected-participant"
    monkeypatch.setenv("ADMIN_KEY", admin_key)
    monkeypatch.setenv("ADMIN_KEY_AUTH_ENABLED", "true")

    with caplog.at_level(logging.WARNING, logger=auth.logger.name):
        response = TestClient(_app(lambda: pytest.fail("compute handler must not run"))).post(
            "/compute",
            headers={"Authorization": f"Bearer {admin_key}{rejected_uid}"},
        )

    assert response.status_code == 403
    assert response.json() == {"detail": "participant_not_admitted"}
    assert "event=admin_key_auth outcome=impersonation_accepted" in caplog.text
    assert rejected_uid not in caplog.text


def test_admitted_metadata_and_rate_limit_errors_do_not_disclose_participant_uid(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
):
    participant_uid = "private-admitted-participant"
    _hosted_policy(monkeypatch, participants=participant_uid)
    monkeypatch.setattr(auth, "verify_token", lambda _token: participant_uid)
    monkeypatch.setattr(database_users, "try_acquire_user_platform_write_lock", lambda *_args: True)
    monkeypatch.setattr(database_users, "try_acquire_client_device_write_lock", lambda *_args: True)

    class FailingFirestore:
        def collection(self, _name: str):
            raise RuntimeError(f"firestore failure for {participant_uid}")

    monkeypatch.setattr(database_users, "db", FailingFirestore())
    monkeypatch.setattr(
        auth,
        "check_rate_limit",
        lambda *_args: (_ for _ in ()).throw(RedisError(f"redis failure for {participant_uid}")),
    )
    monkeypatch.setattr(voice_chat, "is_trial_paywalled", lambda *_args: False)
    app = FastAPI()
    app.include_router(voice_chat.router)

    with caplog.at_level(logging.DEBUG):
        response = TestClient(app).post(
            "/v2/voice-message/transcribe",
            content=b"",
            headers={
                "Authorization": "Bearer valid-firebase-token",
                "Content-Type": "application/octet-stream",
                "X-App-Platform": "macos",
                "X-Device-Id-Hash": "01234567",
            },
        )

    assert response.status_code == 400
    assert "operation=record_user_platform exception_type=RuntimeError" in caplog.text
    assert "operation=record_client_device exception_type=RuntimeError" in caplog.text
    assert "outcome=redis_error policy=voice:transcribe exception_type=RedisError" in caplog.text
    assert "firestore failure" not in caplog.text
    assert "redis failure" not in caplog.text
    assert participant_uid not in caplog.text


def test_admitted_shadow_rate_limit_log_does_not_disclose_participant_uid(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
):
    participant_uid = "private-shadow-participant"
    _hosted_policy(monkeypatch, participants=participant_uid)
    monkeypatch.setattr(auth, "verify_token", lambda _token: participant_uid)
    monkeypatch.setattr(auth, "record_user_platform", lambda *_args: None)
    monkeypatch.setattr(auth, "record_client_device", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(auth, "check_rate_limit", lambda *_args: (False, 0, 17))
    monkeypatch.setattr(auth, "RATE_LIMIT_SHADOW", True)
    monkeypatch.setattr(voice_chat, "is_trial_paywalled", lambda *_args: False)
    app = FastAPI()
    app.include_router(voice_chat.router)

    with caplog.at_level(logging.WARNING, logger=auth.logger.name):
        response = TestClient(app).post(
            "/v2/voice-message/transcribe",
            content=b"",
            headers={"Authorization": "Bearer valid-firebase-token", "Content-Type": "application/octet-stream"},
        )

    assert response.status_code == 400
    assert "outcome=shadow_rejected policy=voice:transcribe retry_after_seconds=17" in caplog.text
    assert participant_uid not in caplog.text


def test_ptt_provider_connection_failure_log_does_not_disclose_participant_uid(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
):
    participant_uid = "private-ptt-participant"
    _hosted_policy(monkeypatch, participants=participant_uid)
    monkeypatch.setattr(auth, "verify_token", lambda _token: participant_uid)
    monkeypatch.setattr(voice_chat, "is_trial_paywalled", lambda *_args: False)
    monkeypatch.setattr(voice_chat, "check_rate_limit", lambda *_args: (True, 59, 0))
    monkeypatch.setattr(voice_chat, "check_budget", lambda *_args: (True, 0, 7_200_000))

    async def unavailable_provider(*_args):
        return None

    monkeypatch.setattr(voice_chat, "process_audio_modulate", unavailable_provider)
    app = FastAPI()
    app.include_router(voice_chat.router)

    with caplog.at_level(logging.ERROR, logger=voice_chat.logger.name):
        with pytest.raises(WebSocketDisconnect) as caught:
            with TestClient(app).websocket_connect(
                "/v2/voice-message/transcribe-stream",
                headers={"Authorization": "Bearer valid-firebase-token"},
            ) as websocket:
                websocket.receive_json()

    assert caught.value.code == 1011
    assert "event=ptt_stream outcome=provider_connection_failed provider=modulate" in caplog.text
    assert participant_uid not in caplog.text
