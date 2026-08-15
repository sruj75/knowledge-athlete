import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from routers import desktop_screen_activity
from utils.other.endpoints import get_current_user_uid


def make_client() -> TestClient:
    app = FastAPI()
    app.include_router(desktop_screen_activity.router)
    app.dependency_overrides[get_current_user_uid] = lambda: "user-1"
    return TestClient(app)


def test_screen_activity_sync_writes_rows_and_embeddings(monkeypatch):
    writes = []
    monkeypatch.setattr(
        desktop_screen_activity, "upsert_screen_activity", lambda uid, rows: writes.append((uid, rows)) or 2
    )
    monkeypatch.setattr(
        desktop_screen_activity,
        "upsert_screen_activity_vectors",
        lambda uid, rows: writes.append(("vectors", uid, rows)),
    )

    response = make_client().post(
        "/v1/screen-activity/sync",
        json={
            "rows": [
                {
                    "id": 4,
                    "timestamp": "2026-07-26T00:00:00Z",
                    "appName": "Safari",
                    "clientDeviceId": "mac-a",
                    "embedding": [0.1],
                },
                {"id": 7, "timestamp": "2026-07-26T00:01:00Z", "ocrText": "hello"},
            ]
        },
    )

    assert response.status_code == 200
    assert response.json() == {"synced": 2, "last_id": 7}
    assert writes == [
        (
            "user-1",
            [
                {
                    "id": 4,
                    "timestamp": "2026-07-26T00:00:00Z",
                    "appName": "Safari",
                    "windowTitle": "",
                    "ocrText": "",
                    "deviceName": None,
                    "clientDeviceId": "mac-a",
                    "embedding": [0.1],
                    "storageId": "mac-a-4",
                },
                {
                    "id": 7,
                    "timestamp": "2026-07-26T00:01:00Z",
                    "appName": "",
                    "windowTitle": "",
                    "ocrText": "hello",
                    "deviceName": None,
                    "clientDeviceId": None,
                    "embedding": None,
                    "storageId": "7",
                },
            ],
        ),
        (
            "vectors",
            "user-1",
            [
                {
                    "id": 4,
                    "timestamp": "2026-07-26T00:00:00Z",
                    "appName": "Safari",
                    "windowTitle": "",
                    "ocrText": "",
                    "deviceName": None,
                    "clientDeviceId": "mac-a",
                    "embedding": [0.1],
                    "storageId": "mac-a-4",
                }
            ],
        ),
    ]


def test_screen_activity_sync_rejects_batches_larger_than_rust_contract():
    response = make_client().post(
        "/v1/screen-activity/sync",
        json={"rows": [{"id": index, "timestamp": "2026-07-26T00:00:00Z"} for index in range(101)]},
    )

    assert response.status_code == 400
    assert response.json() == {"detail": "Maximum 100 rows per batch"}


def test_screen_activity_storage_ids_are_device_scoped():
    first = desktop_screen_activity.ScreenActivityRow(id=1, timestamp="2026-07-26T00:00:00Z", clientDeviceId="mac-a")
    second = desktop_screen_activity.ScreenActivityRow(id=1, timestamp="2026-07-26T00:00:00Z", clientDeviceId="mac-b")

    assert first.storage_id() == "mac-a-1"
    assert second.storage_id() == "mac-b-1"


def test_crisp_unread_route_is_absent_while_screen_sync_remains_available():
    client = make_client()

    assert client.get("/v1/crisp/unread").status_code == 404
    assert client.post("/v1/screen-activity/sync", json={"rows": []}).json() == {"synced": 0, "last_id": 0}


@pytest.mark.asyncio
async def test_screen_activity_rejects_paywalled_desktop_user(monkeypatch):
    async def run_blocking(_, function, *args):
        return function(*args)

    monkeypatch.setattr(desktop_screen_activity, "run_blocking", run_blocking)
    monkeypatch.setattr(desktop_screen_activity, "is_trial_paywalled", lambda uid, platform: True)

    with pytest.raises(HTTPException) as error:
        await desktop_screen_activity._authorized_desktop_user("user")

    assert error.value.status_code == 402
    assert error.value.detail == "trial_expired"
