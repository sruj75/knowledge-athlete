from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any, Mapping
from urllib.parse import urljoin

from utils.billing.config import BillingConfig
from utils.billing.config import load_billing_config
from utils.billing.contracts import BillingProvider, CheckoutSession
from utils.billing.factory import create_dodo_billing_provider
from utils.billing.projection import project_subscription
from utils.billing.store import BillingProjectionStore, FirestoreBillingProjectionStore
from utils.billing.values import as_mapping
from utils.fair_use import clear_fair_use_on_upgrade
from utils.executors import db_executor, run_blocking
from utils.subscription import clear_trial_paywall_cache
from database.redis_db import set_credits_invalidation_signal


class BillingDisabledError(RuntimeError):
    code = 'billing_disabled'


class BillingOfferError(ValueError):
    code = 'invalid_billing_offer'


ProviderFactory = Callable[[BillingConfig], BillingProvider]
ProjectionInvalidator = Callable[[str], None]


def _invalidate_projection_caches(uid: str) -> None:
    clear_trial_paywall_cache(uid)
    set_credits_invalidation_signal(uid)
    clear_fair_use_on_upgrade(uid)


class BillingWebhookVerificationError(ValueError):
    code = 'invalid_webhook_signature'


_SUBSCRIPTION_EVENTS = {
    'subscription.active',
    'subscription.updated',
    'subscription.on_hold',
    'subscription.renewed',
    'subscription.plan_changed',
    'subscription.cancelled',
    'subscription.failed',
    'subscription.expired',
}
_ASSOCIATION_EVENTS = {'payment.succeeded'}


