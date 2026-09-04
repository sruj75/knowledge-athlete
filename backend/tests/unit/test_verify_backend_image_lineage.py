from __future__ import annotations

import os
from pathlib import Path
import subprocess

import pytest
import yaml

from scripts import verify_backend_image_lineage as lineage

ROOT = Path(__file__).resolve().parents[3]
REPOSITORY = 'gcr.io/example/backend'
INDEX_DIGEST = 'sha256:' + '1' * 64
RUNTIME_DIGEST = 'sha256:' + '2' * 64


def _index(*, architecture: str = 'amd64') -> dict[str, object]:
    return {
        'schemaVersion': 2,
        'mediaType': 'application/vnd.oci.image.index.v1+json',
        'manifests': [
            {
                'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                'digest': RUNTIME_DIGEST,
                'platform': {'architecture': architecture, 'os': 'linux'},
            },
            {
                'mediaType': 'application/vnd.oci.image.manifest.v1+json',
                'digest': 'sha256:' + '3' * 64,
                'annotations': {'vnd.docker.reference.type': 'attestation-manifest'},
                'platform': {'architecture': 'unknown', 'os': 'unknown'},
            },
        ],
    }


def test_accepts_index_platform_child_and_emits_canonical_fields() -> None:
    evidence = lineage.verify_lineage(
        build_image_reference=f'{REPOSITORY}@{INDEX_DIGEST}',
        runtime_image_reference=f'{REPOSITORY}@{RUNTIME_DIGEST}',
        manifest=_index(),
    )

    assert evidence['oci_index_digest'] == INDEX_DIGEST
    assert evidence['platform_digest'] == RUNTIME_DIGEST
    assert evidence['lineage']['kind'] == 'image-index-platform-child'


def test_accepts_direct_manifest_only_at_the_same_digest() -> None:
    manifest = {'schemaVersion': 2, 'mediaType': 'application/vnd.oci.image.manifest.v1+json'}
    evidence = lineage.verify_lineage(
        build_image_reference=f'{REPOSITORY}@{INDEX_DIGEST}',
        runtime_image_reference=f'{REPOSITORY}@{INDEX_DIGEST}',
        manifest=manifest,
    )

    assert evidence['lineage']['kind'] == 'direct-image-manifest'


@pytest.mark.parametrize('workflow_name', ['gcp_backend.yml', 'gcp_backend_auto_dev.yml'])
def test_capture_step_emits_an_untagged_immutable_reference_accepted_by_lineage_validator(
    workflow_name: str, tmp_path: Path
) -> None:
    workflow = yaml.safe_load((ROOT / '.github/workflows' / workflow_name).read_text(encoding='utf-8'))
    capture = next(
        step for step in workflow['jobs']['deploy']['steps'] if step.get('name') == 'Capture immutable runtime image'
    )
    tagged_image = f'{REPOSITORY}:abc1234'
    script = (
        capture['run']
        .replace('${{ steps.image-tag.outputs.image_ref }}', tagged_image)
        .replace('${{ steps.image-tag.outputs.repository }}', REPOSITORY)
        .replace('${{ steps.build-runtime-image.outputs.digest }}', INDEX_DIGEST)
    )
    output = tmp_path / 'github-output'

    result = subprocess.run(
        ['bash', '-c', script],
        check=False,
        capture_output=True,
        text=True,
        env={**os.environ, 'GITHUB_OUTPUT': str(output)},
    )

    assert result.returncode == 0, result.stderr
    values = dict(line.split('=', 1) for line in output.read_text(encoding='utf-8').splitlines())
    evidence = lineage.verify_lineage(
        build_image_reference=values['immutable_ref'],
        runtime_image_reference=values['immutable_ref'],
        manifest={'schemaVersion': 2, 'mediaType': 'application/vnd.oci.image.manifest.v1+json'},
    )
    assert evidence['build_image']['reference'] == f'{REPOSITORY}@{INDEX_DIGEST}'


@pytest.mark.parametrize(
    ('runtime_reference', 'manifest', 'message'),
    [
        (f'{REPOSITORY}:latest', _index(), 'exact sha256 digest'),
        (f'{REPOSITORY}@{INDEX_DIGEST}', _index(), 'selects'),
        (f'{REPOSITORY}@{RUNTIME_DIGEST}', _index(architecture='arm64'), 'exactly one linux/amd64'),
    ],
)
def test_rejects_mutable_stale_or_wrong_platform_runtime(
    runtime_reference: str, manifest: dict[str, object], message: str
) -> None:
    with pytest.raises(lineage.LineageError, match=message):
        lineage.verify_lineage(
            build_image_reference=f'{REPOSITORY}@{INDEX_DIGEST}',
            runtime_image_reference=runtime_reference,
            manifest=manifest,
        )


def test_canonical_workflows_bind_candidate_evidence_to_the_runtime_platform_digest() -> None:
    for workflow_name in ('gcp_backend.yml', 'gcp_backend_auto_dev.yml'):
        workflow = (ROOT / '.github/workflows' / workflow_name).read_text(encoding='utf-8')

        assert 'verify_backend_image_lineage.py' in workflow
        assert "--format='value(status.imageDigest)'" in workflow
        assert '--expected-image-digest="${{ steps.verify-image-lineage.outputs.runtime_digest }}"' in workflow
        assert 'us-west1-docker.pkg.dev' in workflow
        assert '${{ vars.ARTIFACT_REGISTRY_REPOSITORY }}' in workflow
        assert 'full_sha=' in workflow
        assert '${{ steps.image-tag.outputs.full_sha }}' in workflow
        assert '${{ steps.push-runtime-image.outputs.immutable_ref }}' in workflow
        assert 'gcr.io/' not in workflow
        assert ':latest' not in workflow
