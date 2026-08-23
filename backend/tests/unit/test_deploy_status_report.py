from __future__ import annotations

from pathlib import Path
import sys

BACKEND_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND_ROOT))

from scripts.deploy_status_report import (
    Finding,
    candidate_acceptance_tracker,
    load_json,
    parse_expected_traffic,
    render_candidate_acceptance_report,
    render_cloud_run_report,
)

FIXTURES = BACKEND_ROOT / 'tests' / 'fixtures' / 'deploy_status'


def test_cloud_run_report_requires_ready_revision_to_serve_expected_traffic() -> None:
    state = load_json(FIXTURES / 'cloud_run_traffic_problem.json')

    report, findings = render_cloud_run_report(
        state,
        services=['backend'],
        expected_traffic=parse_expected_traffic(['backend=backend-abc1234-1']),
        project='based-hardware',
        region='us-central1',
    )

    assert '`backend-old9999-1`=100%' in report
    assert (
        '`gcr.io/example/backend:abc1234@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`'
        in report
    )
    assert (
        Finding(
            'FAIL',
            'backend',
            'expected revision backend-abc1234-1 to serve 100% traffic, observed 0%',
        )
        in findings
    )


def test_cloud_run_report_fails_when_expected_service_is_missing() -> None:
    report, findings = render_cloud_run_report(
        {'services': []},
        services=['backend'],
        expected_traffic=parse_expected_traffic(['backend=backend-abc1234-1']),
    )

    assert '| `backend` | - | - | - | - | - | missing |' in report
    assert (
        Finding(
            'FAIL',
            'backend',
            'expected revision backend-abc1234-1 to serve 100% traffic, but service data is missing',
        )
        in findings
    )


def test_cloud_run_report_fails_when_describe_failed() -> None:
    report, findings = render_cloud_run_report(
        {'services': [], 'errors': [{'service': 'backend', 'exitCode': 1}]},
        services=['backend'],
        expected_traffic=parse_expected_traffic(['backend=backend-abc1234-1']),
    )

    assert '| `backend` | - | - | - | - | - | missing |' in report
    assert Finding('FAIL', 'backend', 'gcloud run services describe failed with exit code 1') in findings


def test_cloud_run_report_flags_spec_status_mismatch_and_emits_repair_command() -> None:
    state = load_json(FIXTURES / 'cloud_run_spec_status_mismatch.json')

    report, findings = render_cloud_run_report(
        state,
        services=['backend'],
        expected_traffic={},
        project='based-hardware',
        region='us-central1',
    )

    assert '`backend-failed-1`=100%' in report
    assert '`backend-good-1`=100%' in report
    assert (
        Finding(
            'FAIL',
            'backend',
            'spec.traffic (backend-failed-1) != status.traffic (backend-good-1); repair: '
            'gcloud run services update-traffic backend --project=based-hardware '
            '--region=us-central1 --to-revisions=backend-good-1=100 --quiet',
        )
        in findings
    )


def test_cloud_run_report_uses_state_project_region_when_cli_project_missing() -> None:
    state = load_json(FIXTURES / 'cloud_run_spec_status_mismatch.json')
    state = {**state, 'project': 'saved-project', 'region': 'europe-west1'}

    _, findings = render_cloud_run_report(
        state,
        services=['backend'],
        expected_traffic={},
    )

    assert (
        Finding(
            'FAIL',
            'backend',
            'spec.traffic (backend-failed-1) != status.traffic (backend-good-1); repair: '
            'gcloud run services update-traffic backend --project=saved-project '
            '--region=europe-west1 --to-revisions=backend-good-1=100 --quiet',
        )
        in findings
    )


def test_candidate_tracker_records_the_failed_contract_without_candidate_url(tmp_path) -> None:
    manifest = tmp_path / 'manifest.json'
    evidence = tmp_path / 'evidence.json'
    manifest.write_text('{"schema_version":1,"services":{"backend":{"contract":"memory_pipeline"}}}', encoding='utf-8')
    evidence.write_text(
        '{"schema_version":1,"status":"FAIL","checks":[{"service":"backend","contract":"memory_pipeline","status":"FAIL"}]}',
        encoding='utf-8',
    )

    tracker = candidate_acceptance_tracker(manifest_path=manifest, evidence_path=evidence)
    report, findings = render_candidate_acceptance_report(tracker)

    assert tracker['status'] == 'FAIL'
    assert tracker['failed_contract_category'] == 'memory_pipeline'
    assert 'candidate contract memory_pipeline failed before traffic promotion' in findings[0].message
    assert 'candidate.example' not in report


def test_candidate_tracker_marks_missing_evidence_not_run(tmp_path) -> None:
    manifest = tmp_path / 'manifest.json'
    manifest.write_text('{"schema_version":1,"services":{"backend":{"contract":"health"}}}', encoding='utf-8')

    tracker = candidate_acceptance_tracker(manifest_path=manifest, evidence_path=tmp_path / 'missing.json')

    assert tracker == {
        'schema_version': 1,
        'status': 'NOT_RUN',
        'failed_contract_category': None,
        'checks': [{'service': 'backend', 'contract': 'health', 'status': 'NOT_RUN'}],
    }
