"""S-23 contract: cloud announcements are gone; app-review version policy remains."""

import main
from database.app_review_config import compare_versions


def test_announcement_routes_are_absent_and_version_matching_remains() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert not {route_key for route_key in route_keys if route_key[1].startswith('/v1/announcements')}
    assert compare_versions('1.0.521', '1.0.521+607') == 0
    assert compare_versions('1.0.521+607', '1.0.521+608') == -1
    assert compare_versions('1.0.522', '1.0.521+608') == 1
