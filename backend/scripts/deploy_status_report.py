#!/usr/bin/env python3
"""Read-only rollout/status report for the canonical backend Cloud Run service."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, cast

DEFAULT_REGION = 'us-central1'
DEFAULT_CLOUD_RUN_SERVICES = ('backend',)


@dataclass(frozen=True)
class Finding:
    severity: str
    scope: str
    message: str


@dataclass(frozen=True)
class CloudRunFetchError:
    service: str
    exit_code: int


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env', choices=('dev', 'prod'), required=True)
    parser.add_argument('--project', help='GCP project id for live Cloud Run reads.')
    parser.add_argument('--region', default=DEFAULT_REGION)
    parser.add_argument('--include-cloud-run', action='store_true')
    parser.add_argument('--cloud-run-service', action='append', dest='cloud_run_services')
    parser.add_argument('--expect-cloud-run-traffic', action='append', default=[], metavar='SERVICE=REVISION')
    parser.add_argument('--cloud-run-state', type=Path, help='Offline Cloud Run state JSON fixture.')
    parser.add_argument('--candidate-acceptance-manifest', type=Path)
    parser.add_argument('--candidate-acceptance-evidence', type=Path)
    parser.add_argument('--candidate-status-output', type=Path)
    args = parser.parse_args()

    services = cast(list[str], args.cloud_run_services or list(DEFAULT_CLOUD_RUN_SERVICES))
    if args.cloud_run_state:
        cloud_run_state = load_json(args.cloud_run_state)
    else:
        if not args.project:
            print('--project is required for live Cloud Run reads', file=sys.stderr)
            return 2
        cloud_run_state = fetch_cloud_run_state(project=args.project, region=args.region, services=services)
    section, findings = render_cloud_run_report(
        cloud_run_state,
        services=services,
        expected_traffic=parse_expected_traffic(args.expect_cloud_run_traffic),
        project=args.project or '',
        region=args.region,
    )
    sections = [section]
    candidate_tracker: dict[str, Any] | None = None
    if args.candidate_acceptance_manifest or args.candidate_acceptance_evidence:
        if not args.candidate_acceptance_manifest or not args.candidate_acceptance_evidence:
            print('candidate acceptance manifest and evidence must be supplied together', file=sys.stderr)
            return 2
        candidate_tracker = candidate_acceptance_tracker(
            manifest_path=args.candidate_acceptance_manifest,
            evidence_path=args.candidate_acceptance_evidence,
        )
        candidate_section, candidate_findings = render_candidate_acceptance_report(candidate_tracker)
        sections.append(candidate_section)
        findings.extend(candidate_findings)
    if args.candidate_status_output:
        if candidate_tracker is None:
            print('--candidate-status-output requires candidate acceptance manifest and evidence', file=sys.stderr)
            return 2
        write_candidate_tracker(args.candidate_status_output, candidate_tracker)
    print('\n\n'.join(sections))
    if findings:
        print('\nFindings')
        for finding in findings:
            print(f'- {finding.severity} [{finding.scope}] {finding.message}')
    return 1 if any(finding.severity == 'FAIL' for finding in findings) else 0


def candidate_acceptance_tracker(*, manifest_path: Path, evidence_path: Path) -> dict[str, Any]:
    try:
        manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
        services = manifest.get('services') if isinstance(manifest, Mapping) else None
        if manifest.get('schema_version') != 1 or not isinstance(services, Mapping):
            raise ValueError
        expected = {
            service: value.get('contract')
            for service, value in services.items()
            if isinstance(service, str) and isinstance(value, Mapping) and isinstance(value.get('contract'), str)
        }
        if not expected or len(expected) != len(services):
            raise ValueError
    except (OSError, ValueError, json.JSONDecodeError, AttributeError):
        return {'schema_version': 1, 'status': 'FAIL', 'failed_contract_category': 'configuration', 'checks': []}
    try:
        evidence = json.loads(evidence_path.read_text(encoding='utf-8'))
    except FileNotFoundError:
        return {
            'schema_version': 1,
            'status': 'NOT_RUN',
            'failed_contract_category': None,
            'checks': [
                {'service': service, 'contract': contract, 'status': 'NOT_RUN'}
                for service, contract in sorted(expected.items())
            ],
        }
    except (OSError, json.JSONDecodeError):
        return {'schema_version': 1, 'status': 'FAIL', 'failed_contract_category': 'configuration', 'checks': []}
    checks = evidence.get('checks') if isinstance(evidence, Mapping) else None
    normalized: list[dict[str, str]] = []
    for raw_check in checks if isinstance(checks, list) else []:
        if not isinstance(raw_check, Mapping):
            continue
        service, contract, status = raw_check.get('service'), raw_check.get('contract'), raw_check.get('status')
        if isinstance(service, str) and isinstance(contract, str) and status in {'PASS', 'FAIL', 'NOT_RUN'}:
            normalized.append({'service': service, 'contract': contract, 'status': cast(str, status)})
    expected_pairs = {(service, contract) for service, contract in expected.items()}
    actual_pairs = {(check['service'], check['contract']) for check in normalized}
    if actual_pairs != expected_pairs or len(actual_pairs) != len(normalized):
        return {
            'schema_version': 1,
            'status': 'FAIL',
            'failed_contract_category': 'configuration',
            'checks': normalized,
        }
    failed = next((check['contract'] for check in normalized if check['status'] == 'FAIL'), None)
    expected_status = 'PASS' if all(check['status'] == 'PASS' for check in normalized) else 'FAIL'
    if evidence.get('status') != expected_status:
        expected_status = 'FAIL'
        failed = 'configuration'
    return {
        'schema_version': 1,
        'status': expected_status,
        'failed_contract_category': failed,
        'checks': sorted(normalized, key=lambda check: check['service']),
    }


def render_candidate_acceptance_report(tracker: Mapping[str, Any]) -> tuple[str, list[Finding]]:
    lines = ['Cloud Run candidate acceptance', '| Service | Contract | Status |', '|---|---|---|']
    findings: list[Finding] = []
    raw_checks = tracker.get('checks')
    checks = raw_checks if isinstance(raw_checks, list) else []
    for check in checks:
        if not isinstance(check, Mapping):
            continue
        service = str(check.get('service') or '-')
        contract = str(check.get('contract') or '-')
        status = str(check.get('status') or 'FAIL')
        lines.append(f'| `{service}` | `{contract}` | {status} |')
        if status == 'FAIL':
            findings.append(Finding('FAIL', service, f'candidate contract {contract} failed before traffic promotion'))
    status = str(tracker.get('status') or 'FAIL')
    lines.extend(['', f'Overall candidate status: **{status}**'])
    if status == 'FAIL' and not findings:
        findings.append(Finding('FAIL', 'candidate-acceptance', 'candidate acceptance evidence is invalid'))
    return '\n'.join(lines), findings


def write_candidate_tracker(path: Path, tracker: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(tracker, indent=2, sort_keys=True) + '\n', encoding='utf-8')


def render_cloud_run_report(
    state: dict[str, Any],
    *,
    services: list[str],
    expected_traffic: dict[str, str],
    project: str = '',
    region: str = DEFAULT_REGION,
) -> tuple[str, list[Finding]]:
    project = project or str(state.get('project') or '')
    region = str(state.get('region') or region)
    service_map = normalize_cloud_run_services(state)
    fetch_errors = cloud_run_fetch_errors_by_service(state)
    lines = [
        'Cloud Run revision status',
        '| Service | Latest created | Latest ready | Spec traffic | Status traffic | Template image | Status |',
        '|---|---|---|---|---|---|---|',
    ]
    findings: list[Finding] = []
    for service_name in services:
        service = service_map.get(service_name)
        if not service:
            lines.append(f'| `{service_name}` | - | - | - | - | - | missing |')
            fetch_error = fetch_errors.get(service_name)
            if fetch_error:
                findings.append(
                    Finding(
                        'FAIL',
                        service_name,
                        f'gcloud run services describe failed with exit code {fetch_error.exit_code}',
                    )
                )
            elif service_name in expected_traffic:
                findings.append(
                    Finding(
                        'FAIL',
                        service_name,
                        f'expected revision {expected_traffic[service_name]} to serve 100% traffic, but service data is missing',
                    )
                )
            else:
                findings.append(Finding('WARN', service_name, 'Cloud Run service not found in report input'))
            continue
        status = cast(dict[str, Any], service.get('status') or {})
        spec = cast(dict[str, Any], service.get('spec') or {})
        latest_created = str(status.get('latestCreatedRevisionName') or '')
        latest_ready = str(status.get('latestReadyRevisionName') or '')
        status_traffic = cast(list[Any], status.get('traffic') or [])
        spec_traffic = cast(list[Any], spec.get('traffic') or [])
        findings.extend(
            traffic_spec_status_findings(
                service_name=service_name,
                spec_traffic=spec_traffic,
                status_traffic=status_traffic,
                project=project,
                region=region,
                latest_ready_revision=latest_ready,
            )
        )
        if latest_created and latest_ready != latest_created:
            findings.append(
                Finding(
                    'FAIL',
                    service_name,
                    f'latest created revision {latest_created} is not latest ready ({latest_ready or "missing"})',
                )
            )
        expected_revision = expected_traffic.get(service_name)
        if expected_revision:
            served = traffic_percent_for_revision(status_traffic, expected_revision)
            if served != 100:
                findings.append(
                    Finding(
                        'FAIL',
                        service_name,
                        f'expected revision {expected_revision} to serve 100% traffic, observed {served}%',
                    )
                )
            elif latest_ready != expected_revision:
                findings.append(
                    Finding(
                        'FAIL',
                        service_name,
                        f'expected served revision {expected_revision} to be latest ready, observed {latest_ready or "missing"}',
                    )
                )
        ready_status = 'ok' if latest_ready and latest_ready == latest_created else 'not-ready'
        lines.append(
            f'| `{service_name}` | `{latest_created or "-"}` | `{latest_ready or "-"}` | '
            f'{format_cloud_run_traffic(spec_traffic)} | {format_cloud_run_traffic(status_traffic)} | '
            f'`{cloud_run_image(service)}` | {ready_status} |'
        )
    return '\n'.join(lines), findings


def traffic_spec_status_findings(
    *,
    service_name: str,
    spec_traffic: list[Any],
    status_traffic: list[Any],
    project: str,
    region: str,
    latest_ready_revision: str = '',
) -> list[Finding]:
    spec_revision = primary_traffic_revision(spec_traffic, fallback_revision=latest_ready_revision)
    status_revision = primary_traffic_revision(status_traffic, fallback_revision=latest_ready_revision)
    if spec_revision and status_revision and spec_revision != status_revision:
        repair = format_traffic_repair_command(
            service=service_name, revision=status_revision, project=project, region=region
        )
        return [
            Finding(
                'FAIL',
                service_name,
                f'spec.traffic ({spec_revision}) != status.traffic ({status_revision}); repair: {repair}',
            )
        ]
    return []


def primary_traffic_revision(traffic: list[Any], *, fallback_revision: str = '') -> str | None:
    for target in traffic:
        if not isinstance(target, dict) or int(target.get('percent') or 0) != 100:
            continue
        revision = target.get('revisionName')
        if isinstance(revision, str) and revision:
            return revision
        if target.get('latestRevision') and fallback_revision:
            return fallback_revision
    return None


def format_traffic_repair_command(*, service: str, revision: str, project: str, region: str) -> str:
    project_flag = f' --project={project}' if project else ''
    return f'gcloud run services update-traffic {service}{project_flag} --region={region} --to-revisions={revision}=100 --quiet'


def fetch_cloud_run_state(*, project: str, region: str, services: list[str]) -> dict[str, Any]:
    fetched: list[Any] = []
    errors: list[dict[str, Any]] = []
    for service in services:
        result = subprocess.run(
            [
                'gcloud',
                'run',
                'services',
                'describe',
                service,
                f'--project={project}',
                f'--region={region}',
                '--format=json',
            ],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            fetched.append(json.loads(result.stdout))
        else:
            errors.append({'service': service, 'exitCode': result.returncode})
    return {'services': fetched, 'errors': errors, 'project': project, 'region': region}


def load_json(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    with path.open('r', encoding='utf-8') as handle:
        loaded = json.load(handle)
    if not isinstance(loaded, dict):
        raise ValueError(f'{path} must contain a JSON object')
    return cast(dict[str, Any], loaded)


def parse_expected_traffic(entries: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for entry in entries:
        if '=' not in entry:
            raise ValueError(f'expected traffic entry must be SERVICE=REVISION: {entry}')
        service, revision = entry.split('=', 1)
        result[service] = revision
    return result


def normalize_cloud_run_services(state: dict[str, Any]) -> dict[str, dict[str, Any]]:
    raw_services = state.get('services', [])
    if isinstance(raw_services, dict):
        return {str(name): service for name, service in raw_services.items() if isinstance(service, dict)}
    if not isinstance(raw_services, list):
        return {}
    result: dict[str, dict[str, Any]] = {}
    for service in raw_services:
        if not isinstance(service, dict):
            continue
        name = str(cast(dict[str, Any], service).get('metadata', {}).get('name') or '')
        if name:
            result[name] = cast(dict[str, Any], service)
    return result


def cloud_run_fetch_errors_by_service(state: dict[str, Any]) -> dict[str, CloudRunFetchError]:
    raw_errors = state.get('errors') or state.get('fetchErrors')
    result: dict[str, CloudRunFetchError] = {}
    for error in raw_errors if isinstance(raw_errors, list) else []:
        if not isinstance(error, dict):
            continue
        service = str(error.get('service') or '')
        if service:
            result[service] = CloudRunFetchError(service=service, exit_code=int(error.get('exitCode') or 1))
    return result


def cloud_run_image(service: dict[str, Any]) -> str:
    containers = cast(list[Any], service.get('spec', {}).get('template', {}).get('spec', {}).get('containers') or [])
    if not containers or not isinstance(containers[0], dict):
        return '-'
    first = cast(dict[str, Any], containers[0])
    image = str(first.get('image') or '-')
    digest = first.get('imageDigest') or service.get('status', {}).get('imageDigest')
    return f'{image}@{digest}' if isinstance(digest, str) and digest else image


def format_cloud_run_traffic(traffic: Any) -> str:
    if not isinstance(traffic, list) or not traffic:
        return '-'
    parts: list[str] = []
    for target in traffic:
        if not isinstance(target, dict):
            continue
        revision = target.get('revisionName') or ('latest' if target.get('latestRevision') else '-')
        parts.append(f'`{revision}`={int(target.get("percent") or 0)}%')
    return ', '.join(parts) or '-'


def traffic_percent_for_revision(traffic: Any, revision: str) -> int:
    if not isinstance(traffic, list):
        return 0
    return sum(
        int(target.get('percent') or 0)
        for target in traffic
        if isinstance(target, dict) and target.get('revisionName') == revision
    )


if __name__ == '__main__':
    raise SystemExit(main())
