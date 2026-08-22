"""S-23 contract: reusable hosted voice identity is not a product surface."""

import main


def test_speech_profile_routes_are_absent_while_transient_listen_remains() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert not {
        route_key
        for route_key in route_keys
        if route_key[1].startswith(('/v3/speech-profile', '/v4/speech-profile', '/v3/upload-audio'))
    }
    assert any(route.path == '/v4/listen' for route in main.app.routes)
