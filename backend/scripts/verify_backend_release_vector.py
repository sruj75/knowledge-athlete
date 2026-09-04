#!/usr/bin/env python3
"""Read-only verification of the canonical backend Cloud Run release vector."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Mapping, Sequence

CLOUD_RUN_TIMEOUT_SECONDS = 3600
IMMUTABLE_IMAGE_RE = re.compile(r'^us-west1-docker\.pkg\.dev/[^/]+/[^/]+/backend@sha256:[0-9a-f]{64}$')
CLOUD_RUN_SERVICE_RE = re.compile(r'^[a-z][a-z0-9-]{0,62}$')


@dataclass(frozen=True)
class DeploymentExpectation:
    commit_sha: str
    deploy_run_id: str
    deploy_run_attempt: str
    project: str
    region: str
    environment: str
    service_name: str
    image: str
    revisions: Mapping[str, str]


def build_expectation(
    *,
    commit_sha: str,
    deploy_run_id: str,
    deploy_run_attempt: str,
    project: str,
    region: str,
    environment: str,
    service_name: str,
    short_sha: str | None = None,
    expected_image: str | None = None,
) -> DeploymentExpectation:
    normalized_sha = commit_sha.strip().lower()
    if len(normalized_sha) < 7 or any(char not in '0123456789abcdef' for char in normalized_sha):
        raise ValueError('commit SHA must be a hexadecimal value with at least seven characters')
    if not deploy_run_id.isdigit() or not deploy_run_attempt.isdigit():
        raise ValueError('deploy run ID and attempt must be decimal integers')
    if environment not in {'dev', 'prod'}:
        raise ValueError("environment must be 'dev' or 'prod'")
    normalized_service_name = service_name.strip()
    if not CLOUD_RUN_SERVICE_RE.fullmatch(normalized_service_name):
        raise ValueError('service name must be a non-empty Cloud Run service identifier')
    if short_sha is not None:
        normalized_short = short_sha.strip().lower()
        if len(normalized_short) < 7 or any(char not in '0123456789abcdef' for char in normalized_short):
            raise ValueError('short SHA must be a hexadecimal value with at least seven characters')
        if not normalized_sha.startswith(normalized_short):
            raise ValueError('short SHA must be a prefix of the commit SHA')
        resolved_short_sha = normalized_short
    else:
        resolved_short_sha = normalized_sha[:7]
    if expected_image is None or not IMMUTABLE_IMAGE_RE.fullmatch(expected_image.strip()):
        raise ValueError(
            'expected image must be the canonical us-west1 Artifact Registry repository plus sha256 digest'
        )
    suffix = f'{resolved_short_sha}-{deploy_run_id}-{deploy_run_attempt}'
    return DeploymentExpectation(
        commit_sha=normalized_sha,
        deploy_run_id=deploy_run_id,
        deploy_run_attempt=deploy_run_attempt,
        project=project,
        region=region,
        environment=environment,
        service_name=normalized_service_name,
        image=expected_image.strip(),
        revisions={'backend': f'{normalized_service_name}-{suffix}'},
    )


def build_read_only_commands(
    expectation: DeploymentExpectation,
    *,
    include_candidate_revisions: bool = False,
) -> dict[str, list[str]]:
    commands = {
        'cloud_run/backend': [
            'gcloud',
            'run',
            'services',
            'describe',
            expectation.service_name,
            f'--project={expectation.project}',
            f'--region={expectation.region}',
            '--format=json',
        ]
    }
    if include_candidate_revisions:
        commands['cloud_run_revision/backend'] = [
            'gcloud',
            'run',
            'revisions',
            'describe',
            expectation.revisions['backend'],
            f'--project={expectation.project}',
            f'--region={expectation.region}',
            '--format=json',
        ]
    return commands


def assert_commands_are_read_only(commands: Mapping[str, Sequence[str]]) -> None:
    for name, command in commands.items():
        rendered = ' '.join(command)
        if not (
            rendered.startswith('gcloud run services describe ')
            or rendered.startswith('gcloud run revisions describe ')
        ):
            raise ValueError(f'{name} is not a read-only acceptance command: {rendered}')
        if any(term in f' {rendered} ' for term in (' apply ', ' delete ', ' patch ', ' create ', ' update ')):
            raise ValueError(f'{name} contains a mutating command: {rendered}')


def collect_documents(commands: Mapping[str, Sequence[str]]) -> dict[str, Mapping[str, Any]]:
    documents: dict[str, Mapping[str, Any]] = {}
    for name, command in commands.items():
        completed = subprocess.run(command, check=False, capture_output=True, text=True)
        if completed.returncode != 0:
            detail = completed.stderr.strip() or completed.stdout.strip() or f'exit code {completed.returncode}'
            raise RuntimeError(f'{name} query failed: {detail}')
        try:
            parsed = json.loads(completed.stdout)
        except json.JSONDecodeError as exc:
            raise RuntimeError(f'{name} did not return JSON: {exc}') from exc
        if not isinstance(parsed, Mapping):
            raise RuntimeError(f'{name} returned a non-object JSON document')
        documents[name] = parsed
    return documents


def evaluate(
    expectation: DeploymentExpectation,
    documents: Mapping[str, Mapping[str, Any]],
    *,
    require_serving_traffic: bool = True,
) -> list[str]:
    document = documents.get('cloud_run/backend')
    if document is None:
        return ['cloud_run/backend: result missing']
    return evaluate_cloud_run_service(
        'backend',
        expectation.revisions['backend'],
        expectation.image,
        document,
        expected_environment=expectation.environment,
        require_serving_traffic=require_serving_traffic,
        expected_revision_document=documents.get('cloud_run_revision/backend'),
    )


def evaluate_cloud_run_service(
    service: str,
    expected_revision: str,
    expected_image: str,
    document: Mapping[str, Any],
    *,
    expected_environment: str,
    require_serving_traffic: bool = True,
    expected_revision_document: Mapping[str, Any] | None = None,
) -> list[str]:
    status = _mapping(document.get('status'))
    template_spec = _mapping(_mapping(_mapping(document.get('spec')).get('template')).get('spec'))
    containers = _list(template_spec.get('containers'))
    image = _mapping(containers[0]).get('image') if containers else None
    traffic = _list(status.get('traffic'))
    expected_traffic = [entry for entry in traffic if _mapping(entry).get('revisionName') == expected_revision]
    errors: list[str] = []
    if status.get('latestCreatedRevisionName') != expected_revision:
        errors.append(f'cloud_run/{service}: latest created revision is not {expected_revision}')
    if require_serving_traffic:
        if status.get('latestReadyRevisionName') != expected_revision:
            errors.append(f'cloud_run/{service}: latest ready revision is not {expected_revision}')
    else:
        revision_status = _mapping(_mapping(expected_revision_document).get('status'))
        ready_condition = next(
            (
                condition
                for condition in _list(revision_status.get('conditions'))
                if _mapping(condition).get('type') == 'Ready'
            ),
            None,
        )
        if _mapping(ready_condition).get('status') != 'True':
            errors.append(f'cloud_run/{service}: expected revision is not Ready')
    if image != expected_image:
        errors.append(f'cloud_run/{service}: template image is not {expected_image}')
    if require_serving_traffic and (not expected_traffic or _mapping(expected_traffic[0]).get('percent') != 100):
        errors.append(f'cloud_run/{service}: expected revision does not receive 100% traffic')
    if not require_serving_traffic:
        for entry in expected_traffic:
            allocation = _effective_candidate_traffic_percent(_mapping(entry).get('percent'))
            if allocation is None:
                errors.append(f'cloud_run/{service}: candidate traffic allocation is ambiguous')
            elif allocation > 0:
                errors.append(f'cloud_run/{service}: expected revision carries traffic before promotion')
    timeout = template_spec.get('timeoutSeconds')
    if timeout != CLOUD_RUN_TIMEOUT_SECONDS:
        errors.append(f'cloud_run/{service}: timeoutSeconds must be {CLOUD_RUN_TIMEOUT_SECONDS}')
    if _container_env(containers).get('OMI_ENV_STAGE') != expected_environment:
        errors.append(f'cloud_run/{service}: OMI_ENV_STAGE must be {expected_environment}')
    return errors


def evidence(
    expectation: DeploymentExpectation,
    documents: Mapping[str, Mapping[str, Any]],
    errors: Sequence[str],
    *,
    require_serving_traffic: bool = True,
) -> dict[str, Any]:
    document = documents.get('cloud_run/backend', {})
    status = _mapping(document.get('status'))
    template_spec = _mapping(_mapping(_mapping(document.get('spec')).get('template')).get('spec'))
    containers = _list(template_spec.get('containers'))
    backend = {
        'expected_revision': expectation.revisions['backend'],
        'latest_created_revision': status.get('latestCreatedRevisionName'),
        'latest_ready_revision': status.get('latestReadyRevisionName'),
        'image': _mapping(containers[0]).get('image') if containers else None,
        'timeout_seconds': template_spec.get('timeoutSeconds'),
        'traffic': [
            {'revision': _mapping(entry).get('revisionName'), 'percent': _mapping(entry).get('percent')}
            for entry in _list(status.get('traffic'))
        ],
    }
    if not require_serving_traffic:
        revision_status = _mapping(_mapping(documents.get('cloud_run_revision/backend', {})).get('status'))
        ready_condition = next(
            (
                condition
                for condition in _list(revision_status.get('conditions'))
                if _mapping(condition).get('type') == 'Ready'
            ),
            {},
        )
        backend['expected_revision_ready'] = {
            'status': _mapping(ready_condition).get('status'),
            'reason': _mapping(ready_condition).get('reason'),
        }
    return {
        'scope': 'canonical backend deploy (read-only)',
        'release_vector': {
            'schema_version': 1,
            'commit_sha': expectation.commit_sha,
            'deploy_run_id': expectation.deploy_run_id,
            'deploy_run_attempt': expectation.deploy_run_attempt,
            'environment': expectation.environment,
            'cloud_run_service': expectation.service_name,
            'immutable_image': expectation.image,
            'cloud_run_revisions': dict(expectation.revisions),
            'require_serving_traffic': require_serving_traffic,
        },
        'cloud_run': {'backend': backend},
        'result': 'pass' if not errors else 'fail',
        'errors': list(errors),
    }


def _mapping(value: Any) -> Mapping[str, Any]:
    return value if isinstance(value, Mapping) else {}


def _list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _container_env(containers: Sequence[Any]) -> dict[str, str]:
    if not containers:
        return {}
    return {
        str(_mapping(entry).get('name')): str(_mapping(entry).get('value'))
        for entry in _list(_mapping(containers[0]).get('env'))
        if _mapping(entry).get('name') and 'value' in _mapping(entry)
    }


def _effective_candidate_traffic_percent(percent: Any) -> float | None:
    if percent is None:
        return 0.0
    if isinstance(percent, bool) or not isinstance(percent, (int, float)) or percent < 0:
        return None
    return float(percent)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--commit-sha', required=True)
    parser.add_argument('--short-sha')
    parser.add_argument('--deploy-run-id', required=True)
    parser.add_argument('--deploy-run-attempt', required=True)
    parser.add_argument('--project', required=True)
    parser.add_argument('--region', default='us-west1')
    parser.add_argument('--environment', choices=('dev', 'prod'), required=True)
    parser.add_argument('--service', required=True, help='Environment-owned Cloud Run service name.')
    parser.add_argument('--expected-image')
    parser.add_argument('--candidate', action='store_true')
    parser.add_argument('--evidence-path', type=Path)
    args = parser.parse_args()
    try:
        expectation = build_expectation(
            commit_sha=args.commit_sha,
            short_sha=args.short_sha,
            deploy_run_id=args.deploy_run_id,
            deploy_run_attempt=args.deploy_run_attempt,
            project=args.project,
            region=args.region,
            environment=args.environment,
            service_name=args.service,
            expected_image=args.expected_image,
        )
        commands = build_read_only_commands(expectation, include_candidate_revisions=args.candidate)
        assert_commands_are_read_only(commands)
        documents = collect_documents(commands)
        errors = evaluate(expectation, documents, require_serving_traffic=not args.candidate)
    except (RuntimeError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 1
    rendered = json.dumps(
        evidence(expectation, documents, errors, require_serving_traffic=not args.candidate),
        indent=2,
        sort_keys=True,
    )
    print(rendered)
    if args.evidence_path:
        args.evidence_path.parent.mkdir(parents=True, exist_ok=True)
        args.evidence_path.write_text(f'{rendered}\n', encoding='utf-8')
    return 1 if errors else 0


if __name__ == '__main__':
    raise SystemExit(main())
