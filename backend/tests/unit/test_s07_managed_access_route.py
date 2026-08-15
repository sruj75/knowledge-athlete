"""S-07 contract: customer BYOK has no backend account entrance.

The changed expectation is authorized by IR-058 and IR-062 in
bootstrap-scaffold/requirements-challenge.md and the S-07 deletion map. The
test exercises the assembled production app so the retired enrollment API
cannot survive as a compatibility handler while managed account access stays
mounted.
"""

import main


def test_customer_byok_enrollment_routes_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}

    assert ("POST", "/v1/users/me/byok-active") not in route_keys
    assert ("DELETE", "/v1/users/me/byok-active") not in route_keys


def test_managed_subscription_route_remains_registered() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, "methods", set())}

    assert ("GET", "/v1/users/me/subscription") in route_keys
