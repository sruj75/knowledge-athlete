from __future__ import annotations

from copy import deepcopy
from pathlib import Path
import sys

import yaml

BACKEND_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(BACKEND_ROOT))

from scripts.foundation_drift import (  # noqa: E402
    collect_live_foundation,
    drift_paths,
    expected_foundation,
    expected_observable_foundation,
)

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


def fake_gcloud(command):
    words = tuple(command)
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
        }
    if words[1:4] == ('tasks', 'queues', 'describe'):
        return {
            'name': 'projects/runtime-dev/locations/us-west1/queues/account-deletion',
            'rateLimits': {'maxConcurrentDispatches': 1},
            'retryConfig': {'maxAttempts': 5},
        }
    if words[1:4] == ('artifacts', 'repositories', 'describe'):
        return {
            'name': 'projects/runtime-dev/locations/us-west1/repositories/backend-dev',
            'format': 'DOCKER',
        }
    if words[1:4] == ('logging', 'buckets', 'describe'):
        return {'name': 'projects/runtime-dev/locations/global/buckets/_Default', 'retentionDays': 30}
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
            }
        ]
    raise AssertionError(f'unexpected command: {words}')


def test_fake_gcloud_describes_match_the_development_foundation() -> None:
    expected = expected_dev()

    actual = collect_live_foundation(expected, project='runtime-dev', runner=fake_gcloud)

    assert drift_paths(expected_observable_foundation(expected), actual) == []


def test_redis_tls_or_tier_drift_is_reported_at_the_exact_field() -> None:
    expected = expected_observable_foundation(expected_dev())
    observed = deepcopy(expected)
    observed['redis']['transit_encryption'] = 'DISABLED'
    observed['redis']['tier'] = 'STANDARD_HA'

    assert drift_paths(expected, observed) == ['redis.tier', 'redis.transit_encryption']


def test_missing_resource_section_fails_closed_without_secret_values() -> None:
    expected = expected_observable_foundation(expected_dev())
    observed = deepcopy(expected)
    del observed['gcs']

    assert drift_paths(expected, observed) == ['gcs']
