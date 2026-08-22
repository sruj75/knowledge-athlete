"""S-23 contract: outbound phone calling is absent from the account product."""

import main
from models.users import UserSubscriptionResponse


def test_phone_routes_and_subscription_schema_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert not {route_key for route_key in route_keys if route_key[1].startswith('/v1/phone/')}
    assert 'phone_call_quota' not in UserSubscriptionResponse.model_fields
    assert ('GET', '/v1/users/me/subscription') in route_keys
