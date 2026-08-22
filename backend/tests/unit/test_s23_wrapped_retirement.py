"""S-23 contract: Wrapped and its exclusive OpenRouter binding are absent."""

import main
from utils.llm import model_config


def test_wrapped_routes_and_openrouter_workload_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert not {route_key for route_key in route_keys if route_key[1].startswith('/v1/wrapped/')}
    assert 'wrapped_analysis' not in model_config.get_all_workloads()
    assert all(workload.provider != 'openrouter' for workload in model_config.get_all_workloads().values())
    assert ('POST', '/v2/chat/completions') in route_keys
