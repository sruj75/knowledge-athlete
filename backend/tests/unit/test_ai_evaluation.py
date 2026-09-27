from contextlib import contextmanager

import pytest

from models.desktop_ai import (
    SupervisorDecisionObservation,
    SupervisorRequest,
    SupervisorResponse,
    ScoreObservation,
    TerminalTurnObservation,
)
from utils.observability import ai_evaluation


@pytest.mark.parametrize('sharing', [False, True])
def test_explicit_supervisor_example_exports_only_reviewed_text_when_enabled(monkeypatch, sharing):
    started, updated, propagated = [], [], []

    class Observation:
        def update(self, **kwargs):
            updated.append(kwargs)

        def end(self):
            pass

    class Client:
        def start_observation(self, **kwargs):
            started.append(kwargs)
            return Observation()

    @contextmanager
    def attributes(**kwargs):
        propagated.append(kwargs)
        yield

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(ai_evaluation, 'propagate_attributes', attributes)
    monkeypatch.setattr(ai_evaluation, 'claim_observation', lambda *_: True)
    event = SupervisorDecisionObservation(
        kind='supervisor_decision',
        decision_id='decision-1',
        observation_id='observation-1',
        session_id='session-1',
        prompt={'name': 'intentive-supervisor-system', 'version': '9', 'source': 'langfuse'},
        evaluation_sharing=sharing,
        transcripts=[{'id': 't1', 'source': 'mixed', 'text': 'synthetic speech'}],
        conversation=[{'turn_id': 'turn-1', 'role': 'assistant', 'text': 'synthetic response'}],
        note='synthetic guidance',
    )
    ai_evaluation.record_client_observation(uid='owner-1', event=event)
    assert len(started) == 1
    assert propagated[0]['metadata']['decision_id'] == 'decision-1'
    assert propagated[0]['metadata']['observation_id'] == 'observation-1'
    exported = str(started) + str(updated)
    assert ('synthetic speech' in exported) is sharing
    assert ('synthetic response' in exported) is sharing
    assert ('synthetic guidance' in exported) is sharing
    assert started[0]['trace_context']['trace_id'] == ai_evaluation.trace_id('owner-1', 'session-1', 'decision-1')


def test_trace_identity_cannot_cross_owners():
    assert ai_evaluation.trace_id('owner-1', 'session', 'turn') != ai_evaluation.trace_id('owner-2', 'session', 'turn')


def test_inflight_supervisor_trace_is_metadata_only_even_when_sharing_was_enabled(monkeypatch):
    captured = []

    class Observation:
        def update(self, **kwargs):
            captured.append(kwargs)

        def end(self):
            pass

    class Client:
        def start_observation(self, **kwargs):
            captured.append(kwargs)
            return Observation()

    @contextmanager
    def attributes(**kwargs):
        captured.append(kwargs)
        yield

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(ai_evaluation, 'propagate_attributes', attributes)
    request = SupervisorRequest(
        observation_id='obs',
        session_id='session',
        context_epoch=0,
        evaluation_sharing=True,
        transcripts=[{'id': 't1', 'text': 'TRANSCRIPT_SENTINEL', 'source': 'mixed'}],
        memories=['MEMORY_SENTINEL'],
        profile='PROFILE_SENTINEL',
    )
    response = SupervisorResponse(
        action='intervene',
        note='GUIDANCE_SENTINEL',
        decision_id='decision',
        observation_id='obs',
        session_id='session',
        context_epoch=0,
        prompt={'text': 'behavior', 'name': 'intentive-supervisor-system', 'version': '1', 'source': 'langfuse'},
        outcome='completed',
    )
    ai_evaluation.record_supervisor_observation(
        uid='owner', request=request, response=response, prompt_client=None, duration_ms=10
    )
    exported = str(captured)
    assert 'SENTINEL' not in exported
    assert 'intervene' in exported
    assert captured[0]['metadata']['observation_id'] == 'obs'
    assert captured[0]['metadata']['decision_id'] == 'decision'


def test_repeated_scores_upsert_same_owner_scoped_record(monkeypatch):
    scores = []

    class Client:
        def create_score(self, **kwargs):
            from inspect import signature

            signature(ai_evaluation.Langfuse.create_score).bind(self, **kwargs)
            scores.append(kwargs)

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    event = ScoreObservation(kind='score', session_id='session', turn_id='turn', decision_id='decision', value=1)
    ai_evaluation.record_client_observation(uid='owner', event=event)
    event.value = 0
    ai_evaluation.record_client_observation(uid='owner', event=event)
    ai_evaluation.record_client_observation(uid='other-owner', event=event)
    assert scores[0]['score_id'] == scores[1]['score_id']
    assert scores[1]['value'] == 0
    assert scores[0]['metadata'] == {'turn_id': 'turn', 'decision_id': 'decision'}
    assert scores[0]['session_id'] == 'session'
    assert scores[2]['score_id'] != scores[0]['score_id']
    assert scores[2]['trace_id'] != scores[0]['trace_id']


def test_normal_terminal_retains_identifiers_without_exporting_conversation(monkeypatch):
    propagated, started = [], []

    class Observation:
        def end(self):
            pass

    class Client:
        def start_observation(self, **kwargs):
            started.append(kwargs)
            return Observation()

    @contextmanager
    def attributes(**kwargs):
        propagated.append(kwargs)
        yield

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(ai_evaluation, 'propagate_attributes', attributes)
    monkeypatch.setattr(ai_evaluation, 'claim_observation', lambda *_: True)
    event = TerminalTurnObservation(
        kind='terminal_turn',
        session_id='session',
        turn_id='turn',
        decision_id='decision',
        outcome='completed',
        duration_ms=100,
        prompt={'name': 'intentive-live-system', 'version': '4', 'source': 'langfuse'},
        conversation=[{'turn_id': 'turn', 'role': 'assistant', 'text': 'PRIVATE_SENTINEL'}],
    )
    ai_evaluation.record_client_observation(uid='owner', event=event)
    assert propagated[0]['metadata']['turn_id'] == 'turn'
    assert propagated[0]['metadata']['decision_id'] == 'decision'
    assert 'PRIVATE_SENTINEL' not in str(started) + str(propagated)


