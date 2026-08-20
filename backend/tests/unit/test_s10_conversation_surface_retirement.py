"""S-10 contract: the Mac conversation projection has no public backend authority."""

import main


def _route_keys() -> set[tuple[str, str]]:
    return {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}


def test_retired_conversation_projection_routes_are_absent() -> None:
    route_keys = _route_keys()
    retired_prefixes = (
        "/v1/conversations",
        "/v1/folders",
        "/v1/sync/audio",
        "/v1/users/people",
        "/v1/users/store-recording-permission",
        "/v1/users/private-cloud-sync",
        "/v1/users/training-data-opt-in",
        "/v1/users/transcription-preferences",
        "/v1/users/geolocation",
        "/v1/users/location-context-consent",
        "/v1/users/migration",
    )

    surviving = sorted((method, path) for method, path in route_keys if path.startswith(retired_prefixes))
    assert surviving == []


def test_transient_compute_listen_ptt_and_worker_routes_remain() -> None:
    route_keys = _route_keys()

    for route_key in (
        ("POST", "/v1/conversation-compute/discard"),
        ("POST", "/v1/conversation-compute/structure"),
        ("POST", "/v1/conversation-compute/action-items"),
        ("GET", "/v1/tools/conversations"),
        ("POST", "/v1/tools/conversations/search"),
        ("POST", "/v1/tools/conversations/search-chunks"),
        ("POST", "/v1/memory/compute/extract"),
        ("POST", "/v1/memory/compute/normalize"),
        ("POST", "/v1/memory/compute/consolidate"),
        ("POST", "/v2/audio-merge-jobs/run"),
        ("GET", "/v1/users/language"),
        ("PATCH", "/v1/users/language"),
    ):
        assert route_key in route_keys, f"retained route {route_key} was unmounted"

    websocket_paths = {route.path for route in main.app.routes if getattr(route, "path", None)}
    assert "/v4/listen" in websocket_paths
