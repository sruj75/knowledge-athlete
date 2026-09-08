from __future__ import annotations

import pytest

from scripts.route_policy_inventory import generate_backend_route_inventory

PARTICIPANT_HTTP_PATHS = {
    "/v2/models/{model}:streamGenerateContent",
    "/v2/chat/initial-message",
    "/v2/chat/generate-title",
    "/v2/voice-messages",
    "/v2/voice-message/transcribe",
    "/v1/proxy/gemini/{path:path}",
    "/v2/realtime/session",
    "/v1/tts/synthesize",
    "/v1/memory/compute/extract",
    "/v1/memory/compute/normalize",
    "/v1/memory/compute/consolidate",
    "/v1/conversation-compute/discard",
    "/v1/conversation-compute/structure",
    "/v1/conversation-compute/action-items",
    "/v1/fair-use/reviews/{review_id}/classify",
}

PARTICIPANT_WEBSOCKET_PATHS = {
    "/v2/voice-message/transcribe-stream",
    "/v4/listen",
}

LEGACY_ACCOUNT_PATHS = {
    ("DELETE", "/v1/users/delete-account"),
    ("GET", "/v1/users/export"),
    ("GET", "/v1/users/language"),
    ("GET", "/v1/users/me/llm-usage/total"),
    ("GET", "/v1/users/me/paywall"),
    ("GET", "/v1/users/me/subscription"),
    ("GET", "/v1/users/me/trial"),
    ("GET", "/v1/users/me/usage-quota"),
    ("GET", "/v1/users/profile"),
    ("PATCH", "/v1/users/language"),
    ("POST", "/v1/payments/checkout-session"),
    ("POST", "/v1/payments/customer-portal"),
    ("POST", "/v2/realtime/usage"),
}


def _dependency_suffixes(route: dict) -> set[str]:
    return {name.rsplit(".", 1)[-1] for name in route["dependencies"]}


@pytest.fixture(scope="module")
def backend_routes() -> dict[tuple[str, str, str], dict]:
    inventory = generate_backend_route_inventory()
    return {(route["route_type"], route["method"], route["path"]): route for route in inventory["routes"]}


def test_real_backend_dependency_graph_gates_only_the_hosted_compute_surface(
    backend_routes: dict[tuple[str, str, str], dict],
):
    routes = backend_routes

    for path in PARTICIPANT_HTTP_PATHS:
        route = routes[("http", "POST", path)]
        assert "get_current_participant_uid" in _dependency_suffixes(route), path

    for path in PARTICIPANT_WEBSOCKET_PATHS:
        route = routes[("websocket", "WEBSOCKET", path)]
        assert "get_current_participant_uid_ws_listen" in _dependency_suffixes(route), path

    for method, path in LEGACY_ACCOUNT_PATHS:
        route = routes[("http", method, path)]
        dependencies = _dependency_suffixes(route)
        assert "get_current_user_uid" in dependencies, path
        assert "get_current_participant_uid" not in dependencies, path
