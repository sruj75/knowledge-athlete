from __future__ import annotations

import base64
import json
from datetime import datetime, timezone
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from standardwebhooks import Webhook

from routers import payment
from utils.billing.catalog import BillingCatalog
from utils.billing.config import BillingConfig, BillingMode
from utils.billing.service import BillingService


WEBHOOK_SECRET = 'whsec_' + base64.b64encode(b'synthetic-webhook-secret').decode()


def _catalog() -> BillingCatalog:
    return BillingCatalog.from_json(
        '''
        {"plans": [{
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
        }]}
        '''
    )


def _subscription(*, product_id: str = 'product-synthetic', uid: str = 'uid-1') -> dict[str, Any]:
    return {
        'subscription_id': 'subscription-synthetic',
        'product_id': product_id,
        'status': 'active',
        'customer': {'customer_id': 'customer-synthetic'},
        'currency': 'USD',
        'recurring_pre_tax_amount': 800,
        'payment_frequency_interval': 'Month',
        'metadata': {'uid': uid},
        'previous_billing_date': '2026-08-01T00:00:00Z',
        'next_billing_date': '2026-09-01T00:00:00Z',
        'cancel_at_next_billing_date': False,
    }


class _SignedProvider:
    def __init__(self, current_subscription: dict[str, Any], current_payment: dict[str, Any] | None = None):
        self.current_subscription = current_subscription
        self.current_payment = current_payment or {}
        self.retrieve_calls: list[str] = []
        self.payment_retrieve_calls: list[str] = []

    def unwrap_webhook(self, raw_body: str, headers):
        Webhook(WEBHOOK_SECRET).verify(raw_body, dict(headers))
        return json.loads(raw_body)

    async def retrieve_subscription(self, subscription_id: str):
        self.retrieve_calls.append(subscription_id)
        return self.current_subscription

    async def retrieve_payment(self, payment_id: str):
        self.payment_retrieve_calls.append(payment_id)
        return self.current_payment


class _MemoryStore:
    def __init__(self, *, existing_uids: set[str] | None = None, fail: bool = False):
        self.existing_uids = existing_uids or {'uid-1'}
        self.fail = fail
        self.receipts: set[str] = set()
        self.projections: dict[str, Any] = {}
        self.associations: dict[str, str] = {}

    async def has_receipt(self, webhook_id: str) -> bool:
        return webhook_id in self.receipts

    async def resolve_uid(self, customer_id: str) -> str | None:
        return self.associations.get(customer_id)

    async def associate(self, uid: str, customer_id: str, webhook_id: str) -> str:
        if webhook_id in self.receipts:
            return 'duplicate'
        self.receipts.add(webhook_id)
        if uid not in self.existing_uids:
            return 'ignored_deleted_user'
        existing = self.associations.get(customer_id)
        if existing is not None and existing != uid:
            raise RuntimeError('synthetic association conflict')
        self.associations[customer_id] = uid
        return 'associated'

    async def apply(self, uid: str, subscription, webhook_id: str) -> str:
        if self.fail:
            raise RuntimeError('synthetic persistence failure')
        if webhook_id in self.receipts:
            return 'duplicate'
        self.receipts.add(webhook_id)
        if uid not in self.existing_uids:
            return 'ignored_deleted_user'
        current = self.projections.get(uid)
        if current and (current.provider_updated_at or 0) > (subscription.provider_updated_at or 0):
            return 'stale'
        self.projections[uid] = subscription
        return 'applied'


def _client(
    provider: _SignedProvider,
    store: _MemoryStore,
    invalidations: list[str] | None = None,
) -> TestClient:
    config = BillingConfig(
        mode=BillingMode.dodo_test,
        api_key='synthetic-api-key',
        webhook_key=WEBHOOK_SECRET,
        catalog=_catalog(),
        public_base_url='https://billing.invalid/',
    )
    service = BillingService(
        config,
        provider_factory=lambda _config: provider,
        projection_store=store,
        projection_invalidator=(invalidations if invalidations is not None else []).append,
    )
    app = FastAPI()
    app.include_router(payment.router)
    app.dependency_overrides[payment.get_billing_service] = lambda: service
    return TestClient(app)


def _signed_request(
    client: TestClient,
    *,
    webhook_id: str = 'webhook-synthetic',
    timestamp: datetime = datetime(2026, 8, 17, 1, 2, 3, tzinfo=timezone.utc),
    event_type: str = 'subscription.updated',
):
    signature_time = datetime.now(timezone.utc)
    body = json.dumps(
        {
            'business_id': 'business-synthetic',
            'type': event_type,
            'timestamp': timestamp.isoformat().replace('+00:00', 'Z'),
            'data': (
                {'payment_id': 'payment-synthetic'}
                if event_type == 'payment.succeeded'
                else {'subscription_id': 'subscription-synthetic'}
            ),
        },
        separators=(',', ':'),
    )
    signature = Webhook(WEBHOOK_SECRET).sign(webhook_id, signature_time, body)
    return client.post(
        '/v1/dodo/webhook',
        content=body,
        headers={
            'content-type': 'application/json',
            'webhook-id': webhook_id,
            'webhook-timestamp': str(int(signature_time.timestamp())),
            'webhook-signature': signature,
        },
    )


