"""S-02 contract: direct wearable HTTP surfaces are retired.

The changed expectation is authorized by IR-012/IR-013/IR-014/IR-359/IR-823
in bootstrap-scaffold/requirements-challenge.md and the S-02 deletion map.
Exercise the real production FastAPI app so deleted handlers cannot survive as
mounted compatibility shells.
"""

from pathlib import Path

from fastapi.testclient import TestClient

import main
from utils.llm.model_config import get_all_configured_features
from utils.llm.usage_tracker import Features


_RETIRED_ROUTES = (
    ("POST", "/v1/sync-local-files"),
    ("POST", "/v2/sync-local-files"),
    ("GET", "/v2/sync-local-files/retired-job"),
    ("POST", "/v2/sync-capture-manifest"),
    ("POST", "/v2/sync-jobs/run"),
    ("GET", "/v2/firmware/latest"),
    ("GET", "/v2/firmware/stable"),
    ("GET", "/v2/firmware/version"),
    ("GET", "/v1/conversations/retired-conversation/photos"),
)


def test_wearable_sync_and_firmware_routes_are_absent() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    for method, path in _RETIRED_ROUTES:
        assert client.request(method, path).status_code == 404, f"{method} {path} is still mounted"


def test_worker_owned_audio_is_absent_and_desktop_updates_remain_mounted() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}

    assert not any(path.startswith("/v1/sync/audio") for _, path in route_keys)
    assert ("POST", "/v2/audio-merge-jobs/run") not in route_keys
    assert ("GET", "/v2/desktop/appcast.xml") in route_keys


def test_wearable_vision_llm_surfaces_are_absent() -> None:
    assert {"openglass", "smart_glasses"}.isdisjoint(get_all_configured_features())
    assert not hasattr(Features, "OPENGLASS")
    assert not (Path(__file__).resolve().parents[2] / "utils" / "llm" / "openglass.py").exists()
