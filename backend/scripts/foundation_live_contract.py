"""Normalize live GCP foundation documents into the S-27 observable contract."""

from __future__ import annotations

import json
import re
from typing import Any, Mapping, Sequence, cast
from urllib.parse import urlparse

try:
    from scripts.wif_claim_policy import ClaimPolicy
except ModuleNotFoundError:  # Direct sibling-script imports place backend/scripts on sys.path.
    from wif_claim_policy import ClaimPolicy  # type: ignore[no-redef]


def normalize_budget(
    value: object,
    *,
    channel_docs: Sequence[Any],
    notification_channels: Sequence[str],
) -> dict[str, Any]:
    if not isinstance(value, Mapping):
        return {}
    amount = _mapping(value.get('amount'), 'budget amount')
    specified = _mapping(amount.get('specifiedAmount'), 'budget specified amount')
    rules = value.get('thresholdRules')
    budget_filter = _mapping(value.get('budgetFilter') or {}, 'budget filter')
    notifications = _mapping(value.get('notificationsRule') or {}, 'budget notifications')
    channels_by_name = {
        str(item.get('name')): item for item in channel_docs if isinstance(item, Mapping) and item.get('name')
    }
    recipients: list[str] = []
    for channel_name in notification_channels:
        channel = channels_by_name.get(channel_name)
        if not isinstance(channel, Mapping) or channel.get('type') != 'email' or channel.get('enabled') is not True:
            recipients.append('INVALID_OR_DISABLED_CHANNEL')
            continue
        labels = _mapping(channel.get('labels') or {}, 'notification channel labels')
        recipients.append(str(labels.get('email_address') or labels.get('emailAddress') or ''))
    projects = budget_filter.get('projects')
    project_number = ''
    if isinstance(projects, list) and len(projects) == 1:
        project_number = _leaf(projects[0])
    return {
        'amount': str(specified.get('units') or ''),
        'currency': specified.get('currencyCode'),
        'thresholds': (
            sorted(item.get('thresholdPercent') for item in rules if isinstance(item, Mapping))
            if isinstance(rules, list)
            else []
        ),
        'project_number': project_number,
        'calendar_period': budget_filter.get('calendarPeriod'),
        'recipients': sorted(recipients),
        'default_iam_recipients_disabled': notifications.get('disableDefaultIamRecipients'),
        'alert_only': not bool(notifications.get('pubsubTopic')),
    }


def provider_parts(provider_resource: str) -> tuple[str, str, str]:
    parts = provider_resource.split('/')
    if (
        len(parts) != 8
        or parts[0] != 'projects'
        or not parts[1].isdigit()
        or parts[2:5] != ['locations', 'global', 'workloadIdentityPools']
        or parts[6] != 'providers'
        or not parts[5]
        or not parts[7]
    ):
        raise ValueError(
            'WIF provider must use projects/<number>/locations/global/'
            'workloadIdentityPools/<pool>/providers/<provider>'
        )
    return parts[1], parts[5], parts[7]


def wif_policies(wif: Mapping[str, Any]) -> list[ClaimPolicy]:
    claims = _mapping(wif.get('claims'), 'WIF claims')
    workflows = _mapping(claims.get('workflow_paths'), 'WIF workflow paths')
    principal_bindings = {
        'deploy': 'deploy_service_account',
        'firestore_readonly': 'firestore_readonly_service_account',
        'firestore_writer': 'firestore_writer_service_account',
    }
    policies: list[ClaimPolicy] = []
    for principal, service_account_key in principal_bindings.items():
        raw_workflows = workflows.get(principal)
        if not isinstance(raw_workflows, list) or not raw_workflows:
            raise ValueError(f'WIF {principal} workflows must be a non-empty list')
        repository = _string(claims.get('repository'), 'WIF repository')
        ref = _string(claims.get('ref'), 'WIF ref')
        policies.append(
            ClaimPolicy(
                environment=_string(claims.get('environment'), 'WIF environment'),
                principal=principal,
                service_account=_string(wif.get(service_account_key), f'WIF {principal} service account'),
                repository=repository,
                repository_id=_string(claims.get('repository_id'), 'WIF repository ID'),
                repository_owner_id=_string(claims.get('repository_owner_id'), 'WIF repository owner ID'),
                ref=ref,
                workflow_refs=tuple(
                    f"{repository}/{_string(path, 'WIF workflow path')}@{ref}" for path in raw_workflows
                ),
            )
        )
    return policies


