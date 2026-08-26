"""S-15 contract: local Rewind has no backend screen-history copy graph.

The changed expectation comes from bootstrap-scaffold/deletion-map.md and the
S-15 TDD plan. Exercise the real production FastAPI app so the retired writer
cannot survive as a mounted compatibility handler while retained desktop routes
keep their existing contracts.
"""

from fastapi.testclient import TestClient

import main


def test_screen_history_sync_is_absent_from_the_production_app() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)

    payload = {"rows": []}
    assert main_client.post("/v1/screen-activity/sync", json=payload).status_code == 404


def test_neighboring_desktop_routes_keep_their_existing_contracts() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)

    proxy_path = "/v1/proxy/gemini/models/gemini-2.5-flash:generateContent"
    assert main_client.post(proxy_path, json={}).status_code == 401
    assert main_client.get("/v1/health").status_code == 200
    assert main_client.post("/v2/chat/completions").status_code == 401
    assert main_client.post("/v2/realtime/session").status_code == 401
