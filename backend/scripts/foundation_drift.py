#!/usr/bin/env python3
"""Compare the retained backend foundation with sanitized live GCP descriptions."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Callable, Mapping, Sequence, cast

import yaml

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / 'backend/deploy/runtime_env.yaml'
JsonValue = dict[str, Any] | list[Any]
Runner = Callable[[Sequence[str]], JsonValue]


def expected_foundation(
    manifest: Mapping[str, Any], *, environment: str, external_inputs: Mapping[str, str]
) -> dict[str, Any]:
    environments = _mapping(manifest.get('environments'), 'environments')
    env_config = _mapping(environments.get(environment), environment)
    foundation = _mapping(env_config.get('foundation'), f'{environment} foundation')
    resolved = _resolve(foundation, external_inputs)
    if not isinstance(resolved, dict):
        raise ValueError('resolved foundation must be a mapping')
    return cast(dict[str, Any], resolved)


def collect_live_foundation(
    expected: Mapping[str, Any], *, project: str, runner: Runner | None = None
) -> dict[str, Any]:
    run = runner or _run_json
    network = _mapping(expected.get('network'), 'network')
    psa = _mapping(network.get('private_service_access'), 'private_service_access')
    redis = _mapping(expected.get('redis'), 'redis')
    firestore = _mapping(expected.get('firestore'), 'firestore')
    gcs = _mapping(expected.get('gcs'), 'gcs')
    tasks = _mapping(_mapping(expected.get('tasks'), 'tasks').get('queue'), 'tasks queue')
    registry = _mapping(expected.get('artifact_registry'), 'artifact_registry')
    logging = _mapping(expected.get('logging'), 'logging')
    alerts = _mapping(expected.get('alerts'), 'alerts')
    budget = _mapping(expected.get('budget'), 'budget')
    region = _string(network.get('region'), 'network region')

    network_doc = _object(
        run(
            (
                'gcloud',
                'compute',
                'networks',
                'describe',
                _string(network.get('vpc'), 'vpc'),
                '--project',
                project,
                '--format=json',
            )
        )
    )
    subnet_doc = _object(
        run(
            (
                'gcloud',
                'compute',
                'networks',
                'subnets',
                'describe',
                _string(network.get('subnet'), 'subnet'),
                '--region',
                region,
                '--project',
                project,
                '--format=json',
            )
        )
    )
    range_doc = _object(
        run(
            (
                'gcloud',
                'compute',
                'addresses',
                'describe',
                _string(psa.get('range_name'), 'private-service range'),
                '--global',
                '--project',
                project,
                '--format=json',
            )
        )
    )
    prefix = int(range_doc.get('prefixLength') or 0)
    range_cidr = str(ipaddress.ip_network(f"{range_doc.get('address')}/{prefix}", strict=False))

    redis_doc = _object(
        run(
            (
                'gcloud',
                'redis',
                'instances',
                'describe',
                _string(redis.get('instance_name'), 'Redis instance'),
                '--region',
                region,
                '--project',
                project,
                '--format=json',
            )
        )
    )
    firestore_doc = _object(
        run(
            (
                'gcloud',
                'firestore',
                'databases',
                'describe',
                f"--database={_string(firestore.get('database'), 'Firestore database')}",
                '--project',
                _string(firestore.get('project'), 'Firestore project'),
                '--format=json',
            )
        )
    )
    bucket_doc = _object(
        run(
            (
                'gcloud',
                'storage',
                'buckets',
                'describe',
                f"gs://{_string(gcs.get('bucket'), 'GCS bucket')}",
                '--project',
                project,
                '--format=json',
            )
        )
    )
    queue_doc = _object(
        run(
            (
                'gcloud',
                'tasks',
                'queues',
                'describe',
                _string(tasks.get('name'), 'tasks queue'),
                '--location',
                _string(tasks.get('location'), 'tasks location'),
                '--project',
                project,
                '--format=json',
            )
        )
    )
    registry_doc = _object(
        run(
            (
                'gcloud',
                'artifacts',
                'repositories',
                'describe',
                _string(registry.get('repository'), 'artifact repository'),
                '--location',
                _string(registry.get('location'), 'artifact location'),
                '--project',
                project,
                '--format=json',
            )
        )
    )
    logging_doc = _object(
        run(
            (
                'gcloud',
                'logging',
                'buckets',
                'describe',
                _string(logging.get('bucket'), 'logging bucket'),
                '--location=global',
                '--project',
                project,
                '--format=json',
            )
        )
    )
    alert_docs = _array(run(('gcloud', 'monitoring', 'policies', 'list', '--project', project, '--format=json')))
    budget_docs = _array(
        run(
            (
                'gcloud',
                'billing',
                'budgets',
                'list',
                f"--billing-account={_string(budget.get('billing_account'), 'billing account')}",
                '--format=json',
            )
        )
    )

    network_name = _leaf(network_doc.get('name'))
    authorized_network = _leaf(redis_doc.get('authorizedNetwork'))
    iam = _mapping(bucket_doc.get('iamConfiguration'), 'bucket IAM configuration')
    ubla = _mapping(iam.get('uniformBucketLevelAccess'), 'bucket uniform access')
    selected_budget = next(
        (
            item
            for item in budget_docs
            if isinstance(item, Mapping) and item.get('displayName') == f'backend-{environment_name(expected)}'
        ),
        None,
    )
    return {
        'network': {
            'region': _leaf(subnet_doc.get('region')),
            'vpc': network_name,
            'subnet': _leaf(subnet_doc.get('name')),
            'private_service_access': {
                'range_name': _leaf(range_doc.get('name')),
                'range_cidr': range_cidr,
                'purpose': range_doc.get('purpose'),
                'status': range_doc.get('status'),
            },
        },
        'redis': {
            'instance_name': _leaf(redis_doc.get('name')),
            'region': _leaf(redis_doc.get('locationId')),
            'tier': redis_doc.get('tier'),
            'memory_gib': redis_doc.get('memorySizeGb'),
            'private_service_access': redis_doc.get('connectMode') == 'PRIVATE_SERVICE_ACCESS'
            and authorized_network == network_name,
            'auth': redis_doc.get('authEnabled'),
            'transit_encryption': redis_doc.get('transitEncryptionMode'),
        },
        'firestore': {
            'project': _resource_segment(firestore_doc.get('name'), 'projects'),
            'database': _leaf(firestore_doc.get('name')),
        },
        'gcs': {
            'bucket': _leaf(bucket_doc.get('name')),
            'location': str(bucket_doc.get('location') or '').lower(),
            'uniform_bucket_level_access': ubla.get('enabled'),
            'public_access_prevention': iam.get('publicAccessPrevention'),
        },
        'tasks': {
            'queue': {
                'name': _leaf(queue_doc.get('name')),
                'location': _resource_segment(queue_doc.get('name'), 'locations'),
                'max_concurrent_dispatches': (_mapping(queue_doc.get('rateLimits'), 'queue rate limits')).get(
                    'maxConcurrentDispatches'
                ),
                'max_attempts': (_mapping(queue_doc.get('retryConfig'), 'queue retry config')).get('maxAttempts'),
            }
        },
        'artifact_registry': {
            'repository': _leaf(registry_doc.get('name')),
            'location': _resource_segment(registry_doc.get('name'), 'locations'),
            'format': registry_doc.get('format'),
        },
        'logging': {
            'bucket': _leaf(logging_doc.get('name')),
            'retention_days': logging_doc.get('retentionDays'),
        },
        'alerts': {
            'policies': sorted(str(item.get('displayName')) for item in alert_docs if isinstance(item, Mapping))
        },
        'budget': _normalize_budget(selected_budget),
    }


def expected_observable_foundation(expected: Mapping[str, Any]) -> dict[str, Any]:
    network = _mapping(expected.get('network'), 'network')
    psa = _mapping(network.get('private_service_access'), 'private_service_access')
    firestore = _mapping(expected.get('firestore'), 'firestore')
    gcs = _mapping(expected.get('gcs'), 'gcs')
    queue = _mapping(_mapping(expected.get('tasks'), 'tasks').get('queue'), 'queue')
    registry = _mapping(expected.get('artifact_registry'), 'artifact_registry')
    logging = _mapping(expected.get('logging'), 'logging')
    alerts = _mapping(expected.get('alerts'), 'alerts')
    budget = _mapping(expected.get('budget'), 'budget')
    return {
        'network': {
            'region': network.get('region'),
            'vpc': network.get('vpc'),
            'subnet': network.get('subnet'),
            'private_service_access': {
                'range_name': psa.get('range_name'),
                'range_cidr': str(ipaddress.ip_network(_string(psa.get('range_cidr'), 'private-service CIDR'))),
                'purpose': 'VPC_PEERING',
                'status': 'RESERVED',
            },
        },
        'redis': dict(_mapping(expected.get('redis'), 'redis')),
        'firestore': {'project': firestore.get('project'), 'database': firestore.get('database')},
        'gcs': {
            'bucket': gcs.get('bucket'),
            'location': gcs.get('location'),
            'uniform_bucket_level_access': gcs.get('uniform_bucket_level_access'),
            'public_access_prevention': gcs.get('public_access_prevention'),
        },
        'tasks': {
            'queue': {
                'name': queue.get('name'),
                'location': queue.get('location'),
                'max_concurrent_dispatches': queue.get('max_concurrent_dispatches'),
                'max_attempts': queue.get('max_attempts'),
            }
        },
        'artifact_registry': {
            'repository': registry.get('repository'),
            'location': registry.get('location'),
            'format': registry.get('format'),
        },
        'logging': {'bucket': logging.get('bucket'), 'retention_days': logging.get('retention_days')},
        'alerts': {'policies': sorted(cast(list[str], alerts.get('policies') or []))},
        'budget': {
            'amount': str(budget.get('amount')),
            'currency': budget.get('currency'),
            'thresholds': budget.get('thresholds'),
        },
    }


def drift_paths(expected: object, actual: object, *, path: str = '') -> list[str]:
    if isinstance(expected, Mapping) and isinstance(actual, Mapping):
        errors: list[str] = []
        for key in sorted(set(expected) | set(actual)):
            child = f'{path}.{key}' if path else str(key)
            if key not in expected or key not in actual:
                errors.append(child)
            else:
                errors.extend(drift_paths(expected[key], actual[key], path=child))
        return errors
    return [] if expected == actual else [path]


def environment_name(expected: Mapping[str, Any]) -> str:
    redis = _mapping(expected.get('redis'), 'redis')
    return 'development' if redis.get('tier') == 'BASIC' else 'prod'


def _normalize_budget(value: object) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        return {}
    amount = _mapping(value.get('amount'), 'budget amount')
    specified = _mapping(amount.get('specifiedAmount'), 'budget specified amount')
    rules = value.get('thresholdRules')
    return {
        'amount': str(specified.get('units') or ''),
        'currency': specified.get('currencyCode'),
        'thresholds': (
            sorted(item.get('thresholdPercent') for item in rules if isinstance(item, Mapping))
            if isinstance(rules, list)
            else []
        ),
    }


def _resolve(value: object, external_inputs: Mapping[str, str]) -> object:
    if isinstance(value, Mapping):
        env_var = value.get('env_var')
        if isinstance(env_var, str):
            resolved = external_inputs.get(env_var, '')
            if not resolved:
                raise ValueError(f'missing required foundation input {env_var}')
            return resolved
        return {str(key): _resolve(nested, external_inputs) for key, nested in value.items()}
    if isinstance(value, list):
        return [_resolve(item, external_inputs) for item in value]
    return value


def _run_json(command: Sequence[str]) -> JsonValue:
    result = subprocess.run(command, check=True, capture_output=True, text=True)
    value = json.loads(result.stdout)
    if not isinstance(value, (dict, list)):
        raise ValueError(f'{command[0]} returned a non-container JSON value')
    return cast(JsonValue, value)


def _mapping(value: object, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f'{label} must be a mapping')
    return cast(Mapping[str, Any], value)


def _object(value: JsonValue) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError('gcloud describe must return a JSON object')
    return value


def _array(value: JsonValue) -> list[Any]:
    if not isinstance(value, list):
        raise ValueError('gcloud list must return a JSON array')
    return value


def _string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f'{label} must be a non-empty string')
    return value


def _leaf(value: object) -> str:
    return str(value or '').rstrip('/').rsplit('/', 1)[-1]


def _resource_segment(value: object, segment: str) -> str:
    parts = str(value or '').split('/')
    try:
        return parts[parts.index(segment) + 1]
    except (ValueError, IndexError):
        return ''


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env', choices=('dev', 'prod'), required=True)
    parser.add_argument('--manifest', type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument('--state', type=Path)
    parser.add_argument('--check-live', action='store_true')
    args = parser.parse_args()
    if bool(args.state) == bool(args.check_live):
        parser.error('select exactly one of --state or --check-live')
    try:
        manifest = yaml.safe_load(args.manifest.read_text(encoding='utf-8'))
        if not isinstance(manifest, Mapping):
            raise ValueError('runtime manifest must be a mapping')
        expected = expected_foundation(manifest, environment=args.env, external_inputs=os.environ)
        wanted = expected_observable_foundation(expected)
        actual = (
            collect_live_foundation(expected, project=os.environ.get('GCP_PROJECT_ID', ''))
            if args.check_live
            else json.loads(args.state.read_text(encoding='utf-8'))
        )
        paths = drift_paths(wanted, actual)
    except (OSError, ValueError, subprocess.CalledProcessError, json.JSONDecodeError, yaml.YAMLError) as exc:
        print(f'ERROR: foundation readiness failed: {exc}')
        return 1
    if paths:
        for path in paths:
            print(f'ERROR: foundation drift at {path}')
        return 1
    print(f'backend foundation matches the {args.env} manifest')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