def role_grants(policy: Mapping[str, Any], role: str) -> list[dict[str, Any]]:
    bindings = policy.get('bindings')
    if not isinstance(bindings, list):
        return []
    grants = [
        {
            'member': str(member),
            'condition': _condition(binding.get('condition')),
        }
        for binding in bindings
        if isinstance(binding, Mapping) and binding.get('role') == role
        for member in (binding.get('members') if isinstance(binding.get('members'), list) else [])
    ]
    return sorted(
        grants,
        key=lambda grant: (grant['member'], json.dumps(grant['condition'], sort_keys=True)),
    )


def member_role_grants(
    policy: Mapping[str, Any],
    member: str,
    *,
    roles: set[str],
    role_prefixes: tuple[str, ...] = (),
    include_custom_roles: bool = False,
) -> list[dict[str, Any]]:
    bindings = policy.get('bindings')
    if not isinstance(bindings, list):
        return []
    grants = [
        {
            'role': str(binding.get('role')),
            'condition': _condition(binding.get('condition')),
        }
        for binding in bindings
        if isinstance(binding, Mapping)
        and isinstance(binding.get('role'), str)
        and (
            binding.get('role') in roles
            or str(binding.get('role')).startswith(role_prefixes)
            or (
                include_custom_roles
                and (
                    str(binding.get('role')).startswith('projects/')
                    or str(binding.get('role')).startswith('organizations/')
                )
            )
        )
        and isinstance(binding.get('members'), list)
        and member in binding['members']
    ]
    return sorted(
        grants,
        key=lambda grant: (grant['role'], json.dumps(grant['condition'], sort_keys=True)),
    )


def bucket_lifecycle_rules(bucket: Mapping[str, Any]) -> list[Any]:
    for container_key in ('lifecycle', 'lifecycle_config'):
        container = bucket.get(container_key)
        if isinstance(container, Mapping) and isinstance(container.get('rule'), list):
            return cast(list[Any], container['rule'])
    rules = bucket.get('lifecycleRule')
    return cast(list[Any], rules) if isinstance(rules, list) else []


def cloud_run_environment(service: Mapping[str, Any]) -> dict[str, str]:
    template_spec = _cloud_run_template_spec(service)
    containers = template_spec.get('containers')
    if not isinstance(containers, list) or len(containers) != 1 or not isinstance(containers[0], Mapping):
        raise ValueError('Cloud Run service must contain exactly one container')
    env = containers[0].get('env')
    if not isinstance(env, list):
        raise ValueError('Cloud Run service environment must be a list')
    return {
        str(item.get('name')): str(item.get('value'))
        for item in env
        if isinstance(item, Mapping) and item.get('name') and 'value' in item
    }


def cloud_run_service_account(service: Mapping[str, Any]) -> str:
    return str(_cloud_run_template_spec(service).get('serviceAccountName') or '')


def cleanup_delete_policies(value: object) -> list[dict[str, str]]:
    entries: list[Mapping[str, Any]] = []
    if isinstance(value, Mapping):
        entries = [dict(item, id=str(name)) for name, item in value.items() if isinstance(item, Mapping)]
    elif isinstance(value, list):
        entries = [item for item in value if isinstance(item, Mapping)]
    normalized: list[dict[str, str]] = []
    for item in entries:
        action = item.get('action')
        action_type = action.get('type') if isinstance(action, Mapping) else action
        if str(action_type or '').upper() != 'DELETE':
            continue
        condition = _mapping(item.get('condition') or {}, 'cleanup condition')
        normalized.append(
            {
                'action': 'DELETE',
                'tag_state': str(condition.get('tagState') or '').upper(),
                'older_than': str(condition.get('olderThan') or ''),
            }
        )
    return sorted(normalized, key=lambda item: (item['tag_state'], item['older_than']))


