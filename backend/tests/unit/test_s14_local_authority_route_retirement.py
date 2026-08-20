"""S-14 contract: private desktop product state has no hosted authority."""

from fastapi.testclient import TestClient

import main


def _registered_methods(path: str) -> set[str]:
    return {method for route in main.app.routes if route.path == path for method in getattr(route, 'methods', set())}


def test_private_desktop_product_routes_are_not_registered() -> None:
    retired_routes = {
        '/v1/focus-sessions',
        '/v1/focus-sessions/{session_id}',
        '/v1/focus-stats',
        '/v1/users/ai-profile',
        '/v1/users/assistant-settings',
        '/v1/users/notification-settings',
        '/v1/users/mentor-notification-settings',
        '/v1/users/daily-summary-settings',
        '/v1/users/daily-summary-settings/test',
        '/v1/users/daily-summaries',
        '/v1/users/daily-summaries/{summary_id}',
        '/v1/users/daily-summaries/{summary_id}/regenerate',
    }

    registered = {route.path for route in main.app.routes}
    assert retired_routes.isdisjoint(registered)


def test_retired_private_desktop_routes_return_not_found() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)
    for method, path in (
        ('GET', '/v1/focus-sessions'),
        ('POST', '/v1/focus-sessions'),
        ('GET', '/v1/focus-stats'),
        ('GET', '/v1/users/ai-profile'),
        ('PATCH', '/v1/users/assistant-settings'),
        ('GET', '/v1/users/notification-settings'),
        ('PATCH', '/v1/users/mentor-notification-settings'),
        ('GET', '/v1/users/daily-summary-settings'),
        ('POST', '/v1/users/daily-summary-settings/test'),
        ('GET', '/v1/users/daily-summaries'),
        ('GET', '/v1/users/daily-summaries/example'),
        ('DELETE', '/v1/users/daily-summaries/example'),
        ('POST', '/v1/users/daily-summaries/example/regenerate'),
    ):
        assert client.request(method, path).status_code == 404, f'{method} {path} is still mounted'


def test_neighboring_user_and_update_policy_routes_remain_registered() -> None:
    assert _registered_methods('/v1/users/profile') == {'GET'}
    assert _registered_methods('/v2/desktop/update-policy') == {'GET'}
