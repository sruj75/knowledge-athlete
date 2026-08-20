"""S-14 contract: billing and quota truth do not trigger generated push copy."""

from pathlib import Path

import utils.notifications as notifications

ROOT = Path(__file__).resolve().parents[2]


def test_personalized_purchase_and_credit_push_helpers_are_absent() -> None:
    assert not hasattr(notifications, 'send_subscription_paid_personalized_notification')
    assert not hasattr(notifications, 'send_credit_limit_notification')


def test_credit_push_dedupe_storage_is_absent() -> None:
    source = (ROOT / 'database/redis_db.py').read_text(encoding='utf-8')
    assert 'credit_limit_notification_sent' not in source


def test_static_silent_user_nudge_remains_without_an_llm_dependency() -> None:
    assert hasattr(notifications, 'send_silent_user_notification')
    source = (ROOT / 'utils/notifications.py').read_text(encoding='utf-8')
    assert 'utils.llm.notifications' not in source
    assert 'get_llm(' not in source
