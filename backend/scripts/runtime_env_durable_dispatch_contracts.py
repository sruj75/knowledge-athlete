"""Deployment contract for the retained durable account-deletion task."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, cast

ConfigDict = dict[str, Any]

_LITERAL_ENV = {
    'ACCOUNT_DELETION_DISPATCH_MODE': 'cloud_tasks',
    'ACCOUNT_DELETION_TASKS_QUEUE': 'account-deletion',
    'ACCOUNT_DELETION_TASKS_LOCATION': 'us-central1',
    'ACCOUNT_DELETION_TASKS_MAX_ATTEMPTS': '5',
    'HTTP_ACCOUNT_DELETION_WIPE_RUN_TIMEOUT': '1500',
}
_DYNAMIC_ENV = frozenset(
    {
        'ACCOUNT_DELETION_HANDLER_URL',
        'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE',
        'ACCOUNT_DELETION_TASKS_INVOKER_SA',
        'ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE',
        'ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA',
    }
)


@dataclass(frozen=True)
class ValidationError:
    scope: str
    message: str


def validate_account_deletion_dispatch_contract(env: str, env_config: ConfigDict) -> list[ValidationError]:
    """Require one truthful account-deletion task binding on canonical backend."""
    errors: list[ValidationError] = []
    cloud_run = _as_config_dict(env_config.get('cloud_run')) or {}
    services = _as_config_dict(cloud_run.get('services')) or {}
    if set(services) != {'backend'}:
        errors.append(ValidationError(f'{env}/cloud_run', 'canonical backend must be the only Cloud Run service'))
    backend = _as_config_dict(services.get('backend')) or {}
    entries = _as_config_dict(backend.get('env')) or {}
    scope = f'{env}/cloud_run/backend'

    expected_literals = dict(_LITERAL_ENV)
    expected_literals['ACCOUNT_DELETION_TASKS_PROJECT'] = str(env_config.get('gcp_project', ''))
    for name, expected_value in expected_literals.items():
        entry = _as_config_dict(entries.get(name))
        if entry is None:
            errors.append(ValidationError(scope, f'missing required account-deletion env {name}'))
        elif str(entry.get('value', '')) != expected_value:
            errors.append(ValidationError(scope, f'account-deletion env {name} must be literal {expected_value!r}'))

    for name in _DYNAMIC_ENV:
        entry = _as_config_dict(entries.get(name))
        if entry is None:
            errors.append(ValidationError(scope, f'missing required account-deletion env {name}'))
        elif entry.get('env_var') != name:
            errors.append(ValidationError(scope, f'account-deletion env {name} must bind ${name}'))

    stale_names = sorted(name for name in entries if name.startswith(('SYNC_TASKS_', 'LISTEN_FINALIZATION_')))
    for name in stale_names:
        errors.append(ValidationError(scope, f'retired task setting is forbidden: {name}'))
    return errors


def _as_config_dict(value: object) -> ConfigDict | None:
    return cast(ConfigDict, value) if isinstance(value, dict) else None
