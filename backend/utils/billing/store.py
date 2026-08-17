from __future__ import annotations

from typing import Protocol

from database import users as users_db
from models.users import Subscription
from utils.executors import db_executor, run_blocking


class BillingProjectionStore(Protocol):
    async def has_receipt(self, webhook_id: str) -> bool: ...

    async def resolve_uid(self, customer_id: str) -> str | None: ...

    async def apply(self, uid: str, subscription: Subscription, webhook_id: str) -> str: ...


class FirestoreBillingProjectionStore:
    async def has_receipt(self, webhook_id: str) -> bool:
        return await run_blocking(db_executor, users_db.has_billing_webhook_receipt, webhook_id)

    async def resolve_uid(self, customer_id: str) -> str | None:
        user = await run_blocking(db_executor, users_db.get_user_by_billing_customer_id, customer_id)
        uid = user.get('uid') if isinstance(user, dict) else None
        return uid if isinstance(uid, str) and uid else None

    async def apply(self, uid: str, subscription: Subscription, webhook_id: str) -> str:
        return await run_blocking(
            db_executor,
            users_db.apply_billing_webhook_projection,
            uid,
            subscription.model_dump(mode='json'),
            webhook_id,
            subscription.provider_updated_at or 0,
        )
