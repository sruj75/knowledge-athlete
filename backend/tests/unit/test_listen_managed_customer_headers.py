from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import transcribe
from utils.other import endpoints as auth


def test_v4_listen_ignores_legacy_customer_headers_and_keeps_transient_contract(monkeypatch):
    async def immediate(_executor, function, *args, **kwargs):
        return function(*args, **kwargs)

    async def fake_run_listen_session(request):
        assert request.uid == 'managed-user'
        await request.websocket.send_json(
            {
                'type': 'segments',
                'segments': [
                    {
                        'segmentId': 'cb955089-655a-4b5a-b5e7-fb6fe0d7a774',
                        'speakerId': 0,
                        'text': 'managed transcript',
                        'start': 0.0,
                        'end': 1.0,
                    }
                ],
            }
        )

    monkeypatch.setattr(auth, 'run_blocking', immediate)
    monkeypatch.setattr(auth, '_verify_ws_auth', lambda authorization: 'managed-user')
    monkeypatch.setattr(transcribe, 'run_listen_session', fake_run_listen_session)

    app = FastAPI()
    app.include_router(transcribe.router)
    with TestClient(app) as client:
        with client.websocket_connect(
            '/v4/listen?language=en',
            headers={
                'Authorization': 'Bearer managed-account-token',
                'X-BYOK-Deepgram': 'legacy-deepgram-key',
                'X-BYOK-OpenAI': 'legacy-openai-key',
            },
        ) as websocket:
            event = websocket.receive_json()

    assert event == {
        'type': 'segments',
        'segments': [
            {
                'segmentId': 'cb955089-655a-4b5a-b5e7-fb6fe0d7a774',
                'speakerId': 0,
                'text': 'managed transcript',
                'start': 0.0,
                'end': 1.0,
            }
        ],
    }
