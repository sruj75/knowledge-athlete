from __future__ import annotations

from typing import Protocol

from database import billing as billing_db
from models.users import Subscription
from utils.executors import db_executor, run_blocking


class BillingProjectionStore(Protocol):
    async def has_receipt(self, webhook_id: str) -> bool: ...

    async def resolve_uid(self, customer_id: str) -> str | None: ...

    async def associate(self, uid: str, customer_id: str, webhook_id: str) -> str: ...

    async def apply(self, uid: str, subscription: Subscription, webhook_id: str) -> str: ...


class FirestoreBillingProjectionStore:
    async def has_receipt(self, webhook_id: str) -> bool:
        return await run_blocking(db_executor, billing_db.has_webhook_receipt, webhook_id)

    async def resolve_uid(self, customer_id: str) -> str | None:
        return await run_blocking(db_executor, billing_db.get_customer_uid, customer_id)

    async def associate(self, uid: str, customer_id: str, webhook_id: str) -> str:
        return await run_blocking(db_executor, billing_db.associate_customer, uid, customer_id, webhook_id)

    async def apply(self, uid: str, subscription: Subscription, webhook_id: str) -> str:
        return await run_blocking(
            db_executor,
            billing_db.apply_webhook_projection,
            uid,
            subscription.model_dump(mode='json'),
            webhook_id,
            subscription.provider_updated_at or 0,
        )
