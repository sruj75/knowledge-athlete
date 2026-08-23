from __future__ import annotations

import json
from pathlib import Path

import pytest

from scripts import verify_backend_release_vector as verify

BACKEND_DIR = Path(__file__).resolve().parents[2]
REPO_DIR = BACKEND_DIR.parent
COMMIT_SHA = 'abcdef1234567890abcdef1234567890abcdef12'


def _expectation(*, environment: str = 'dev') -> verify.DeploymentExpectation:
    return verify.build_expectation(
        commit_sha=COMMIT_SHA,
        short_sha='abcdef1',
        deploy_run_id='12345',
        deploy_run_attempt='2',
        project='based-hardware-dev' if environment == 'dev' else 'based-hardware',
        region='us-central1',
        environment=environment,
    )


def _service_document(
    expectation: verify.DeploymentExpectation,
    *,
    traffic_percent: object = 100,
    latest_created: str | None = None,
    latest_ready: str | None = None,
    image: str | None = None,
    environment: str | None = None,
    timeout_seconds: int = 1500,
) -> dict:
    revision = expectation.revisions['backend']
    return {
        'spec': {
            'template': {
                'spec': {
                    'containers': [
                        {
                            'image': image or expectation.image,
                            'env': [{'name': 'OMI_ENV_STAGE', 'value': environment or expectation.environment}],
                        }
                    ],
                    'timeoutSeconds': timeout_seconds,
                }
            }
        },
        'status': {
            'latestCreatedRevisionName': latest_created or revision,
            'latestReadyRevisionName': latest_ready or revision,
            'traffic': [{'revisionName': revision, 'percent': traffic_percent}],
        },
    }


def _ready_revision_document(status: str = 'True') -> dict:
    return {'status': {'conditions': [{'type': 'Ready', 'status': status}]}}


def test_expectation_binds_one_backend_revision_to_commit_and_deploy_attempt() -> None:
    expectation = _expectation()

    assert expectation.image == 'gcr.io/based-hardware-dev/backend:abcdef1'
    assert expectation.revisions == {'backend': 'backend-abcdef1-12345-2'}
    assert expectation.environment == 'dev'


@pytest.mark.parametrize(
    ('kwargs', 'message'),
    [
        ({'commit_sha': 'not-a-sha'}, 'commit SHA'),
        ({'short_sha': '1234567'}, 'prefix'),
        ({'deploy_run_id': 'run'}, 'decimal integers'),
        ({'environment': 'stage'}, 'environment'),
    ],
)
def test_expectation_rejects_ambiguous_release_identity(kwargs: dict, message: str) -> None:
    arguments = {
        'commit_sha': COMMIT_SHA,
        'short_sha': 'abcdef1',
        'deploy_run_id': '12345',
        'deploy_run_attempt': '2',
        'project': 'based-hardware-dev',
        'region': 'us-central1',
        'environment': 'dev',
    }
    arguments.update(kwargs)

    with pytest.raises(ValueError, match=message):
        verify.build_expectation(**arguments)


def test_read_only_commands_query_only_canonical_backend() -> None:
    expectation = _expectation()
    serving = verify.build_read_only_commands(expectation)
    candidate = verify.build_read_only_commands(expectation, include_candidate_revisions=True)

    assert set(serving) == {'cloud_run/backend'}
    assert set(candidate) == {'cloud_run/backend', 'cloud_run_revision/backend'}
    verify.assert_commands_are_read_only(candidate)
    with pytest.raises(ValueError, match='not a read-only'):
        verify.assert_commands_are_read_only({'bad': ['gcloud', 'run', 'services', 'update', 'backend']})


def test_serving_evaluation_accepts_exact_backend_revision() -> None:
    expectation = _expectation()

    assert verify.evaluate(expectation, {'cloud_run/backend': _service_document(expectation)}) == []


