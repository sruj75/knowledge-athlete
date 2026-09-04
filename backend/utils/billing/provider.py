from __future__ import annotations

from typing import Any, Mapping

from dodopayments import DodoPayments

from utils.billing.config import BillingConfig, BillingMode
from utils.billing.contracts import BillingProvider, CheckoutSession
from utils.billing.values import as_mapping, format_recurring_price
from utils.executors import billing_executor, run_blocking


class DodoBillingProvider(BillingProvider):
    """Narrow async adapter around the Dodo SDK.

    Loading the SDK module and constructing its client are both delayed until
    an active operation crosses the service guard.
    """

    def __init__(self, config: BillingConfig):
        if not config.active or not config.api_key or not config.webhook_key:
            raise ValueError('Dodo provider requires complete active billing configuration')

        environment = 'test_mode' if config.mode is BillingMode.dodo_test else 'live_mode'
        self._client = DodoPayments(
            bearer_token=config.api_key,
            webhook_key=config.webhook_key,
            environment=environment,
        )

    async def create_checkout(
        self, *, product_id: str, uid: str, offer_id: str, return_url: str, cancel_url: str
    ) -> CheckoutSession:
        response = await run_blocking(
            billing_executor,
            self._client.checkout_sessions.create,
            product_cart=[{'product_id': product_id, 'quantity': 1}],
            metadata={'uid': uid, 'offer_id': offer_id},
            return_url=return_url,
            cancel_url=cancel_url,
        )
        if not response.checkout_url:
            raise RuntimeError('billing provider returned no checkout URL')
        return CheckoutSession(session_id=response.session_id, url=response.checkout_url)

    async def create_portal(self, *, customer_id: str, return_url: str) -> str:
        response = await run_blocking(
            billing_executor,
            self._client.customers.customer_portal.create,
            customer_id,
            return_url=return_url,
        )
        return response.link

    async def cancel_subscription(self, subscription_id: str) -> bool:
        response = await run_blocking(
            billing_executor,
            self._client.subscriptions.update,
            subscription_id,
            status='cancelled',
            cancel_reason='cancelled_by_customer',
        )
        return getattr(response, 'status', None) == 'cancelled'

    async def retrieve_subscription(self, subscription_id: str) -> Any:
        return await run_blocking(billing_executor, self._client.subscriptions.retrieve, subscription_id)

    async def retrieve_payment(self, payment_id: str) -> Any:
        return await run_blocking(billing_executor, self._client.payments.retrieve, payment_id)

    async def retrieve_product_price(self, product_id: str, expected_interval: str) -> str:
        product = as_mapping(
            await run_blocking(billing_executor, self._client.products.retrieve, product_id),
            label='billing product',
        )
        if product.get('product_id') != product_id:
            raise ValueError('billing provider returned the wrong product')
        price = as_mapping(product.get('price'), label='billing product price')
        if price.get('type') != 'recurring_price':
            raise ValueError('billing product must have a recurring price')
        interval = str(price.get('payment_frequency_interval')).lower()
        if interval != expected_interval:
            raise ValueError('billing product interval does not match the server offer')
        return format_recurring_price(price.get('price'), price.get('currency'), interval)

    def unwrap_webhook(self, raw_body: str, headers: Mapping[str, str]) -> Any:
        return self._client.webhooks.unwrap(raw_body, headers=headers)

    async def close(self) -> None:
        await run_blocking(billing_executor, self._client.close)
