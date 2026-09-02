from __future__ import annotations

import os
from dataclasses import dataclass
from enum import Enum

from models.users import BillingAvailability, BillingPresentation
from utils.billing.catalog import BillingCatalog


class BillingConfigurationError(RuntimeError):
    pass


class BillingMode(str, Enum):
    disabled = 'disabled'
    dodo_test = 'dodo_test'
    dodo_live = 'dodo_live'


@dataclass(frozen=True)
class BillingConfig:
    mode: BillingMode
    api_key: str | None
    webhook_key: str | None
    catalog: BillingCatalog | None
    public_base_url: str

    @property
    def active(self) -> bool:
        return self.mode is not BillingMode.disabled

    @property
    def availability(self) -> BillingAvailability:
        enabled = self.active
        return BillingAvailability(
            checkout_enabled=enabled,
            portal_enabled=enabled,
            presentation=BillingPresentation.checkout if enabled else BillingPresentation.skip,
        )


def _nonempty_env(name: str) -> str | None:
    value = os.getenv(name)
    if value is None:
        return None
    stripped = value.strip()
    return stripped or None


def load_billing_config() -> BillingConfig:
    raw_mode = _nonempty_env('BILLING_MODE') or BillingMode.disabled.value
    try:
        mode = BillingMode(raw_mode)
    except ValueError as exc:
        allowed = ', '.join(item.value for item in BillingMode)
        raise BillingConfigurationError(f'BILLING_MODE must be one of: {allowed}') from exc

    configured_base_url = _nonempty_env('BASE_URL')
    if mode is BillingMode.disabled:
        return BillingConfig(
            mode=mode,
            api_key=None,
            webhook_key=None,
            catalog=None,
            public_base_url=configured_base_url.rstrip('/') + '/' if configured_base_url else '',
        )

    required = {
        'DODO_PAYMENTS_API_KEY': _nonempty_env('DODO_PAYMENTS_API_KEY'),
        'DODO_PAYMENTS_WEBHOOK_KEY': _nonempty_env('DODO_PAYMENTS_WEBHOOK_KEY'),
        'DODO_BILLING_CATALOG_JSON': _nonempty_env('DODO_BILLING_CATALOG_JSON'),
        'BASE_URL': configured_base_url,
    }
    missing = [name for name, value in required.items() if value is None]
    if missing:
        raise BillingConfigurationError(f'active billing is missing required configuration: {", ".join(missing)}')

    try:
        catalog = BillingCatalog.from_json(required['DODO_BILLING_CATALOG_JSON'] or '')
    except ValueError as exc:
        raise BillingConfigurationError(str(exc)) from exc

    return BillingConfig(
        mode=mode,
        api_key=required['DODO_PAYMENTS_API_KEY'],
        webhook_key=required['DODO_PAYMENTS_WEBHOOK_KEY'],
        catalog=catalog,
        public_base_url=(required['BASE_URL'] or '').rstrip('/') + '/',
    )


def validate_billing_config() -> None:
    """Validate the selected runtime mode without constructing a provider client."""

    load_billing_config()
