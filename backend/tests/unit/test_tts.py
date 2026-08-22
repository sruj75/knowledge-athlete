"""S-22 contract: only the retained OpenAI TTS route remains mounted."""

from fastapi.testclient import TestClient

import main


def test_elevenlabs_tts_route_is_retired() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    assert client.post('/v2/tts/synthesize', json={'text': 'hello'}).status_code == 404


def test_openai_tts_route_remains_authenticated() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    assert client.post('/v1/tts/synthesize', json={'text': 'hello', 'voice_id': 'marin'}).status_code == 401
