from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

from fastapi import FastAPI
from fastapi.testclient import TestClient

from routers import conversation_compute
from models.structured import ActionItem
from utils.other.endpoints import get_current_user_uid


def make_client(*, authenticated: bool = True) -> TestClient:
    app = FastAPI()
    app.include_router(conversation_compute.router)
    if authenticated:
        app.dependency_overrides[get_current_user_uid] = lambda: 'user-1'
    return TestClient(app)


def test_discard_requires_authentication():
    response = make_client(authenticated=False).post(
        '/v1/conversation-compute/discard',
        json={'generation_id': str(uuid4()), 'transcript': 'remember this', 'duration_seconds': 4},
    )

    assert response.status_code == 401


def test_discard_rejects_blank_oversized_and_invalid_duration_without_classification(monkeypatch):
    calls = []
    monkeypatch.setattr(conversation_compute, 'classify_discard', lambda *_: calls.append(True) or False)
    client = make_client()
    generation_id = str(uuid4())

    blank = client.post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': ' \n ', 'duration_seconds': 1},
    )
    oversized = client.post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': 'x' * 1_000_001, 'duration_seconds': 1},
    )
    negative = client.post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': 'hello', 'duration_seconds': -1},
    )
    infinite = client.post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': 'hello', 'duration_seconds': 'Infinity'},
    )

    assert [blank.status_code, oversized.status_code, negative.status_code, infinite.status_code] == [422] * 4
    assert calls == []


def test_discard_over_one_hundred_words_keeps_without_model_call(monkeypatch):
    model_calls = []
    monkeypatch.setattr(
        conversation_compute.conversation_processing,
        'get_workload_client',
        lambda *_args, **_kwargs: model_calls.append(True),
    )
    generation_id = str(uuid4())

    response = make_client().post(
        '/v1/conversation-compute/discard',
        json={
            'generation_id': generation_id,
            'transcript': ' '.join(f'word-{index}' for index in range(101)),
            'duration_seconds': 30,
        },
    )

    assert response.status_code == 200
    assert response.json() == {'generation_id': generation_id, 'discard': False}
    assert model_calls == []


def test_discard_echoes_generation_and_tracks_the_discard_feature(monkeypatch):
    usage = []

    @contextmanager
    def tracked(uid, feature):
        usage.append((uid, feature))
        yield

    monkeypatch.setattr(conversation_compute, 'track_usage', tracked)
    monkeypatch.setattr(conversation_compute, 'classify_discard', lambda transcript, duration: True)
    generation_id = str(uuid4())

    response = make_client().post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': 'okay', 'duration_seconds': 3.5},
    )

    assert response.status_code == 200
    assert response.json() == {'generation_id': generation_id, 'discard': True}
    assert usage == [('user-1', 'conv_discard')]


def test_discard_classifier_failure_is_distinguishable_and_does_not_leak_the_error(monkeypatch):
    def fail(*_args):
        raise RuntimeError('secret provider detail')

    monkeypatch.setattr(conversation_compute, 'classify_discard', fail)
    generation_id = str(uuid4())

    response = make_client().post(
        '/v1/conversation-compute/discard',
        json={'generation_id': generation_id, 'transcript': 'short content', 'duration_seconds': 5},
    )

    assert response.status_code == 502
    assert response.json() == {'detail': 'compute_failed'}
    assert 'secret provider detail' not in response.text


def test_discard_router_has_no_persistence_collaborators():
    collaborator_modules = {
        value.__name__
        for value in vars(conversation_compute).values()
        if hasattr(value, '__name__') and isinstance(value.__name__, str)
    }

    assert not any(
        name == 'database' or name.startswith(('database.', 'services.', 'utils.conversations'))
        for name in collaborator_modules
    )


