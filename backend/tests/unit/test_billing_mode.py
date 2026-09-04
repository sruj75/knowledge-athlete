from __future__ import annotations

import subprocess
import sys

import pytest
from pydantic import ValidationError

from models.users import BillingAvailability
from utils.billing.config import BillingConfigurationError, BillingMode, load_billing_config
from utils.billing.service import BillingDisabledError, BillingService, cancel_subscription_for_account_deletion


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


def test_disabled_mode_ignores_nonempty_malformed_dodo_configuration(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('BILLING_MODE', 'disabled')
    monkeypatch.setenv('DODO_PAYMENTS_API_KEY', 'must-not-be-read')
    monkeypatch.setenv('DODO_PAYMENTS_WEBHOOK_KEY', 'must-not-be-read')
    monkeypatch.setenv('DODO_BILLING_CATALOG_JSON', '{not-json')

    config = load_billing_config()

    assert config.api_key is None
    assert config.webhook_key is None
    assert config.catalog is None


def test_disabled_runtime_does_not_require_the_dodo_sdk() -> None:
    script = r'''
import builtins
import os
import sys

real_import = builtins.__import__

def reject_dodo(name, globals=None, locals=None, fromlist=(), level=0):
    if name == 'dodopayments' or name.startswith('dodopayments.'):
        raise ModuleNotFoundError('synthetic missing Dodo SDK')
    return real_import(name, globals, locals, fromlist, level)

builtins.__import__ = reject_dodo
os.environ['BILLING_MODE'] = 'disabled'

from utils.billing.config import load_billing_config
from utils.billing.service import BillingDisabledError, BillingService

service = BillingService(load_billing_config())
try:
    service.ensure_active()
except BillingDisabledError:
    pass
else:
    raise AssertionError('disabled billing unexpectedly became active')

assert 'dodopayments' not in sys.modules
'''

    result = subprocess.run(
        [sys.executable, '-c', script],
        cwd=str(__file__).rsplit('/tests/', 1)[0],
        capture_output=True,
        text=True,
        check=False,
    )

    assert result.returncode == 0, result.stderr


def test_billing_presentation_rejects_unknown_wire_values() -> None:
    with pytest.raises(ValidationError):
        BillingAvailability(checkout_enabled=False, portal_enabled=False, presentation='unknown')


def test_disabled_mode_refuses_to_cancel_a_legacy_paid_record(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv('BILLING_MODE', 'disabled')
    monkeypatch.setenv('DODO_PAYMENTS_API_KEY', 'must-not-be-read')

    with pytest.raises(BillingDisabledError):
        cancel_subscription_for_account_deletion('legacy-subscription')


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

    class ForbiddenStore:
        def __getattr__(self, name):
            raise AssertionError(f'disabled billing must not access projection store method {name}')

    service = BillingService(
        load_billing_config(),
        provider_factory=provider_factory,
        projection_store=ForbiddenStore(),
    )

    with pytest.raises(BillingDisabledError):
        await service.create_checkout('uid-1', 'offer-1')
    with pytest.raises(BillingDisabledError):
        await service.create_portal('customer-1')
    with pytest.raises(BillingDisabledError):
        await service.cancel_subscription('subscription-1')
    with pytest.raises(BillingDisabledError):
        await service.catalog_price_strings()
    with pytest.raises(BillingDisabledError):
        await service.process_webhook('{malformed', {})

    assert provider_constructions == []