def external_logging_sinks(values: Sequence[Any]) -> list[dict[str, str]]:
    return sorted(
        (
            {'name': str(item.get('name') or ''), 'destination': str(item.get('destination') or '')}
            for item in values
            if isinstance(item, Mapping) and str(item.get('name') or '') not in {'_Default', '_Required'}
        ),
        key=lambda item: (item['name'], item['destination']),
    )


def normalize_alerts(
    values: Sequence[Any],
    channel_docs: Sequence[Any],
    uptime_docs: Sequence[Any],
    *,
    expected: Mapping[str, Any],
    expected_health_host: str,
) -> dict[str, Any]:
    channel_name = _string(expected.get('notification_channel'), 'alert notification channel')
    selected_channel = next(
        (item for item in channel_docs if isinstance(item, Mapping) and item.get('name') == channel_name),
        None,
    )
    channel = (
        {
            'name': channel_name,
            'enabled': selected_channel.get('enabled'),
            'type': selected_channel.get('type'),
        }
        if isinstance(selected_channel, Mapping)
        else {}
    )
    return {
        'notification_channel': channel,
        'policies': sorted(
            (
                _normalize_alert_policy(item, uptime_docs, expected_health_host=expected_health_host)
                for item in values
                if isinstance(item, Mapping)
            ),
            key=lambda item: item['id'],
        ),
    }


def expected_alerts(alerts: Mapping[str, Any], *, expected_health_host: str) -> dict[str, Any]:
    channel = _string(alerts.get('notification_channel'), 'alert notification channel')
    policies = alerts.get('policies')
    if not isinstance(policies, list):
        raise ValueError('alert policies must be a list')
    expected_policies: list[dict[str, Any]] = []
    for policy in policies:
        policy_id = _string(policy, 'alert policy')
        if policy_id == 'health_unreachable':
            expected_policies.append(
                {
                    'id': policy_id,
                    'enabled': True,
                    'notification_channels': [channel],
                    'condition_kind': 'ABSENT',
                    'duration': '300s',
                    'comparison': None,
                    'threshold_value': None,
                    'no_data': 'ACTIVE',
                    'health_host': expected_health_host,
                    'health_path': '/v1/health',
                    'health_uses_tls': True,
                    'targets_owned_service': True,
                }
            )
        elif policy_id == 'cloud_run_5xx':
            expected_policies.append(
                {
                    'id': policy_id,
                    'enabled': True,
                    'notification_channels': [channel],
                    'condition_kind': 'THRESHOLD',
                    'duration': '300s',
                    'comparison': 'COMPARISON_GT',
                    'threshold_value': 0,
                    'no_data': 'EVALUATION_MISSING_DATA_INACTIVE',
                    'targets_owned_service': True,
                }
            )
        else:
            raise ValueError(f'unsupported alert policy {policy_id}')
    return {
        'notification_channel': {'name': channel, 'enabled': True, 'type': 'email'},
        'policies': sorted(expected_policies, key=lambda item: item['id']),
    }


def budget_notification_channels(value: object) -> list[str]:
    if not isinstance(value, Mapping):
        return []
    notifications = value.get('notificationsRule')
    if not isinstance(notifications, Mapping):
        return []
    channels = notifications.get('monitoringNotificationChannels')
    return sorted(str(item) for item in channels) if isinstance(channels, list) else []


def csv_values(value: object) -> list[str]:
    return [item.strip() for item in str(value or '').split(',') if item.strip()]


