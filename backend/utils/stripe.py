import os
from typing import Any, Dict, Optional
from urllib.parse import urljoin

import stripe

import logging

logger = logging.getLogger(__name__)

stripe.api_key = os.getenv('STRIPE_API_KEY')
endpoint_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
base_url = os.getenv('BASE_API_URL')
if base_url and not base_url.startswith(('http://', 'https://')):
    base_url = 'https://' + base_url


def create_subscription_checkout_session(
    uid: str,
    price_id: str,
    idempotency_key: Optional[str] = None,
    customer_id: Optional[str] = None,
    promotion_code_id: Optional[str] = None,
):
    """Create a Stripe Checkout session for a subscription."""
    try:
        success_url = urljoin(base_url, 'v1/payments/success?session_id={CHECKOUT_SESSION_ID}')  # type: ignore[reportArgumentType]  # base_url validated at runtime
        cancel_url = urljoin(base_url, 'v1/payments/cancel')  # type: ignore[reportArgumentType]  # base_url validated at runtime

        # session creation parameters
        session_params: Dict[str, Any] = {
            'client_reference_id': uid,
            'payment_method_types': ['card'],
            'line_items': [
                {
                    'price': price_id,
                    'quantity': 1,
                },
            ],
            'mode': 'subscription',
            'success_url': success_url,
            'cancel_url': cancel_url,
            'metadata': {
                'uid': uid,
                'sub_type': 'unlimited',
            },
            'subscription_data': {
                'metadata': {
                    'uid': uid,
                    'sub_type': 'unlimited',
                }
            },
        }

        if promotion_code_id:
            session_params['discounts'] = [{'promotion_code': promotion_code_id}]
        else:
            session_params['allow_promotion_codes'] = True

        if customer_id:
            session_params['customer'] = customer_id
            session_params['customer_update'] = {'name': 'auto', 'address': 'auto'}

        if idempotency_key:
            session_params['idempotency_key'] = idempotency_key

        checkout_session = stripe.checkout.Session.create(**session_params)
        return checkout_session
    except stripe.error.InvalidRequestError:  # type: ignore[reportAttributeAccessIssue,reportUnknownMemberType]  # stripe.error exposed dynamically at runtime
        raise
    except Exception as e:
        logger.error(f"Error creating checkout session: {e}")
        return None


def cancel_subscription(subscription_id: str):
    """Cancel a Stripe subscription at the end of the current period."""
    try:
        return stripe.Subscription.modify(
            subscription_id,
            cancel_at_period_end=True,
        )
    except Exception as e:
        logger.error(f"Error canceling subscription: {e}")
        return None


def parse_event(payload: Any, sig_header: Any) -> Any:
    """Parse the Stripe event."""
    return stripe.Webhook.construct_event(payload, sig_header, endpoint_secret)  # type: ignore[reportUnknownMemberType]  # stripe Webhook.construct_event partially typed
