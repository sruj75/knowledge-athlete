"""High-risk immutable-image and fresh-service contracts for backend deploy workflows."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Mapping, cast


def validate_immutable_deploy_contract(workflow_file: str, workflow: Mapping[str, Any]) -> list[str]:
    if Path(workflow_file).name not in {'gcp_backend.yml', 'gcp_backend_auto_dev.yml'}:
        return []
    jobs = _mapping(workflow.get('jobs'))
    deploy = _mapping(jobs.get('deploy'))
    deploy_env = _mapping(deploy.get('env'))
    steps = [_mapping(step) for step in _list(deploy.get('steps'))]
    named = {str(step.get('name')): (index, step) for index, step in enumerate(steps)}
    required_names = (
        'Build runtime image',
        'Capture immutable runtime image',
        'Verify published runtime image by digest',
        'Resolve canonical account-deletion task target',
        'Validate discovered canonical service URL',
    )
    errors: list[str] = []
    if any(name not in named for name in required_names):
        return ['backend deployment must retain build, digest, smoke, and canonical-URL control steps']

    build_index, build = named['Build runtime image']
    capture_index, capture = named['Capture immutable runtime image']
    smoke_index, smoke = named['Verify published runtime image by digest']
    target_index, target = named['Resolve canonical account-deletion task target']
    url_index, url_check = named['Validate discovered canonical service URL']
    deploy_steps = [
        (index, step)
        for index, step in enumerate(steps)
        if step.get('uses') == 'google-github-actions/deploy-cloudrun@v3'
        and _mapping(step.get('with')).get('service') == '${{ env.CLOUD_RUN_SERVICE }}'
    ]
    if len(deploy_steps) != 1:
        errors.append('backend workflow must deploy exactly one canonical Cloud Run service')
        return errors
    deploy_index, deploy_step = deploy_steps[0]
    if deploy_env.get('CLOUD_RUN_SERVICE') != '${{ vars.BACKEND_CLOUD_RUN_SERVICE }}':
        errors.append('backend workflow must bind the Cloud Run service through its deployment environment')

    build_with = _mapping(build.get('with'))
    capture_run = str(capture.get('run') or '')
    smoke_run = str(smoke.get('run') or '')
    deploy_with = _mapping(deploy_step.get('with'))
    if (
        build.get('id') != 'build-runtime-image'
        or build.get('uses') != 'docker/build-push-action@v7'
        or build_with.get('push') is not True
        or build_with.get('tags') != '${{ steps.image-tag.outputs.image_ref }}'
    ):
        errors.append('backend runtime image must be pushed once under the admitted full-SHA tag')
    if (
        capture.get('id') != 'push-runtime-image'
        or '${{ steps.build-runtime-image.outputs.digest }}' not in capture_run
        or 'sha256:[0-9a-f]{64}' not in capture_run
        or 'immutable_ref=${image}@${digest}' not in capture_run
    ):
        errors.append('backend image identity must come from the build action sha256 digest output')
    if (
        'image="${{ steps.push-runtime-image.outputs.immutable_ref }}"' not in smoke_run
        or 'docker pull "$image"' not in smoke_run
        or '--image "$image"' not in smoke_run
    ):
        errors.append('backend runtime smoke must execute the published immutable digest')
    if deploy_with.get('image') != '${{ steps.push-runtime-image.outputs.immutable_ref }}':
        errors.append('Cloud Run deployment must consume the same smoke-tested immutable digest')
    if not (build_index < capture_index < smoke_index < deploy_index < url_index):
        errors.append('backend digest capture and smoke must precede deploy and live URL validation')

    target_run = str(target.get('run') or '')
    target_env = _mapping(target.get('env'))
    url_run = str(url_check.get('run') or '')
    if (
        target_index >= deploy_index
        or target_env.get('BACKEND_CANONICAL_URL') != '${{ vars.BACKEND_CANONICAL_URL }}'
        or 'BACKEND_URL="${BACKEND_CANONICAL_URL%/}"' not in target_run
        or 'gcloud run services describe' in target_run
    ):
        errors.append('fresh service bootstrap must take its canonical URL from an explicit environment input')
    if (
        url_index <= deploy_index
        or 'gcloud run services describe' not in url_run
        or 'test "$discovered" = "$EXPECTED_BACKEND_URL"' not in url_run
    ):
        errors.append('the deployed service URL must be discovered and matched after service creation')
    return errors


def _mapping(value: object) -> dict[str, Any]:
    return cast(dict[str, Any], value) if isinstance(value, dict) else {}


def _list(value: object) -> list[Any]:
    return cast(list[Any], value) if isinstance(value, list) else []
