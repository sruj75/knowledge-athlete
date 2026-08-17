"""Route-level coverage for the retained managed-cost aggregate only."""

from unittest.mock import MagicMock

from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import users as users_router


app = FastAPI()
app.include_router(users_router.router)
app.dependency_overrides[users_router.auth.get_current_user_uid] = lambda: 'test-user'
client = TestClient(app)


def test_detailed_and_personal_usage_routes_are_absent() -> None:
    assert client.get('/v1/users/me/llm-usage?days=14').status_code == 404
    assert client.get('/v1/users/me/llm-usage/top-features?days=7&limit=2').status_code == 404
    assert client.post('/v1/users/me/llm-usage', json={'feature': 'chat'}).status_code == 404


def test_total_managed_cost_route_is_retained(monkeypatch) -> None:
    get_total = MagicMock(return_value=1.25)
    monkeypatch.setattr(users_router.llm_usage_db, 'get_total_llm_cost', get_total)

    response = client.get('/v1/users/me/llm-usage/total')

    assert response.status_code == 200
    assert response.json() == {'total_cost_usd': 1.25}
    get_total.assert_called_once_with('test-user')
