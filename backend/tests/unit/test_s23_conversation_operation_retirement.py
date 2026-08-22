"""S-23 contract: hosted conversation operations have no backend product API."""

import main
from scripts import check_no_data_dict_bodies


def test_hosted_conversation_and_calendar_operations_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}
    retired_prefixes = (
        '/v1/calendar/meetings',
        '/v1/agents/hume/callback',
        '/v1/conversations',
        '/v1/folders',
        '/v1/tools/conversations',
    )

    assert not {route_key for route_key in route_keys if route_key[1].startswith(retired_prefixes)}
    assert ('POST', '/v1/conversation-compute/structure') in route_keys
    assert ('POST', '/v1/conversation-compute/action-items') in route_keys
    assert check_no_data_dict_bodies.LEGIT_FREE_FORM == {}
