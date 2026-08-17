from datetime import datetime, timezone
from typing import Any

from google.cloud.firestore_v1 import transactional

from ._client import get_firestore_client


class BillingAssociationConflictError(RuntimeError):
    pass


def get_customer_uid(customer_id: str, *, firestore_client: Any | None = None) -> str | None:
    client = firestore_client or get_firestore_client()
    snapshot = client.collection('billing_customer_associations').document(customer_id).get()
    if not snapshot.exists:
        return None
    data = snapshot.to_dict() or {}
    uid = data.get('uid')
    return uid if isinstance(uid, str) and uid else None


@transactional
def _associate_customer_txn(transaction, user_ref, association_ref, receipt_ref, uid: str):
    receipt = receipt_ref.get(transaction=transaction)
    if receipt.exists:
        return 'duplicate'

    user = user_ref.get(transaction=transaction)
    association = association_ref.get(transaction=transaction)
    if not user.exists:
        transaction.set(
            receipt_ref,
            {'outcome': 'ignored_deleted_user', 'received_at': datetime.now(timezone.utc)},
        )
        return 'ignored_deleted_user'

    if association.exists:
        association_uid = (association.to_dict() or {}).get('uid')
        if association_uid != uid:
            raise BillingAssociationConflictError('billing customer is already associated with another account')

    transaction.set(association_ref, {'uid': uid, 'updated_at': datetime.now(timezone.utc)})
    transaction.set(receipt_ref, {'outcome': 'associated', 'received_at': datetime.now(timezone.utc)})
    return 'associated'


def associate_customer(
    uid: str,
    customer_id: str,
    webhook_id: str,
    *,
    firestore_client: Any | None = None,
) -> str:
    """Atomically bind a verified checkout customer to its user without granting entitlement."""

    client = firestore_client or get_firestore_client()
    transaction = client.transaction()
    return _associate_customer_txn(
        transaction,
        client.collection('users').document(uid),
        client.collection('billing_customer_associations').document(customer_id),
        client.collection('billing_webhook_receipts').document(webhook_id),
        uid,
    )


@transactional
def _apply_webhook_projection_txn(
    transaction,
    user_ref,
    receipt_ref,
    subscription_data: dict,
    provider_updated_at: int,
):
    receipt = receipt_ref.get(transaction=transaction)
    if receipt.exists:
        return 'duplicate'

    user = user_ref.get(transaction=transaction)
    if not user.exists:
        transaction.set(
            receipt_ref,
            {'outcome': 'ignored_deleted_user', 'received_at': datetime.now(timezone.utc)},
        )
        return 'ignored_deleted_user'

    user_data = user.to_dict() or {}
    current = user_data.get('subscription') or {}
    current_updated_at = current.get('provider_updated_at', 0) if isinstance(current, dict) else 0
    if isinstance(current_updated_at, (int, float)) and current_updated_at > provider_updated_at:
        transaction.set(
            receipt_ref,
            {'outcome': 'stale', 'received_at': datetime.now(timezone.utc)},
        )
        return 'stale'

    transaction.update(user_ref, {'subscription': subscription_data})
    transaction.set(
        receipt_ref,
        {'outcome': 'applied', 'received_at': datetime.now(timezone.utc)},
    )
    return 'applied'


def apply_webhook_projection(
    uid: str,
    subscription_data: dict,
    webhook_id: str,
    provider_updated_at: int,
    *,
    firestore_client: Any | None = None,
) -> str:
    """Atomically persist one normalized projection and durable webhook receipt."""

    client = firestore_client or get_firestore_client()
    user_ref = client.collection('users').document(uid)
    receipt_ref = client.collection('billing_webhook_receipts').document(webhook_id)
    transaction = client.transaction()
    return _apply_webhook_projection_txn(
        transaction,
        user_ref,
        receipt_ref,
        subscription_data,
        provider_updated_at,
    )


def has_webhook_receipt(webhook_id: str, *, firestore_client: Any | None = None) -> bool:
    client = firestore_client or get_firestore_client()
    return client.collection('billing_webhook_receipts').document(webhook_id).get().exists