def test_structure_returns_only_retained_candidates_and_tracks_usage(monkeypatch):
    usage = []

    @contextmanager
    def tracked(uid, feature):
        usage.append((uid, feature))
        yield

    monkeypatch.setattr(conversation_compute, 'track_usage', tracked)
    monkeypatch.setattr(
        conversation_compute,
        'compute_structure_candidate',
        lambda request, uid: SimpleNamespace(
            title='Team Ships Local Conversations',
            overview='The team agreed on the local authority boundary.',
            emoji='✅',
            category='business',
            action_items=[{'description': 'must not leak'}],
            events=[
                SimpleNamespace(
                    title='Review',
                    description='Review the local result',
                    start=datetime(2026, 8, 18, 9, tzinfo=timezone.utc),
                    duration=30,
                    created=True,
                    meeting_link='must-not-leak',
                )
            ],
        ),
    )
    generation_id = str(uuid4())

    response = make_client().post(
        '/v1/conversation-compute/structure',
        json={
            'generation_id': generation_id,
            'transcript': 'User: We agreed to review tomorrow.',
            'started_at': '2026-08-17T03:30:00Z',
            'language': 'en',
            'output_language': 'en',
            'timezone': 'Asia/Kolkata',
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        'generation_id': generation_id,
        'title': 'Team Ships Local Conversations',
        'overview': 'The team agreed on the local authority boundary.',
        'emoji': '✅',
        'category': 'business',
        'commitments': [
            {
                'title': 'Review',
                'description': 'Review the local result',
                'start': '2026-08-18T09:00:00Z',
                'duration_minutes': 30,
                'created': False,
            }
        ],
    }
    assert usage == [('user-1', 'conv_structure')]
    assert 'meeting_link' not in response.text
    assert 'action_items' not in response.text


def test_structure_and_action_requests_enforce_shared_bounds_and_iana_timezone(monkeypatch):
    monkeypatch.setattr(conversation_compute, 'compute_structure_candidate', lambda *_: None)
    client = make_client()
    base = {
        'generation_id': str(uuid4()),
        'transcript': 'content',
        'started_at': '2026-08-17T03:30:00Z',
        'language': 'en',
        'output_language': 'en',
        'timezone': 'Not/AZone',
    }

    assert client.post('/v1/conversation-compute/structure', json=base).status_code == 422
    assert client.post('/v1/conversation-compute/action-items', json={**base, 'related_tasks': []}).status_code == 422


def test_action_items_filter_completed_context_validate_targets_and_track_separately(monkeypatch):
    captured = []
    usage = []

    @contextmanager
    def tracked(uid, feature):
        usage.append((uid, feature))
        yield

    def compute(request, uid):
        captured.extend(request.related_tasks)
        return [
            SimpleNamespace(
                description='Finish local conversation storage',
                due_at=datetime(2026, 8, 19, 12, tzinfo=timezone.utc),
                candidate_action='update',
                target_task_id='t0',
            )
        ]

    monkeypatch.setattr(conversation_compute, 'track_usage', tracked)
    monkeypatch.setattr(conversation_compute, 'compute_action_item_candidates', compute)
    generation_id = str(uuid4())
    response = make_client().post(
        '/v1/conversation-compute/action-items',
        json={
            'generation_id': generation_id,
            'transcript': 'User: Update the local conversation task.',
            'started_at': '2026-08-17T03:30:00Z',
            'language': 'en',
            'output_language': 'en',
            'timezone': 'UTC',
            'related_tasks': [
                {'token': 't0', 'description': 'Existing open task', 'completed': False},
                {'token': 't1', 'description': 'Completed task', 'completed': True},
            ],
        },
    )

    assert response.status_code == 200
    assert response.json() == {
        'generation_id': generation_id,
        'candidates': [
            {
                'action': 'update',
                'description': 'Finish local conversation storage',
                'target_task_token': 't0',
                'due_at': '2026-08-19T12:00:00Z',
            }
        ],
    }
    assert [task.token for task in captured] == ['t0']
    assert usage == [('user-1', 'conv_action_items')]


def test_action_items_reject_model_target_not_supplied_by_the_mac(monkeypatch):
    monkeypatch.setattr(
        conversation_compute,
        'compute_action_item_candidates',
        lambda *_: [
            SimpleNamespace(
                description='Mutate arbitrary task',
                due_at=None,
                candidate_action='complete',
                target_task_id='t9',
            )
        ],
    )

    response = make_client().post(
        '/v1/conversation-compute/action-items',
        json={
            'generation_id': str(uuid4()),
            'transcript': 'complete it',
            'started_at': '2026-08-17T03:30:00Z',
            'language': 'en',
            'output_language': 'en',
            'timezone': 'UTC',
            'related_tasks': [{'token': 't0', 'description': 'Allowed task'}],
        },
    )

    assert response.status_code == 502
    assert response.json() == {'detail': 'invalid_candidate_response'}


def test_action_items_provider_failure_is_not_reported_as_an_empty_success(monkeypatch):
    def fail(*_args, **_kwargs):
        raise RuntimeError('secret provider detail')

    monkeypatch.setattr(conversation_compute, 'compute_action_item_candidates', fail)

    response = make_client().post(
        '/v1/conversation-compute/action-items',
        json={
            'generation_id': str(uuid4()),
            'transcript': 'User: Please follow up.',
            'started_at': '2026-08-17T03:30:00Z',
            'language': 'en',
            'output_language': 'en',
            'timezone': 'UTC',
            'related_tasks': [],
        },
    )

    assert response.status_code == 502
    assert response.json() == {'detail': 'compute_failed'}
    assert 'secret provider detail' not in response.text


def test_past_due_normalization_logs_only_sanitized_metadata(caplog):
    sentinel = 'SENSITIVE TRANSCRIPT TASK'
    now = datetime(2026, 8, 17, 12, tzinfo=timezone.utc)
    item = ActionItem(description=sentinel, due_at=now - timedelta(days=2))

    conversation_compute.conversation_processing._normalize_action_item_due_dates(
        [item], user_tz=timezone.utc, now=now, log_past_due_clears=True
    )

    assert item.due_at is None
    assert 'Clearing action-item due date outside the retained time boundary' in caplog.text
    assert sentinel not in caplog.text
