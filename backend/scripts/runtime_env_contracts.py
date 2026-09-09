"""Focused deployment subcontracts for canonical backend runtime environments."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, cast

ConfigDict = dict[str, Any]

_LITERAL_ENV = {
    'ACCOUNT_DELETION_DISPATCH_MODE': 'cloud_tasks',
    'ACCOUNT_DELETION_TASKS_QUEUE': 'account-deletion',
    'ACCOUNT_DELETION_TASKS_LOCATION': 'us-west1',
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
_DEV_BETA_RELEASE_SECRET_BINDINGS = {
    'ADMIN_KEY': {'secret': 'ADMIN_KEY', 'version_env_var': 'ADMIN_KEY_VERSION'},
    'BETA_PROMOTION_TOKEN': {
        'secret': 'BETA_PROMOTION_TOKEN',
        'version_env_var': 'BETA_PROMOTION_TOKEN_VERSION',
    },
    'GITHUB_TOKEN': {'secret': 'GITHUB_TOKEN', 'version_env_var': 'GITHUB_TOKEN_VERSION'},
}


@dataclass(frozen=True)
class ValidationError:
    scope: str
    message: str


def validate_runtime_env_contracts(env: str, env_config: ConfigDict) -> list[ValidationError]:
    """Validate the focused runtime contracts owned by this helper boundary."""
    return [
        *validate_account_deletion_dispatch_contract(env, env_config),
        *_validate_dev_beta_runtime_contract(env, env_config),
    ]


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

    for name, expected_value in _LITERAL_ENV.items():
        entry = _as_config_dict(entries.get(name))
        if entry is None:
            errors.append(ValidationError(scope, f'missing required account-deletion env {name}'))
        elif str(entry.get('value', '')) != expected_value:
            errors.append(ValidationError(scope, f'account-deletion env {name} must be literal {expected_value!r}'))

    project_entry = _as_config_dict(entries.get('ACCOUNT_DELETION_TASKS_PROJECT'))
    if project_entry is None:
        errors.append(ValidationError(scope, 'missing required account-deletion env ACCOUNT_DELETION_TASKS_PROJECT'))
    elif project_entry.get('env_var') != 'GCP_PROJECT_ID':
        errors.append(
            ValidationError(
                scope,
                'account-deletion env ACCOUNT_DELETION_TASKS_PROJECT must bind $GCP_PROJECT_ID',
            )
        )

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


def _validate_dev_beta_runtime_contract(env: str, env_config: ConfigDict) -> list[ValidationError]:
    if env != 'dev':
        return []

    scope = 'dev/cloud_run/backend'
    services = _as_config_dict((_as_config_dict(env_config.get('cloud_run')) or {}).get('services')) or {}
    backend = _as_config_dict(services.get('backend')) or {}
    env_map = _as_config_dict(backend.get('env')) or {}
    secrets = _as_config_dict(backend.get('secrets')) or {}
    errors: list[ValidationError] = []

    if env_map.get('INTENTIVE_HOSTED_PARTICIPANT_UIDS') != {
        'env_var': 'INTENTIVE_HOSTED_PARTICIPANT_UIDS',
        'category': 'access_control',
    }:
        errors.append(
            ValidationError(
                scope,
                'INTENTIVE_HOSTED_PARTICIPANT_UIDS must bind the environment-owned input of the same name',
            )
        )
    if env_map.get('ADMIN_KEY_AUTH_ENABLED') != {'value': 'false', 'category': 'access_control'}:
        errors.append(ValidationError(scope, "hosted Beta ADMIN_KEY impersonation must be literal 'false'"))
    if env_map.get('OMI_PARITY_PACK_CAPTURE') != {'value': '0', 'category': 'replay_capture'}:
        errors.append(ValidationError(scope, "hosted Beta parity capture must be literal '0'"))
    for name in ('OMI_PARITY_PACK_ALLOWED_PRINCIPALS', 'OMI_PARITY_PACK_ROOT'):
        if name in env_map:
            errors.append(ValidationError(scope, f'hosted Beta parity capture must not declare {name}'))

    for name, expected_binding in _DEV_BETA_RELEASE_SECRET_BINDINGS.items():
        if secrets.get(name) != expected_binding:
            errors.append(
                ValidationError(
                    scope,
                    f'{name} must bind Secret Manager {expected_binding["secret"]} '
                    f'through ${expected_binding["version_env_var"]}',
                )
            )
    return errors


def _as_config_dict(value: object) -> ConfigDict | None:
    return cast(ConfigDict, value) if isinstance(value, dict) else None
