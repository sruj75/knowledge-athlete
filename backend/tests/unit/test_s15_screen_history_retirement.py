"""S-15 contract: local Rewind has no backend screen-history copy graph.

The changed expectation comes from bootstrap-scaffold/deletion-map.md and the
S-15 TDD plan. Exercise both real production FastAPI apps so the retired writer
cannot survive as a mounted compatibility handler while retained desktop routes
keep their existing contracts.
"""

from fastapi.testclient import TestClient

import desktop_backend
import main


def test_screen_history_sync_is_absent_from_production_apps() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)
    desktop_client = TestClient(desktop_backend.app, raise_server_exceptions=False)

    payload = {"rows": []}
    assert main_client.post("/v1/screen-activity/sync", json=payload).status_code == 404
    assert desktop_client.post("/v1/screen-activity/sync", json=payload).status_code == 404


def test_neighboring_desktop_routes_keep_their_existing_contracts() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)
    desktop_client = TestClient(desktop_backend.app, raise_server_exceptions=False)

    proxy_path = "/v1/proxy/gemini/models/gemini-2.5-flash:generateContent"
    for client in (main_client, desktop_client):
        assert client.post(proxy_path, json={}).status_code == 401
        assert client.get("/health").status_code == 200
        assert client.post("/v2/chat/completions").status_code == 401
        assert client.post("/v2/realtime/session").status_code == 401
