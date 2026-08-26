#!/usr/bin/env python3
"""Compare the retained backend foundation with sanitized live GCP descriptions."""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import subprocess
from pathlib import Path
from typing import Any, Callable, Iterable, Mapping, Sequence, cast

import yaml

try:
    from scripts.foundation_live_contract import (
        bucket_lifecycle_rules as _bucket_lifecycle_rules,
        budget_notification_channels as _budget_notification_channels,
        cleanup_delete_policies as _cleanup_delete_policies,
        cloud_run_environment as _cloud_run_environment,
        cloud_run_service_account as _cloud_run_service_account,
        csv_values as _csv_values,
        expected_alerts as _expected_alerts,
        external_logging_sinks as _external_logging_sinks,
        member_role_grants as _member_role_grants,
        normalize_alerts as _normalize_alerts,
        normalize_budget as _normalize_budget,
        provider_parts as _provider_parts,
        role_grants as _role_grants,
        url_host as _url_host,
        wif_policies as _wif_policies,
    )
except ModuleNotFoundError:  # Direct script execution places backend/scripts on sys.path.
    from foundation_live_contract import (  # type: ignore[no-redef]
        bucket_lifecycle_rules as _bucket_lifecycle_rules,
        budget_notification_channels as _budget_notification_channels,
        cleanup_delete_policies as _cleanup_delete_policies,
        cloud_run_environment as _cloud_run_environment,
        cloud_run_service_account as _cloud_run_service_account,
        csv_values as _csv_values,
        expected_alerts as _expected_alerts,
        external_logging_sinks as _external_logging_sinks,
        member_role_grants as _member_role_grants,
        normalize_alerts as _normalize_alerts,
        normalize_budget as _normalize_budget,
        provider_parts as _provider_parts,
        role_grants as _role_grants,
        url_host as _url_host,
        wif_policies as _wif_policies,
    )

try:
    from scripts.wif_claim_policy import (
        provider_attribute_condition,
        provider_attribute_mapping,
        workflow_principal_member,
    )
