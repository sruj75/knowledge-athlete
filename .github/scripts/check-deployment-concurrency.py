#!/usr/bin/env python3
"""Enforce serialization and phase ordering for persistent deploy writers."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = ROOT / 'backend'
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from scripts.firestore_workflow_policy import (  # noqa: E402
    has_direct_firestore_mutation,
    reconciliation_invocations,
)

WORKFLOWS = ROOT / '.github' / 'workflows'


@dataclass(frozen=True)
class LockContract:
    group: str


LOCK_CONTRACTS = {
    'gcp_backend.yml': LockContract('deploy-backend-stack-${{ github.event.inputs.environment }}'),
    'gcp_backend_auto_dev.yml': LockContract('deploy-backend-stack-development'),
    'gcp_firestore_indexes.yml': LockContract('deploy-backend-stack-${{ github.event.inputs.environment }}'),
}
FIRESTORE_SCHEMA_WRITERS = frozenset({'gcp_firestore_indexes.yml'})
WRITER_MARKERS = (
    'google-github-actions/deploy-cloudrun@',
    'gcloud run services update-traffic',
    'gcloud run services update ',
    'gcloud run deploy ',
    'gcloud run jobs deploy ',
    'gcloud run jobs update ',
)
AUTO_DEPLOY_ADMITTED_SHA = '${{ needs.firestore_readiness.outputs.admitted_sha }}'
RETIRED_BACKEND_TOPOLOGY_MARKERS = (
    'backend-sync',
    'backend-listen',
    'gcp_backend_listen_helm',
    'gcp_backend_pusher',
    'gcp_llm_gateway',
    'kubectl ',
    'helm upgrade',
)


class PolicyError(ValueError):
    pass


def parse_top_level_concurrency(text: str) -> dict[str, str] | None:
    lines = text.splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line == 'concurrency:')
    except StopIteration:
        return None
    fields: dict[str, str] = {}
    for line in lines[start + 1 :]:
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if not line.startswith(' '):
            break
        if line.startswith('  ') and not line.startswith('    ') and ':' in line:
            key, value = line.strip().split(':', 1)
            fields[key] = value.strip()
    return fields


def job_block(text: str, job: str) -> list[str] | None:
    lines = text.splitlines()
    try:
        start = next(index for index, line in enumerate(lines) if line == f'  {job}:')
    except StopIteration:
        return None
    block: list[str] = []
    for line in lines[start + 1 :]:
        if line and not line.startswith('    '):
            break
        block.append(line)
    return block


def deploy_job_steps(block: list[str]) -> list[list[str]]:
    steps: list[list[str]] = []
    index = 0
    while index < len(block):
        if block[index].startswith('      - '):
            start = index
            index += 1
            while index < len(block) and not block[index].startswith('      - '):
                index += 1
            steps.append(block[start:index])
        else:
            index += 1
    return steps


def step_name(step: list[str]) -> str | None:
    first = step[0].strip() if step else ''
    prefix = '- name:'
    return first[len(prefix) :].strip() if first.startswith(prefix) else None


def active_step_text(step: list[str]) -> str:
    return '\n'.join(line for line in step if not line.lstrip().startswith('#'))


def active_workflow_text(text: str) -> str:
    return '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('#'))


def workflow_steps(text: str) -> list[list[str]]:
    steps: list[list[str]] = []
    current: list[str] | None = None
    for line in text.splitlines():
        if line.startswith('      - '):
            if current is not None:
                steps.append(current)
            current = [line]
        elif current is not None:
            if line and len(line) - len(line.lstrip()) < 6:
                steps.append(current)
                current = None
            else:
                current.append(line)
    if current is not None:
        steps.append(current)
    return steps


def has_firestore_index_writer(text: str) -> bool:
    for step in workflow_steps(text):
        active = '\n'.join(line for line in step if not line.lstrip().startswith('#'))
        if has_direct_firestore_mutation(active):
            return True
        if any(invocation.mutates_schema for invocation in reconciliation_invocations(active)):
            return True
    return False


def is_persistent_writer(text: str) -> bool:
    return any(marker in text for marker in WRITER_MARKERS) or has_firestore_index_writer(text)


def validate_lock(name: str, text: str, contract: LockContract) -> list[str]:
    concurrency = parse_top_level_concurrency(text)
    if concurrency is None:
        return [f'{name}: missing workflow-level concurrency block']
    errors: list[str] = []
    if concurrency.get('group') != contract.group:
        errors.append(f'{name}: concurrency group must be {contract.group!r}, got {concurrency.get("group")!r}')
    if concurrency.get('cancel-in-progress') != 'false':
        errors.append(f'{name}: deploy locks must use cancel-in-progress: false')
    return errors


def _development_group(group: str) -> str:
    return group.replace('${{ github.event.inputs.environment }}', 'development')


def validate_shared_backend_lock(groups: dict[str, str]) -> list[str]:
    automatic = groups['gcp_backend_auto_dev.yml']
    errors: list[str] = []
    for manual in ('gcp_backend.yml', 'gcp_firestore_indexes.yml'):
        resolved = _development_group(groups[manual])
        if resolved != automatic:
            errors.append(f'{manual}: development lock {resolved!r} does not match {automatic!r}')
        if groups[manual].replace('${{ github.event.inputs.environment }}', 'prod') == resolved:
            errors.append(f'{manual}: development and prod must use different lock groups')
    return errors


def validate_firestore_schema_writers(workflows: dict[str, str]) -> list[str]:
    detected = {name for name, text in workflows.items() if has_firestore_index_writer(text)}
    return [
        *(
            f'{name}: Firestore schema writes have no canonical ownership'
            for name in sorted(detected - FIRESTORE_SCHEMA_WRITERS)
        ),
        *(
            f'{name}: canonical Firestore schema writer is missing'
            for name in sorted(FIRESTORE_SCHEMA_WRITERS - detected)
        ),
    ]


def validate_automatic_backend_lifecycle(workflows: dict[str, str]) -> list[str]:
    automatic = []
    for name, text in workflows.items():
        trigger = text.split('\njobs:', 1)[0]
        if 'group: deploy-backend-stack-development' in trigger and (
            'workflow_run:' in trigger or '\n  push:' in trigger
        ):
            automatic.append(name)
    return (
        []
        if automatic == ['gcp_backend_auto_dev.yml']
        else [
            f'automatic development backend deployment must be owned only by gcp_backend_auto_dev.yml, found {automatic!r}'
        ]
    )


def validate_backend_deploy(name: str, text: str) -> list[str]:
    block = job_block(text, 'deploy')
    if block is None:
        return [f'{name}: missing deploy job']
    steps = deploy_job_steps(block)

    required = (
        'Accept no-traffic Cloud Run candidate',
        'Capture Cloud Run pre-promotion traffic snapshot',
        'Shift Cloud Run traffic to validated revisions',
        'Verify serving backend release vector',
        'Restore Cloud Run traffic snapshot after failed promotion',
    )
    indexes = {
        required_name: next(
            (index for index, step in enumerate(steps) if step_name(step) == required_name),
            -1,
        )
        for required_name in required
    }
    errors = [f'{name}: missing {marker}' for marker, index in indexes.items() if index < 0]
    if not errors and list(indexes.values()) != sorted(indexes.values()):
        errors.append(f'{name}: candidate, snapshot, promotion, verification, and restore steps are out of order')

    named_steps = {step_name(step): active_step_text(step) for step in steps if step_name(step) is not None}
    evidence_prefix = 'dev-backend' if name == 'gcp_backend_auto_dev.yml' else 'backend'
    required_step_fragments = {
        'Accept no-traffic Cloud Run candidate': (
            'verify_backend_release_vector.py',
            '--candidate',
            '--commit-sha',
            '--short-sha',
            '--deploy-run-id',
            '--deploy-run-attempt',
            '--project',
            '--region',
            '--environment',
            f'artifacts/{evidence_prefix}-cloud-run-candidate-release-vector.json',
        ),
        'Capture Cloud Run pre-promotion traffic snapshot': (
            (
                'cloud_run_traffic_snapshot.py" capture'
                if name == 'gcp_backend.yml'
                else 'cloud_run_traffic_snapshot.py capture'
            ),
            '--project',
            '--region',
            '--service backend',
            f'--output artifacts/{evidence_prefix}-cloud-run-pre-promotion-traffic-snapshot.json',
        ),
        'Shift Cloud Run traffic to validated revisions': (
            'gcloud run services update-traffic backend',
            '--to-revisions=${{ steps.capture-backend-revision.outputs.revision }}=100',
            '--quiet',
        ),
        'Verify serving backend release vector': (
            'verify_backend_release_vector.py',
            '--commit-sha',
            '--short-sha',
            '--deploy-run-id',
            '--deploy-run-attempt',
            '--project',
            '--region',
            '--environment',
            f'artifacts/{evidence_prefix}-serving-release-vector.json',
        ),
        'Restore Cloud Run traffic snapshot after failed promotion': (
            'if: ${{ failure()',
            'steps.cloud-run-traffic-snapshot.outcome == \'success\'',
            'steps.shift-cloud-run-traffic.outcome == \'failure\'',
            'steps.verify-serving-release-vector.outcome == \'failure\'',
            (
                'cloud_run_traffic_snapshot.py" restore'
                if name == 'gcp_backend.yml'
                else 'cloud_run_traffic_snapshot.py restore'
            ),
            f'--snapshot artifacts/{evidence_prefix}-cloud-run-pre-promotion-traffic-snapshot.json',
            f'--evidence-path artifacts/{evidence_prefix}-cloud-run-traffic-restore.json',
        ),
    }
    for required_name, fragments in required_step_fragments.items():
        step_text = named_steps.get(required_name, '')
        for fragment in fragments:
            if fragment not in step_text:
                errors.append(f'{name}: {required_name} is missing active contract fragment {fragment!r}')

    cloud_run_deploy = named_steps.get('Deploy ${{ env.SERVICE }} to Cloud Run', '')
    for fragment in ('uses: google-github-actions/deploy-cloudrun@', 'service: ${{ env.SERVICE }}', '--timeout=1500s'):
        if fragment not in cloud_run_deploy:
            errors.append(f'{name}: canonical Cloud Run deploy is missing active contract fragment {fragment!r}')

    deploy_text = active_workflow_text('\n'.join(block))
    for marker in (
        'verify_backend_release_vector.py',
        'cloud_run_traffic_snapshot.py',
        '--service backend',
        'SHORT_SHA="$(git rev-parse --short=7 HEAD)"',
        'revision_suffix=${SHORT_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}',
    ):
        if marker not in deploy_text:
            errors.append(f'{name}: canonical backend deploy is missing {marker!r}')
    if name == 'gcp_backend_auto_dev.yml' and f'--commit-sha "{AUTO_DEPLOY_ADMITTED_SHA}"' not in deploy_text:
        errors.append(f'{name}: candidate verification is not bound to admitted source')
    active_text = active_workflow_text(text)
    for marker in RETIRED_BACKEND_TOPOLOGY_MARKERS:
        if marker in active_text:
            errors.append(f'{name}: retired backend topology marker is present: {marker}')
    return errors


def check_repository() -> list[str]:
    workflows = {
        path.name: path.read_text(encoding='utf-8')
        for pattern in ('*.yml', '*.yaml')
        for path in WORKFLOWS.glob(pattern)
    }
    errors = validate_firestore_schema_writers(workflows)
    errors.extend(validate_automatic_backend_lifecycle(workflows))

    detected = {name for name, text in workflows.items() if is_persistent_writer(text)}
    expected = set(LOCK_CONTRACTS)
    errors.extend(
        f'{name}: persistent deployment writer is missing from the lock policy' for name in sorted(detected - expected)
    )
    errors.extend(
        f'{name}: lock policy entry no longer contains a persistent writer' for name in sorted(expected - detected)
    )

    groups: dict[str, str] = {}
    for name, contract in LOCK_CONTRACTS.items():
        text = workflows.get(name)
        if text is None:
            errors.append(f'{name}: audited deploy workflow is missing')
            continue
        errors.extend(validate_lock(name, text, contract))
        concurrency = parse_top_level_concurrency(text)
        if concurrency and concurrency.get('group'):
            groups[name] = concurrency['group']
    if set(groups) == expected:
        errors.extend(validate_shared_backend_lock(groups))
    for name in ('gcp_backend.yml', 'gcp_backend_auto_dev.yml'):
        errors.extend(validate_backend_deploy(name, workflows.get(name, '')))
    return errors


def run_self_test() -> None:
    fixture = """name: fixture
