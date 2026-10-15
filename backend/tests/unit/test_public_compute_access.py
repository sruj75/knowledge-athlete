"""Public hosted compute keeps Firebase auth, quotas and owner account operations."""

from __future__ import annotations

from collections.abc import Callable
import logging

import pytest
from fastapi import Depends, FastAPI, WebSocket
from fastapi.testclient import TestClient
from firebase_admin.auth import InvalidIdTokenError
from redis.exceptions import RedisError
from starlette.websockets import WebSocketDisconnect

import main
from database import users as database_users
from routers import chat as voice_chat
from routers import chat_sessions, desktop_conversation, desktop_realtime, transcribe
from scripts.firebase_release_probe_token import PROBE_UID
from services import desktop_inference
from services.users import account_deletion, data_export
from utils.observability.conversation_prompts import conversation_prompt_receipt, _fallback
from utils.other import endpoints as auth


@pytest.fixture(autouse=True)
def hosted_runtime(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('OMI_ENV_STAGE', 'prod')
    monkeypatch.setenv('ADMIN_KEY_AUTH_ENABLED', 'false')
    monkeypatch.delenv('LOCAL_DEVELOPMENT', raising=False)
    monkeypatch.delenv('K_SERVICE', raising=False)
    monkeypatch.delenv('SERVICE_ACCOUNT_JSON', raising=False)
    monkeypatch.delenv('GOOGLE_APPLICATION_CREDENTIALS', raising=False)


def _app(work: Callable[[], None]) -> FastAPI:
    app = FastAPI()

    @app.post('/compute')
    def compute(uid: str = Depends(auth.get_current_user_uid)) -> dict[str, str]:
        work()
        return {'uid': uid}

    @app.websocket('/compute-ws')
    async def compute_ws(websocket: WebSocket, uid: str = Depends(auth.get_current_user_uid_ws_listen)) -> None:
        work()
        await websocket.accept()
        await websocket.send_json({'uid': uid})

    return app


@pytest.mark.parametrize('uid', [*(f'new-firebase-user-{index}' for index in range(6)), PROBE_UID])
def test_any_verified_firebase_account_can_compute_without_an_invite(monkeypatch: pytest.MonkeyPatch, uid: str):
    calls: list[str] = []
    monkeypatch.setattr(auth, 'verify_token', lambda _token: uid)
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: calls.append('platform'))
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: calls.append('device'))

    response = TestClient(_app(lambda: calls.append('compute'))).post(
        '/compute', headers={'Authorization': 'Bearer valid-firebase-token'}
    )

    assert response.status_code == 200
    assert response.json() == {'uid': uid}
    assert calls == ['platform', 'device', 'compute']


@pytest.mark.parametrize('authorization', [None, 'malformed', 'Bearer invalid-firebase-token'])
def test_http_auth_failure_precedes_metadata_and_compute(monkeypatch: pytest.MonkeyPatch, authorization: str | None):
    calls: list[str] = []

    def invalid(_token):
        raise InvalidIdTokenError('invalid token')

    monkeypatch.setattr(auth, 'verify_token', invalid)
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: calls.append('platform'))
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: calls.append('device'))
    headers = {'Authorization': authorization} if authorization is not None else {}

    response = TestClient(_app(lambda: calls.append('compute'))).post('/compute', headers=headers)

    assert response.status_code == 401
    assert calls == []


@pytest.mark.parametrize('uid', ['new-firebase-user', PROBE_UID])
def test_verified_websocket_accounts_do_not_require_invites(monkeypatch: pytest.MonkeyPatch, uid: str):
    calls: list[str] = []
    monkeypatch.setattr(auth, 'verify_token', lambda _token: uid)

    with TestClient(_app(lambda: calls.append('compute'))).websocket_connect(
        '/compute-ws', headers={'Authorization': 'Bearer valid-firebase-token'}
    ) as websocket:
        assert websocket.receive_json() == {'uid': uid}

    assert calls == ['compute']


@pytest.mark.parametrize('authorization', [None, 'malformed', 'Bearer invalid-firebase-token'])
def test_websocket_auth_failure_precedes_compute(monkeypatch: pytest.MonkeyPatch, authorization: str | None):
    calls: list[str] = []

    def invalid(_token):
        raise InvalidIdTokenError('invalid token')

    monkeypatch.setattr(auth, 'verify_token', invalid)
    headers = {'Authorization': authorization} if authorization is not None else {}

    with pytest.raises(WebSocketDisconnect) as caught:
        with TestClient(_app(lambda: calls.append('compute'))).websocket_connect('/compute-ws', headers=headers):
            pass

    assert caught.value.code == 1008
    assert calls == []


