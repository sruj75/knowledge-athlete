"""Behavioral coverage for the retained desktop trial contract.

The billing migration normalizes plan identity to free/bounded/unlimited. Trial
timing remains account-age based and applies only to the free entitlement.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock

import utils.subscription as subscription
from models.users import PlanType, Subscription


def _user_created_at(seconds: int) -> SimpleNamespace:
    return SimpleNamespace(user_metadata=SimpleNamespace(creation_timestamp=seconds * 1000))


def _paid(plan: PlanType) -> Subscription:
    return Subscription(plan=plan, plan_name=plan.value.capitalize())


def test_trial_length_remains_three_days() -> None:
    assert subscription.TRIAL_LENGTH_SECONDS == 3 * 24 * 60 * 60


def test_free_trial_reports_remaining_and_expired_time(monkeypatch) -> None:
    now = 2_000_000_000
    monkeypatch.setattr(subscription, 'TRIAL_PAYWALL_ENABLED', True)
    monkeypatch.setattr(subscription.users_db, 'get_user_valid_subscription', MagicMock(return_value=None))
    monkeypatch.setattr(subscription.time, 'time', lambda: now)

    monkeypatch.setattr(subscription, '_get_user', lambda _uid: _user_created_at(now - 60))
    active = subscription.get_trial_metadata('uid')
    assert active.trial_expired is False
    assert active.trial_remaining_seconds == subscription.TRIAL_LENGTH_SECONDS - 60
    assert active.trial_ends_at == active.trial_started_at + subscription.TRIAL_LENGTH_SECONDS

    monkeypatch.setattr(
        subscription,
        '_get_user',
        lambda _uid: _user_created_at(now - subscription.TRIAL_LENGTH_SECONDS - 1),
    )
    expired = subscription.get_trial_metadata('uid')
    assert expired.trial_expired is True
    assert expired.trial_remaining_seconds == 0


def test_paid_entitlements_are_not_trial_paywalled(monkeypatch) -> None:
    monkeypatch.setattr(subscription, 'TRIAL_PAYWALL_ENABLED', True)
    get_user = MagicMock()
    monkeypatch.setattr(subscription, '_get_user', get_user)

    for plan in (PlanType.bounded, PlanType.unlimited):
        monkeypatch.setattr(
            subscription.users_db,
            'get_user_valid_subscription',
            MagicMock(return_value=_paid(plan)),
        )
        metadata = subscription.get_trial_metadata('uid')
        assert metadata.trial_expired is False
        assert metadata.trial_remaining_seconds == 0

    get_user.assert_not_called()


def test_disabled_trial_policy_and_lookup_failures_fail_open(monkeypatch) -> None:
    monkeypatch.setattr(subscription, 'TRIAL_PAYWALL_ENABLED', False)
    get_subscription = MagicMock(side_effect=RuntimeError('synthetic lookup failure'))
    monkeypatch.setattr(subscription.users_db, 'get_user_valid_subscription', get_subscription)
    assert subscription.get_trial_metadata('uid').trial_expired is False
    get_subscription.assert_not_called()

    monkeypatch.setattr(subscription, 'TRIAL_PAYWALL_ENABLED', True)
    assert subscription.get_trial_metadata('uid').trial_expired is False


def test_normalized_desktop_access_policy() -> None:
    assert subscription.desktop_trial_paywall_eligible(PlanType.free) is True
    assert subscription.plan_grants_desktop(PlanType.free) is False
    assert subscription.plan_grants_desktop(PlanType.bounded) is True
    assert subscription.plan_grants_desktop(PlanType.unlimited) is True
