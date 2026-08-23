"""S-25 contract: one backend serves retained work and retired workers are absent."""

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

import main


def test_retired_worker_routes_are_genuine_not_found() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    for method, path in (
        ('POST', '/v2/audio-merge-jobs/run'),
        ('POST', '/v1/conversation-finalization-jobs/run'),
        ('POST', '/v1/diarization'),
        ('POST', '/v1/embedding'),
        ('POST', '/v2/embedding'),
    ):
        response = client.request(method, path)
        assert response.status_code == 404, f'{method} {path} returned {response.status_code}, not 404'

    with pytest.raises(WebSocketDisconnect) as websocket_error:
        with client.websocket_connect('/v1/trigger/listen'):
            pytest.fail('retired Pusher WebSocket unexpectedly accepted an upgrade')
    assert websocket_error.value.code == 1000


def test_canonical_backend_retains_health_metrics_listen_and_account_deletion() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    assert client.get('/v1/health').status_code == 200
    assert client.get('/metrics').status_code in {401, 403}

    registered_paths = {route.path for route in main.app.routes}
    assert '/v4/listen' in registered_paths
    assert '/v1/users/delete-account' in registered_paths
    assert '/v1/users/account-deletion-wipes/run' in registered_paths

    unauthenticated_worker = client.post('/v1/users/account-deletion-wipes/run', json={'job_id': 'opaque-job'})
    assert unauthenticated_worker.status_code == 403
