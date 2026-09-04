"""Resolve and validate environment-owned Cloud Run deployment identity."""

from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any, Mapping, Sequence
from urllib.parse import urlsplit


class CloudRunServiceUrlError(ValueError):
    """Cloud Run cannot prove the configured canonical URL belongs to the service."""


def resolve_external_value(
    name: str,
    raw_value: object,
    *,
    external_inputs: Mapping[str, str] | None = None,
) -> str:
    inputs = os.environ if external_inputs is None else external_inputs
    if isinstance(raw_value, Mapping):
        env_var = raw_value.get('env_var')
        value = inputs.get(env_var, '').strip() if isinstance(env_var, str) else ''
    else:
        value = str(raw_value or '').strip()
    if not value:
        raise ValueError(f'{name} requires its declared external input')
    return value


def resolve_workflow_string(value: object, workflow_env: Mapping[str, Any]) -> str | None:
    if not isinstance(value, str):
        return None
    resolved = value
    for env_name, env_value in workflow_env.items():
        resolved = resolved.replace('${{ env.' + str(env_name) + ' }}', str(env_value))
    return resolved


def logical_service_name(deployment_name: str, expected_services: Mapping[str, Any]) -> str:
    for logical_name, raw_config in expected_services.items():
        service_config = raw_config if isinstance(raw_config, Mapping) else {}
        raw_binding = service_config.get('deployment_name')
        binding = raw_binding if isinstance(raw_binding, Mapping) else {}
        env_var = binding.get('env_var')
        if isinstance(env_var, str) and deployment_name in {
            '${{ vars.' + env_var + ' }}',
            '${{vars.' + env_var + '}}',
        }:
            return str(logical_name)
        if 'value' in binding and deployment_name == str(binding['value']):
            return str(logical_name)
    return deployment_name


def validate_assigned_service_url(
    service_document: Mapping[str, Any],
    *,
    expected_service: str,
    expected_url: str,
) -> tuple[str, ...]:
    """Require the configured URL to appear in Cloud Run's assigned URL set."""

    metadata = service_document.get('metadata')
    if not isinstance(metadata, Mapping) or metadata.get('name') != expected_service:
        raise CloudRunServiceUrlError(f'Cloud Run did not return the requested service {expected_service!r}')
    annotations = metadata.get('annotations')
    raw_urls = annotations.get('run.googleapis.com/urls') if isinstance(annotations, Mapping) else None
    try:
        assigned_urls = json.loads(raw_urls) if isinstance(raw_urls, str) else None
    except json.JSONDecodeError as error:
        raise CloudRunServiceUrlError('Cloud Run assigned URLs are not valid JSON') from error
    if not isinstance(assigned_urls, list) or not assigned_urls:
        raise CloudRunServiceUrlError('Cloud Run did not report any assigned service URLs')

    normalized_urls: list[str] = []
    for value in assigned_urls:
        if not isinstance(value, str) or value != value.strip():
            raise CloudRunServiceUrlError('Cloud Run reported an invalid assigned service URL')
        parsed = urlsplit(value)
        if (
            parsed.scheme != 'https'
            or not parsed.hostname
            or not parsed.hostname.endswith('.run.app')
            or parsed.port is not None
            or parsed.path
            or parsed.query
            or parsed.fragment
        ):
            raise CloudRunServiceUrlError('Cloud Run reported an invalid assigned service URL')
        normalized_urls.append(value)
    if len(normalized_urls) != len(set(normalized_urls)):
        raise CloudRunServiceUrlError('Cloud Run reported duplicate assigned service URLs')
    if expected_url not in normalized_urls:
        raise CloudRunServiceUrlError(
            f'configured canonical URL is not assigned to Cloud Run service {expected_service!r}'
        )

    status = service_document.get('status')
    reported_url = status.get('url') if isinstance(status, Mapping) else None
    if reported_url not in normalized_urls:
        raise CloudRunServiceUrlError('Cloud Run status URL is not present in its assigned service URLs')
    return tuple(normalized_urls)


def _parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--service', required=True)
    parser.add_argument('--expected-url', required=True)
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    try:
        service_document = json.load(sys.stdin)
        if not isinstance(service_document, Mapping):
            raise CloudRunServiceUrlError('Cloud Run service description must be a JSON object')
        assigned_urls = validate_assigned_service_url(
            service_document,
            expected_service=args.service,
            expected_url=args.expected_url,
        )
    except (CloudRunServiceUrlError, json.JSONDecodeError) as error:
        print(f'ERROR: {error}', file=sys.stderr)
        return 1
    print(f'Validated canonical URL among {len(assigned_urls)} URLs assigned to {args.service}.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
