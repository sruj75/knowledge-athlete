"""Retained prompt-cache routing contracts for explicit direct workloads."""

from utils.llm.model_config import get_route_options, supports_prompt_cache


def test_direct_workloads_expose_cache_key_capability():
    assert supports_prompt_cache('gpt-5.4-mini')
    assert supports_prompt_cache('gpt-4.1-mini')
    assert not supports_prompt_cache('gemini-2.5-flash-lite')


def test_openai_workload_owns_cache_retention_option():
    assert get_route_options('conv_action_items') == {'extra_body': {'prompt_cache_retention': '24h'}}
