"""S-01 contract: the rejected cloud Agent VM has no HTTP entrance.

The changed expectation comes from bootstrap-scaffold/deletion-map.md and
IR-001/IR-002 in bootstrap-scaffold/requirements-challenge.md.  Exercise the
real production FastAPI app objects so a leftover router registration cannot
hide behind source deletion or a compatibility handler.
"""

from fastapi.testclient import TestClient

import desktop_backend
import main


_RETIRED_MAIN_ROUTES = (
    ("GET", "/v1/agent/vm-status"),
    ("POST", "/v1/agent/vm-ensure"),
    ("POST", "/v1/agent/keepalive"),
    ("GET", "/v1/agent/tools"),
    ("POST", "/v1/agent/execute-tool"),
    ("POST", "/v2/agent/provision"),
    ("GET", "/v2/agent/status"),
)


def test_cloud_agent_vm_routes_are_absent_from_production_apps() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)
    desktop_client = TestClient(desktop_backend.app, raise_server_exceptions=False)

    for method, path in _RETIRED_MAIN_ROUTES:
        assert main_client.request(method, path).status_code == 404, f"{method} {path} is still mounted on main"

    for method, path in _RETIRED_MAIN_ROUTES[-2:]:
        assert (
            desktop_client.request(method, path).status_code == 404
        ), f"{method} {path} is still mounted on desktop_backend"


def test_neighboring_retained_routes_keep_their_existing_contracts() -> None:
    main_client = TestClient(main.app, raise_server_exceptions=False)
    desktop_client = TestClient(desktop_backend.app, raise_server_exceptions=False)

    assert main_client.post("/v1/memory/compute/extract").status_code == 401
    assert main_client.post("/v1/agents/hume/callback").status_code == 422
    assert desktop_client.get("/health").status_code == 200
    assert desktop_client.post("/v2/chat/completions").status_code == 401
    assert desktop_client.post("/v2/realtime/session").status_code == 401