@pytest.fixture
def signed_subscription_case():
    provider = _SignedProvider(_subscription())
    store = _MemoryStore()
    store.associations['customer-synthetic'] = 'uid-1'
    invalidations: list[str] = []
    client = _client(provider, store, invalidations)
    warmup = _signed_request(client, webhook_id='webhook-warmup', event_type='customer.created')
    assert warmup.json() == {'status': 'ignored'}
    return provider, store, invalidations, client


def test_signed_webhook_retrieves_current_state_and_applies_once(signed_subscription_case) -> None:
    provider, store, invalidations, client = signed_subscription_case

    first = _signed_request(client)
    assert first.status_code == 200
    assert first.json() == {'status': 'applied'}
    assert store.projections['uid-1'].offer_id == 'synthetic-monthly'
    assert provider.retrieve_calls == ['subscription-synthetic']
    assert invalidations == ['uid-1']


def test_duplicate_webhook_receipt_is_a_no_op_success() -> None:
    provider = _SignedProvider(_subscription())
    store = _MemoryStore()
    store.receipts.add('webhook-synthetic')
    client = _client(provider, store)

    duplicate = _signed_request(client)

    assert duplicate.status_code == 200
    assert duplicate.json() == {'status': 'duplicate'}
    assert provider.retrieve_calls == []
    assert store.projections == {}


def test_invalid_signature_is_rejected_before_projection() -> None:
    provider = _SignedProvider(_subscription())
    store = _MemoryStore()
    client = _client(provider, store)

    response = client.post(
        '/v1/dodo/webhook',
        content='{}',
        headers={
            'webhook-id': 'webhook-invalid',
            'webhook-timestamp': '1',
            'webhook-signature': 'v1,invalid',
        },
    )

    assert response.status_code == 401
    assert response.json()['detail']['code'] == 'invalid_webhook_signature'
    assert store.projections == {}


def test_stale_delivery_cannot_replace_newer_projection() -> None:
    provider = _SignedProvider(_subscription())
    store = _MemoryStore()
    store.associations['customer-synthetic'] = 'uid-1'
    client = _client(provider, store)
    newer = datetime(2026, 8, 17, 2, tzinfo=timezone.utc)
    older = datetime(2026, 8, 17, 1, tzinfo=timezone.utc)

    assert _signed_request(client, webhook_id='webhook-newer', timestamp=newer).json()['status'] == 'applied'
    assert _signed_request(client, webhook_id='webhook-older', timestamp=older).json()['status'] == 'stale'
    assert store.projections['uid-1'].provider_updated_at == int(newer.timestamp())


def test_unknown_product_deleted_user_and_persistence_failure_fail_safe() -> None:
    unknown_store = _MemoryStore()
    unknown_store.associations['customer-synthetic'] = 'uid-1'
    unknown = _signed_request(_client(_SignedProvider(_subscription(product_id='unknown', uid='')), unknown_store))
    assert unknown.status_code == 400

    deleted_store = _MemoryStore(existing_uids={'another-user'})
    deleted_store.associations['customer-synthetic'] = 'uid-1'
    deleted = _signed_request(_client(_SignedProvider(_subscription()), deleted_store))
    assert deleted.status_code == 200
    assert deleted.json()['status'] == 'ignored_deleted_user'
    assert deleted_store.projections == {}

    failed_store = _MemoryStore(fail=True)
    failed_store.associations['customer-synthetic'] = 'uid-1'
    failed = _signed_request(_client(_SignedProvider(_subscription(uid='')), failed_store))
    assert failed.status_code == 502


def test_payment_webhook_associates_customer_without_granting_access_before_subscription() -> None:
    store = _MemoryStore()
    provider = _SignedProvider(
        _subscription(uid=''),
        {
            'payment_id': 'payment-synthetic',
            'customer': {'customer_id': 'customer-synthetic'},
            'metadata': {'uid': 'uid-1', 'offer_id': 'synthetic-monthly'},
        },
    )
    client = _client(provider, store)

    association = _signed_request(
        client,
        webhook_id='webhook-payment',
        event_type='payment.succeeded',
    )
    projected = _signed_request(client, webhook_id='webhook-subscription')

    assert association.status_code == 200
    assert association.json() == {'status': 'associated'}
    assert provider.payment_retrieve_calls == ['payment-synthetic']
    assert projected.json() == {'status': 'applied'}
    assert store.associations == {'customer-synthetic': 'uid-1'}
    assert store.projections['uid-1'].billing_subscription_id == 'subscription-synthetic'


def test_subscription_metadata_cannot_bypass_or_override_customer_association() -> None:
    associated_store = _MemoryStore(existing_uids={'uid-1', 'uid-attacker'})
    associated_store.associations['customer-synthetic'] = 'uid-1'
    conflicting = _signed_request(
        _client(_SignedProvider(_subscription(uid='uid-attacker')), associated_store),
        webhook_id='webhook-conflicting-metadata',
    )

    assert conflicting.status_code == 200
    assert conflicting.json() == {'status': 'applied'}
    assert set(associated_store.projections) == {'uid-1'}

    unassociated_store = _MemoryStore()
    bypass = _signed_request(
        _client(_SignedProvider(_subscription(uid='uid-1')), unassociated_store),
        webhook_id='webhook-unassociated-metadata',
    )

    assert bypass.status_code == 400
    assert unassociated_store.projections == {}
