from __future__ import annotations

from collections.abc import Callable

import pytest
from fastapi import HTTPException
from starlette.requests import Request

from utils import cloud_tasks


CANONICAL_AUDIENCE = 'https://backend.example.test/v1/users/account-deletion-wipes/run'
CANONICAL_INVOKER = 'account-deletion@example.test'
LEGACY_AUDIENCE = 'https://backend-sync.example.test/v1/users/account-deletion-wipes/run'
LEGACY_INVOKER = 'legacy-account-deletion@example.test'


def _request(token: str) -> Request:
    return Request(
        {
            'type': 'http',
            'method': 'POST',
            'path': '/v1/users/account-deletion-wipes/run',
            'headers': [
                (b'authorization', f'Bearer {token}'.encode()),
                (b'x-cloudtasks-taskretrycount', b'2'),
            ],
        }
    )


@pytest.fixture(autouse=True)
def _task_identity_environment(monkeypatch: pytest.MonkeyPatch) -> None:
    values = {
        'OMI_ENV_STAGE': 'prod',
        'ACCOUNT_DELETION_DISPATCH_MODE': 'cloud_tasks',
        'ACCOUNT_DELETION_TASKS_PROJECT': 'project',
        'ACCOUNT_DELETION_TASKS_LOCATION': 'us-central1',
        'ACCOUNT_DELETION_TASKS_QUEUE': 'account-deletion',
        'ACCOUNT_DELETION_HANDLER_URL': CANONICAL_AUDIENCE,
        'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE': CANONICAL_AUDIENCE,
        'ACCOUNT_DELETION_TASKS_INVOKER_SA': CANONICAL_INVOKER,
        'ACCOUNT_DELETION_LEGACY_TASKS_OIDC_AUDIENCE': LEGACY_AUDIENCE,
        'ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA': LEGACY_INVOKER,
    }
    for name, value in values.items():
        monkeypatch.setenv(name, value)


def _install_token_verifier(
    monkeypatch: pytest.MonkeyPatch,
    verifier: Callable[[str, str], dict[str, object]],
) -> None:
    def verify(token: str, _request: object, audience: str) -> dict[str, object]:
        return verifier(token, audience)

    monkeypatch.setattr(cloud_tasks.id_token, 'verify_oauth2_token', verify)


def test_canonical_and_legacy_task_identities_are_both_exact(monkeypatch: pytest.MonkeyPatch) -> None:
    def verify(token: str, audience: str) -> dict[str, object]:
        if token == 'canonical' and audience == CANONICAL_AUDIENCE:
            return {'email': CANONICAL_INVOKER, 'email_verified': True}
        if token == 'legacy' and audience == LEGACY_AUDIENCE:
            return {'email': LEGACY_INVOKER, 'email_verified': True}
        raise ValueError('audience mismatch')

    _install_token_verifier(monkeypatch, verify)

    canonical = cloud_tasks.verify_account_deletion_cloud_tasks_oidc(_request('canonical'))
    legacy = cloud_tasks.verify_account_deletion_cloud_tasks_oidc(_request('legacy'))

    assert canonical == cloud_tasks.AccountDeletionTaskAuthentication(retry_count=2, audience='account_deletion')
    assert legacy == cloud_tasks.AccountDeletionTaskAuthentication(retry_count=2, audience='legacy')


@pytest.mark.parametrize(
    'claims',
    [
        {'email': 'wrong@example.test', 'email_verified': True},
        {'email': CANONICAL_INVOKER, 'email_verified': False},
    ],
)
def test_task_identity_rejects_wrong_or_unverified_signer(
    monkeypatch: pytest.MonkeyPatch, claims: dict[str, object]
) -> None:
    _install_token_verifier(monkeypatch, lambda _token, _audience: claims)

    with pytest.raises(HTTPException) as error:
        cloud_tasks.verify_account_deletion_cloud_tasks_oidc(_request('wrong'))

    assert error.value.status_code == 403


def test_task_identity_rejects_token_for_another_audience(monkeypatch: pytest.MonkeyPatch) -> None:
    def reject(_token: str, _audience: str) -> dict[str, object]:
        raise ValueError('token audience does not match')

    _install_token_verifier(monkeypatch, reject)

    with pytest.raises(HTTPException) as error:
        cloud_tasks.verify_account_deletion_cloud_tasks_oidc(_request('other-audience'))

    assert error.value.status_code == 403


@pytest.mark.parametrize(
    ('name', 'value', 'message'),
    [
        ('ACCOUNT_DELETION_HANDLER_URL', 'http://backend.example.test/run', 'must use HTTPS'),
        ('ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE', 'http://backend.example.test/run', 'must use HTTPS'),
        (
            'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE',
            'https://backend.example.test/another-path',
            'must exactly match',
        ),
    ],
)
def test_production_task_configuration_rejects_inexact_or_insecure_target(
    monkeypatch: pytest.MonkeyPatch, name: str, value: str, message: str
) -> None:
    monkeypatch.setenv(name, value)

    with pytest.raises(RuntimeError, match=message):
        cloud_tasks.validate_account_deletion_dispatch_configuration()


def test_production_task_configuration_requires_bounded_legacy_identity(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv('ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA')

    with pytest.raises(RuntimeError, match='ACCOUNT_DELETION_LEGACY_TASKS_INVOKER_SA'):
        cloud_tasks.validate_account_deletion_dispatch_configuration()
