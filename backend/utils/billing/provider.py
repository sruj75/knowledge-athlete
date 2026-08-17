from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol

from utils.billing.config import BillingConfig, BillingMode


@dataclass(frozen=True)
class CheckoutSession:
    session_id: str
    url: str


class BillingProvider(Protocol):
    async def create_checkout(
        self, *, product_id: str, uid: str, offer_id: str, return_url: str, cancel_url: str
    ) -> CheckoutSession: ...

    async def create_portal(self, *, customer_id: str, return_url: str) -> str: ...

    async def cancel_subscription(self, subscription_id: str) -> bool: ...

    async def retrieve_subscription(self, subscription_id: str) -> Any: ...

    def unwrap_webhook(self, raw_body: str, headers: Mapping[str, str]) -> Any: ...

    async def close(self) -> None: ...


class DodoBillingProvider:
    """Narrow async adapter around the Dodo SDK.

    Import and client construction are intentionally delayed until an active
    operation crosses the service guard.
    """

    def __init__(self, config: BillingConfig):
        if not config.active or not config.api_key or not config.webhook_key:
            raise ValueError('Dodo provider requires complete active billing configuration')

        from dodopayments import AsyncDodoPayments

        environment = 'test_mode' if config.mode is BillingMode.dodo_test else 'live_mode'
        self._client = AsyncDodoPayments(
            bearer_token=config.api_key,
            webhook_key=config.webhook_key,
            environment=environment,
        )

    async def create_checkout(
        self, *, product_id: str, uid: str, offer_id: str, return_url: str, cancel_url: str
    ) -> CheckoutSession:
        response = await self._client.checkout_sessions.create(
            product_cart=[{'product_id': product_id, 'quantity': 1}],
            metadata={'uid': uid, 'offer_id': offer_id},
            return_url=return_url,
            cancel_url=cancel_url,
        )
        if not response.checkout_url:
            raise RuntimeError('billing provider returned no checkout URL')
        return CheckoutSession(session_id=response.session_id, url=response.checkout_url)

    async def create_portal(self, *, customer_id: str, return_url: str) -> str:
        response = await self._client.customers.customer_portal.create(customer_id, return_url=return_url)
        return response.link

    async def cancel_subscription(self, subscription_id: str) -> bool:
        response = await self._client.subscriptions.update(
            subscription_id,
            status='cancelled',
            cancel_reason='cancelled_by_customer',
        )
        return getattr(response, 'status', None) == 'cancelled'

    async def retrieve_subscription(self, subscription_id: str) -> Any:
        subscription = await self._client.subscriptions.retrieve(subscription_id)
        subscription_data = self._mapping(subscription)
        metadata = dict(self._mapping(subscription_data.get('metadata') or {}))
        if metadata.get('uid'):
            return subscription

        # Checkout-session metadata is attached to the first payment, not the
        # subscription. Resolve that authenticated checkout association before
        # the first webhook has established the durable customer -> UID map.
        payment_id = subscription_data.get('payment_id')
        if not isinstance(payment_id, str) or not payment_id:
            return subscription
        payment = await self._client.payments.retrieve(payment_id)
        payment_data = self._mapping(payment)
        payment_metadata = self._mapping(payment_data.get('metadata') or {})
        uid = payment_metadata.get('uid')
        if not isinstance(uid, str) or not uid:
            return subscription

        normalized = dict(subscription_data)
        normalized['metadata'] = {**metadata, 'uid': uid}
        return normalized

    def unwrap_webhook(self, raw_body: str, headers: Mapping[str, str]) -> Any:
        return self._client.webhooks.unwrap(raw_body, headers=headers)

    async def close(self) -> None:
        await self._client.close()

    @staticmethod
    def _mapping(value: Any) -> Mapping[str, Any]:
        if isinstance(value, Mapping):
            return value
        dump = getattr(value, 'model_dump', None)
        if callable(dump):
            result = dump(mode='json')
            if isinstance(result, Mapping):
                return result
        raise TypeError('Dodo billing value must be a mapping')
