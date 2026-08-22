"""S-11 contract: normal Chat durability is local and retired cloud routes are absent."""

from fastapi.testclient import TestClient

import main


def test_retired_chat_storage_routes_return_404_from_the_mounted_app() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)
    retired = (
        ('GET', '/v2/chat-sessions'),
        ('POST', '/v2/chat-sessions'),
        ('GET', '/v2/chat-sessions/chat-1'),
        ('PATCH', '/v2/chat-sessions/chat-1'),
        ('DELETE', '/v2/chat-sessions/chat-1'),
        ('GET', '/v2/desktop/messages'),
        ('POST', '/v2/desktop/messages'),
        ('GET', '/v2/desktop/messages/reconcile'),
        ('DELETE', '/v2/desktop/messages'),
        ('PATCH', '/v2/desktop/messages/message-1/rating'),
        ('PATCH', '/v2/messages/message-1/rating'),
        ('GET', '/v2/messages'),
        ('POST', '/v2/messages'),
        ('DELETE', '/v2/messages'),
        ('POST', '/v2/messages/message-1/report'),
        ('POST', '/v1/messages/message-1/report'),
        ('POST', '/v2/initial-message'),
        ('DELETE', '/v1/messages'),
        ('POST', '/v1/initial-message'),
        ('GET', '/v1/users/stats/chat-messages'),
        ('POST', '/v1/users/analytics/chat_message'),
        ('POST', '/v2/files'),
        ('POST', '/v1/files'),
    )

    for method, path in retired:
        assert client.request(method, path).status_code == 404, f'{method} {path} is still mounted'


def test_retained_chat_compute_routes_remain_mounted() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    assert client.post('/v2/chat/initial-message').status_code == 401
    assert client.post('/v2/chat/generate-title').status_code == 401
    assert client.post('/v2/chat/completions').status_code == 401
    assert client.post('/v2/voice-messages').status_code == 401


def test_retired_v1_files_is_genuine_404_before_authentication() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    assert client.post('/v1/files').status_code == 404
    assert client.post('/v1/files', headers={'Authorization': 'Bearer synthetic'}).status_code == 404
