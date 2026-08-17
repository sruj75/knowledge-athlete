from __future__ import annotations

import asyncio
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any, Mapping
from urllib.parse import urljoin

from utils.billing.config import BillingConfig
from utils.billing.provider import BillingProvider, CheckoutSession, DodoBillingProvider
from utils.billing.projection import project_subscription
from utils.billing.store import BillingProjectionStore, FirestoreBillingProjectionStore
from utils.executors import db_executor, run_blocking


class BillingDisabledError(RuntimeError):
    code = 'billing_disabled'


class BillingOfferError(ValueError):
    code = 'invalid_billing_offer'


ProviderFactory = Callable[[BillingConfig], BillingProvider]
ProjectionInvalidator = Callable[[str], None]


def _invalidate_projection_caches(uid: str) -> None:
    from database.redis_db import set_credits_invalidation_signal
    from utils.fair_use import clear_fair_use_on_upgrade
    from utils.subscription import clear_trial_paywall_cache

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


class BillingService:
    def __init__(
        self,
        config: BillingConfig,
        provider_factory: ProviderFactory = DodoBillingProvider,
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

    async def close(self) -> None:
        provider = self._provider
        self._provider = None
        if provider is None:
            return
        close = getattr(provider, 'close', None)
        if callable(close):
            await close()

    async def process_webhook(self, raw_body: str, headers: Mapping[str, str]) -> str:
        provider = self._active_provider()
        try:
            event = provider.unwrap_webhook(raw_body, headers)
        except Exception as exc:
            raise BillingWebhookVerificationError('webhook signature verification failed') from exc

        raw_event = self._mapping(event)
        event_type = raw_event.get('type')
        if event_type not in _SUBSCRIPTION_EVENTS:
            return 'ignored'
        webhook_id = headers.get('webhook-id') or headers.get('Webhook-Id')
        if not webhook_id:
            raise BillingWebhookVerificationError('webhook-id header is required')
        if await self._projection_store.has_receipt(webhook_id):
            return 'duplicate'

        event_data = self._mapping(raw_event.get('data'))
        subscription_id = event_data.get('subscription_id') or event_data.get('id')
        if not isinstance(subscription_id, str) or not subscription_id:
            raise ValueError('subscription webhook has no subscription identity')

        # Dodo documents that webhook deliveries can arrive out of order. The
        # event timestamp is not a resource version, so retrieve the current
        # provider object before projecting it.
        provider_subscription = await provider.retrieve_subscription(subscription_id)
        provider_data = self._mapping(provider_subscription)
        metadata = self._mapping(provider_data.get('metadata') or {})
        uid = metadata.get('uid')
        if not isinstance(uid, str) or not uid:
            customer = self._mapping(provider_data.get('customer') or {})
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
            await run_blocking(db_executor, self._projection_invalidator, uid)
        return outcome

    @staticmethod
    def _mapping(value: Any) -> Mapping[str, Any]:
        if isinstance(value, Mapping):
            return value
        dump = getattr(value, 'model_dump', None)
        if callable(dump):
            result = dump(mode='json')
            if isinstance(result, Mapping):
                return result
        raise TypeError('billing value must be a mapping')

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

    from utils.billing.config import load_billing_config

    async def cancel_and_close() -> bool:
        service = BillingService(load_billing_config())
        try:
            return await service.cancel_subscription(subscription_id)
        finally:
            await service.close()

    return asyncio.run(cancel_and_close())
