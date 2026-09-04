from __future__ import annotations

from copy import deepcopy
import json
import os
from pathlib import Path
import sys
from unittest.mock import patch

import pytest
import yaml

BACKEND_ROOT = Path(__file__).resolve().parents[2]
ROOT = BACKEND_ROOT.parent
sys.path.insert(0, str(BACKEND_ROOT))

from scripts.backend_workflow_contract import validate_immutable_deploy_contract  # noqa: E402
from scripts.cloud_run_deployment_identity import (  # noqa: E402
    CloudRunServiceUrlError,
    resolve_external_value,
    validate_assigned_service_url,
)


@pytest.mark.parametrize('filename', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_repository_workflow_has_one_digest_from_build_through_smoke_and_deploy(filename: str) -> None:
    path = ROOT / '.github/workflows' / filename
    workflow = yaml.safe_load(path.read_text(encoding='utf-8'))

    assert validate_immutable_deploy_contract(str(path), workflow) == []


@pytest.mark.parametrize('filename', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_repository_workflow_deploys_environment_owned_cloud_run_service(filename: str) -> None:
    path = ROOT / '.github/workflows' / filename
    workflow = yaml.safe_load(path.read_text(encoding='utf-8'))
    deploy = workflow['jobs']['deploy']

    assert deploy['env']['BACKEND_CLOUD_RUN_SERVICE'] == '${{ vars.BACKEND_CLOUD_RUN_SERVICE }}'
    assert deploy['env']['CLOUD_RUN_SERVICE'] == '${{ vars.BACKEND_CLOUD_RUN_SERVICE }}'
    deploy_step = next(
        step for step in deploy['steps'] if step.get('uses') == 'google-github-actions/deploy-cloudrun@v3'
    )
    assert deploy_step['with']['service'] == '${{ env.CLOUD_RUN_SERVICE }}'

    deploy_text = path.read_text(encoding='utf-8')
    assert 'gcloud run services describe backend' not in deploy_text
    assert 'gcloud run services update-traffic backend' not in deploy_text


@pytest.mark.parametrize(
    ('filename', 'job_name'),
    [
        ('gcp_backend.yml', 'foundation-maintenance'),
        ('gcp_backend.yml', 'deploy'),
        ('gcp_backend_auto_dev.yml', 'deploy'),
    ],
)
def test_workflow_job_exports_manifest_deployment_binding_for_runtime_resolver(filename: str, job_name: str) -> None:
    workflow_path = ROOT / '.github/workflows' / filename
    workflow = yaml.safe_load(workflow_path.read_text(encoding='utf-8'))
    workflow_env = workflow['jobs'][job_name]['env']
    manifest = yaml.safe_load((BACKEND_ROOT / 'deploy/runtime_env.yaml').read_text(encoding='utf-8'))
    binding = manifest['environments']['dev']['cloud_run']['services']['backend']['deployment_name']
    resolved_job_env = {
        name: ('knowledge-athlete-dev' if value == '${{ vars.BACKEND_CLOUD_RUN_SERVICE }}' else str(value))
        for name, value in workflow_env.items()
    }

    with patch.dict(os.environ, resolved_job_env, clear=True):
        assert resolve_external_value('backend deployment_name', binding) == 'knowledge-athlete-dev'


@pytest.mark.parametrize('filename', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_tag_smoke_or_predeploy_service_discovery_mutations_fail_closed(filename: str) -> None:
    path = ROOT / '.github/workflows' / filename
    workflow = yaml.safe_load(path.read_text(encoding='utf-8'))

    mutable_smoke = deepcopy(workflow)
    smoke = next(
        step
        for step in mutable_smoke['jobs']['deploy']['steps']
        if step.get('name') == 'Verify published runtime image by digest'
    )
    smoke['run'] = smoke['run'].replace(
        '${{ steps.push-runtime-image.outputs.immutable_ref }}', '${{ steps.image-tag.outputs.image_ref }}'
    )
    assert 'backend runtime smoke must execute the published immutable digest' in validate_immutable_deploy_contract(
        str(path), mutable_smoke
    )

    stale_bootstrap = deepcopy(workflow)
    target = next(
        step
        for step in stale_bootstrap['jobs']['deploy']['steps']
        if step.get('name') == 'Resolve canonical account-deletion task target'
    )
    target['run'] += '\ngcloud run services describe backend\n'
    assert 'fresh service bootstrap must take its canonical URL from an explicit environment input' in (
        validate_immutable_deploy_contract(str(path), stale_bootstrap)
    )

    status_url_only = deepcopy(workflow)
    url_check = next(
        step
        for step in status_url_only['jobs']['deploy']['steps']
        if step.get('name') == 'Validate discovered canonical service URL'
    )
    url_check['run'] = '''
discovered="$(gcloud run services describe "$CLOUD_RUN_SERVICE" --format='value(status.url)')"
test "$discovered" = "$EXPECTED_BACKEND_URL"
'''
    assert 'the configured URL must be proven among the deployed service assigned URLs' in (
        validate_immutable_deploy_contract(str(path), status_url_only)
    )


def _service_document(*, assigned_urls: list[str], status_url: str) -> dict[str, object]:
    return {
        'metadata': {
            'name': 'knowledge-athlete-dev',
            'annotations': {'run.googleapis.com/urls': json.dumps(assigned_urls)},
        },
        'status': {'url': status_url},
    }


def test_configured_deterministic_url_accepts_cloud_run_hash_status_alias() -> None:
    deterministic_url = 'https://knowledge-athlete-dev-674306938907.us-west1.run.app'
    hash_alias = 'https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app'
    service_document = _service_document(
        assigned_urls=[deterministic_url, hash_alias],
        status_url=hash_alias,
    )

    assert validate_assigned_service_url(
        service_document,
        expected_service='knowledge-athlete-dev',
        expected_url=deterministic_url,
    ) == (deterministic_url, hash_alias)


def test_unassigned_configured_url_fails_closed() -> None:
    hash_alias = 'https://knowledge-athlete-dev-sbgrr24rwa-uw.a.run.app'
    service_document = _service_document(assigned_urls=[hash_alias], status_url=hash_alias)

    with pytest.raises(CloudRunServiceUrlError, match='configured canonical URL is not assigned'):
        validate_assigned_service_url(
            service_document,
            expected_service='knowledge-athlete-dev',
            expected_url='https://wrong-service-674306938907.us-west1.run.app',
        )


def test_workflow_contract_does_not_apply_to_unrelated_workflows() -> None:
    assert validate_immutable_deploy_contract('.github/workflows/backend-checks.yml', {'jobs': {}}) == []
