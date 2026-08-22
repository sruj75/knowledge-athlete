from __future__ import annotations

import importlib
from pathlib import Path

import pytest

from utils.llm import clients, model_config
from utils.llm.model_config import WorkloadLifecycle


EXPECTED_ROUTES = {
    'chat_agent': ('anthropic', 'claude-sonnet-4-6'),
    'chat_greeting': ('openai', 'gpt-5.4-mini'),
    'conv_action_items': ('openai', 'gpt-5.4-mini'),
    'conv_discard': ('openai', 'gpt-4.1-nano'),
    'conv_folder': ('openai', 'gpt-4.1-nano'),
    'conv_structure': ('openai', 'gpt-5.4-mini'),
    'fair_use': ('openai', 'gpt-5.1'),
    'followup': ('gemini', 'gemini-2.5-flash-lite'),
    'memory_conflict': ('openai', 'gpt-4.1-mini'),
    'memory_l1': ('openai', 'gpt-4.1-mini'),
    'memory_l2': ('openai', 'gpt-4.1-mini'),
    'session_titles': ('gemini', 'gemini-2.5-flash-lite'),
    'translation': ('gemini', 'gemini-2.5-flash-lite'),
    'wrapped_analysis': ('openrouter', 'gemini-3-flash-preview'),
}


def test_workload_inventory_is_exhaustive_and_names_every_result_owner():
    workloads = model_config.get_all_workloads()

    assert {key: (value.provider, value.model) for key, value in workloads.items()} == EXPECTED_ROUTES
    for key, workload in workloads.items():
        assert workload.key == key
        assert workload.caller
        assert workload.input_contract
        assert workload.output_contract
        assert workload.usage_feature
        assert workload.result_owner
        assert workload.failure_policy


def test_inventory_contains_only_retained_workloads_plus_declared_handoffs():
    workloads = model_config.get_all_workloads()

    assert {key for key, value in workloads.items() if value.lifecycle is WorkloadLifecycle.DEPENDENCY_S20} == {
        'fair_use'
    }
    assert {key for key, value in workloads.items() if value.lifecycle is WorkloadLifecycle.SUCCESSOR_S23} == {
        'conv_folder',
        'followup',
        'wrapped_analysis',
    }
    assert not {key for key, value in workloads.items() if value.lifecycle is WorkloadLifecycle.RETIRING_S22}


def test_wrapped_is_the_only_openrouter_workload():
    assert [key for key, workload in model_config.get_all_workloads().items() if workload.provider == 'openrouter'] == [
        'wrapped_analysis'
    ]


def test_unknown_workload_fails_closed():
    for accessor in (model_config.get_workload, model_config.get_model, model_config.get_provider):
        with pytest.raises(KeyError, match='unknown-workload'):
            accessor('unknown-workload')


def test_legacy_profile_and_gateway_environment_cannot_change_routes(monkeypatch):
    monkeypatch.setenv('MODEL_QOS', 'max')
    monkeypatch.setenv('OMI_LLM_GATEWAY_FEATURE_MODE', 'gateway')
    monkeypatch.setenv('FAIR_USE_CLASSIFIER_MODEL', 'customer-selected-model')

    reloaded = importlib.reload(model_config)

    assert {
        key: (value.provider, value.model) for key, value in reloaded.get_all_workloads().items()
    } == EXPECTED_ROUTES


def test_retained_workload_client_uses_the_explicit_direct_route(monkeypatch):
    direct_client = object()
    calls = []

    def construct(model, provider, streaming, options, *, feature):
        calls.append((model, provider, streaming, options, feature))
        return direct_client

    monkeypatch.setattr(clients, 'get_default_client', construct)
    assert clients.get_workload_client('chat_greeting') is direct_client
    assert calls == [
        ('gpt-5.4-mini', 'openai', False, {'extra_body': {'prompt_cache_retention': '24h'}}, 'chat_greeting')
    ]


def test_route_options_are_workload_owned():
    assert model_config.get_route_options('wrapped_analysis') == {'temperature': 0.7}
    assert model_config.get_route_options('translation') == {}
    assert model_config.get_route_options('chat_greeting') == {'extra_body': {'prompt_cache_retention': '24h'}}


def test_callerless_onboarding_and_trends_model_helpers_are_absent():
    backend = Path(__file__).resolve().parents[2]

    assert not (backend / 'utils/onboarding.py').exists()
    assert not (backend / 'utils/llm/trends.py').exists()
    assert {'onboarding', 'trends'}.isdisjoint(model_config.get_all_workloads())


def test_application_gateway_and_unread_attempt_ledger_are_absent():
    backend = Path(__file__).resolve().parents[2]
    retired_paths = [
        'database/llm_gateway_accounting.py',
        'utils/llm/gateway_anthropic.py',
        'utils/llm/gateway_client.py',
        'utils/llm/gateway_observability.py',
        'utils/llm/gateway_resilience.py',
        'utils/llm/gateway_serving.py',
        'utils/llm/gateway_shadow.py',
    ]

    assert [path for path in retired_paths if (backend / path).exists()] == []
    application_source = '\n'.join(
        path.read_text(encoding='utf-8')
        for root in ('routers', 'utils', 'database')
        for path in (backend / root).rglob('*.py')
    )
    assert 'utils.llm.gateway_' not in application_source
    assert 'llm_gateway_attempts' not in application_source
