from fastapi.routing import APIRoute

import main


def test_rejected_feedback_score_and_detailed_usage_routes_are_absent():
    route_keys = {
        (method, route.path) for route in main.app.routes if isinstance(route, APIRoute) for method in route.methods
    }
    rejected = {
        ('GET', '/v1/users/analytics/memory_summary'),
        ('POST', '/v1/users/analytics/memory_summary'),
        ('GET', '/v1/daily-score'),
        ('GET', '/v1/users/me/usage'),
        ('GET', '/v1/users/me/llm-usage'),
        ('POST', '/v1/users/me/llm-usage'),
        ('GET', '/v1/users/me/llm-usage/top-features'),
    }

    assert route_keys.isdisjoint(rejected)
    assert ('GET', '/v1/users/me/subscription') in route_keys
    assert ('GET', '/v1/users/me/usage-quota') in route_keys
    assert ('GET', '/v1/users/me/llm-usage/total') in route_keys
