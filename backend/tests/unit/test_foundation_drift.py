from __future__ import annotations

from copy import deepcopy
import json
from pathlib import Path
import sys

import pytest
import yaml

BACKEND_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND_ROOT))

from scripts.foundation_drift import (  # noqa: E402
    collect_live_foundation,
    drift_paths,
    expected_foundation,
    expected_observable_foundation,
    main,
)
from scripts.foundation_live_contract import member_role_grants, normalize_alerts, role_grants  # noqa: E402

MANIFEST = BACKEND_ROOT / 'deploy/runtime_env.yaml'


def external_inputs() -> dict[str, str]:
    return {
        'GITHUB_REPOSITORY': 'hypermind-ai/knowledge-athlete',
        'GITHUB_REPOSITORY_ID': '123456',
        'GITHUB_REPOSITORY_OWNER_ID': '654321',
        'GCP_WORKLOAD_IDENTITY_PROVIDER': 'projects/123/locations/global/workloadIdentityPools/github/providers/actions',
        'GCP_DEPLOY_SERVICE_ACCOUNT': 'deploy-dev@project-dev.iam.gserviceaccount.com',
        'GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT': 'reader-dev@project-dev.iam.gserviceaccount.com',
        'GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT': 'writer-dev@project-dev.iam.gserviceaccount.com',
        'CLOUD_RUN_VPC_NETWORK': 'backend-dev',
        'CLOUD_RUN_VPC_SUBNET': 'backend-dev-west1',
        'PRIVATE_SERVICE_ACCESS_RANGE_NAME': 'backend-dev-services',
        'PRIVATE_SERVICE_ACCESS_RANGE_CIDR': '10.80.0.0/16',
        'REDIS_INSTANCE_NAME': 'backend-dev-cache',
        'REDIS_DB_HOST': 'redis.external.example',
        'REDIS_DB_PORT': '6379',
        'RUNTIME_GCP_PROJECT_ID': 'runtime-dev',
        'BUCKET_DESKTOP_UPDATES': 'desktop-updates-dev',
        'BACKEND_RUNTIME_SERVICE_ACCOUNT': 'runtime-dev@project-dev.iam.gserviceaccount.com',
        'ACCOUNT_DELETION_TASKS_INVOKER_SA': 'tasks-dev@project-dev.iam.gserviceaccount.com',
        'ACCOUNT_DELETION_HANDLER_URL': 'https://backend-dev.run.app/v1/account-deletion/tasks/execute',
        'ARTIFACT_REGISTRY_REPOSITORY': 'backend-dev',
        'ALERT_NOTIFICATION_CHANNEL': 'projects/runtime-dev/notificationChannels/1',
        'GCP_BILLING_ACCOUNT_ID': '000000-000000-000000',
        'GCP_MONTHLY_BUDGET_AMOUNT': '100',
        'GCP_MONTHLY_BUDGET_CURRENCY': 'USD',
        'GCP_BUDGET_RECIPIENTS': 'owner@example.com',
    }


def expected_dev() -> dict:
    manifest = yaml.safe_load(MANIFEST.read_text(encoding='utf-8'))
    return expected_foundation(manifest, environment='dev', external_inputs=external_inputs())


def expected_prod() -> dict:
    manifest = yaml.safe_load(MANIFEST.read_text(encoding='utf-8'))
    return expected_foundation(manifest, environment='prod', external_inputs=external_inputs())


def grant_members(grants: list[dict]) -> list[str]:
    return [grant['member'] for grant in grants]


