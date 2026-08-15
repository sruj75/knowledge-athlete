from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import metrics


def make_client() -> TestClient:
    app = FastAPI()
    app.include_router(metrics.router)
    return TestClient(app)


def test_metrics_requires_the_exact_bearer_secret(monkeypatch):
    monkeypatch.setenv("METRICS_SECRET", "metrics-test-secret")
    client = make_client()

    assert client.get("/metrics").status_code == 401
    assert client.get("/metrics", headers={"Authorization": "Bearer wrong"}).status_code == 401


def test_metrics_returns_a_bounded_low_cardinality_payload(monkeypatch):
    secret = "metrics-test-secret"
    monkeypatch.setenv("METRICS_SECRET", secret)

    response = make_client().get("/metrics", headers={"Authorization": f"Bearer {secret}"})

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "pusher_ready 1.0" in response.text
    assert "omi_journey_accepted_total" in response.text
    assert len(response.content) < 2_000_000
    assert secret not in response.text