def test_public_hosted_access_keeps_admin_impersonation_disabled(monkeypatch: pytest.MonkeyPatch):
    calls: list[str] = []
    admin_key = 'admin-key-longer-than-sixteen'
    monkeypatch.setenv('ADMIN_KEY', admin_key)

    def invalid(_token):
        raise InvalidIdTokenError('invalid token')

    monkeypatch.setattr(auth.auth, 'verify_id_token', invalid)

    response = TestClient(_app(lambda: calls.append('compute'))).post(
        '/compute', headers={'Authorization': f'Bearer {admin_key}{PROBE_UID}'}
    )

    assert response.status_code == 401
    assert calls == []


@pytest.mark.parametrize('stage', ['dev', 'prod', 'typo'])
@pytest.mark.parametrize('transport', ['http', 'websocket'])
def test_hosted_stage_rejects_invalid_tokens_even_with_development_flag(monkeypatch, stage, transport):
    monkeypatch.setenv('OMI_ENV_STAGE', stage)
    monkeypatch.setenv('LOCAL_DEVELOPMENT', 'true')
    _assert_invalid_token_stays_rejected(monkeypatch, transport)


@pytest.mark.parametrize('stage', ['', 'local', 'offline'])
@pytest.mark.parametrize('transport', ['http', 'websocket'])
def test_cloud_run_identity_rejects_synthetic_token_bypass(monkeypatch, stage, transport):
    monkeypatch.setenv('K_SERVICE', 'owned-backend')
    monkeypatch.setenv('OMI_ENV_STAGE', stage)
    monkeypatch.setenv('LOCAL_DEVELOPMENT', 'true')
    _assert_invalid_token_stays_rejected(monkeypatch, transport)


def _assert_invalid_token_stays_rejected(monkeypatch, transport):
    calls: list[str] = []

    def invalid(_token):
        raise InvalidIdTokenError('invalid token')

    monkeypatch.setattr(auth.auth, 'verify_id_token', invalid)
    client = TestClient(_app(lambda: calls.append('compute')))
    headers = {'Authorization': 'Bearer invalid-firebase-token'}
    if transport == 'http':
        assert client.post('/compute', headers=headers).status_code == 401
    else:
        with pytest.raises(WebSocketDisconnect) as caught:
            with client.websocket_connect('/compute-ws', headers=headers):
                pass
        assert caught.value.code == 1008
    assert calls == []


@pytest.mark.parametrize('stage', ['', 'local', 'offline'])
def test_local_harness_synthetic_users_are_preserved(monkeypatch, stage):
    monkeypatch.setenv('OMI_ENV_STAGE', stage)
    monkeypatch.setenv('LOCAL_DEVELOPMENT', 'true')

    def invalid(_token):
        raise InvalidIdTokenError('invalid token')

    monkeypatch.setattr(auth.auth, 'verify_id_token', invalid)
    assert auth.verify_token('local-only-token') == '123'


@pytest.mark.parametrize('uid', ['new-firebase-user', PROBE_UID])
def test_real_conversation_bootstrap_accepts_verified_public_and_probe_accounts(monkeypatch, uid):
    monkeypatch.setattr(auth, 'verify_token', lambda _token: uid)
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: None)
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_inference, 'is_trial_paywalled', lambda *_args: False)
    monkeypatch.setattr(
        desktop_conversation, 'bootstrap_conversation_prompt', lambda: conversation_prompt_receipt(_fallback())
    )
    app = FastAPI()
    app.include_router(desktop_conversation.router)

    response = TestClient(app).post(
        '/v1/conversation/session',
        headers={'Authorization': 'Bearer valid-firebase-token'},
        json={'conversation_id': 'conversation-1'},
    )

    assert response.status_code == 200
    assert response.json()['conversation_id'] == 'conversation-1'


def test_real_rate_limited_route_still_denies_public_account_before_provider(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(auth, 'verify_token', lambda _token: 'new-firebase-user')
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: None)
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(auth, 'check_rate_limit', lambda *_args: (False, 0, 17))
    monkeypatch.setattr(auth, 'RATE_LIMIT_SHADOW', False)
    monkeypatch.setattr(chat_sessions, 'get_workload_client', lambda *_args: calls.append('provider'))
    app = FastAPI()
    app.include_router(chat_sessions.router)

    response = TestClient(app).post(
        '/v2/chat/initial-message', headers={'Authorization': 'Bearer valid-firebase-token'}, json={}
    )

    assert response.status_code == 429
    assert response.headers['Retry-After'] == '17'
    assert calls == []


def test_real_listen_route_authenticates_new_account_before_provider(monkeypatch):
    calls: list[str] = []
    monkeypatch.setattr(auth, 'verify_token', lambda _token: 'new-firebase-user')

    async def listen(request):
        calls.append(request.uid)
        await request.websocket.send_json({'uid': request.uid})

    monkeypatch.setattr(transcribe, 'run_listen_session', listen)
    app = FastAPI()
    app.include_router(transcribe.router)

    with TestClient(app).websocket_connect(
        '/v4/listen?language=en', headers={'Authorization': 'Bearer valid-firebase-token'}
    ) as websocket:
        assert websocket.receive_json() == {'uid': 'new-firebase-user'}

    assert calls == ['new-firebase-user']