concurrency:
  group: shared
  cancel-in-progress: false
jobs:
  deploy:
    steps:
      - uses: google-github-actions/deploy-cloudrun@v3
"""
    assert validate_lock('fixture.yml', fixture, LockContract('shared')) == []
    assert is_persistent_writer(fixture)
    assert not is_persistent_writer(
        'jobs:\n  verify:\n    steps:\n      - run: python3 backend/scripts/reconcile_firestore_indexes.py --check-only\n'
    )
    assert is_persistent_writer(
        'jobs:\n  deploy:\n    steps:\n      - run: python3 backend/scripts/reconcile_firestore_indexes.py --provision-missing\n'
    )
    if not validate_lock(
        'fixture.yml', fixture.replace('cancel-in-progress: false', 'cancel-in-progress: true'), LockContract('shared')
    ):
        raise PolicyError('cancel-in-progress mutation escaped the lock contract')

    backend_fixture = """name: fixture
jobs:
  deploy:
    steps:
      - name: Prepare immutable revision
        run: |
          SHORT_SHA="$(git rev-parse --short=7 HEAD)"
          echo 'revision_suffix=${SHORT_SHA}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}'
      - name: Deploy ${{ env.SERVICE }} to Cloud Run
        uses: google-github-actions/deploy-cloudrun@v3
        with:
          service: ${{ env.SERVICE }}
          flags: --timeout=1500s
      - name: Accept no-traffic Cloud Run candidate
        run: |
          python3 backend/scripts/verify_backend_release_vector.py --candidate \\
            --commit-sha "${{ needs.firestore_readiness.outputs.admitted_sha }}" --short-sha abcdef0 \\
            --deploy-run-id 1 --deploy-run-attempt 1 --project project --region region \\
            --environment dev --evidence-path artifacts/dev-backend-cloud-run-candidate-release-vector.json
      - name: Capture Cloud Run pre-promotion traffic snapshot
        run: |
          python3 backend/scripts/cloud_run_traffic_snapshot.py capture --project project --region region \\
            --service backend --output artifacts/dev-backend-cloud-run-pre-promotion-traffic-snapshot.json
      - name: Shift Cloud Run traffic to validated revisions
        run: gcloud run services update-traffic backend --to-revisions=${{ steps.capture-backend-revision.outputs.revision }}=100 --quiet
      - name: Verify serving backend release vector
        run: |
          python3 backend/scripts/verify_backend_release_vector.py \\
            --commit-sha "${{ needs.firestore_readiness.outputs.admitted_sha }}" --short-sha abcdef0 \\
            --deploy-run-id 1 --deploy-run-attempt 1 --project project --region region \\
            --environment dev --evidence-path artifacts/dev-backend-serving-release-vector.json
      - name: Restore Cloud Run traffic snapshot after failed promotion
        if: ${{ failure() && steps.cloud-run-traffic-snapshot.outcome == 'success' && (steps.shift-cloud-run-traffic.outcome == 'failure' || steps.verify-serving-release-vector.outcome == 'failure') }}
        run: |
          python3 backend/scripts/cloud_run_traffic_snapshot.py restore \\
            --snapshot artifacts/dev-backend-cloud-run-pre-promotion-traffic-snapshot.json \\
            --evidence-path artifacts/dev-backend-cloud-run-traffic-restore.json
"""
    if validate_backend_deploy('gcp_backend_auto_dev.yml', backend_fixture):
        raise PolicyError('safe backend deploy fixture does not satisfy the narrowed lifecycle contract')
    mutations = (
        ('verify_backend_release_vector.py --candidate', 'verify_backend_release_vector.py'),
        ('--service backend', '--service backend-sync'),
        ('if: ${{ failure()', 'if: ${{ always()'),
        ('--evidence-path artifacts/dev-backend-serving-release-vector.json', '# serving evidence removed'),
        ('--timeout=1500s', '--timeout=300s'),
    )
    for expected, replacement in mutations:
        mutated = backend_fixture.replace(expected, replacement, 1)
        if not validate_backend_deploy('gcp_backend_auto_dev.yml', mutated):
            raise PolicyError(f'backend deploy mutation escaped the lifecycle contract: {expected}')


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--self-test', action='store_true')
    args = parser.parse_args()
    if args.self_test:
        run_self_test()
        print('deployment concurrency policy self-test OK')
        return 0
    errors = check_repository()
    if errors:
        for error in errors:
            print(f'FAIL: {error}')
        return 1
    print(f'deployment concurrency policy OK ({len(LOCK_CONTRACTS)} persistent writers)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