class BillingService:
    def __init__(
        self,
        config: BillingConfig,
        provider_factory: ProviderFactory = create_dodo_billing_provider,
        projection_store: BillingProjectionStore | None = None,
        projection_invalidator: ProjectionInvalidator = _invalidate_projection_caches,
    ):
        self.config = config
        self._provider_factory = provider_factory
        self._provider: BillingProvider | None = None
        self._projection_store = projection_store or FirestoreBillingProjectionStore()
        self._projection_invalidator = projection_invalidator

    def _active_provider(self) -> BillingProvider:
        self.ensure_active()
        if self._provider is None:
            self._provider = self._provider_factory(self.config)
        return self._provider

    def ensure_active(self) -> None:
        if not self.config.active:
            raise BillingDisabledError('billing is disabled')

    async def create_checkout(self, uid: str, offer_id: str) -> CheckoutSession:
        provider = self._active_provider()
        assert self.config.catalog is not None
        resolved = self.config.catalog.offer(offer_id)
        if resolved is None:
            raise BillingOfferError('offer is not present in the server billing catalog')
        return await provider.create_checkout(
            product_id=resolved.offer.product_id,
            uid=uid,
            offer_id=offer_id,
            return_url=urljoin(self.config.public_base_url, 'v1/payments/success'),
            cancel_url=urljoin(self.config.public_base_url, 'v1/payments/cancel'),
        )

    async def create_portal(self, customer_id: str) -> str:
        provider = self._active_provider()
        if not customer_id:
            raise ValueError('customer has no billing profile')
        return await provider.create_portal(
            customer_id=customer_id,
            return_url=urljoin(self.config.public_base_url, 'v1/payments/portal-return'),
        )

    async def cancel_subscription(self, subscription_id: str) -> bool:
        provider = self._active_provider()
        return await provider.cancel_subscription(subscription_id)

    async def catalog_price_strings(self) -> dict[str, str]:
        provider = self._active_provider()
        assert self.config.catalog is not None
        prices: dict[str, str] = {}
        for plan in self.config.catalog.plans:
            for offer in plan.offers:
                prices[offer.id] = await provider.retrieve_product_price(offer.product_id, offer.interval)
        return prices

    async def close(self) -> None:
        provider = self._provider
        self._provider = None
        if provider is None:
            return
        await provider.close()

    async def process_webhook(self, raw_body: str, headers: Mapping[str, str]) -> str:
        provider = self._active_provider()
        try:
            event = provider.unwrap_webhook(raw_body, headers)
        except Exception as exc:
            raise BillingWebhookVerificationError('webhook signature verification failed') from exc

        raw_event = as_mapping(event)
        event_type = raw_event.get('type')
        if event_type not in _SUBSCRIPTION_EVENTS | _ASSOCIATION_EVENTS:
            return 'ignored'
        webhook_id = headers.get('webhook-id') or headers.get('Webhook-Id')
        if not webhook_id:
            raise BillingWebhookVerificationError('webhook-id header is required')
        if await self._projection_store.has_receipt(webhook_id):
            return 'duplicate'

        event_data = as_mapping(raw_event.get('data'), label='billing webhook data')
        if event_type in _ASSOCIATION_EVENTS:
            return await self._associate_checkout_customer(provider, event_data, webhook_id)

        subscription_id = event_data.get('subscription_id') or event_data.get('id')
        if not isinstance(subscription_id, str) or not subscription_id:
            raise ValueError('subscription webhook has no subscription identity')

        # Dodo documents that webhook deliveries can arrive out of order. The
        # event timestamp is not a resource version, so retrieve the current
        # provider object before projecting it.
        provider_subscription = await provider.retrieve_subscription(subscription_id)
        provider_data = as_mapping(provider_subscription)
        customer = as_mapping(provider_data.get('customer') or {}, label='billing customer')
        customer_id = customer.get('customer_id') or customer.get('id')
        uid = (
            await self._projection_store.resolve_uid(customer_id)
            if isinstance(customer_id, str) and customer_id
            else None
        )
        if not uid:
            raise ValueError('subscription webhook has no known user association')

        assert self.config.catalog is not None
        projected = project_subscription(
            provider_subscription,
            catalog=self.config.catalog,
            provider_updated_at=self._event_timestamp(raw_event.get('timestamp')),
        )
        outcome = await self._projection_store.apply(uid, projected, webhook_id)
        if outcome == 'applied':

            def invalidate_projection() -> None:
                self._projection_invalidator(uid)

            await run_blocking(db_executor, invalidate_projection)
        return outcome

    async def _associate_checkout_customer(
        self,
        provider: BillingProvider,
        event_data: Mapping[str, Any],
        webhook_id: str,
    ) -> str:
        payment_id = event_data.get('payment_id') or event_data.get('id')
        if not isinstance(payment_id, str) or not payment_id:
            raise ValueError('payment webhook has no payment identity')
        payment = as_mapping(await provider.retrieve_payment(payment_id), label='billing payment')
        metadata = as_mapping(payment.get('metadata') or {}, label='payment metadata')
        customer = as_mapping(payment.get('customer') or {}, label='billing customer')
        uid = metadata.get('uid')
        customer_id = customer.get('customer_id') or customer.get('id')
        if not isinstance(uid, str) or not uid or not isinstance(customer_id, str) or not customer_id:
            raise ValueError('payment webhook has no authenticated user association')
        return await self._projection_store.associate(uid, customer_id, webhook_id)

    @staticmethod
    def _event_timestamp(value: Any) -> int:
        if isinstance(value, datetime):
            parsed = value
        elif isinstance(value, str):
            parsed = datetime.fromisoformat(value.replace('Z', '+00:00'))
        else:
            raise ValueError('subscription webhook has no timestamp')
        if parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=timezone.utc)
        return int(parsed.timestamp())


def cancel_subscription_for_account_deletion(subscription_id: str) -> bool:
    """Cancel one potentially billable subscription from the synchronous wipe worker."""

    async def cancel_and_close() -> bool:
        service = BillingService(load_billing_config())
        try:
            return await service.cancel_subscription(subscription_id)
        finally:
            await service.close()

    return asyncio.run(cancel_and_close())


def catalog_price_strings_for_config(config: BillingConfig) -> dict[str, str]:
    async def load_and_close() -> dict[str, str]:
        service = BillingService(config)
        try:
            return await service.catalog_price_strings()
        finally:
            await service.close()

    return asyncio.run(load_and_close())
