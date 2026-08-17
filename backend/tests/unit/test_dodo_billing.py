from __future__ import annotations

from unittest.mock import MagicMock

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from routers import payment
from routers.payment import (
    CreateCheckoutRequest,
    create_checkout_session_endpoint,
    create_customer_portal_endpoint,
)
from utils.billing.config import BillingConfig, BillingMode, load_billing_config
from utils.billing.catalog import BillingCatalog
from utils.billing.projection import UnknownBillingProductError, project_subscription
from utils.billing.provider import CheckoutSession, DodoBillingProvider
from utils.billing.service import BillingService


@pytest.mark.parametrize(
    ('method', 'path'),
    [
        ('get', '/v1/payments/available-plans'),
        ('get', '/v1/payments/overage-info'),
        ('post', '/v1/payments/upgrade-subscription'),
        ('delete', '/v1/payments/subscription'),
        ('post', '/v1/stripe/webhook'),
    ],
)
def test_removed_payment_routes_are_absent(method: str, path: str) -> None:
    app = FastAPI()
    app.include_router(payment.router)

    response = getattr(TestClient(app), method)(path)

    assert response.status_code in {404, 405}


class _ActiveProvider:
    def __init__(self) -> None:
        self.checkout_calls: list[dict] = []
        self.portal_calls: list[dict] = []
        self.price_calls: list[tuple[str, str]] = []
        self.close_calls = 0

    async def create_checkout(self, **kwargs):
        self.checkout_calls.append(kwargs)
        return CheckoutSession(session_id='session-synthetic', url='https://checkout.invalid/session')

    async def create_portal(self, **kwargs):
        self.portal_calls.append(kwargs)
        return 'https://portal.invalid/session'

    async def retrieve_product_price(self, product_id: str, expected_interval: str) -> str:
        self.price_calls.append((product_id, expected_interval))
        return 'USD 8.00/month'

    async def close(self) -> None:
        self.close_calls += 1


class _RetrieveResource:
    def __init__(self, value: dict) -> None:
        self.value = value
        self.calls: list[str] = []

    def retrieve(self, identity: str) -> dict:
        self.calls.append(identity)
        return self.value


class _RetrieveClient:
    def __init__(self, subscription: dict, payment: dict) -> None:
        self.subscriptions = _RetrieveResource(subscription)
        self.payments = _RetrieveResource(payment)


class _ProductClient:
    def __init__(self, product: dict) -> None:
        self.products = _RetrieveResource(product)


def _active_service(provider: _ActiveProvider) -> BillingService:
    return BillingService(
        BillingConfig(
            mode=BillingMode.dodo_test,
            api_key='synthetic-api-key',
            webhook_key='synthetic-webhook-key',
            catalog=_catalog(),
            public_base_url='https://billing.invalid/',
        ),
        provider_factory=lambda _config: provider,
    )


