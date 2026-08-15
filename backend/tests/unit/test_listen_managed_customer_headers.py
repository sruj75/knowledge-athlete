from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import transcribe
from utils.byok import get_byok_keys, set_byok_keys
from utils.other import endpoints as auth


def test_v4_listen_ignores_legacy_customer_headers_and_emits_managed_transcript(monkeypatch):
    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def fake_run_listen_session(request):
        assert request.uid == 'managed-user'
        assert get_byok_keys() == {}
        await request.websocket.send_json(
            {
                'type': 'transcript',
                'segments': [{'text': 'managed transcript', 'speaker': 'SPEAKER_00'}],
            }
        )

    monkeypatch.setattr(auth, 'run_blocking', immediate)
    monkeypatch.setattr(auth, '_verify_ws_auth', lambda authorization: 'managed-user')
    monkeypatch.setattr(transcribe, 'run_listen_session', fake_run_listen_session)

    app = FastAPI()
    app.include_router(transcribe.router)
    set_byok_keys({})

    with TestClient(app) as client:
        with client.websocket_connect(
            '/v4/listen',
            headers={
                'Authorization': 'Bearer managed-account-token',
                'X-BYOK-Deepgram': 'legacy-deepgram-key',
                'X-BYOK-OpenAI': 'legacy-openai-key',
            },
        ) as websocket:
            event = websocket.receive_json()

    assert event == {
        'type': 'transcript',
        'segments': [{'text': 'managed transcript', 'speaker': 'SPEAKER_00'}],
    }
