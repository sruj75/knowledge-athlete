"""Behavioral prompt-cache contracts for retained direct conversation workloads."""

from __future__ import annotations

from datetime import datetime, timezone
import inspect

from models.calendar_context import CalendarMeetingContext, MeetingParticipant
from utils.llm import clients, conversation_processing, model_config
from utils.llm.conversation_processing import _build_conversation_context


def _calendar(**overrides):
    values = {
        'calendar_event_id': 'event-1',
        'title': 'Sprint Planning',
        'start_time': datetime(2025, 3, 15, 10, 0, tzinfo=timezone.utc),
        'duration_minutes': 30,
        'platform': 'Zoom',
        'notes': 'Discuss backlog items',
        'meeting_link': 'https://zoom.us/j/123',
        'participants': [MeetingParticipant(name='Bob', email='bob@example.com')],
    }
    values.update(overrides)
    return CalendarMeetingContext(**values)


def test_conversation_context_is_deterministic_and_calendar_precedes_transcript():
    calendar = _calendar()
    transcript = 'Speaker 0: Review the backlog.'

    first = _build_conversation_context(transcript, calendar)
    second = _build_conversation_context(transcript, calendar)

    assert first == second
    assert first.index('CALENDAR MEETING CONTEXT') < first.index('Transcript:')
    assert 'Meeting Link: https://zoom.us/j/123' in first
    assert 'Bob <bob@example.com>' in first


def test_conversation_context_omits_absent_optional_calendar_fields():
    context = _build_conversation_context(
        'Speaker 0: Hello',
        _calendar(platform=None, notes=None, meeting_link=None, participants=[]),
    )

    assert 'Meeting Notes' not in context
    assert 'Meeting Link' not in context


def test_conversation_context_without_content_is_empty():
    assert _build_conversation_context('', None) == ''
    assert _build_conversation_context('   ', None) == ''


def test_retained_prompts_keep_static_instructions_before_dynamic_context():
    for function in (conversation_processing.get_transcript_structure, conversation_processing.extract_action_items):
        source = inspect.getsource(function)
        assert source.index("('system', instructions_text)") < source.index("('system', context_message)")


def test_direct_workload_client_binds_bounded_cache_key(monkeypatch):
    bound = []

    class FakeClient:
        def bind(self, **kwargs):
            bound.append(kwargs)
            return self

    fake_client = FakeClient()
    monkeypatch.setattr(clients, 'get_default_client', lambda *_args, **_kwargs: fake_client)

    assert clients.get_workload_client('conv_structure', cache_key='omi-transcript-structure') is fake_client
    assert bound == [{'prompt_cache_key': 'omi-transcript-structure'}]


def test_retained_openai_route_owns_cache_retention():
    assert model_config.get_route_options('conv_structure') == {'extra_body': {'prompt_cache_retention': '24h'}}
    assert model_config.supports_prompt_cache('gpt-5.9-turbo')
    assert model_config.supports_cache_retention('gpt-5.1')
    assert model_config.supports_prompt_cache('gpt-4.1-mini')
    assert not model_config.supports_cache_retention('gpt-4.1-mini')
    assert not model_config.supports_prompt_cache('gemini-2.5-flash-lite')


def test_retained_conversation_workloads_use_distinct_non_user_cache_keys():
    structure_source = inspect.getsource(conversation_processing.get_transcript_structure)
    action_source = inspect.getsource(conversation_processing.extract_action_items)

    assert "cache_key='omi-transcript-structure'" in structure_source
    assert "cache_key='omi-extract-actions'" in action_source