def fake_gcloud(command, wanted):
    words = tuple(command)
    if words[1:5] == ('iam', 'workload-identity-pools', 'providers', 'describe'):
        provider = wanted['wif']
        return {
            'name': 'projects/123/locations/global/workloadIdentityPools/github/providers/actions',
            'state': provider['state'],
            'disabled': provider['disabled'],
            'oidc': {'issuerUri': provider['issuer_uri']},
            'attributeMapping': provider['attribute_mapping'],
            'attributeCondition': provider['attribute_condition'],
        }
    if words[1:4] == ('iam', 'service-accounts', 'get-iam-policy'):
        service_account = words[4]
        for binding in wanted['wif']['service_account_bindings'].values():
            if binding['service_account'] == service_account:
                return {
                    'bindings': [
                        {
                            'role': 'roles/iam.workloadIdentityUser',
                            'members': grant_members(binding['workload_identity_grants']),
                        }
                    ]
                }
        if service_account == wanted['gcs']['signing']['service_account']:
            return {
                'bindings': [
                    {
                        'role': 'roles/iam.serviceAccountTokenCreator',
                        'members': grant_members(wanted['gcs']['signing']['token_creator_grants']),
                    }
                ]
            }
        if service_account == wanted['tasks']['queue']['oidc_signer']:
            return {
                'bindings': [
                    {
                        'role': 'roles/iam.serviceAccountTokenCreator',
                        'members': grant_members(wanted['tasks']['queue']['signer_token_creator_grants']),
                    },
                    {
                        'role': 'roles/iam.serviceAccountUser',
                        'members': grant_members(wanted['tasks']['queue']['runtime_act_as_grants']),
                    },
                ]
            }
    if words[1:3] == ('projects', 'get-iam-policy'):
        return {'bindings': []}
    if words[1:4] == ('compute', 'networks', 'describe'):
        return {'name': 'backend-dev'}
    if words[1:5] == ('compute', 'networks', 'subnets', 'describe'):
        return {'name': 'backend-dev-west1', 'region': 'projects/p/regions/us-west1'}
    if words[1:4] == ('compute', 'addresses', 'describe'):
        return {
            'name': 'backend-dev-services',
            'address': '10.80.0.0',
            'prefixLength': 16,
            'purpose': 'VPC_PEERING',
            'status': 'RESERVED',
        }
    if words[1:4] == ('redis', 'instances', 'describe'):
        return {
            'name': 'projects/p/locations/us-west1/instances/backend-dev-cache',
            'locationId': 'us-west1',
            'tier': 'BASIC',
            'memorySizeGb': 1,
            'connectMode': 'PRIVATE_SERVICE_ACCESS',
            'authorizedNetwork': 'projects/p/global/networks/backend-dev',
            'authEnabled': True,
            'transitEncryptionMode': 'SERVER_AUTHENTICATION',
        }
    if words[1:4] == ('firestore', 'databases', 'describe'):
        return {'name': 'projects/runtime-dev/databases/(default)'}
    if words[1:4] == ('storage', 'buckets', 'describe'):
        return {
            'name': 'desktop-updates-dev',
            'location': 'US-WEST1',
            'iamConfiguration': {
                'uniformBucketLevelAccess': {'enabled': True},
                'publicAccessPrevention': 'enforced',
            },
            'lifecycle': {'rule': []},
        }
    if words[1:4] == ('storage', 'buckets', 'get-iam-policy'):
        return {
            'bindings': [
                {
                    'role': 'roles/storage.objectViewer',
                    'members': grant_members(wanted['gcs']['runtime_viewer_grants']),
                }
            ]
        }
    if words[1:4] == ('tasks', 'queues', 'describe'):
        return {
            'name': 'projects/runtime-dev/locations/us-west1/queues/account-deletion',
            'rateLimits': {'maxConcurrentDispatches': 1},
            'retryConfig': {'maxAttempts': 5},
        }
    if words[1:4] == ('tasks', 'queues', 'get-iam-policy'):
        return {
            'bindings': [
                {
                    'role': 'roles/cloudtasks.enqueuer',
                    'members': grant_members(wanted['tasks']['queue']['enqueuer_grants']),
                }
            ]
        }
    if words[1:4] == ('run', 'services', 'describe'):
        queue = wanted['tasks']['queue']
        return {
            'spec': {
                'template': {
                    'spec': {
                        'serviceAccountName': queue['runtime_service_account'],
                        'containers': [
                            {
                                'env': [
                                    {
                                        'name': 'ACCOUNT_DELETION_TASKS_INVOKER_SA',
                                        'value': queue['oidc_signer'],
                                    },
                                    {
                                        'name': 'ACCOUNT_DELETION_TASKS_OIDC_AUDIENCE',
                                        'value': queue['handler_audience'],
                                    },
                                    {
                                        'name': 'HTTP_ACCOUNT_DELETION_WIPE_RUN_TIMEOUT',
                                        'value': str(queue['dispatch_deadline_seconds']),
                                    },
                                ]
                            }
                        ],
                    }
                }
            }
        }
    if words[1:4] == ('artifacts', 'repositories', 'describe'):
        return {
            'name': 'projects/runtime-dev/locations/us-west1/repositories/backend-dev',
            'format': 'DOCKER',
            'cleanupPolicyDryRun': True,
            'cleanupPolicies': {
                'delete-old-untagged': {
                    'action': 'DELETE',
                    'condition': {'tagState': 'UNTAGGED', 'olderThan': '2592000s'},
                }
            },
        }
    if words[1:4] == ('logging', 'buckets', 'describe'):
        return {'name': 'projects/runtime-dev/locations/global/buckets/_Default', 'retentionDays': 30}
    if words[1:4] == ('logging', 'sinks', 'list'):
        return [
            {
                'name': '_Default',
                'destination': 'logging.googleapis.com/projects/runtime-dev/locations/global/buckets/_Default',
            },
            {
                'name': '_Required',
                'destination': 'logging.googleapis.com/projects/runtime-dev/locations/global/buckets/_Required',
            },
        ]
    if words[1:4] == ('monitoring', 'channels', 'list'):
        return [
            {
                'name': 'projects/runtime-dev/notificationChannels/1',
                'enabled': True,
                'type': 'email',
                'labels': {'email_address': 'alerts@example.com'},
            },
            {
                'name': 'projects/runtime-dev/notificationChannels/budget-owner',
                'enabled': True,
                'type': 'email',
                'labels': {'email_address': 'owner@example.com'},
            },
        ]
    if words[1:4] == ('monitoring', 'uptime', 'list-configs'):
        return []
    if words[1:4] == ('monitoring', 'policies', 'list'):
        return []
    if words[1:4] == ('billing', 'budgets', 'list'):
        return [
            {
                'displayName': 'backend-development',
                'amount': {'specifiedAmount': {'units': '100', 'currencyCode': 'USD'}},
                'thresholdRules': [
                    {'thresholdPercent': 0.5},
                    {'thresholdPercent': 0.8},
                    {'thresholdPercent': 1.0},
                ],
                'budgetFilter': {'projects': ['projects/123'], 'calendarPeriod': 'MONTH'},
                'notificationsRule': {
                    'disableDefaultIamRecipients': True,
                    'monitoringNotificationChannels': ['projects/runtime-dev/notificationChannels/budget-owner'],
                },
            }
        ]
    raise AssertionError(f'unexpected command: {words}')


