"""Boundary contract e2e coverage for mobile/client-facing validation.

These tests exercise the real FastAPI routes through the hermetic harness. Unit
coverage owns the pure validation helpers; this file pins the integration seams:
FastAPI parameter binding, auth, multipart parsing, fake storage side effects,
and listen WebSocket close behavior.
"""

import json
from unittest.mock import AsyncMock, MagicMock

from database import conversations as conversations_db
from fakes.storage import list_storage_files
from listen_test_helpers import is_ready_event, receive_until, seed_listen_user
from routers.listen import receiver as listen_receiver


def _fake_png_file():
    return {"file": ("logo.png", b"not-a-real-png-but-validation-runs-first", "image/png")}


def test_malformed_app_form_json_is_rejected_before_storage_write(client, auth_headers):
    response = client.post(
        "/v1/apps",
        data={"app_data": "not-json"},
        files=_fake_png_file(),
        headers=auth_headers,
    )

    assert response.status_code == 422, response.text
    assert "app_data" in response.json()["detail"]
    assert list_storage_files("plugins-logos") == []
    assert list_storage_files("app-thumbnails") == []


def test_persona_form_json_must_be_an_object(client, auth_headers):
    response = client.post(
        "/v1/personas",
        data={"persona_data": "[]"},
        files=_fake_png_file(),
        headers=auth_headers,
    )

    assert response.status_code == 422, response.text
    assert "persona_data" in response.json()["detail"]
    assert list_storage_files("plugins-logos") == []


def test_real_routes_reject_invalid_boundary_query_values_without_500(client, auth_headers):
    cases = [
        ("/v1/conversations?limit=0", 422),
        ("/v1/conversations?offset=-1", 422),
        ("/v1/calendar/meetings?limit=101", 422),
        ("/v1/goals/goal-123/history?days=0", 422),
        ("/v1/goals/goal-123/history?days=366", 422),
        ("/v1/scores?date=2024-02-30", 422),
        ("/v1/daily-score?date=2024-02-30", 422),
        ("/v1/focus-sessions?date=2024-02-30", 422),
    ]

    for path, expected_status in cases:
        response = client.get(path, headers=auth_headers)

        assert response.status_code == expected_status, f"{path}: {response.text}"
        assert response.status_code < 500
        assert "detail" in response.json()


def test_retired_listen_image_chunk_closes_without_photo_side_effects_and_transcripts_still_work(
    client, test_uid, monkeypatch
):
    seed_listen_user(test_uid)
    describe_image = AsyncMock()
    store_photos = MagicMock()
    monkeypatch.setattr(listen_receiver, "describe_image", describe_image, raising=False)
    monkeypatch.setattr(conversations_db, "store_conversation_photos", store_photos, raising=False)

    with client.websocket_connect(
        "/v4/web/listen?custom_stt=enabled&sample_rate=8000&codec=pcm8&channels=2&source=phone_call"
    ) as websocket:
        websocket.send_text(json.dumps({"type": "auth", "token": "dev-token"}))
        assert websocket.receive_json() == {"type": "auth_response", "success": True}
        receive_until(websocket, is_ready_event)

        websocket.send_text(json.dumps({"type": "image_chunk", "id": "img-1", "index": 0, "total": 1, "data": "abc"}))
        close_message = websocket.receive()

    assert close_message["type"] == "websocket.close"
    assert close_message["code"] == 1008
    describe_image.assert_not_called()
    store_photos.assert_not_called()

    with client.websocket_connect(
        "/v4/web/listen?custom_stt=enabled&sample_rate=8000&codec=pcm8&source=desktop"
    ) as websocket:
        websocket.send_text(json.dumps({"type": "auth", "token": "dev-token"}))
        assert websocket.receive_json() == {"type": "auth_response", "success": True}
        receive_until(websocket, is_ready_event)
        websocket.send_bytes(b"\x80" * 320)
        websocket.send_text(
            json.dumps(
                {
                    "type": "suggested_transcript",
                    "stt_provider": "s02-contract",
                    "segments": [
                        {
                            "id": "seg-s02-normal",
                            "text": "Normal transcript remains supported.",
                            "start": 0.0,
                            "end": 1.0,
                            "speaker": "SPEAKER_00",
                            "speaker_id": 0,
                            "is_user": True,
                        }
                    ],
                }
            )
        )
        emitted = receive_until(
            websocket,
            lambda payload: isinstance(payload, list) and payload and payload[0].get("id") == "seg-s02-normal",
        )

    assert emitted[0]["text"] == "Normal transcript remains supported."
