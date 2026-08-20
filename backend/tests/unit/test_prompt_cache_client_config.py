"""Retained prompt-cache routing contracts for the shared LLM client."""

from pathlib import Path


BACKEND_DIR = Path(__file__).resolve().parents[2]


def _source(relative_path: str) -> str:
    return (BACKEND_DIR / relative_path).read_text(encoding='utf-8')


def test_qos_cache_key_in_clients():
    source = _source('utils/llm/clients.py')
    assert 'cache_key' in source
    assert 'supports_prompt_cache' in source
    assert '_CACHE_KEY_MODEL_PREFIXES' in _source('utils/llm/model_config.py')


def test_qos_medium_tier_uses_extra_body_for_cache_retention():
    source = _source('utils/llm/clients.py') + _source('utils/llm/model_config.py')
    assert 'extra_body={"prompt_cache_retention"' in source or '"prompt_cache_retention": "24h"' in source
