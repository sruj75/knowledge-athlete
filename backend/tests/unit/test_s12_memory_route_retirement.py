"""S-12 contract: Memory product authority is absent from the backend app."""

from fastapi.testclient import TestClient

import main


def test_hosted_memory_product_routes_return_404_for_every_retired_surface() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)
    retired_routes = (
        ('GET', '/v3/memories'),
        ('POST', '/v3/memories'),
        ('PATCH', '/v3/memories/local-id'),
        ('DELETE', '/v3/memories/local-id'),
        ('GET', '/v1/tools/memories'),
        ('POST', '/v1/tools/memories/search'),
        ('POST', '/memory/search'),
        ('POST', '/memory/vector'),
        ('POST', '/memory/admin/rebuild'),
    )

    for method, path in retired_routes:
        assert client.request(method, path).status_code == 404, f'{method} {path} is still mounted'


def test_production_app_exposes_exactly_three_memory_routes() -> None:
    memory_routes = {
        (method, route.path)
        for route in main.app.routes
        if route.path.startswith('/v1/memory/') or route.path.startswith('/memory/')
        for method in getattr(route, 'methods', set())
    }

    assert memory_routes == {
        ('POST', '/v1/memory/compute/extract'),
        ('POST', '/v1/memory/compute/normalize'),
        ('POST', '/v1/memory/compute/consolidate'),
    }


def test_transient_memory_compute_routes_require_authentication() -> None:
    client = TestClient(main.app, raise_server_exceptions=False)

    for path in (
        '/v1/memory/compute/extract',
        '/v1/memory/compute/normalize',
        '/v1/memory/compute/consolidate',
    ):
        assert client.post(path).status_code == 401
