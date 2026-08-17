from models.users import PlanLimits, PlanType, Subscription, UserSubscriptionResponse
from utils.billing.config import BillingAvailability


def _response(subscription: Subscription) -> UserSubscriptionResponse:
    return UserSubscriptionResponse(
        subscription=subscription,
        transcription_seconds_used=0,
        transcription_seconds_limit=0,
        words_transcribed_used=0,
        words_transcribed_limit=0,
        insights_gained_used=0,
        insights_gained_limit=0,
        billing_availability=BillingAvailability(
            checkout_enabled=False,
            portal_enabled=False,
            presentation='skip',
        ),
    )


def test_normalized_subscription_wire_contract_contains_no_provider_aliases() -> None:
    response = _response(
        Subscription(
            plan=PlanType.bounded,
            plan_name='Synthetic plan',
            offer_id='synthetic-offer',
            billing_customer_id='customer-synthetic',
            billing_subscription_id='subscription-synthetic',
            billing_product_id='product-synthetic',
            entitlement_policy=PlanType.bounded,
            limits=PlanLimits(chat_questions_per_month=8),
        )
    )
    wire = response.model_dump(mode='json')

    assert wire['subscription']['plan'] == 'bounded'
    assert wire['subscription']['offer_id'] == 'synthetic-offer'
    assert wire['subscription']['entitlement_policy'] == 'bounded'
    assert wire['billing_availability']['presentation'] == 'skip'
    assert not any('stripe' in key for key in wire['subscription'])
    assert 'deprecated' not in wire['subscription']


def test_disabled_billing_capability_is_explicit_and_has_no_catalog() -> None:
    response = _response(Subscription())

    assert response.billing_availability.checkout_enabled is False
    assert response.billing_availability.portal_enabled is False
    assert response.billing_availability.presentation == 'skip'
    assert response.available_plans == []
