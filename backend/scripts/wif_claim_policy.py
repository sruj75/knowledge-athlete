#!/usr/bin/env python3
"""Resolve and test the exact GitHub OIDC claim policy for one cloud principal."""

from __future__ import annotations

import argparse
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, cast

import yaml

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / 'backend/deploy/runtime_env.yaml'

_PRINCIPAL_BINDINGS = {
    'deploy': 'deploy_service_account',
    'firestore_readonly': 'firestore_readonly_service_account',
    'firestore_writer': 'firestore_writer_service_account',
}
_REPOSITORY_PATTERN = re.compile(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')
_WORKFLOW_PATH_PATTERN = re.compile(r'^\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$')


@dataclass(frozen=True)
class ClaimPolicy:
    environment: str
    principal: str
    service_account: str
    repository: str
    repository_id: str
    repository_owner_id: str
    ref: str
    workflow_refs: tuple[str, ...]


def load_manifest(path: Path = DEFAULT_MANIFEST) -> dict[str, Any]:
    loaded = yaml.safe_load(path.read_text(encoding='utf-8'))
    if not isinstance(loaded, dict):
        raise ValueError('runtime manifest must be a mapping')
    return cast(dict[str, Any], loaded)


def resolve_claim_policy(
    manifest: Mapping[str, Any],
    *,
    environment: str,
    principal: str,
    external_inputs: Mapping[str, str],
) -> ClaimPolicy:
    if principal not in _PRINCIPAL_BINDINGS:
        raise ValueError(f'unsupported WIF principal: {principal}')
    environments = _mapping(manifest.get('environments'), 'environments')
    env_config = _mapping(environments.get(environment), f'environment {environment}')
    foundation = _mapping(env_config.get('foundation'), f'{environment} foundation')
    wif = _mapping(foundation.get('wif'), f'{environment} WIF')
    claims = _mapping(wif.get('claims'), f'{environment} WIF claims')

    repository = _external(claims, 'repository', external_inputs)
    repository_id = _external(claims, 'repository_id', external_inputs)
    repository_owner_id = _external(claims, 'repository_owner_id', external_inputs)
    service_account = _external(wif, _PRINCIPAL_BINDINGS[principal], external_inputs)
    ref = _required_string(claims, 'ref')
    github_environment = _required_string(claims, 'environment')
    paths_by_principal = _mapping(claims.get('workflow_paths'), f'{environment} workflow paths')
    raw_paths = paths_by_principal.get(principal)
    if not isinstance(raw_paths, list) or not raw_paths:
        raise ValueError(f'{environment} WIF principal {principal} must allow at least one workflow')

    if not _REPOSITORY_PATTERN.fullmatch(repository):
        raise ValueError('GITHUB_REPOSITORY must be an exact owner/repository name')
    for name, value in (
        ('GITHUB_REPOSITORY_ID', repository_id),
        ('GITHUB_REPOSITORY_OWNER_ID', repository_owner_id),
    ):
        if not value.isdigit() or value == '0':
            raise ValueError(f'{name} must be a non-zero numeric GitHub ID')
    if not service_account.endswith('.iam.gserviceaccount.com') or any(char.isspace() for char in service_account):
        raise ValueError(f'{principal} service account must be an exact IAM service-account email')

    workflow_refs: list[str] = []
    for raw_path in raw_paths:
        if not isinstance(raw_path, str) or not _WORKFLOW_PATH_PATTERN.fullmatch(raw_path):
            raise ValueError(f'{environment} WIF workflow path must be exact: {raw_path!r}')
        workflow_refs.append(f'{repository}/{raw_path}@{ref}')
    if len(set(workflow_refs)) != len(workflow_refs):
        raise ValueError(f'{environment} WIF workflow paths must be unique')

    return ClaimPolicy(
        environment=github_environment,
        principal=principal,
        service_account=service_account,
        repository=repository,
        repository_id=repository_id,
        repository_owner_id=repository_owner_id,
        ref=ref,
        workflow_refs=tuple(workflow_refs),
    )


def claim_rejections(
    policy: ClaimPolicy,
    claims: Mapping[str, object],
    *,
    requested_service_account: str,
) -> list[str]:
    expected = {
        'repository': policy.repository,
        'repository_id': policy.repository_id,
        'repository_owner_id': policy.repository_owner_id,
        'ref': policy.ref,
        'environment': policy.environment,
    }
    rejected = [name for name, value in expected.items() if claims.get(name) != value]
    if claims.get('workflow_ref') not in policy.workflow_refs:
        rejected.append('workflow_ref')
    if requested_service_account != policy.service_account:
        rejected.append('service_account')
    return rejected


def attribute_condition(policy: ClaimPolicy) -> str:
    workflow_clause = ' || '.join(f"assertion.workflow_ref=='{workflow_ref}'" for workflow_ref in policy.workflow_refs)
    return ' && '.join(
        (
            f"assertion.repository=='{policy.repository}'",
            f"assertion.repository_id=='{policy.repository_id}'",
            f"assertion.repository_owner_id=='{policy.repository_owner_id}'",
            f"assertion.ref=='{policy.ref}'",
            f"assertion.environment=='{policy.environment}'",
            f'({workflow_clause})',
        )
    )


def _mapping(value: object, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f'{label} must be a mapping')
    return cast(Mapping[str, Any], value)


def _required_string(parent: Mapping[str, Any], key: str) -> str:
    value = parent.get(key)
    if not isinstance(value, str) or not value:
        raise ValueError(f'{key} must be a non-empty string')
    return value


def _external(parent: Mapping[str, Any], key: str, external_inputs: Mapping[str, str]) -> str:
    binding = _mapping(parent.get(key), key)
    env_var = binding.get('env_var')
    if not isinstance(env_var, str) or not env_var:
        raise ValueError(f'{key} must name one external env input')
    value = external_inputs.get(env_var, '')
    if not value:
        raise ValueError(f'missing required WIF input {env_var}')
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env', choices=('dev', 'prod'), required=True)
    parser.add_argument('--principal', choices=tuple(_PRINCIPAL_BINDINGS), required=True)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()
    try:
        policy = resolve_claim_policy(
            load_manifest(args.manifest),
            environment=args.env,
            principal=args.principal,
            external_inputs=os.environ,
        )
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f'ERROR: {exc}')
        return 1
    print(
        json.dumps(
            {
                'environment': policy.environment,
                'principal': policy.principal,
                'service_account': policy.service_account,
                'attribute_condition': attribute_condition(policy),
            },
            sort_keys=True,
        )
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
