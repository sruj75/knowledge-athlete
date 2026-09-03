from __future__ import annotations

import pytest
from pydantic import ValidationError

from models.users import BillingAvailability
from utils.billing.config import BillingConfigurationError, BillingMode, load_billing_config
from utils.billing.service import BillingDisabledError, BillingService


def test_missing_mode_defaults_to_disabled_without_credentials(monkeypatch: pytest.MonkeyPatch) -> None:
    for name in (
        'BILLING_MODE',
        'DODO_PAYMENTS_API_KEY',
        'DODO_PAYMENTS_WEBHOOK_KEY',
        'DODO_BILLING_CATALOG_JSON',
        'BASE_URL',
    ):
        monkeypatch.delenv(name, raising=False)

    config = load_billing_config()

    assert config.mode is BillingMode.disabled
    assert config.availability.model_dump() == {
        'checkout_enabled': False,
        'portal_enabled': False,
        'presentation': 'skip',
    }


def test_billing_presentation_rejects_unknown_wire_values() -> None:
    with pytest.raises(ValidationError):
        BillingAvailability(checkout_enabled=False, portal_enabled=False, presentation='unknown')


@pytest.mark.parametrize('mode', ['dodo_test', 'dodo_live'])
def test_active_modes_fail_closed_when_any_required_value_is_missing(
    monkeypatch: pytest.MonkeyPatch, mode: str
) -> None:
    monkeypatch.setenv('BILLING_MODE', mode)
    monkeypatch.setenv('DODO_PAYMENTS_API_KEY', 'synthetic-api-key')
    monkeypatch.setenv('DODO_PAYMENTS_WEBHOOK_KEY', 'synthetic-webhook-key')
    monkeypatch.delenv('DODO_BILLING_CATALOG_JSON', raising=False)

    with pytest.raises(BillingConfigurationError, match='DODO_BILLING_CATALOG_JSON') as error:
        load_billing_config()
    assert 'BASE_URL' in str(error.value)


@pytest.mark.asyncio
async def test_disabled_checkout_and_portal_guard_before_provider_construction(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv('BILLING_MODE', 'disabled')
    provider_constructions: list[str] = []

    def provider_factory(_config):
        provider_constructions.append('constructed')
        raise AssertionError('disabled billing must not construct a provider')

    service = BillingService(load_billing_config(), provider_factory=provider_factory)

    with pytest.raises(BillingDisabledError):
        await service.create_checkout('uid-1', 'offer-1')
    with pytest.raises(BillingDisabledError):
        await service.create_portal('customer-1')

    assert provider_constructions == []
