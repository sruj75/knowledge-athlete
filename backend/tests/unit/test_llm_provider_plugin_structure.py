"""Unit tests for maintainable LLM provider/model plug-in seams."""

import os
import sys
from unittest.mock import MagicMock

import pytest

_HEAVY_MOCKS = {
    'anthropic': MagicMock(),
    'firebase_admin': MagicMock(),
    'firebase_admin.firestore': MagicMock(),
    'google.cloud.firestore': MagicMock(),
    'google.cloud.firestore_v1': MagicMock(),
    'google.cloud.firestore_v1.base_query': MagicMock(),
    'tiktoken': MagicMock(encoding_for_model=MagicMock(return_value=MagicMock())),
    'database': MagicMock(),
    'database._client': MagicMock(),
    'database.llm_usage': MagicMock(),
}
for _mod, _mock in _HEAVY_MOCKS.items():
    sys.modules.setdefault(_mod, _mock)

os.environ.setdefault('OPENAI_API_KEY', 'sk-test')
os.environ.setdefault('ANTHROPIC_API_KEY', 'sk-ant-test')

from utils.llm import providers
from utils.llm.model_config import get_route_options


@pytest.fixture(autouse=True)
def clear_provider_cache():
    providers._llm_cache.clear()
    yield
    providers._llm_cache.clear()


class FakeChatOpenAI:
    calls = []

    def __init__(self, **kwargs):
        self.kwargs = kwargs
        FakeChatOpenAI.calls.append(kwargs)

    def bind(self, **kwargs):
        self.bound_kwargs = kwargs
        return self


def test_openai_compatible_provider_constructs_the_retained_openai_route(monkeypatch):
    FakeChatOpenAI.calls.clear()
    providers._llm_cache.clear()
    monkeypatch.setattr(providers, 'ChatOpenAI', FakeChatOpenAI)
    monkeypatch.setenv('OPENAI_API_KEY', 'sk-openai')

    llm = providers.get_or_create_openai_compatible_llm('openai', 'gpt-5.4-mini')

    assert isinstance(llm, FakeChatOpenAI)
    call = FakeChatOpenAI.calls[-1]
    assert call['model'] == 'gpt-5.4-mini'
    assert call['api_key'] == 'sk-openai'
    assert 'base_url' not in call
    assert 'default_headers' not in call
    # Explicit direct workloads retain their provider-sized timeout/retry budget.
    assert call['request_timeout'] == 120
    assert call['max_retries'] == 1


def test_unknown_openai_compatible_provider_fails_loudly():
    with pytest.raises(ValueError, match="Unknown OpenAI-compatible provider"):
        providers.get_or_create_openai_compatible_llm('missing-provider', 'some-model')


def test_route_options_keep_provider_quirks_out_of_callsites():
    assert get_route_options('translation') == {}
    assert get_route_options('fair_use')['extra_body'] == {"prompt_cache_retention": "24h"}
