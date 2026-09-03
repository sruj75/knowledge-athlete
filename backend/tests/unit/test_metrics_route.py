from fastapi import FastAPI
from fastapi.testclient import TestClient

from database import firestore_read_metrics
from routers import metrics
from utils.translation_core.metrics import get_translation_metrics


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
    assert "live_stt_active_ws_connections 0.0" in response.text
    assert "intentive_journey_accepted_total" in response.text
    assert "omi_journey_accepted_total" not in response.text
    assert len(response.content) < 2_000_000
    assert secret not in response.text


def test_component_metrics_use_current_product_namespace():
    translation = get_translation_metrics()

    assert firestore_read_metrics.FIRESTORE_READ_OPERATIONS._name == "intentive_firestore_read_operations"
    assert firestore_read_metrics.FIRESTORE_DOCUMENTS_PER_OPERATION._name == (
        "intentive_firestore_documents_per_operation"
    )
    assert translation._requests._name == "intentive_translation_requests"
    assert translation._latency._name == "intentive_translation_latency_seconds"