def test_fake_gcloud_describes_match_the_development_foundation() -> None:
    expected = expected_dev()
    wanted = expected_observable_foundation(expected)
    commands = []

    def recording_runner(command):
        commands.append(tuple(command))
        return fake_gcloud(command, wanted)

    actual = collect_live_foundation(
        expected,
        project='runtime-dev',
        cloud_run_service='knowledge-athlete-dev',
        runner=recording_runner,
    )

    assert drift_paths(wanted, actual) == []
    assert not any(command[1:2] == ('compute',) for command in commands)
    assert not any(command[1:2] == ('redis',) for command in commands)
    cloud_run_describes = [command for command in commands if command[1:4] == ('run', 'services', 'describe')]
    assert cloud_run_describes == [
        (
            'gcloud',
            'run',
            'services',
            'describe',
            'knowledge-athlete-dev',
            '--region',
            'us-west1',
            '--project',
            'runtime-dev',
            '--format=json',
        )
    ]


def test_external_redis_tls_or_plan_drift_is_reported_at_the_exact_field() -> None:
    expected = expected_observable_foundation(expected_dev())
    observed = deepcopy(expected)
    observed['redis']['transit_encryption'] = 'DISABLED'
    observed['redis']['plan'] = 'paid'

    assert drift_paths(expected, observed) == ['redis.plan', 'redis.transit_encryption']


def test_missing_resource_section_fails_closed_without_secret_values() -> None:
    expected = expected_observable_foundation(expected_dev())
    observed = deepcopy(expected)
    del observed['gcs']

    assert drift_paths(expected, observed) == ['gcs']


def test_conditional_required_iam_binding_is_not_treated_as_unconditional() -> None:
    member = 'serviceAccount:runtime@project.iam.gserviceaccount.com'
    policy = {
        'bindings': [
            {
                'role': 'roles/storage.objectViewer',
                'members': [member],
                'condition': {'title': 'disabled', 'expression': 'false'},
            }
        ]
    }

    assert role_grants(policy, 'roles/storage.objectViewer') == [
        {
            'member': member,
            'condition': {'title': 'disabled', 'expression': 'false'},
        }
    ]


