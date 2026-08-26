"""Static schema rules for the retained backend cloud foundation."""

from __future__ import annotations

from typing import Any, Mapping, cast


def validation_messages(environment: str, env_config: Mapping[str, Any]) -> list[str]:
    foundation = _mapping(env_config.get('foundation'))
    if foundation is None:
        return ['foundation must be a mapping']
    expected_sections = {
        'wif',
        'network',
        'redis',
        'firestore',
        'gcs',
        'tasks',
        'artifact_registry',
        'logging',
        'alerts',
        'budget',
    }
    errors: list[str] = []
    if set(foundation) != expected_sections:
        errors.append('foundation sections must match the retained dependency set')

    wif = _mapping(foundation.get('wif')) or {}
    claims = _mapping(wif.get('claims')) or {}
    automatic = ['.github/workflows/gcp_backend_auto_dev.yml'] if environment == 'dev' else []
    expected_workflow_paths = {
        'deploy': ['.github/workflows/gcp_backend.yml', *automatic],
        'firestore_readonly': ['.github/workflows/gcp_backend.yml', *automatic],
        'firestore_writer': ['.github/workflows/gcp_firestore_indexes.yml'],
    }
    if claims != {
        'repository': {'env_var': 'GITHUB_REPOSITORY'},
        'repository_id': {'env_var': 'GITHUB_REPOSITORY_ID'},
        'repository_owner_id': {'env_var': 'GITHUB_REPOSITORY_OWNER_ID'},
        'ref': 'refs/heads/main',
        'environment': 'development' if environment == 'dev' else 'prod',
        'workflow_paths': expected_workflow_paths,
    }:
        errors.append('WIF claims must bind exact repository IDs, main, environment, and workflows')
    principal_keys = (
        'provider',
        'deploy_service_account',
        'firestore_readonly_service_account',
        'firestore_writer_service_account',
    )
    if {key: wif.get(key) for key in principal_keys} != {
        'provider': {'env_var': 'GCP_WORKLOAD_IDENTITY_PROVIDER'},
        'deploy_service_account': {'env_var': 'GCP_DEPLOY_SERVICE_ACCOUNT'},
        'firestore_readonly_service_account': {'env_var': 'GCP_FIRESTORE_READONLY_SERVICE_ACCOUNT'},
        'firestore_writer_service_account': {'env_var': 'GCP_FIRESTORE_WRITER_SERVICE_ACCOUNT'},
    }:
        errors.append('WIF principals must use distinct environment-scoped external identities')

    network = _mapping(foundation.get('network')) or {}
    if network != {
        'region': 'us-west1',
        'vpc': {'env_var': 'CLOUD_RUN_VPC_NETWORK'},
        'subnet': {'env_var': 'CLOUD_RUN_VPC_SUBNET'},
        'private_service_access': {
            'range_name': {'env_var': 'PRIVATE_SERVICE_ACCESS_RANGE_NAME'},
            'range_cidr': {'env_var': 'PRIVATE_SERVICE_ACCESS_RANGE_CIDR'},
        },
    }:
        errors.append('network foundation must name one exact private-service range')

    redis = _mapping(foundation.get('redis')) or {}
    if redis != {
        'instance_name': {'env_var': 'REDIS_INSTANCE_NAME'},
        'region': 'us-west1',
        'tier': 'BASIC' if environment == 'dev' else 'STANDARD_HA',
        'memory_gib': 1,
        'private_service_access': True,
        'auth': True,
        'transit_encryption': 'SERVER_AUTHENTICATION',
    }:
        errors.append('Redis foundation must match owned TLS/AUTH topology')

    tasks = _mapping(foundation.get('tasks')) or {}
    queue = _mapping(tasks.get('queue')) or {}
    if queue != {
        'name': 'account-deletion',
        'location': 'us-west1',
        'max_concurrent_dispatches': 1,
        'max_attempts': 5,
        'dispatch_deadline_seconds': 1500,
        'oidc_signer': {'env_var': 'ACCOUNT_DELETION_TASKS_INVOKER_SA'},
        'handler_audience': {'env_var': 'ACCOUNT_DELETION_HANDLER_URL'},
    }:
        errors.append('account-deletion queue contract is incomplete')

    gcs = _mapping(foundation.get('gcs')) or {}
    if gcs != {
        'bucket': {'env_var': 'BUCKET_DESKTOP_UPDATES'},
        'location': 'us-west1',
        'uniform_bucket_level_access': True,
        'public_access_prevention': 'enforced',
        'runtime_access': 'read-and-sign-only',
        'signing_method': 'iamcredentials.signBlob',
        'signing_service_account': {'env_var': 'BACKEND_RUNTIME_SERVICE_ACCOUNT'},
        'publisher_access': 'future-s29-prefix-writer',
        'retained_prefixes': ['updates/', 'previews/'],
        'lifecycle_rules': [],
    }:
        errors.append('GCS foundation must retain read-only IAM signBlob access')

    logging = _mapping(foundation.get('logging')) or {}
    if logging != {'bucket': '_Default', 'retention_days': 30, 'external_archive': False}:
        errors.append('logging must retain only _Default for 30 days without an archive')
    alerts = _mapping(foundation.get('alerts')) or {}
    expected_alerts = [] if environment == 'dev' else ['health_unreachable', 'cloud_run_5xx']
    if alerts.get('policies') != expected_alerts:
        errors.append('alert policies must be empty in dev and health/5xx only in prod')
    budget = _mapping(foundation.get('budget')) or {}
    if budget.get('thresholds') != [0.5, 0.8, 1.0] or budget.get('alert_only') is not True:
        errors.append('budget must be alert-only at 50/80/100 percent')
    for key in ('billing_account', 'amount', 'currency', 'recipients'):
        entry = _mapping(budget.get(key))
        if entry is None or not isinstance(entry.get('env_var'), str) or not entry['env_var']:
            errors.append(f'budget {key} must be an explicit external input')

    registry = _mapping(foundation.get('artifact_registry')) or {}
    cleanup = _mapping(registry.get('cleanup')) or {}
    if (
        registry.get('location') != 'us-west1'
        or registry.get('format') != 'DOCKER'
        or registry.get('release_tag') != 'full-commit-sha'
        or registry.get('deploy_identity') != 'sha256-digest'
        or cleanup
        != {
            'dry_run_required': True,
            'delete_only_untagged_older_than_days': 30,
            'preserve_exact_release_images': True,
            'delete_cloud_run_revisions': False,
        }
    ):
        errors.append('Artifact Registry identity or cleanup contract is unsafe')
    return errors


def _mapping(value: object) -> dict[str, Any] | None:
    return cast(dict[str, Any], value) if isinstance(value, dict) else None
