"""Resolve logical backend labels to environment-owned Cloud Run names."""

from __future__ import annotations

import os
from typing import Any, Mapping


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