def test_project_basic_storage_and_custom_runtime_grants_are_observable() -> None:
    member = 'serviceAccount:runtime@project.iam.gserviceaccount.com'
    policy = {
        'bindings': [
            {'role': 'roles/editor', 'members': [member]},
            {'role': 'roles/cloudtasks.admin', 'members': [member]},
            {'role': 'roles/iam.serviceAccountUser', 'members': [member]},
            {'role': 'roles/iam.serviceAccountTokenCreator', 'members': [member]},
            {'role': 'roles/storage.objectViewer', 'members': [member]},
            {'role': 'projects/runtime/roles/customRuntime', 'members': [member]},
            {'role': 'roles/logging.logWriter', 'members': [member]},
        ]
    }

    assert member_role_grants(
        policy,
        member,
        roles={'roles/editor', 'roles/owner'},
        role_prefixes=('roles/cloudtasks.', 'roles/iam.serviceAccount', 'roles/storage.'),
        include_custom_roles=True,
    ) == [
        {'role': 'projects/runtime/roles/customRuntime', 'condition': None},
        {'role': 'roles/cloudtasks.admin', 'condition': None},
        {'role': 'roles/editor', 'condition': None},
        {'role': 'roles/iam.serviceAccountTokenCreator', 'condition': None},
        {'role': 'roles/iam.serviceAccountUser', 'condition': None},
        {'role': 'roles/storage.objectViewer', 'condition': None},
    ]


def test_production_alert_conditions_channel_target_and_no_data_behavior_are_observable() -> None:
    expected = expected_observable_foundation(expected_prod())['alerts']
    channel = 'projects/runtime-dev/notificationChannels/1'
    actual = normalize_alerts(
        [
            {
                'displayName': 'health_unreachable',
                'enabled': True,
                'notificationChannels': [channel],
                'conditions': [
                    {
                        'conditionAbsent': {
                            'filter': (
                                'metric.type="monitoring.googleapis.com/uptime_check/check_passed" '
                                'AND metric.labels.check_id="backend-health"'
                            ),
                            'duration': '300s',
                        }
                    }
                ],
            },
            {
                'displayName': 'cloud_run_5xx',
                'enabled': True,
                'notificationChannels': [channel],
                'conditions': [
                    {
                        'conditionThreshold': {
                            'filter': (
                                'metric.type="run.googleapis.com/request_count" '
                                'AND metric.labels.response_code_class="5xx" '
                                'AND resource.labels.service_name="backend"'
                            ),
                            'duration': '300s',
                            'comparison': 'COMPARISON_GT',
                            'thresholdValue': 0,
                            'evaluationMissingData': 'EVALUATION_MISSING_DATA_INACTIVE',
                        }
                    }
                ],
            },
        ],
        [{'name': channel, 'enabled': True, 'type': 'email'}],
        [
            {
                'name': 'projects/runtime-dev/uptimeCheckConfigs/backend-health',
                'monitoredResource': {'labels': {'host': 'backend-dev.run.app'}},
                'httpCheck': {'path': '/v1/health', 'useSsl': True},
            }
        ],
        expected={'notification_channel': channel},
        expected_health_host='backend-dev.run.app',
    )

    assert drift_paths(expected, actual) == []