def test_serving_evaluation_fails_closed_on_revision_image_traffic_timeout_or_environment() -> None:
    expectation = _expectation()
    document = _service_document(
        expectation,
        traffic_percent=0,
        latest_created='backend-stale',
        latest_ready='backend-stale',
        image='gcr.io/based-hardware-dev/backend:stale',
        environment='prod',
        timeout_seconds=60,
    )

    errors = verify.evaluate(expectation, {'cloud_run/backend': document})

    assert len(errors) == 6
    assert all(error.startswith('cloud_run/backend:') for error in errors)


@pytest.mark.parametrize('percent', [None, 0])
def test_candidate_evaluation_accepts_ready_zero_traffic_revision(percent: object) -> None:
    expectation = _expectation()
    documents = {
        'cloud_run/backend': _service_document(expectation, traffic_percent=percent),
        'cloud_run_revision/backend': _ready_revision_document(),
    }

    assert verify.evaluate(expectation, documents, require_serving_traffic=False) == []


@pytest.mark.parametrize(
    ('percent', 'message'),
    [
        (5, 'carries traffic before promotion'),
        (True, 'traffic allocation is ambiguous'),
        (-1, 'traffic allocation is ambiguous'),
    ],
)
def test_candidate_evaluation_rejects_unsafe_traffic(percent: object, message: str) -> None:
    expectation = _expectation()
    documents = {
        'cloud_run/backend': _service_document(expectation, traffic_percent=percent),
        'cloud_run_revision/backend': _ready_revision_document(),
    }

    assert any(message in error for error in verify.evaluate(expectation, documents, require_serving_traffic=False))


def test_candidate_evaluation_requires_ready_revision_document() -> None:
    expectation = _expectation()
    documents = {
        'cloud_run/backend': _service_document(expectation, traffic_percent=0),
        'cloud_run_revision/backend': _ready_revision_document('False'),
    }

    assert verify.evaluate(expectation, documents, require_serving_traffic=False) == [
        'cloud_run/backend: expected revision is not Ready'
    ]


def test_evidence_is_bounded_to_canonical_backend() -> None:
    expectation = _expectation(environment='prod')
    documents = {'cloud_run/backend': _service_document(expectation)}

    result = verify.evidence(expectation, documents, [])

    assert result['result'] == 'pass'
    assert result['release_vector']['cloud_run_revisions'] == {'backend': 'backend-abcdef1-12345-2'}
    assert set(result['cloud_run']) == {'backend'}
    assert 'gke' not in result


def test_main_writes_candidate_evidence_without_mutating_cloud(monkeypatch, tmp_path: Path) -> None:
    expectation = _expectation()
    documents = {
        'cloud_run/backend': _service_document(expectation, traffic_percent=0),
        'cloud_run_revision/backend': _ready_revision_document(),
    }
    evidence_path = tmp_path / 'release-vector.json'
    monkeypatch.setattr(verify, 'collect_documents', lambda _commands: documents)
    monkeypatch.setattr(
        'sys.argv',
        [
            'verify_backend_release_vector.py',
            '--commit-sha',
            COMMIT_SHA,
            '--short-sha',
            'abcdef1',
            '--deploy-run-id',
            '12345',
            '--deploy-run-attempt',
            '2',
            '--project',
            'based-hardware-dev',
            '--environment',
            'dev',
            '--candidate',
            '--evidence-path',
            str(evidence_path),
        ],
    )

    assert verify.main() == 0
    written = json.loads(evidence_path.read_text(encoding='utf-8'))
    assert written['result'] == 'pass'
    assert written['release_vector']['require_serving_traffic'] is False


def test_backend_workflows_verify_only_one_cloud_run_release_vector() -> None:
    for workflow_name in ('gcp_backend.yml', 'gcp_backend_auto_dev.yml'):
        workflow = (REPO_DIR / '.github' / 'workflows' / workflow_name).read_text(encoding='utf-8')
        assert 'verify_backend_release_vector.py' in workflow
        assert '--expect-cloud-run-traffic backend=' in workflow
        assert 'backend-sync' not in workflow
        assert 'backend-listen' not in workflow
        assert 'kubectl ' not in workflow
