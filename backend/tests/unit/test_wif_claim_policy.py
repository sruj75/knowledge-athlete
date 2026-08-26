from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import sys

import pytest

BACKEND_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND_ROOT))

from scripts.wif_claim_policy import (  # noqa: E402
    attribute_condition,
    claim_rejections,
    load_manifest,
    resolve_claim_policy,
)


def inputs(env: str) -> dict[str, str]:
    return {
        'GITHUB_REPOSITORY': 'hypermind-ai/knowledge-athlete',
        'GITHUB_REPOSITORY_ID': '123456',
        'GITHUB_REPOSITORY_OWNER_ID': '654321',
        'GCP_DEPLOY_SERVICE_ACCOUNT': f'deploy-{env}@project-{env}.iam.gserviceaccount.com',
        'GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT': f'firestore-reader-{env}@project-{env}.iam.gserviceaccount.com',
        'GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT': f'firestore-writer-{env}@project-{env}.iam.gserviceaccount.com',
    }


def claims_for(policy) -> dict[str, str]:
    return {
        'repository': policy.repository,
        'repository_id': policy.repository_id,
        'repository_owner_id': policy.repository_owner_id,
        'ref': policy.ref,
        'environment': policy.environment,
        'workflow_ref': policy.workflow_refs[0],
    }


@pytest.mark.parametrize('environment', ['dev', 'prod'])
@pytest.mark.parametrize('principal', ['deploy', 'firestore_readonly', 'firestore_writer'])
def test_exact_claim_set_authorizes_only_the_matching_principal(environment: str, principal: str) -> None:
    policy = resolve_claim_policy(
        load_manifest(), environment=environment, principal=principal, external_inputs=inputs(environment)
    )

    assert claim_rejections(policy, claims_for(policy), requested_service_account=policy.service_account) == []


@pytest.mark.parametrize(
    ('claim_name', 'replacement'),
    [
        ('ref', 'refs/heads/feature'),
        ('repository', 'fork-owner/knowledge-athlete'),
        ('repository_id', '999999'),
        ('repository_owner_id', '999999'),
        ('environment', 'prod'),
        ('workflow_ref', 'hypermind-ai/knowledge-athlete/.github/workflows/untrusted.yml@refs/heads/main'),
    ],
)
def test_mutated_branch_fork_ids_environment_and_workflow_are_denied(claim_name: str, replacement: str) -> None:
    policy = resolve_claim_policy(load_manifest(), environment='dev', principal='deploy', external_inputs=inputs('dev'))
    claims = claims_for(policy)
    claims[claim_name] = replacement

    assert claim_name in claim_rejections(policy, claims, requested_service_account=policy.service_account)


def test_cross_environment_service_account_is_denied() -> None:
    dev_policy = resolve_claim_policy(
        load_manifest(), environment='dev', principal='deploy', external_inputs=inputs('dev')
    )
    prod_policy = resolve_claim_policy(
        load_manifest(), environment='prod', principal='deploy', external_inputs=inputs('prod')
    )

    assert claim_rejections(
        prod_policy,
        claims_for(prod_policy),
        requested_service_account=dev_policy.service_account,
    ) == ['service_account']


def test_prod_deploy_policy_rejects_the_automatic_development_workflow() -> None:
    policy = resolve_claim_policy(
        load_manifest(), environment='prod', principal='deploy', external_inputs=inputs('prod')
    )
    claims = claims_for(policy)
    claims['workflow_ref'] = 'hypermind-ai/knowledge-athlete/.github/workflows/gcp_backend_auto_dev.yml@refs/heads/main'

    assert claim_rejections(policy, claims, requested_service_account=policy.service_account) == ['workflow_ref']


def test_attribute_condition_names_every_immutable_and_workflow_claim() -> None:
    policy = resolve_claim_policy(load_manifest(), environment='dev', principal='deploy', external_inputs=inputs('dev'))

    condition = attribute_condition(policy)

    for claim in ('repository', 'repository_id', 'repository_owner_id', 'ref', 'environment', 'workflow_ref'):
        assert f'assertion.{claim}' in condition
    assert '*' not in condition


def test_policy_rejects_wildcard_or_missing_external_coordinates() -> None:
    manifest = deepcopy(load_manifest())
    manifest['environments']['dev']['foundation']['wif']['claims']['workflow_paths']['deploy'] = [
        '.github/workflows/*.yml'
    ]
    with pytest.raises(ValueError, match='workflow path must be exact'):
        resolve_claim_policy(manifest, environment='dev', principal='deploy', external_inputs=inputs('dev'))

    missing_id = inputs('dev')
    missing_id.pop('GITHUB_REPOSITORY_ID')
    with pytest.raises(ValueError, match='missing required WIF input GITHUB_REPOSITORY_ID'):
        resolve_claim_policy(load_manifest(), environment='dev', principal='deploy', external_inputs=missing_id)