@pytest.mark.asyncio
async def test_disabled_transaction_routes_return_typed_error_without_provider(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv('BILLING_MODE', BillingMode.disabled.value)
    factory = MagicMock(side_effect=AssertionError('provider must not be constructed'))
    service = BillingService(load_billing_config(), provider_factory=factory)

    with pytest.raises(HTTPException) as checkout_error:
        await create_checkout_session_endpoint(CreateCheckoutRequest(offer_id='synthetic-offer'), 'uid-1', service)
    with pytest.raises(HTTPException) as portal_error:
        await create_customer_portal_endpoint('uid-1', service)

    assert checkout_error.value.status_code == 503
    assert checkout_error.value.detail['code'] == 'billing_disabled'
    assert portal_error.value.status_code == 503
    assert portal_error.value.detail['code'] == 'billing_disabled'
    factory.assert_not_called()


def _catalog() -> BillingCatalog:
    return BillingCatalog.from_json(
        '''
        {
          "plans": [{
            "id": "synthetic-plan",
            "title": "Synthetic plan",
            "features": ["managed_chat"],
            "entitlement_policy": "bounded",
            "limits": {"chat_questions_per_month": 8, "transcription_seconds": 28800},
            "offers": [{
              "id": "synthetic-monthly",
              "product_id": "product-synthetic",
              "title": "Monthly",
              "interval": "month"
            }]
          }]
        }
        '''
    )


@pytest.mark.asyncio
async def test_service_close_releases_constructed_provider_once() -> None:
    provider = _ActiveProvider()
    service = _active_service(provider)

    await service.create_checkout('uid-1', 'synthetic-monthly')
    await service.close()
    await service.close()

    assert provider.close_calls == 1


@pytest.mark.asyncio
async def test_catalog_price_presentation_comes_from_provider_adapter() -> None:
    provider = _ActiveProvider()
    service = _active_service(provider)

    prices = await service.catalog_price_strings()

    assert prices == {'synthetic-monthly': 'USD 8.00/month'}
    assert provider.price_calls == [('product-synthetic', 'month')]


@pytest.mark.asyncio
async def test_subscription_retrieval_uses_the_official_subscription_schema() -> None:
    provider = object.__new__(DodoBillingProvider)
    client = _RetrieveClient(
        {
            'subscription_id': 'subscription-synthetic',
            'metadata': {'uid': 'uid-1'},
        },
        {'payment_id': 'payment-synthetic', 'metadata': {'uid': 'uid-1', 'offer_id': 'synthetic-monthly'}},
    )
    provider._client = client

    subscription = await provider.retrieve_subscription('subscription-synthetic')

    assert subscription['metadata']['uid'] == 'uid-1'
    assert client.subscriptions.calls == ['subscription-synthetic']
    assert client.payments.calls == []


@pytest.mark.asyncio
async def test_product_retrieval_formats_provider_price_and_validates_interval() -> None:
    provider = object.__new__(DodoBillingProvider)
    client = _ProductClient(
        {
            'product_id': 'product-synthetic',
            'price': {
                'type': 'recurring_price',
                'price': 1250,
                'currency': 'USD',
                'payment_frequency_interval': 'Month',
            },
        }
    )
    provider._client = client

    assert await provider.retrieve_product_price('product-synthetic', 'month') == 'USD 12.50/month'
    assert client.products.calls == ['product-synthetic']

    with pytest.raises(ValueError, match='interval'):
        await provider.retrieve_product_price('product-synthetic', 'year')


def test_catalog_projects_provider_subscription_to_normalized_entitlement() -> None:
    projected = project_subscription(
        {
            'subscription_id': 'subscription-synthetic',
            'product_id': 'product-synthetic',
            'status': 'active',
            'customer': {'customer_id': 'customer-synthetic'},
            'currency': 'USD',
            'recurring_pre_tax_amount': 800,
            'payment_frequency_interval': 'Month',
            'previous_billing_date': '2026-08-01T00:00:00Z',
            'next_billing_date': '2026-09-01T00:00:00Z',
            'cancel_at_next_billing_date': True,
        },
        catalog=_catalog(),
        provider_updated_at=1_775_000_000,
    )

    assert projected.plan.value == 'bounded'
    assert projected.plan_name == 'Synthetic plan'
    assert projected.offer_id == 'synthetic-monthly'
    assert projected.billing_product_id == 'product-synthetic'
    assert projected.billing_customer_id == 'customer-synthetic'
    assert projected.billing_subscription_id == 'subscription-synthetic'
    assert projected.price_string == 'USD 8.00/month'
    assert projected.cancel_at_next_billing_date is True
    assert projected.limits.chat_questions_per_month == 8
    assert projected.entitlement_policy.value == 'bounded'


def test_unknown_provider_product_never_grants_paid_access() -> None:
    with pytest.raises(UnknownBillingProductError):
        project_subscription(
            {
                'subscription_id': 'subscription-synthetic',
                'product_id': 'unknown-product',
                'status': 'active',
                'customer': {'customer_id': 'customer-synthetic'},
                'currency': 'USD',
                'recurring_pre_tax_amount': 800,
                'payment_frequency_interval': 'Month',
                'previous_billing_date': '2026-08-01T00:00:00Z',
                'next_billing_date': '2026-09-01T00:00:00Z',
                'cancel_at_next_billing_date': False,
            },
            catalog=_catalog(),
            provider_updated_at=1_775_000_000,
        )


@pytest.mark.asyncio
async def test_checkout_resolves_server_offer_and_ignores_tampered_identity() -> None:
    provider = _ActiveProvider()
    service = _active_service(provider)

    response = await create_checkout_session_endpoint(
        CreateCheckoutRequest(offer_id='synthetic-monthly'), 'uid-1', service
    )

    assert response.url == 'https://checkout.invalid/session'
    assert response.session_id == 'session-synthetic'
    assert provider.checkout_calls == [
        {
            'product_id': 'product-synthetic',
            'uid': 'uid-1',
            'offer_id': 'synthetic-monthly',
            'return_url': 'https://billing.invalid/v1/payments/success',
            'cancel_url': 'https://billing.invalid/v1/payments/cancel',
        }
    ]

    with pytest.raises(HTTPException) as error:
        await create_checkout_session_endpoint(CreateCheckoutRequest(offer_id='product-synthetic'), 'uid-1', service)
    assert error.value.status_code == 400
    assert error.value.detail['code'] == 'invalid_billing_offer'
    assert len(provider.checkout_calls) == 1


@pytest.mark.asyncio
async def test_portal_uses_normalized_customer_and_free_user_fails_bounded(monkeypatch) -> None:
    provider = _ActiveProvider()
    service = _active_service(provider)
    monkeypatch.setattr(
        'routers.payment.users_db.get_existing_user_subscription',
        lambda _uid: type('Subscription', (), {'billing_customer_id': 'customer-synthetic'})(),
    )

    response = await create_customer_portal_endpoint('uid-1', service)
    assert response.url == 'https://portal.invalid/session'
    assert provider.portal_calls == [
        {
            'customer_id': 'customer-synthetic',
            'return_url': 'https://billing.invalid/v1/payments/portal-return',
        }
    ]

    monkeypatch.setattr('routers.payment.users_db.get_existing_user_subscription', lambda _uid: None)
    with pytest.raises(HTTPException) as error:
        await create_customer_portal_endpoint('uid-free', service)
    assert error.value.status_code == 400
    assert error.value.detail['code'] == 'billing_profile_unavailable'
    assert len(provider.portal_calls) == 1