@pytest.mark.parametrize(
    ('path', 'replacement', 'drift_path'),
    [
        (('wif', 'attribute_mapping'), {}, 'wif.attribute_mapping'),
        (('wif', 'attribute_condition'), 'assertion.repository=="wrong/repo"', 'wif.attribute_condition'),
        (
            ('wif', 'service_account_bindings', 'deploy', 'workload_identity_grants'),
            [],
            'wif.service_account_bindings.deploy.workload_identity_grants',
        ),
        (('gcs', 'lifecycle_rules'), [{'action': {'type': 'Delete'}}], 'gcs.lifecycle_rules'),
        (('gcs', 'runtime_viewer_grants'), [], 'gcs.runtime_viewer_grants'),
        (
            ('gcs', 'runtime_bucket_mutating_grants'),
            [{'role': 'roles/storage.objectAdmin', 'condition': None}],
            'gcs.runtime_bucket_mutating_grants',
        ),
        (
            ('gcs', 'runtime_project_storage_grants'),
            [{'role': 'roles/editor', 'condition': None}],
            'gcs.runtime_project_storage_grants',
        ),
        (('gcs', 'signing', 'token_creator_grants'), [], 'gcs.signing.token_creator_grants'),
        (('tasks', 'queue', 'dispatch_deadline_seconds'), 300, 'tasks.queue.dispatch_deadline_seconds'),
        (('tasks', 'queue', 'oidc_signer'), 'wrong@project-dev.iam.gserviceaccount.com', 'tasks.queue.oidc_signer'),
        (('tasks', 'queue', 'handler_audience'), 'https://candidate.example.test', 'tasks.queue.handler_audience'),
        (
            ('tasks', 'queue', 'project_task_or_signer_grants'),
            [{'role': 'roles/cloudtasks.admin', 'condition': None}],
            'tasks.queue.project_task_or_signer_grants',
        ),
        (('tasks', 'queue', 'runtime_act_as_grants'), [], 'tasks.queue.runtime_act_as_grants'),
        (('artifact_registry', 'cleanup_policy_dry_run'), False, 'artifact_registry.cleanup_policy_dry_run'),
        (('artifact_registry', 'cleanup_delete_policies'), [], 'artifact_registry.cleanup_delete_policies'),
        (
            ('logging', 'external_sinks'),
            [{'name': 'archive', 'destination': 'storage.googleapis.com/archive'}],
            'logging.external_sinks',
        ),
        (('alerts', 'notification_channel'), {}, 'alerts.notification_channel'),
        (('budget', 'recipients'), ['wrong@example.com'], 'budget.recipients'),
        (
            ('budget', 'default_iam_recipients_disabled'),
            False,
            'budget.default_iam_recipients_disabled',
        ),
        (('budget', 'alert_only'), False, 'budget.alert_only'),
    ],
)
def test_owned_identity_iam_policy_and_notification_drift_cannot_report_a_match(
    path: tuple[str, ...], replacement: object, drift_path: str
) -> None:
    expected = expected_observable_foundation(expected_dev())
    observed = deepcopy(expected)
    target = observed
    for key in path[:-1]:
        target = target[key]
    target[path[-1]] = replacement

    paths = drift_paths(expected, observed)
    assert any(item == drift_path or item.startswith(f'{drift_path}.') for item in paths)


def test_alert_condition_and_missing_data_drift_cannot_report_a_match() -> None:
    expected = expected_observable_foundation(expected_prod())
    observed = deepcopy(expected)
    policy = next(item for item in observed['alerts']['policies'] if item['id'] == 'cloud_run_5xx')
    policy['condition_kind'] = 'ABSENT'
    policy['no_data'] = 'EVALUATION_MISSING_DATA_ACTIVE'

    assert drift_paths(expected, observed) == [
        'alerts.policies',
    ]


def test_5xx_alert_requires_the_exact_owned_cloud_run_service() -> None:
    channel = 'projects/runtime-dev/notificationChannels/1'
    actual = normalize_alerts(
        [
            {
                'displayName': 'cloud_run_5xx',
                'enabled': True,
                'notificationChannels': [channel],
                'conditions': [
                    {
                        'conditionThreshold': {
                            'filter': (
                                'metric.type="run.googleapis.com/request_count" '
                                'AND metric.labels.response_code_class="5xx" '
                                'AND (resource.labels.service_name="backend" '
                                'OR resource.labels.service_name="backend-candidate")'
                            ),
                            'duration': '300s',
                            'comparison': 'COMPARISON_GT',
                            'thresholdValue': 0,
                            'evaluationMissingData': 'EVALUATION_MISSING_DATA_INACTIVE',
                        }
                    }
                ],
            }
        ],
        [{'name': channel, 'enabled': True, 'type': 'email'}],
        [],
        expected={'notification_channel': channel},
        expected_health_host='backend-dev.run.app',
    )

    assert actual['policies'][0]['targets_owned_service'] is False


def test_success_output_limits_match_to_observable_state(tmp_path: Path, monkeypatch, capsys) -> None:
    expected = expected_observable_foundation(expected_dev())
    state = tmp_path / 'foundation-state.json'
    state.write_text(json.dumps(expected), encoding='utf-8')
    for name, value in external_inputs().items():
        monkeypatch.setenv(name, value)
    monkeypatch.setattr(sys, 'argv', ['foundation_drift.py', '--env=dev', f'--state={state}'])

    assert main() == 0
    output = capsys.readouterr().out
    assert 'read-only observable foundation matches' in output
    assert 'separately authorized behavioral probes remain required' in output
