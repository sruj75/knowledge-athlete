from __future__ import annotations

import pytest
from fastapi import HTTPException

from models.users import PlanLimits, PlanType, Subscription, SubscriptionStatus
from utils import subscription as subscription_module


def _subscription(policy: PlanType, allowance: int) -> Subscription:
    return Subscription(
        plan=policy,
        plan_name=policy.value.capitalize(),
        entitlement_policy=policy if policy is not PlanType.free else PlanType.bounded,
        status=SubscriptionStatus.active,
        limits=PlanLimits(chat_questions_per_month=allowance),
    )


@pytest.mark.parametrize(
    ('subscription', 'used'),
    [
        (None, subscription_module.FREE_CHAT_QUESTIONS_PER_MONTH),
        (_subscription(PlanType.bounded, 8), 8),
        (_subscription(PlanType.unlimited, 20), 20),
    ],
)
def test_every_entitlement_is_hard_capped_at_its_included_allowance(monkeypatch, subscription, used) -> None:
    monkeypatch.setattr(subscription_module, 'is_trial_paywalled', lambda *_args, **_kwargs: False)
    monkeypatch.setattr(
        subscription_module.users_db,
        'get_user_valid_subscription',
        lambda _uid: subscription,
    )
    monkeypatch.setattr(
        subscription_module.user_usage_db,
        'get_monthly_chat_usage',
        lambda _uid: {'questions': used, 'cost_usd': 0.0, 'reset_at': 1_777_593_600},
    )

    with pytest.raises(HTTPException) as error:
        subscription_module.enforce_chat_quota('uid-1', platform='macos')

    assert error.value.status_code == 402
    assert error.value.detail['error'] == 'quota_exceeded'
    assert error.value.detail['used'] == used
    assert error.value.detail['limit'] == used
    assert error.value.detail['reset_at'] == 1_777_593_600


def test_snapshot_preserves_server_unit_usage_reset_and_warning_inputs(monkeypatch) -> None:
    paid = _subscription(PlanType.bounded, 10)
    monkeypatch.setattr(subscription_module, 'is_trial_paywalled', lambda *_args, **_kwargs: False)
    monkeypatch.setattr(subscription_module.users_db, 'get_user_valid_subscription', lambda _uid: paid)
    monkeypatch.setattr(
        subscription_module.user_usage_db,
        'get_monthly_chat_usage',
        lambda _uid: {'questions': 8, 'cost_usd': 1.5, 'reset_at': 1_777_593_600},
    )

    snapshot = subscription_module.get_chat_quota_snapshot('uid-1')

    assert snapshot == {
        'plan': PlanType.bounded,
        'plan_name': 'Bounded',
        'unit': 'questions',
        'used': 8.0,
        'limit': 10.0,
        'allowed': True,
        'reset_at': 1_777_593_600,
    }


def test_billing_mode_does_not_mutate_quota_authority(monkeypatch) -> None:
    paid = _subscription(PlanType.unlimited, 20)
    monkeypatch.setenv('BILLING_MODE', 'disabled')
    monkeypatch.setattr(subscription_module, 'is_trial_paywalled', lambda *_args, **_kwargs: False)
    monkeypatch.setattr(subscription_module.users_db, 'get_user_valid_subscription', lambda _uid: paid)
    monkeypatch.setattr(
        subscription_module.user_usage_db,
        'get_monthly_chat_usage',
        lambda _uid: {'questions': 19, 'cost_usd': 0.0, 'reset_at': 1_777_593_600},
    )

    assert subscription_module.get_chat_quota_snapshot('uid-1')['allowed'] is True
