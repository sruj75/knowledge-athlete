from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Mapping, Protocol


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

    async def retrieve_payment(self, payment_id: str) -> Any: ...

    async def retrieve_product_price(self, product_id: str, expected_interval: str) -> str: ...

    def unwrap_webhook(self, raw_body: str, headers: Mapping[str, str]) -> Any: ...

    async def close(self) -> None: ...
