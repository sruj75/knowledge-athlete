"""S-23 contract: hosted Chat report/share products are not backend authority."""

import main


def test_hosted_message_report_and_sharing_routes_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert ('POST', '/v1/messages/{message_id}/report') not in route_keys
    assert ('POST', '/v2/messages/{message_id}/report') not in route_keys
    assert not {path for _, path in route_keys if '/share' in path or '/persona' in path}
    assert ('POST', '/v2/chat/completions') in route_keys