@pytest.mark.parametrize('sharing', [False, True])
def test_chat_example_joins_actual_prompt_and_trace(monkeypatch, sharing):
    from models.desktop_ai import ChatTerminalObservation, PromptReference
    from utils.observability.langfuse import create_chat_trace_id

    started, propagated = [], []

    class Observation:
        def end(self):
            pass

    class Client:
        def start_observation(self, **kwargs):
            started.append(kwargs)
            return Observation()

    @contextmanager
    def attributes(**kwargs):
        propagated.append(kwargs)
        yield

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(ai_evaluation, 'propagate_attributes', attributes)
    monkeypatch.setattr(ai_evaluation, 'claim_observation', lambda *_: True)
    monkeypatch.setattr(
        ai_evaluation,
        'chat_prompt_reference',
        lambda *_: PromptReference(name='intentive-chat-system', version='17', source='langfuse'),
    )
    event = ChatTerminalObservation(
        kind='chat_terminal',
        session_id='selected-session',
        turn_id='canonical-turn',
        request_id='actual-retry-request',
        outcome='completed',
        duration_ms=42,
        evaluation_sharing=sharing,
        conversation=[
            {'turn_id': 'canonical-turn', 'role': 'user', 'text': 'SELECTED_QUESTION'},
            {'turn_id': 'canonical-turn', 'role': 'assistant', 'text': 'SELECTED_ANSWER'},
        ],
    )
    ai_evaluation.record_client_observation(uid='owner', event=event)
    assert started[0]['trace_context']['trace_id'] == create_chat_trace_id('owner', 'actual-retry-request')
    assert propagated[0]['metadata']['prompt_name'] == 'intentive-chat-system'
    assert propagated[0]['metadata']['prompt_version'] == '17'
    assert propagated[0]['metadata']['request_id'] == 'actual-retry-request'
    exported = str(started) + str(propagated)
    assert ('SELECTED_QUESTION' in exported) is sharing
    assert ('SELECTED_ANSWER' in exported) is sharing
    assert all(key not in started[0]['input'] for key in ['tools', 'memories', 'profile', 'screen', 'audio'])


def test_chat_without_actual_prompt_receipt_does_not_invent_live_prompt(monkeypatch):
    from models.desktop_ai import ChatTerminalObservation

    class Client:
        def start_observation(self, **kwargs):
            pytest.fail('missing Chat prompt must not produce a mislabeled example')

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    monkeypatch.setattr(ai_evaluation, 'chat_prompt_reference', lambda *_: None)
    event = ChatTerminalObservation(
        kind='chat_terminal', session_id='s', turn_id='t', request_id='r', outcome='completed', duration_ms=1
    )
    ai_evaluation.record_client_observation(uid='owner', event=event)


def test_chat_prompt_cache_is_owner_scoped_metadata_only_and_expires(monkeypatch):
    from models.desktop_ai import PromptReference
    from utils.observability import chat_evaluation

    saved = {}
    expirations = []

    class Redis:
        def set(self, key, value, *, ex):
            saved[key] = value
            expirations.append(ex)

        def get(self, key):
            return saved.get(key)

    monkeypatch.setattr(chat_evaluation, 'get_redis_client', lambda: Redis())
    prompt = PromptReference(name='intentive-chat-system', version='17', source='langfuse')
    chat_evaluation.remember_chat_prompt('owner', 'actual-request', prompt)
    assert chat_evaluation.chat_prompt_reference('owner', 'actual-request') == prompt
    assert chat_evaluation.chat_prompt_reference('another-owner', 'actual-request') is None
    assert chat_evaluation.chat_prompt_reference('owner', 'failed-request') is None
    assert expirations == [86400]
    import json

    assert set(json.loads(next(iter(saved.values())))) == {'name', 'version', 'source'}
    saved[next(iter(saved))] = 'invalid receipt'
    assert chat_evaluation.chat_prompt_reference('owner', 'actual-request') is None


def test_chat_feedback_joins_managed_chat_trace(monkeypatch):
    from utils.observability.langfuse import create_chat_trace_id

    scores = []

    class Client:
        def create_score(self, **kwargs):
            scores.append(kwargs)

    monkeypatch.setattr(ai_evaluation, 'get_langfuse_client', lambda: Client())
    event = ScoreObservation(kind='score', session_id='s', turn_id='t', request_id='successful-request', value=1)
    ai_evaluation.record_client_observation(uid='owner', event=event)
    assert scores[0]['trace_id'] == create_chat_trace_id('owner', 'successful-request')
    assert scores[0]['metadata']['request_id'] == 'successful-request'
    assert 'score_id' in scores[0]


def test_chat_terminal_rejects_client_prompt_and_provider_payloads():
    from models.desktop_ai import ChatTerminalObservation
    from pydantic import ValidationError

    event = dict(kind='chat_terminal', session_id='s', turn_id='t', request_id='r', outcome='completed', duration_ms=1)
    for forbidden in ['prompt', 'tools', 'memories', 'profile', 'screen', 'audio']:
        with pytest.raises(ValidationError):
            ChatTerminalObservation.model_validate({**event, forbidden: 'must never enter export'})
