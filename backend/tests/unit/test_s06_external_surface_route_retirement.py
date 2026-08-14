"""S-06 contract: rejected external product surfaces have no HTTP entrance.

The changed expectation comes from bootstrap-scaffold/deletion-map.md and the
S-06 TDD plan. Exercise the real production FastAPI app so deleted products
cannot survive as mounted compatibility handlers while retained product routes
remain registered.
"""

import main


_RETIRED_ROUTES = (
    ("GET", "/v1/apps"),
    ("GET", "/v2/apps"),
    ("GET", "/v1/integrations/gmail"),
    ("GET", "/v1/task-integrations"),
    ("GET", "/v1/x/connection-status"),
    ("GET", "/v1/calendar/google/events"),
    ("GET", "/v1/mcp/memories"),
    ("GET", "/.well-known/oauth-authorization-server"),
    ("POST", "/v1/mcp/sse"),
    ("GET", "/v1/knowledge-graph"),
    ("POST", "/v1/tools/calendar-events"),
    ("POST", "/v1/conversations/shared/chat"),
    ("PATCH", "/v1/users/daily-summaries/{summary_id}/visibility"),
    ("GET", "/v1/daily-summaries/{summary_id}/shared"),
    ("POST", "/v1/action-items/share"),
    ("POST", "/v1/import/limitless"),
    ("GET", "/v1/action-items/pending-sync"),
    ("PATCH", "/v1/action-items/sync-batch"),
    ("POST", "/v1/candidates/integrations/drain"),
)


def test_external_product_routes_are_absent_from_production_app() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}

    for method, path in _RETIRED_ROUTES:
        assert (method, path) not in route_keys, f"{method} {path} is still mounted"


def test_neighboring_retained_product_routes_remain_registered() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}

    for route_key in (
        ("GET", "/v1/tools/memories"),
        ("GET", "/v1/action-items"),
        ("GET", "/v3/memories"),
        ("GET", "/v1/users/me/subscription"),
        ("GET", "/v1/auth/authorize"),
    ):
        assert route_key in route_keys, f"retained route {route_key} was unmounted"
