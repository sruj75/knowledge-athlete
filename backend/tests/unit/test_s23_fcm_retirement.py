from pathlib import Path

from fastapi.routing import APIRoute

import main
from database import fair_use as fair_use_db


def test_fcm_routes_and_delivery_leases_are_absent_while_fair_use_receipts_remain():
    route_keys = {
        (method, route.path) for route in main.app.routes if isinstance(route, APIRoute) for method in route.methods
    }

    assert ('POST', '/v1/users/fcm-token') not in route_keys
    assert ('POST', '/v1/notification') not in route_keys
    assert ('POST', '/v1/fair-use/reviews/{review_id}/classify') in route_keys
    assert not hasattr(fair_use_db, 'claim_fair_use_review_notification')
    assert not hasattr(fair_use_db, 'release_fair_use_review_notification')
    assert not hasattr(fair_use_db, 'mark_fair_use_review_notification_sent')
    retired_runbook = Path(__file__).resolve().parents[1] / 'integration' / 'README.md'
    assert not retired_runbook.exists()
