from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from models.users import PlanLimits, PlanType, Subscription, SubscriptionStatus
from utils.billing.catalog import BillingCatalog, EntitlementPolicy
from utils.billing.values import as_mapping, format_recurring_price


class UnknownBillingProductError(ValueError):
    pass


def _unix_seconds(value: Any) -> int | None:
    if value is None:
        return None
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str):
        parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
    else:
        raise TypeError('billing period timestamps must be ISO-8601 values')
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return int(parsed.timestamp())


_STATUS_MAP = {
    'active': SubscriptionStatus.active,
    'on_hold': SubscriptionStatus.on_hold,
    'cancelled': SubscriptionStatus.cancelled,
    'failed': SubscriptionStatus.failed,
    'expired': SubscriptionStatus.expired,
}


def project_subscription(
    provider_subscription: Any,
    *,
    catalog: BillingCatalog,
    provider_updated_at: int,
) -> Subscription:
    raw = as_mapping(provider_subscription, label='billing provider object')
    product_id = raw.get('product_id')
    if not isinstance(product_id, str):
        raise UnknownBillingProductError('provider subscription has no product identity')
    resolved = catalog.product(product_id)
    if resolved is None:
        raise UnknownBillingProductError('provider product is not mapped by the server catalog')

    customer = as_mapping(raw.get('customer') or {}, label='billing customer')
    customer_id = customer.get('customer_id') or customer.get('id')
    subscription_id = raw.get('subscription_id') or raw.get('id')
    if not isinstance(customer_id, str) or not isinstance(subscription_id, str):
        raise ValueError('provider subscription is missing customer or subscription identity')

    policy = resolved.plan.entitlement_policy
    plan = PlanType.unlimited if policy is EntitlementPolicy.unlimited else PlanType.bounded
    status = _STATUS_MAP.get(str(raw.get('status')), SubscriptionStatus.inactive)
    return Subscription(
        plan=plan,
        plan_name=resolved.plan.title,
        offer_id=resolved.offer.id,
        billing_customer_id=customer_id,
        billing_subscription_id=subscription_id,
        billing_product_id=product_id,
        entitlement_policy=plan,
        status=status,
        current_period_start=_unix_seconds(raw.get('previous_billing_date')),
        current_period_end=_unix_seconds(raw.get('next_billing_date')),
        cancel_at_next_billing_date=bool(raw.get('cancel_at_next_billing_date')),
        billing_interval=resolved.offer.interval,
        price_string=format_recurring_price(
            raw.get('recurring_pre_tax_amount'),
            raw.get('currency'),
            raw.get('payment_frequency_interval'),
        ),
        provider_updated_at=provider_updated_at,
        features=list(resolved.plan.features),
        limits=PlanLimits(**resolved.plan.limits.model_dump()),
    )
