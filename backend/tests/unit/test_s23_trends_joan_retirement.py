"""S-23 contract: Trends, Joan, and Daily Summary stay absent."""

import main
from utils.llm import model_config


def test_trends_joan_and_daily_summary_routes_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert ('GET', '/v1/trends') not in route_keys
    assert ('DELETE', '/v1/joan/{memory_id}/followup-question') not in route_keys
    assert not {path for _, path in route_keys if 'daily-summary' in path}
    assert 'followup' not in model_config.get_all_workloads()
    assert {'chat_greeting', 'session_titles'} <= set(model_config.get_all_workloads())
