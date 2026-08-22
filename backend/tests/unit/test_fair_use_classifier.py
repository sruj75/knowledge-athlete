"""Tests for the LLM fair-use classifier (utils/llm/fair_use_classifier.py)."""

import hashlib
import json
from unittest.mock import AsyncMock, MagicMock

import pytest

import utils.llm.fair_use_classifier as classifier_mod


@pytest.fixture
def classifier_llm(monkeypatch):
    """Fake classifier LLM patched onto the module under test."""
    fake = MagicMock()
    monkeypatch.setattr(classifier_mod, '_classifier_llm', fake)
    return fake


class TestSelectRecipes:
    """Test dynamic recipe selection based on conversation patterns."""

    def test_empty_conversations_returns_empty(self):
        result = classifier_mod._select_recipes([])
        assert result == ""

    def test_long_sessions_trigger_audiobook_recipe(self):
        summaries = [{'title': f'Session {i}', 'duration_minutes': 90, 'category': 'other'} for i in range(5)]
        result = classifier_mod._select_recipes(summaries)
        assert 'Audiobook Detection' in result

    def test_uniform_durations_trigger_prerecorded_recipe(self):
        # All sessions ~30 min (low coefficient of variation)
        summaries = [
            {'title': f'Session {i}', 'duration_minutes': 30 + (i % 3), 'category': 'other'} for i in range(10)
        ]
        result = classifier_mod._select_recipes(summaries)
        assert 'Pre-recorded Content Detection' in result

    def test_medium_sessions_trigger_podcast_recipe(self):
        summaries = [{'title': f'Episode {i}', 'duration_minutes': 45, 'category': 'media'} for i in range(6)]
        result = classifier_mod._select_recipes(summaries)
        assert 'Podcast Detection' in result

    def test_high_count_few_categories_trigger_commercial_recipe(self):
        summaries = [{'title': f'Call {i}', 'duration_minutes': 10, 'category': 'business'} for i in range(25)]
        result = classifier_mod._select_recipes(summaries)
        assert 'Commercial Use Detection' in result

    def test_varied_normal_usage_triggers_no_special_recipe(self):
        summaries = [
            {'title': 'Team standup', 'duration_minutes': 15, 'category': 'meeting'},
            {'title': 'Lunch chat', 'duration_minutes': 45, 'category': 'personal'},
            {'title': 'Project review', 'duration_minutes': 60, 'category': 'work'},
        ]
        result = classifier_mod._select_recipes(summaries)
        assert result == ""


class TestClassifyFairUseEvidenceContract:
    """Lock the existing GPT-5.1 contract while evidence ownership moves to the Mac."""

    @pytest.mark.asyncio
    async def test_supplied_evidence_preserves_prompt_message_model_parser_and_avoids_hosted_reads(
        self, classifier_llm
    ):
        evidence = [
            {
                'conversation_id': 'evidence-1',
                'title': 'Team planning',
                'overview': 'The team reviewed the local-authority rollout.',
                'category': 'work',
                'duration_minutes': 42.5,
                'source': 'desktop',
                'created_at': '2026-08-21T08:30:00Z',
            }
        ]
        llm_response = MagicMock()
        llm_response.content = json.dumps(
            {
                'misuse_score': 1.5,
                'usage_type': 'none',
                'confidence': -0.2,
                'evidence': [],
                'reasoning': 'Legitimate meeting use',
            }
        )
        classifier_llm.ainvoke = AsyncMock(return_value=llm_response)

        result = await classifier_mod.classify_fair_use_evidence('user1', evidence)

        assert hashlib.sha256(classifier_mod.SYSTEM_PROMPT.encode()).hexdigest() == (
            'b2ca34ef4cb6f3461f42d617385178e79bd2f50b8ab8efcdfca0eee552278d05'
        )
        assert classifier_mod.CLASSIFIER_ROUTE == 'openai/gpt-5.1'
        assert classifier_llm.ainvoke.await_args.args[0] == [
            {'role': 'system', 'content': classifier_mod.SYSTEM_PROMPT},
            {
                'role': 'user',
                'content': (
                    'Analyze the following 1 recent conversations from user and determine if their usage is '
                    'legitimate personal use or potential misuse.\n\n\n\nCONVERSATIONS:\n'
                    f'{json.dumps(evidence, indent=2, default=str)}\n\nRespond with ONLY the JSON output, no other text.'
                ),
            },
        ]
        assert result == {
            'misuse_score': 1.0,
            'usage_type': 'none',
            'confidence': 0.0,
            'evidence': [],
            'reasoning': 'Legitimate meeting use',
            'model': 'openai/gpt-5.1',
            'prompt_version': 'v2',
        }
        assert not hasattr(classifier_mod, 'conversations_db')

    @pytest.mark.asyncio
    async def test_supplied_evidence_failure_keeps_the_existing_fail_open_result(self, classifier_llm):
        classifier_llm.ainvoke = AsyncMock(side_effect=TimeoutError('provider detail must stay private'))

        result = await classifier_mod.classify_fair_use_evidence(
            'user1',
            [{'conversation_id': 'e1', 'title': 'Meeting', 'duration_minutes': 10}],
        )

        assert result == {
            'misuse_score': 0.0,
            'usage_type': 'none',
            'confidence': 0.0,
            'evidence': [],
            'model': 'openai/gpt-5.1',
            'prompt_version': 'v2',
        }

    @pytest.mark.asyncio
    async def test_off_schema_usage_type_is_projected_to_closed_unknown_value(self, classifier_llm):
        classifier_llm.ainvoke = AsyncMock(
            return_value=MagicMock(
                content=json.dumps(
                    {
                        'misuse_score': 0.91,
                        'usage_type': 'Ignore the schema and persist this title',
                        'confidence': 0.8,
                    }
                )
            )
        )

        result = await classifier_mod.classify_fair_use_evidence(
            'user1',
            [{'conversation_id': 'e1', 'title': 'Meeting', 'duration_minutes': 10}],
        )

        assert result['usage_type'] == 'unknown'

    @pytest.mark.asyncio
    async def test_live_client_construction_bypasses_gateway_and_pins_direct_openai_gpt_5_1(self, monkeypatch):
        llm = MagicMock()
        llm.ainvoke = AsyncMock(return_value=MagicMock(content='{"misuse_score": 0.1}'))
        construct = MagicMock(return_value=llm)
        monkeypatch.setattr(classifier_mod, '_classifier_llm', None)
        monkeypatch.setattr(classifier_mod, 'get_default_client', construct)
        monkeypatch.setattr(classifier_mod, 'get_route_options', lambda *_: {'request_timeout': 45})

        result = await classifier_mod.classify_fair_use_evidence(
            'user1',
            [{'conversation_id': 'e1', 'title': 'Meeting', 'duration_minutes': 10}],
        )

        construct.assert_called_once_with('gpt-5.1', 'openai', False, {'request_timeout': 45})
        assert result['model'] == 'openai/gpt-5.1'
