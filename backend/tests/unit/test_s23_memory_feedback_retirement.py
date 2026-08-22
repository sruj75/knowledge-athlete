"""S-23 contract: cloud Memory/conversation feedback is not a product API."""

import main


def test_summary_rating_routes_are_absent_while_memory_compute_remains() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert ('GET', '/v1/users/analytics/memory_summary') not in route_keys
    assert ('POST', '/v1/users/analytics/memory_summary') not in route_keys
    assert ('POST', '/v1/memory/compute/extract') in route_keys
    assert ('POST', '/v1/memory/compute/normalize') in route_keys
    assert ('POST', '/v1/memory/compute/consolidate') in route_keys
