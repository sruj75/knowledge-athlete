"""S-26 contract for the one assembled canonical FastAPI application."""

from unittest.mock import AsyncMock, Mock

from fastapi.testclient import TestClient
from starlette.middleware.cors import CORSMiddleware
from starlette.websockets import WebSocketDisconnect

import pytest

import main


def test_main_app_owns_retained_routes_and_rejects_retired_service_routes() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    health = client.get('/v1/health')
    assert health.status_code == 200
    assert health.json() == {'status': 'ok'}
    assert client.head('/v1/health').status_code == 200

    for path in ('/health', '/ready', '/v2/chat-context'):
        response = client.get(path)
        assert response.status_code == 404, f'GET {path} returned {response.status_code}, not 404'

    for method, path in (
        ('GET', '/v1/config/api-keys'),
        ('POST', '/v2/chat/completions'),
        ('POST', '/v1/proxy/gemini/models'),
        ('POST', '/v2/realtime/session'),
        ('POST', '/v1/tts/synthesize'),
        ('DELETE', '/v1/users/delete-account'),
        ('POST', '/v1/users/account-deletion-wipes/run'),
    ):
        response = client.request(method, path)
        assert response.status_code in {401, 403, 422}, f'{method} {path} is not mounted on main.app'

    registered_paths = {route.path for route in main.app.routes}
    assert '/v4/listen' in registered_paths
    assert '/metrics' in registered_paths


def test_main_app_cors_is_default_deny() -> None:
    cors_middleware = [middleware for middleware in main.app.user_middleware if middleware.cls is CORSMiddleware]

    assert len(cors_middleware) == 1
    assert cors_middleware[0].kwargs['allow_origins'] == []
    assert cors_middleware[0].kwargs['allow_credentials'] is False


def test_main_app_owns_the_single_backend_lifecycle_and_retained_operational_routes(monkeypatch) -> None:
    validate_dispatch = Mock()
    drain_tasks = AsyncMock()
    close_clients = AsyncMock()
    started_tasks: list[str] = []

    def capture_background_task(coroutine, *, name: str) -> None:
        started_tasks.append(name)
        coroutine.close()

    monkeypatch.setattr(main, 'validate_account_deletion_dispatch_configuration', validate_dispatch)
    monkeypatch.setattr(main, 'start_background_task', capture_background_task)
    monkeypatch.setattr(main, 'drain_background_tasks', drain_tasks)
    monkeypatch.setattr(main, 'close_all_clients', close_clients)

    with TestClient(main.app, raise_server_exceptions=False) as client:
        assert client.get('/').json() == {
            'status': 'healthy',
            'service': 'omi-backend',
            'version': '0.1.0',
            'chat_contract_version': '1',
        }
        assert client.get('/metrics').status_code == 401
        with pytest.raises(WebSocketDisconnect) as closed:
            with client.websocket_connect('/v4/listen'):
                pass
        assert closed.value.code == 1008

    validate_dispatch.assert_called_once_with()
    assert started_tasks == ['startup_deletion_wipe_reconcile', 'periodic_deletion_wipe_reconcile']
    drain_tasks.assert_awaited_once_with(timeout=10.0)
    close_clients.assert_awaited_once_with()