def url_host(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != 'https' or not parsed.hostname:
        raise ValueError('owned health/task URL must be an absolute HTTPS URL')
    return parsed.hostname


def _normalize_alert_policy(
    value: Mapping[str, Any], uptime_docs: Sequence[Any], *, expected_health_host: str
) -> dict[str, Any]:
    policy_id = str(value.get('displayName') or '')
    conditions = value.get('conditions')
    condition = conditions[0] if isinstance(conditions, list) and len(conditions) == 1 else {}
    if not isinstance(condition, Mapping):
        condition = {}
    absent = condition.get('conditionAbsent')
    threshold = condition.get('conditionThreshold')
    if isinstance(absent, Mapping):
        kind, details, comparison, threshold_value, no_data = 'ABSENT', absent, None, None, 'ACTIVE'
    elif isinstance(threshold, Mapping):
        kind, details = 'THRESHOLD', threshold
        comparison = threshold.get('comparison')
        threshold_value = threshold.get('thresholdValue')
        no_data = threshold.get('evaluationMissingData')
    else:
        kind, details, comparison, threshold_value, no_data = 'UNKNOWN', {}, None, None, None
    filter_text = str(details.get('filter') or '')
    normalized = {
        'id': policy_id,
        'enabled': value.get('enabled'),
        'notification_channels': sorted(str(item) for item in value.get('notificationChannels') or []),
        'condition_kind': kind,
        'duration': details.get('duration'),
        'comparison': comparison,
        'threshold_value': threshold_value,
        'no_data': no_data,
        'targets_owned_service': _alert_targets_owned_service(policy_id, filter_text),
    }
    if policy_id == 'health_unreachable':
        uptime = _uptime_check_for_filter(filter_text, uptime_docs)
        monitored_resource = _mapping(uptime.get('monitoredResource') or {}, 'uptime monitored resource')
        labels = _mapping(monitored_resource.get('labels') or {}, 'uptime monitored resource labels')
        http_check = _mapping(uptime.get('httpCheck') or {}, 'uptime HTTP check')
        normalized.update(
            {
                'health_host': labels.get('host'),
                'health_path': http_check.get('path'),
                'health_uses_tls': http_check.get('useSsl'),
                'targets_owned_service': normalized['targets_owned_service']
                and labels.get('host') == expected_health_host,
            }
        )
    return normalized


def _alert_targets_owned_service(policy_id: str, filter_text: str) -> bool:
    if policy_id == 'health_unreachable':
        return _filter_values(filter_text, 'metric.type') == {'monitoring.googleapis.com/uptime_check/check_passed'}
    if policy_id == 'cloud_run_5xx':
        return (
            _filter_values(filter_text, 'metric.type') == {'run.googleapis.com/request_count'}
            and _filter_values(filter_text, 'metric.labels.response_code_class') == {'5xx'}
            and _filter_values(filter_text, 'resource.labels.service_name') == {'backend'}
        )
    return False


def _filter_values(filter_text: str, field: str) -> set[str]:
    return set(re.findall(rf'(?<![\w.]){re.escape(field)}\s*=\s*"([^"]+)"', filter_text))


def _uptime_check_for_filter(filter_text: str, values: Sequence[Any]) -> Mapping[str, Any]:
    check_ids = _filter_values(filter_text, 'metric.labels.check_id')
    check_id = next(iter(check_ids)) if len(check_ids) == 1 else ''
    selected = next(
        (item for item in values if isinstance(item, Mapping) and _leaf(item.get('name')) == check_id),
        None,
    )
    return selected if isinstance(selected, Mapping) else {}


def _cloud_run_template_spec(service: Mapping[str, Any]) -> Mapping[str, Any]:
    spec = _mapping(service.get('spec'), 'Cloud Run service spec')
    template = _mapping(spec.get('template'), 'Cloud Run template')
    return _mapping(template.get('spec'), 'Cloud Run template spec')


def _mapping(value: object, label: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise ValueError(f'{label} must be a mapping')
    return cast(Mapping[str, Any], value)


def _string(value: object, label: str) -> str:
    if not isinstance(value, str) or not value:
        raise ValueError(f'{label} must be a non-empty string')
    return value


def _leaf(value: object) -> str:
    return str(value or '').rstrip('/').rsplit('/', 1)[-1]


def _condition(value: object) -> dict[str, str] | None:
    if value is None:
        return None
    if not isinstance(value, Mapping):
        return {'invalid': str(value)}
    return {key: str(value[key]) for key in ('title', 'description', 'expression') if key in value}
