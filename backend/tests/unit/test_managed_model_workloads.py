from __future__ import annotations

import ast
from collections import Counter
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
    'conv_structure': ('openai', 'gpt-5.4-mini'),
    'fair_use': ('openai', 'gpt-5.1'),
    'memory_conflict': ('openai', 'gpt-4.1-mini'),
    'memory_l1': ('openai', 'gpt-4.1-mini'),
    'memory_l2': ('openai', 'gpt-4.1-mini'),
    'session_titles': ('gemini', 'gemini-2.5-flash-lite'),
    'translation': ('gemini', 'gemini-2.5-flash-lite'),
}

_PROVIDER_CONSTRUCTORS = {
    'Anthropic',
    'AsyncAnthropic',
    'AsyncOpenAI',
    'ChatAnthropic',
    'ChatGoogleGenerativeAI',
    'ChatOpenAI',
    'OpenAI',
    'OpenAIEmbeddings',
}
_EXPECTED_PROVIDER_CONSTRUCTION = Counter(
    {
        ('utils/llm/clients.py', 'AsyncAnthropic'): 1,
        ('utils/llm/clients.py', 'OpenAIEmbeddings'): 1,
        ('utils/llm/providers.py', 'ChatGoogleGenerativeAI'): 2,
        ('utils/llm/providers.py', 'ChatOpenAI'): 2,
    }
)
_EXPECTED_DIRECT_DEFAULT_CLIENT_CALLS = Counter(
    {
        'utils/llm/clients.py': 1,
        'utils/llm/fair_use_classifier.py': 1,
    }
)
_APPLICATION_MODEL_CALL_TOKENS = tuple(sorted({'get_default_client', 'get_workload_client', *_PROVIDER_CONSTRUCTORS}))


def _application_python_sources() -> list[tuple[str, str]]:
    backend = Path(__file__).resolve().parents[2]
    excluded_roots = {'llm_gateway', 'migrations', 'scripts', 'tests'}
    sources = []
    for path in backend.rglob('*.py'):
        if path.relative_to(backend).parts[0] in excluded_roots or any(
            part in {'.openapi-venv', '.venv', '__pycache__'} for part in path.parts
        ):
            continue
        source = path.read_text(encoding='utf-8')
        if any(token in source for token in _APPLICATION_MODEL_CALL_TOKENS):
            sources.append((path.relative_to(backend).as_posix(), source))
    return sources


def _call_name(node: ast.expr, imported_names: dict[str, str]) -> str:
    if isinstance(node, ast.Name):
        return imported_names.get(node.id, node.id)
    if isinstance(node, ast.Attribute):
        return node.attr
    return ''


def _application_model_calls():
    workload_calls: list[tuple[str, int, object]] = []
    direct_default_calls: Counter[str] = Counter()
    provider_construction: Counter[tuple[str, str]] = Counter()

    for relative_path, source in _application_python_sources():
        tree = ast.parse(source, filename=relative_path)
        imported_names = {
            alias.asname or alias.name: alias.name
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom)
            for alias in node.names
        }
        for node in ast.walk(tree):
            if not isinstance(node, ast.Call):
                continue
            call_name = _call_name(node.func, imported_names)
            if call_name == 'get_workload_client':
                feature = node.args[0].value if node.args and isinstance(node.args[0], ast.Constant) else None
                workload_calls.append((relative_path, node.lineno, feature))
            elif call_name == 'get_default_client':
                direct_default_calls[relative_path] += 1
            elif call_name in _PROVIDER_CONSTRUCTORS:
                provider_construction[(relative_path, call_name)] += 1

    return workload_calls, direct_default_calls, provider_construction


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


def test_inventory_contains_only_retained_workloads_plus_s20_dependency():
    workloads = model_config.get_all_workloads()

    assert {key for key, value in workloads.items() if value.lifecycle is WorkloadLifecycle.DEPENDENCY_S20} == {
        'fair_use'
    }
    assert all(
        value.lifecycle in {WorkloadLifecycle.RETAINED, WorkloadLifecycle.DEPENDENCY_S20}
        for value in workloads.values()
    )


@pytest.mark.slow
def test_application_model_call_sites_cannot_bypass_the_typed_inventory():
    """Static C12 tripwire: all application construction stays in its declared owner seam."""

    workload_calls, direct_default_calls, provider_construction = _application_model_calls()
    workloads = model_config.get_all_workloads()

    assert [
        (path, line, feature) for path, line, feature in workload_calls if feature and feature not in workloads
    ] == []
    assert Counter(path for path, _, feature in workload_calls if feature is None) == Counter(
        {'utils/llm/memory_compute.py': 1}
    )
    assert direct_default_calls == _EXPECTED_DIRECT_DEFAULT_CLIENT_CALLS
    assert provider_construction == _EXPECTED_PROVIDER_CONSTRUCTION

    assert all(workload.provider != 'openrouter' for workload in workloads.values())


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
