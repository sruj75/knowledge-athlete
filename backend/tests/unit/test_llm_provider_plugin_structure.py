"""Unit tests for maintainable LLM provider/model plug-in seams."""

import os
import sys
from unittest.mock import MagicMock

import pytest

_HEAVY_MOCKS = {
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

os.environ.setdefault('GEMINI_API_KEY', 'gemini-test')

from utils.llm import providers
from utils.llm.model_config import get_route_options


@pytest.fixture(autouse=True)
def clear_provider_cache():
    providers._llm_cache.clear()
    yield
    providers._llm_cache.clear()


class FakeChatGemini:
    calls = []

    def __init__(self, **kwargs):
        self.kwargs = kwargs
        FakeChatGemini.calls.append(kwargs)

    def bind(self, **kwargs):
        self.bound_kwargs = kwargs
        return self


def test_gemini_provider_constructs_the_developer_api_route(monkeypatch):
    FakeChatGemini.calls.clear()
    providers._llm_cache.clear()
    monkeypatch.setattr(providers, 'ChatGoogleGenerativeAI', FakeChatGemini)
    monkeypatch.setenv('GEMINI_API_KEY', 'gemini-auth-key')
    monkeypatch.setenv('GOOGLE_CLOUD_PROJECT', 'infra-project')

    llm = providers.get_or_create_gemini_llm('gemini-3.7-flash')

    assert isinstance(llm, FakeChatGemini)
    call = FakeChatGemini.calls[-1]
    assert call['model'] == 'gemini-3.7-flash'
    assert call['google_api_key'] == 'gemini-auth-key'
    assert 'project' not in call
    assert 'location' not in call
    assert call['timeout'] == 120
    assert call['max_retries'] == 1


def test_non_gemini_managed_provider_fails_loudly():
    with pytest.raises(ValueError, match="Unknown managed provider"):
        providers.get_default_client('some-model', 'openai', False)


def test_route_options_keep_provider_quirks_out_of_callsites():
    assert get_route_options('translation') == {}
    assert get_route_options('fair_use') == {}