except ModuleNotFoundError:  # Direct script execution places backend/scripts on sys.path.
    from wif_claim_policy import (  # type: ignore[no-redef]
        provider_attribute_condition,
        provider_attribute_mapping,
        workflow_principal_member,
    )

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
    wif = _mapping(expected.get('wif'), 'wif')
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

    provider_resource = _string(wif.get('provider'), 'WIF provider')
    provider_project, provider_pool, provider_name = _provider_parts(provider_resource)
    provider_doc = _object(
        run(
            (
                'gcloud',
                'iam',
                'workload-identity-pools',
                'providers',
                'describe',
                provider_name,
                '--workload-identity-pool',
                provider_pool,
                '--location=global',
                '--project',
                provider_project,
                '--format=json',
            )
        )
    )
    wif_policies = _wif_policies(wif)
    wif_policy_docs = {
        policy.principal: _object(
            run(
                (
                    'gcloud',
                    'iam',
                    'service-accounts',
                    'get-iam-policy',
                    policy.service_account,
                    '--project',
                    project,
                    '--format=json',
                )
            )
        )
        for policy in wif_policies
    }
    project_iam_doc = _object(
        run(
            (
                'gcloud',
                'projects',
                'get-iam-policy',
                project,
                '--format=json',
            )
        )
    )

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
    bucket_iam_doc = _object(
        run(
            (
                'gcloud',
                'storage',
                'buckets',
                'get-iam-policy',
                f"gs://{_string(gcs.get('bucket'), 'GCS bucket')}",
                '--project',
                project,
                '--format=json',
            )
        )
    )
    runtime_service_account = _string(gcs.get('signing_service_account'), 'GCS signing service account')
    runtime_service_account_iam = _object(
        run(
            (
                'gcloud',
                'iam',
                'service-accounts',
                'get-iam-policy',
                runtime_service_account,
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
    queue_iam_doc = _object(
        run(
            (
                'gcloud',
                'tasks',
                'queues',
                'get-iam-policy',
                _string(tasks.get('name'), 'tasks queue'),
                '--location',
                _string(tasks.get('location'), 'tasks location'),
                '--project',
                project,
                '--format=json',
            )
        )
    )
    task_signer = _string(tasks.get('oidc_signer'), 'task OIDC signer')
    task_signer_iam = _object(
        run(
            (
                'gcloud',
                'iam',
                'service-accounts',
                'get-iam-policy',
                task_signer,
                '--project',
                project,
                '--format=json',
            )
        )
    )
    service_doc = _object(
        run(
            (
                'gcloud',
                'run',
                'services',
                'describe',
                'backend',
                '--region',
                region,
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
    logging_sink_docs = _array(run(('gcloud', 'logging', 'sinks', 'list', '--project', project, '--format=json')))
    channel_docs = _array(run(('gcloud', 'monitoring', 'channels', 'list', '--project', project, '--format=json')))
    uptime_docs = _array(run(('gcloud', 'monitoring', 'uptime', 'list-configs', '--project', project, '--format=json')))
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
    service_env = _cloud_run_environment(service_doc)
    budget_notification_channels = _budget_notification_channels(selected_budget)
    return {
        'wif': {
            'provider': _leaf(provider_doc.get('name')),
            'state': provider_doc.get('state'),
            'disabled': bool(provider_doc.get('disabled', False)),
            'issuer_uri': (_mapping(provider_doc.get('oidc'), 'WIF OIDC')).get('issuerUri'),
            'attribute_mapping': provider_doc.get('attributeMapping'),
            'attribute_condition': provider_doc.get('attributeCondition'),
            'service_account_bindings': {
                policy.principal: {
                    'service_account': policy.service_account,
                    'workload_identity_grants': _role_grants(
                        wif_policy_docs[policy.principal], 'roles/iam.workloadIdentityUser'
                    ),
                }
                for policy in wif_policies
            },
        },
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
            'lifecycle_rules': _bucket_lifecycle_rules(bucket_doc),
            'runtime_viewer_grants': _role_grants(bucket_iam_doc, 'roles/storage.objectViewer'),
            'runtime_bucket_mutating_grants': _member_role_grants(
                bucket_iam_doc,
                f'serviceAccount:{runtime_service_account}',
                roles={
                    'roles/storage.admin',
                    'roles/storage.objectAdmin',
                    'roles/storage.objectCreator',
                    'roles/storage.legacyBucketOwner',
                    'roles/storage.legacyObjectOwner',
                },
                include_custom_roles=True,
            ),
            'runtime_project_storage_grants': _member_role_grants(
                project_iam_doc,
                f'serviceAccount:{runtime_service_account}',
                roles={'roles/editor', 'roles/owner'},
                role_prefixes=('roles/storage.',),
                include_custom_roles=True,
            ),
            'signing': {
                'method': 'iamcredentials.signBlob',
                'service_account': runtime_service_account,
                'token_creator_grants': _role_grants(
                    runtime_service_account_iam, 'roles/iam.serviceAccountTokenCreator'
                ),
            },
        },
        'tasks': {
            'queue': {
                'name': _leaf(queue_doc.get('name')),
                'location': _resource_segment(queue_doc.get('name'), 'locations'),
                'max_concurrent_dispatches': (_mapping(queue_doc.get('rateLimits'), 'queue rate limits')).get(
                    'maxConcurrentDispatches'
                ),
                'max_attempts': (_mapping(queue_doc.get('retryConfig'), 'queue retry config')).get('maxAttempts'),
                'dispatch_deadline_seconds': int(service_env.get('HTTP_ACCOUNT_DELETION_WIPE_RUN_TIMEOUT') or 0),
                'oidc_signer': service_env.get('ACCOUNT_DELETION_TASKS_INVOKER_SA'),
                'handler_audience': service_env.get('ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE'),
                'runtime_service_account': _cloud_run_service_account(service_doc),
                'enqueuer_grants': _role_grants(queue_iam_doc, 'roles/cloudtasks.enqueuer'),
                'project_task_or_signer_grants': _member_role_grants(
                    project_iam_doc,
                    f'serviceAccount:{runtime_service_account}',
                    roles={'roles/editor', 'roles/owner'},
                    role_prefixes=('roles/cloudtasks.', 'roles/iam.serviceAccount'),
                    include_custom_roles=True,
                ),
                'runtime_act_as_grants': _role_grants(task_signer_iam, 'roles/iam.serviceAccountUser'),
                'signer_token_creator_grants': _role_grants(task_signer_iam, 'roles/iam.serviceAccountTokenCreator'),
            }
        },
        'artifact_registry': {
            'repository': _leaf(registry_doc.get('name')),
            'location': _resource_segment(registry_doc.get('name'), 'locations'),
            'format': registry_doc.get('format'),
            'cleanup_policy_dry_run': registry_doc.get('cleanupPolicyDryRun'),
            'cleanup_delete_policies': _cleanup_delete_policies(registry_doc.get('cleanupPolicies')),
        },
        'logging': {
            'bucket': _leaf(logging_doc.get('name')),
            'retention_days': logging_doc.get('retentionDays'),
            'external_sinks': _external_logging_sinks(logging_sink_docs),
        },
        'alerts': _normalize_alerts(
            alert_docs,
            channel_docs,
            uptime_docs,
            expected=alerts,
            expected_health_host=_url_host(_string(tasks.get('handler_audience'), 'task handler audience')),
        ),
        'budget': _normalize_budget(
            selected_budget,
            channel_docs=channel_docs,
            notification_channels=budget_notification_channels,
        ),
    }


def expected_observable_foundation(expected: Mapping[str, Any]) -> dict[str, Any]:
    wif = _mapping(expected.get('wif'), 'wif')
    wif_policies = _wif_policies(wif)
    provider_resource = _string(wif.get('provider'), 'WIF provider')
    provider_project_number, _, provider_name = _provider_parts(provider_resource)
    network = _mapping(expected.get('network'), 'network')
    psa = _mapping(network.get('private_service_access'), 'private_service_access')
    firestore = _mapping(expected.get('firestore'), 'firestore')
    gcs = _mapping(expected.get('gcs'), 'gcs')
    queue = _mapping(_mapping(expected.get('tasks'), 'tasks').get('queue'), 'queue')
    registry = _mapping(expected.get('artifact_registry'), 'artifact_registry')
    logging = _mapping(expected.get('logging'), 'logging')
    alerts = _mapping(expected.get('alerts'), 'alerts')
    budget = _mapping(expected.get('budget'), 'budget')
    runtime_service_account = _string(gcs.get('signing_service_account'), 'GCS signing service account')
    task_signer = _string(queue.get('oidc_signer'), 'task OIDC signer')
    return {
        'wif': {
            'provider': provider_name,
            'state': 'ACTIVE',
            'disabled': False,
            'issuer_uri': 'https://token.actions.githubusercontent.com/',
            'attribute_mapping': provider_attribute_mapping(),
            'attribute_condition': provider_attribute_condition(wif_policies),
            'service_account_bindings': {
                policy.principal: {
                    'service_account': policy.service_account,
                    'workload_identity_grants': _unconditional_grants(
                        workflow_principal_member(provider_resource, workflow_ref)
                        for workflow_ref in policy.workflow_refs
                    ),
                }
                for policy in wif_policies
            },
        },
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
            'lifecycle_rules': gcs.get('lifecycle_rules'),
            'runtime_viewer_grants': _unconditional_grants([f'serviceAccount:{runtime_service_account}']),
            'runtime_bucket_mutating_grants': [],
            'runtime_project_storage_grants': [],
            'signing': {
                'method': gcs.get('signing_method'),
                'service_account': runtime_service_account,
                'token_creator_grants': _unconditional_grants([f'serviceAccount:{runtime_service_account}']),
            },
        },
        'tasks': {
            'queue': {
                'name': queue.get('name'),
                'location': queue.get('location'),
                'max_concurrent_dispatches': queue.get('max_concurrent_dispatches'),
                'max_attempts': queue.get('max_attempts'),
                'dispatch_deadline_seconds': queue.get('dispatch_deadline_seconds'),
                'oidc_signer': task_signer,
                'handler_audience': queue.get('handler_audience'),
                'runtime_service_account': runtime_service_account,
                'enqueuer_grants': _unconditional_grants([f'serviceAccount:{runtime_service_account}']),
                'project_task_or_signer_grants': [],
                'runtime_act_as_grants': _unconditional_grants([f'serviceAccount:{runtime_service_account}']),
                'signer_token_creator_grants': _unconditional_grants(
                    [f'serviceAccount:service-{provider_project_number}@gcp-sa-cloudtasks.iam.gserviceaccount.com']
                ),
            }
        },
        'artifact_registry': {
            'repository': registry.get('repository'),
            'location': registry.get('location'),
            'format': registry.get('format'),
            'cleanup_policy_dry_run': True,
            'cleanup_delete_policies': [
                {
                    'action': 'DELETE',
                    'tag_state': 'UNTAGGED',
                    'older_than': f"{int(_mapping(registry.get('cleanup'), 'registry cleanup').get('delete_only_untagged_older_than_days') or 0) * 86400}s",
                }
            ],
        },
        'logging': {
            'bucket': logging.get('bucket'),
            'retention_days': logging.get('retention_days'),
            'external_sinks': [],
        },
        'alerts': _expected_alerts(
            alerts,
            expected_health_host=_url_host(_string(queue.get('handler_audience'), 'task handler audience')),
        ),
        'budget': {
            'amount': str(budget.get('amount')),
            'currency': budget.get('currency'),
            'thresholds': budget.get('thresholds'),
            'project_number': provider_project_number,
            'calendar_period': 'MONTH',
            'recipients': sorted(_csv_values(budget.get('recipients'))),
            'default_iam_recipients_disabled': True,
            'alert_only': bool(budget.get('alert_only')),
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


def _unconditional_grants(members: Iterable[str]) -> list[dict[str, Any]]:
    return [{'member': member, 'condition': None} for member in sorted(members)]


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
    print(
        f'backend read-only observable foundation matches the {args.env} manifest; '
        'separately authorized behavioral probes remain required'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
