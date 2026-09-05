"""Typed lazy construction boundary for the optional Dodo adapter module."""

from __future__ import annotations

from importlib import import_module
from typing import Protocol, cast

from utils.billing.config import BillingConfig
from utils.billing.contracts import BillingProvider


class _ProviderConstructor(Protocol):
    def __call__(self, config: BillingConfig) -> BillingProvider: ...


def create_dodo_billing_provider(config: BillingConfig) -> BillingProvider:
    """Load the concrete adapter only after the service proves billing is active."""

    provider_module = import_module('utils.billing.provider')
    constructor = cast(_ProviderConstructor, getattr(provider_module, 'DodoBillingProvider'))
    return constructor(config)
