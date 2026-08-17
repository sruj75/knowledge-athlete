from __future__ import annotations

import json
from dataclasses import dataclass
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator


class EntitlementPolicy(str, Enum):
    bounded = 'bounded'
    unlimited = 'unlimited'


class CatalogLimits(BaseModel):
    model_config = ConfigDict(extra='forbid')

    transcription_seconds: int | None = Field(default=None, ge=0)
    words_transcribed: int | None = Field(default=None, ge=0)
    insights_gained: int | None = Field(default=None, ge=0)
    chat_questions_per_month: int | None = Field(default=None, ge=0)
    chat_cost_usd_per_month: float | None = Field(default=None, ge=0)

    @model_validator(mode='after')
    def exactly_one_chat_allowance(self) -> 'CatalogLimits':
        configured = (self.chat_questions_per_month is not None, self.chat_cost_usd_per_month is not None)
        if configured.count(True) != 1:
            raise ValueError('exactly one chat allowance must be configured')
        return self


class CatalogOffer(BaseModel):
    model_config = ConfigDict(extra='forbid')

    id: str = Field(min_length=1)
    product_id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    price_string: str = Field(min_length=1)
    description: str | None = None
    interval: str = Field(pattern='^(month|year)$')

    @field_validator('id', 'product_id')
    @classmethod
    def opaque_identity(cls, value: str) -> str:
        if value.strip() != value:
            raise ValueError('identities must not contain surrounding whitespace')
        return value


class CatalogPlan(BaseModel):
    model_config = ConfigDict(extra='forbid')

    id: str = Field(min_length=1)
    title: str = Field(min_length=1)
    subtitle: str | None = None
    description: str | None = None
    eyebrow: str | None = None
    features: list[str] = Field(default_factory=list)
    entitlement_policy: EntitlementPolicy
    limits: CatalogLimits
    offers: list[CatalogOffer] = Field(min_length=1)


class CatalogDocument(BaseModel):
    model_config = ConfigDict(extra='forbid')

    plans: list[CatalogPlan] = Field(min_length=1)


@dataclass(frozen=True)
class ResolvedOffer:
    plan: CatalogPlan
    offer: CatalogOffer


class BillingCatalog:
    def __init__(self, document: CatalogDocument):
        self.document = document
        self._by_offer: dict[str, ResolvedOffer] = {}
        self._by_product: dict[str, ResolvedOffer] = {}
        plan_ids: set[str] = set()
        for plan in document.plans:
            if plan.id in plan_ids:
                raise ValueError(f'duplicate plan id: {plan.id}')
            plan_ids.add(plan.id)
            for offer in plan.offers:
                if offer.id in self._by_offer:
                    raise ValueError(f'duplicate offer id: {offer.id}')
                if offer.product_id in self._by_product:
                    raise ValueError(f'duplicate product id: {offer.product_id}')
                resolved = ResolvedOffer(plan=plan, offer=offer)
                self._by_offer[offer.id] = resolved
                self._by_product[offer.product_id] = resolved

    @classmethod
    def from_json(cls, raw: str) -> 'BillingCatalog':
        try:
            value: Any = json.loads(raw)
            return cls(CatalogDocument.model_validate(value))
        except (json.JSONDecodeError, ValidationError, ValueError) as exc:
            raise ValueError(f'invalid billing catalog: {exc}') from exc

    def offer(self, offer_id: str) -> ResolvedOffer | None:
        return self._by_offer.get(offer_id)

    def product(self, product_id: str) -> ResolvedOffer | None:
        return self._by_product.get(product_id)

    @property
    def plans(self) -> tuple[CatalogPlan, ...]:
        return tuple(self.document.plans)
