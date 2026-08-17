from datetime import datetime, timezone

import pytest

from database.billing import (
    BillingAssociationConflictError,
    apply_webhook_projection,
    associate_customer,
    get_customer_uid,
)
from tests.unit.fixtures.strict_firestore_transaction import StrictFirestore


def _subscription(updated_at: int, *, status: str = 'active') -> dict:
    return {
        'plan': 'bounded',
        'offer_id': 'synthetic-monthly',
        'billing_customer_id': 'customer-synthetic',
        'billing_subscription_id': 'subscription-synthetic',
        'billing_product_id': 'product-synthetic',
        'entitlement_policy': 'bounded',
        'status': status,
        'provider_updated_at': updated_at,
        'current_period_end': updated_at + 3600,
        'limits': {'chat_questions_per_month': 8, 'transcription_seconds': 28800},
    }


def test_projection_and_receipt_commit_in_one_transaction() -> None:
    client = StrictFirestore({('users', 'uid-1'): {'subscription': _subscription(10)}})

    outcome = apply_webhook_projection(
        'uid-1',
        _subscription(20),
        'webhook-1',
        20,
        firestore_client=client,
    )

    assert outcome == 'applied'
    transaction = client.transactions[-1]
    assert transaction.updates == [(('users', 'uid-1'), {'subscription': _subscription(20)})]
    assert transaction.sets[0][0] == ('billing_webhook_receipts', 'webhook-1')
    assert transaction.sets[0][1]['outcome'] == 'applied'
    assert isinstance(transaction.sets[0][1]['received_at'], datetime)
    assert transaction.sets[0][1]['received_at'].tzinfo is timezone.utc


def test_duplicate_and_stale_delivery_cannot_replace_projection() -> None:
    current = _subscription(30)
    client = StrictFirestore(
        {
            ('users', 'uid-1'): {'subscription': current},
            ('billing_webhook_receipts', 'webhook-duplicate'): {'outcome': 'applied'},
        }
    )

    duplicate = apply_webhook_projection(
        'uid-1',
        _subscription(40),
        'webhook-duplicate',
        40,
        firestore_client=client,
    )
    stale = apply_webhook_projection(
        'uid-1',
        _subscription(20, status='cancelled'),
        'webhook-stale',
        20,
        firestore_client=client,
    )

    assert duplicate == 'duplicate'
    assert stale == 'stale'
    assert client.rows[('users', 'uid-1')]['subscription'] == current
    assert client.rows[('billing_webhook_receipts', 'webhook-stale')]['outcome'] == 'stale'


def test_deleted_user_is_not_recreated() -> None:
    client = StrictFirestore()

    outcome = apply_webhook_projection(
        'deleted-uid',
        _subscription(20),
        'webhook-deleted',
        20,
        firestore_client=client,
    )

    assert outcome == 'ignored_deleted_user'
    assert ('users', 'deleted-uid') not in client.rows
    assert client.rows[('billing_webhook_receipts', 'webhook-deleted')]['outcome'] == 'ignored_deleted_user'


def test_customer_association_is_owner_safe_and_grants_no_entitlement() -> None:
    client = StrictFirestore({('users', 'uid-1'): {'subscription': {'plan': 'free'}}})

    outcome = associate_customer(
        'uid-1',
        'customer-synthetic',
        'webhook-payment',
        firestore_client=client,
    )

    assert outcome == 'associated'
    assert get_customer_uid('customer-synthetic', firestore_client=client) == 'uid-1'
    assert client.rows[('users', 'uid-1')]['subscription'] == {'plan': 'free'}
    assert client.rows[('billing_webhook_receipts', 'webhook-payment')]['outcome'] == 'associated'

    client.rows[('users', 'uid-2')] = {'subscription': {'plan': 'free'}}
    with pytest.raises(BillingAssociationConflictError):
        associate_customer(
            'uid-2',
            'customer-synthetic',
            'webhook-conflict',
            firestore_client=client,
        )
    assert get_customer_uid('customer-synthetic', firestore_client=client) == 'uid-1'
