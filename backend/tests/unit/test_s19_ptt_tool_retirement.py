"""S-19 contract: PTT conversation retrieval is local to the macOS owner."""

from fastapi.testclient import TestClient

import main


def test_hosted_ptt_conversation_tool_routes_are_absent() -> None:
    client = TestClient(main.app)

    responses = (
        client.get('/v1/tools/conversations'),
        client.post('/v1/tools/conversations/search', json={'query': 'planning'}),
        client.post('/v1/tools/conversations/search-chunks', json={'query': 'planning'}),
    )

    assert [response.status_code for response in responses] == [404, 404, 404]


def test_shared_conversation_compute_and_listen_surfaces_remain() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}
    websocket_paths = {route.path for route in main.app.routes if getattr(route, 'path', None)}

    assert ('POST', '/v1/conversation-compute/structure') in route_keys
    assert ('POST', '/v1/conversation-compute/action-items') in route_keys
    assert '/v4/listen' in websocket_paths
