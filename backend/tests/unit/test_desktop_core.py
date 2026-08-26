from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import desktop_core
from utils.other.endpoints import get_current_user_uid


def make_client() -> TestClient:
    app = FastAPI()
    app.include_router(desktop_core.router)
    app.dependency_overrides[get_current_user_uid] = lambda: "user-1"
    return TestClient(app)


def test_root_reports_only_canonical_backend_identity(monkeypatch):
    monkeypatch.setenv("OMI_DESKTOP_RELEASE_TAG", "v1.2.3")
    monkeypatch.setenv("OMI_DESKTOP_RELEASE_SHA", "abc123")
    monkeypatch.setenv("OMI_DESKTOP_RELEASE_CHANNEL", "stable")
    monkeypatch.setenv("OMI_DESKTOP_BACKEND_RELEASE_SHA", "a" * 40)
    monkeypatch.setenv("OMI_DESKTOP_BACKEND_RELEASE_CHANNEL", "development")

    client = make_client()
    expected = {
        "status": "healthy",
        "service": "omi-backend",
        "version": "0.1.0",
        "chat_contract_version": "1",
    }

    assert client.get("/").json() == expected


def test_retired_service_health_and_readiness_aliases_are_absent():
    client = make_client()

    assert client.get("/health").status_code == 404
    assert client.get("/ready").status_code == 404


def test_api_keys_require_firebase_auth_and_omit_unset_values(monkeypatch):
    monkeypatch.setenv("FIREBASE_API_KEY", "firebase-key")
    monkeypatch.delenv("GOOGLE_CALENDAR_API_KEY", raising=False)
    monkeypatch.delenv("DESKTOP_LEGACY_ANTHROPIC_KEY", raising=False)

    app = FastAPI()
    app.include_router(desktop_core.router)
    client = TestClient(app)

    assert client.get("/v1/config/api-keys").status_code == 401

    app.dependency_overrides[get_current_user_uid] = lambda: "user-1"
    response = client.get("/v1/config/api-keys")

    assert response.status_code == 200
    assert response.json() == {"firebase_api_key": "firebase-key"}


def test_sentry_task_bridge_routes_are_absent_while_health_and_config_remain():
    client = make_client()

    assert client.post("/v1/webhooks/sentry").status_code == 404
    assert client.post("/v1/webhooks/sentry/poll").status_code == 404
    assert client.get("/").status_code == 200
    assert client.get("/v1/config/api-keys").status_code == 200


def test_apple_domain_association_remains_public():
    assert make_client().get("/.well-known/apple-developer-domain-association.txt").text == ""
