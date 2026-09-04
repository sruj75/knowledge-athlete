import json
from pathlib import Path
from types import SimpleNamespace

from scripts import run_dev_candidate_acceptance as acceptance


def test_checked_in_manifest_declares_exactly_the_dev_cloud_run_candidates():
    checks = acceptance.load_manifest(acceptance.DEFAULT_MANIFEST)

    assert [(check.service, check.contract) for check in checks] == [
        ('backend', 'health'),
    ]
    assert all('{base_url}' in check.command for check in checks)


def test_candidate_urls_require_a_complete_unique_https_mapping():
    expected = {'backend', 'backend-beta'}

    assert acceptance.parse_candidate_urls(
        ['backend=https://backend-candidate.example', 'backend-beta=https://beta-candidate.example'],
        expected_services=expected,
    ) == {
        'backend': 'https://backend-candidate.example',
        'backend-beta': 'https://beta-candidate.example',
    }

    for values in (
        ['backend=https://backend-candidate.example'],
        ['backend=https://backend-candidate.example', 'backend=https://other.example'],
        ['backend=http://backend-candidate.example', 'backend-beta=https://beta-candidate.example'],
    ):
        try:
            acceptance.parse_candidate_urls(values, expected_services=expected)
        except ValueError:
            pass
        else:
            raise AssertionError(f'expected invalid candidate map: {values}')


def test_checked_in_public_health_check_does_not_mint_cloud_run_identity(monkeypatch):
    [check] = acceptance.load_manifest(acceptance.DEFAULT_MANIFEST)
    captured = {}

    def fake_run(command, **kwargs):
        assert command[:3] != ['gcloud', 'auth', 'print-identity-token']
        captured['command'] = command
        captured['environment'] = kwargs['env']
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(acceptance.subprocess, 'run', fake_run)

    outcome = acceptance.run_check(
        check,
        base_url='https://candidate.example',
        audience='https://backend-service.example',
    )

    assert outcome == acceptance.CheckOutcome(service='backend', contract='health', status='PASS')
    assert captured['command'][-1] == 'https://candidate.example'
    assert acceptance.IDENTITY_TOKEN_ENV not in captured['environment']


def test_private_candidate_check_passes_oidc_only_to_the_child_environment(monkeypatch):
    check = acceptance.CandidateCheck(
        service='private-backend',
        contract='health',
        command=(
            'python3',
            'backend/scripts/smoke_cloud_run_health.py',
            '--base-url',
            '{base_url}',
            '--cloud-run-identity-token-env',
            acceptance.IDENTITY_TOKEN_ENV,
        ),
    )
    captured = {}
    monkeypatch.setattr(acceptance, 'mint_cloud_run_identity_token', lambda *, audience: f'token-for:{audience}')

    def fake_run(command, **kwargs):
        captured['command'] = command
        captured['environment'] = kwargs['env']
        return SimpleNamespace(returncode=0)

    monkeypatch.setattr(acceptance.subprocess, 'run', fake_run)

    outcome = acceptance.run_check(
        check,
        base_url='https://private-candidate.example',
        audience='https://private-backend-service.example',
    )

    assert outcome == acceptance.CheckOutcome(service='private-backend', contract='health', status='PASS')
    assert captured['environment'][acceptance.IDENTITY_TOKEN_ENV] == 'token-for:https://private-backend-service.example'
    assert 'token-for:' not in json.dumps(acceptance.evidence_document([outcome]))


def test_main_writes_redacted_failed_contract_evidence(monkeypatch, tmp_path, capsys):
    evidence_path = tmp_path / 'candidate.json'
    manifest = tmp_path / 'manifest.json'
    manifest.write_text(
        json.dumps(
            {
                'schema_version': 1,
                'services': {
                    'backend': {
                        'contract': 'health',
                        'command': ['python3', 'backend/scripts/smoke_cloud_run_health.py', '--base-url', '{base_url}'],
                    }
                },
            }
        ),
        encoding='utf-8',
    )
    monkeypatch.setattr(
        acceptance,
        'run_check',
        lambda check, *, base_url, audience: acceptance.CheckOutcome(check.service, check.contract, 'FAIL'),
    )

    assert (
        acceptance.main(
            [
                '--manifest',
                str(manifest),
                '--candidate',
                'backend=https://candidate.example',
                '--audience',
                'backend=https://backend-service.example',
                '--evidence-path',
                str(evidence_path),
            ]
        )
        == 1
    )

    evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    assert evidence == {
        'checks': [{'contract': 'health', 'service': 'backend', 'status': 'FAIL'}],
        'schema_version': 1,
        'status': 'FAIL',
    }
    assert 'candidate.example' not in capsys.readouterr().out


def test_failure_marks_later_manifest_contracts_not_run(monkeypatch, tmp_path):
    evidence_path = tmp_path / 'candidate.json'
    manifest = tmp_path / 'manifest.json'
    manifest.write_text(
        json.dumps(
            {
                'schema_version': 1,
                'services': {
                    'backend': {'contract': 'health', 'command': ['echo', '{base_url}']},
                    'backend-beta': {'contract': 'health', 'command': ['echo', '{base_url}']},
                },
            }
        ),
        encoding='utf-8',
    )
    monkeypatch.setattr(
        acceptance,
        'run_check',
        lambda check, *, base_url, audience: acceptance.CheckOutcome(check.service, check.contract, 'FAIL'),
    )

    assert (
        acceptance.main(
            [
                '--manifest',
                str(manifest),
                '--candidate',
                'backend=https://candidate.example',
                '--candidate',
                'backend-beta=https://beta.example',
                '--audience',
                'backend=https://backend-service.example',
                '--audience',
                'backend-beta=https://beta-service.example',
                '--evidence-path',
                str(evidence_path),
            ]
        )
        == 1
    )

    assert json.loads(evidence_path.read_text(encoding='utf-8'))['checks'] == [
        {'contract': 'health', 'service': 'backend', 'status': 'FAIL'},
        {'contract': 'health', 'service': 'backend-beta', 'status': 'NOT_RUN'},
    ]