@pytest.mark.parametrize('outcome', ['burst', 'daily', 'redis_unavailable', 'allowed'])
def test_real_live_mint_enforces_server_quota_before_provider(monkeypatch, outcome):
    uid = 'new-firebase-user'
    policies: list[str] = []
    provider_calls: list[str] = []
    monkeypatch.setenv('GEMINI_API_KEY', 'synthetic-provider-key')
    monkeypatch.setenv('OMI_LLM_STUB', '0')
    monkeypatch.setattr(auth, 'verify_token', lambda _token: uid)
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: None)
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(desktop_realtime, 'is_trial_paywalled', lambda *_args: False)
    monkeypatch.setattr(desktop_realtime, 'resolve_conversation_prompt', lambda _reference: _fallback())

    async def immediate(_executor, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_realtime, 'run_blocking', immediate)
    monkeypatch.setattr(desktop_inference, 'run_blocking', immediate)

    def rate_limit(owner, policy, limit, window):
        assert owner == uid
        policies.append(policy)
        if outcome == 'redis_unavailable':
            raise RedisError('synthetic limiter unavailable')
        assert (limit, window) == ((30, 60) if policy == 'desktop_gemini_burst' else (1500, 86_400))
        denied = (outcome == 'burst' and policy == 'desktop_gemini_burst') or (
            outcome == 'daily' and policy == 'desktop_gemini_daily'
        )
        return not denied, 0, 17

    monkeypatch.setattr(desktop_inference.redis_db, 'check_rate_limit', rate_limit)

    async def mint(*_args):
        provider_calls.append(uid)
        return {'name': 'synthetic-ephemeral-token'}, None

    monkeypatch.setattr(desktop_realtime, '_post_json', mint)
    app = FastAPI()
    app.include_router(desktop_realtime.router)
    receipt = conversation_prompt_receipt(_fallback())
    response = TestClient(app).post(
        '/v2/realtime/session',
        headers={'Authorization': 'Bearer valid-firebase-token'},
        json={'conversation_id': 'conversation-1', 'prompt_ref': receipt.reference().model_dump()},
    )

    if outcome == 'allowed':
        assert response.status_code == 200
        assert response.json()['token'] == 'synthetic-ephemeral-token'
        assert provider_calls == [uid]
    else:
        assert response.status_code == (503 if outcome == 'redis_unavailable' else 429)
        assert 'token' not in response.json()
        assert provider_calls == []
    assert policies == (
        ['desktop_gemini_burst']
        if outcome in {'burst', 'redis_unavailable'}
        else ['desktop_gemini_burst', 'desktop_gemini_daily']
    )


def test_owner_account_export_and_deletion_remain_available(monkeypatch):
    uid = 'new-firebase-user'
    monkeypatch.setattr(auth, 'verify_token', lambda _token: uid)
    monkeypatch.setattr(auth, 'record_user_platform', lambda *_args: None)
    monkeypatch.setattr(auth, 'record_client_device', lambda *_args, **_kwargs: None)
    monkeypatch.setattr(data_export, 'get_user_profile', lambda _uid: {'language': 'en'})
    monkeypatch.setattr(data_export, 'get_existing_user_subscription', lambda _uid: None)
    monkeypatch.setattr(data_export, 'get_monthly_usage_for_subscription', lambda _uid: {})
    monkeypatch.setattr(data_export.llm_usage_db, 'get_total_llm_cost', lambda _uid: 0)
    deletion_intents: list[str] = []

    def persisted_intent(owner: str) -> dict:
        deletion_intents.append(owner)
        return {'wipe_job_id': 'existing-account-wipe', 'dispatch_claimed': False}

    monkeypatch.setattr(account_deletion.users_db, 'mark_user_deletion_wipe_intent', persisted_intent)
    monkeypatch.setattr(account_deletion.users_db, 'require_deletion_wipe_dispatch', lambda _uid, _job_id: None)
    client = TestClient(main.app)
    headers = {'Authorization': 'Bearer valid-firebase-token'}

    account = client.get('/v1/users/export', headers=headers)
    deletion = client.delete('/v1/users/delete-account', headers=headers)

    assert account.status_code == 200
    assert account.json()['account'] == {'uid': uid, 'language': 'en'}
    assert account.json()['schema_version'] == 1
    assert deletion.status_code == 200
    assert deletion.json() == {'status': 'ok', 'message': 'Account deletion started'}
    assert deletion_intents == [uid]


def test_admitted_metadata_and_rate_limit_errors_do_not_disclose_participant_uid(
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
):
    participant_uid = "private-admitted-participant"
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
