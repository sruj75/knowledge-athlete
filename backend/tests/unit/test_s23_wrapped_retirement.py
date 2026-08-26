"""S-23 contract: Wrapped and its exclusive OpenRouter binding are absent."""

import json
from pathlib import Path

import main
from testing.e2e.fakes.llm import configure_llm_error, configure_llm_fakes
from utils.llm import model_config


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]


class _EndpointRecorder:
    def __init__(self) -> None:
        self.paths: list[str] = []

    def expect_request(self, path: str):
        self.paths.append(path)
        return self

    def respond_with_json(self, *_args, **_kwargs):
        return self


def test_wrapped_routes_and_openrouter_workload_are_absent() -> None:
    route_keys = {(method, route.path) for route in main.app.routes for method in getattr(route, 'methods', set())}

    assert not {route_key for route_key in route_keys if route_key[1].startswith('/v1/wrapped/')}
    assert 'wrapped_analysis' not in model_config.get_all_workloads()
    assert all(workload.provider != 'openrouter' for workload in model_config.get_all_workloads().values())
    assert ('POST', '/v2/chat/completions') in route_keys


def test_e2e_llm_fake_registers_only_retained_provider_endpoints() -> None:
    success = _EndpointRecorder()
    failure = _EndpointRecorder()

    configure_llm_fakes(success)
    configure_llm_error(failure)

    assert success.paths == ['/v1/chat/completions', '/v1/messages', '/v1/embeddings']
    assert failure.paths == ['/v1/chat/completions', '/v1/messages']


def test_openrouter_secret_is_absent_from_deployment_classification() -> None:
    classification = json.loads(
        (REPOSITORY_ROOT / 'config/deployment-setting-classification.json').read_text(encoding='utf-8')
    )

    assert 'OPENROUTER_API_KEY' not in classification['kinds']['secret']
