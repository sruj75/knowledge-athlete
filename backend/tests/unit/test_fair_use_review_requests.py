import json
import logging
from datetime import datetime, timedelta, timezone
from unittest.mock import AsyncMock, Mock

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from models.fair_use import FairUseClassificationRequest
from models.users import PlanType
from routers import fair_use_reviews
from utils import fair_use_reviews as review_state
from utils.other.endpoints import get_current_user_uid
import database.fair_use as fair_use_db
from tests.unit.fixtures.strict_firestore_transaction import StrictFirestore


def evidence(token: str = 'request-token') -> dict:
    return {
        'conversation_id': token,
        'title': 'Planning',
        'overview': 'A local meeting overview',
        'category': 'work',
        'duration_minutes': 12.5,
        'source': 'desktop',
        'created_at': '2026-08-21T07:30:00Z',
    }


def assert_redis_fallback(fallback: Mock, from_mode: str) -> None:
    fallback.assert_called_once_with(
        component='fair_use',
        from_mode=from_mode,
        to_mode='redis_unavailable',
        reason='other',
        outcome='degraded',
        log=review_state.logger,
    )


def test_classification_request_is_strict_bounded_and_content_only():
    request = FairUseClassificationRequest(conversations=[evidence(str(index)) for index in range(30)])
    assert len(request.conversations) == 30

    with pytest.raises(ValidationError):
        FairUseClassificationRequest(conversations=[evidence(str(index)) for index in range(31)])
    with pytest.raises(ValidationError):
        FairUseClassificationRequest(conversations=[evidence() | {'transcript': 'must never cross'}])
    with pytest.raises(ValidationError):
        FairUseClassificationRequest(conversations=[evidence() | {'score': 1.0}])


def test_processing_claim_outlives_the_model_timeout_without_consuming_the_review_window(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    client = StrictFirestore()
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    token = fair_use_db.claim_fair_use_review_processing('owner-a', 'review-1', firestore_client=client, now=now)

    assert token is not None
    processing = client.rows[('users', 'owner-a', 'fair_use_review_processing', 'review-1')]
    assert processing['claim_token'] == token
    assert processing['expires_at'] == now + timedelta(minutes=5)


def test_stale_processing_owner_cannot_release_a_reacquired_lock(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    client = StrictFirestore()
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    first_token = fair_use_db.claim_fair_use_review_processing('owner-a', 'review-1', firestore_client=client, now=now)
    second_token = fair_use_db.claim_fair_use_review_processing(
        'owner-a', 'review-1', firestore_client=client, now=now + timedelta(minutes=5)
    )
    assert first_token is not None and second_token is not None and first_token != second_token

    fair_use_db.release_fair_use_review_processing(
        'owner-a', 'review-1', first_token, firestore_client=client, now=now + timedelta(minutes=5)
    )

    processing = client.rows[('users', 'owner-a', 'fair_use_review_processing', 'review-1')]
    assert processing['claim_token'] == second_token


def test_pending_review_is_content_free_uid_bound_and_exactly_twelve_hours(monkeypatch):
    redis = Mock()
    redis.eval.return_value = 1
    monkeypatch.setattr(review_state.redis_db, 'r', redis)
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    review = review_state.create_pending_fair_use_review(
        'owner-a',
        [{'trigger': 'daily', 'speech_ms': 7_200_001, 'threshold_ms': 7_200_000}],
        {'daily_ms': 7_200_001, 'three_day_ms': 8_000_000, 'weekly_ms': 10_000_000},
        PlanType.bounded,
        'listen-1',
        now=now,
    )

    assert review is not None
    assert review['classifier_contract'] == 'gemini/gemini-3.7-flash:prompt-v2'
    assert review['thresholds_ms'] == {
        'daily_ms': 7_200_000,
        'three_day_ms': 28_800_000,
        'weekly_ms': 36_000_000,
    }
    assert datetime.fromisoformat(review['expires_at']) - datetime.fromisoformat(review['requested_at']) == timedelta(
        hours=12
    )
    assert not {'uid', 'title', 'overview', 'conversation_id', 'score', 'stage', 'action'} & review.keys()
    call = redis.eval.call_args.args
    assert call[:5] == (
        review_state._CREATE_PENDING_REVIEW_SCRIPT,
        2,
        'fair_use:review:cooldown:owner-a',
        'fair_use:review:pending:owner-a',
        review['review_id'],
    )
    assert call[5] == 12 * 60 * 60
    stored = json.loads(call[6])
    assert stored == review


def test_pending_review_redis_failure_is_caught_without_stranding_a_cooldown(monkeypatch):
    redis = Mock()
    redis.eval.side_effect = RuntimeError('redis unavailable')
    monkeypatch.setattr(review_state.redis_db, 'r', redis)
    fallback = Mock()
    monkeypatch.setattr(review_state, 'record_fallback', fallback, raising=False)

    result = review_state.create_pending_fair_use_review(
        'owner-a',
        [{'trigger': 'daily'}],
        {'daily_ms': 7_200_001},
        PlanType.bounded,
    )

    assert result is None
    redis.set.assert_not_called()
    redis.setex.assert_not_called()
    assert_redis_fallback(fallback, 'pending_review_create')


def test_pending_review_read_fails_open_when_redis_is_unavailable(monkeypatch):
    redis = Mock()
    redis.get.side_effect = RuntimeError('redis unavailable')
    monkeypatch.setattr(review_state.redis_db, 'r', redis)
    fallback = Mock()
    monkeypatch.setattr(review_state, 'record_fallback', fallback, raising=False)

    assert review_state.get_pending_fair_use_review('owner-a') is None
    assert_redis_fallback(fallback, 'pending_review_read')


def test_pending_review_consumption_is_compare_and_delete_by_review_id(monkeypatch):
    redis = Mock()
    monkeypatch.setattr(review_state.redis_db, 'r', redis)

    review_state.mark_fair_use_review_consumed('owner-a', 'review-a')

    redis.eval.assert_called_once_with(
        review_state._CONSUME_PENDING_REVIEW_SCRIPT,
        1,
        'fair_use:review:pending:owner-a',
        'review-a',
    )


def test_pending_review_consume_fails_open_when_redis_is_unavailable(monkeypatch):
    redis = Mock()
    redis.eval.side_effect = RuntimeError('redis unavailable')
    monkeypatch.setattr(review_state.redis_db, 'r', redis)
    fallback = Mock()
    monkeypatch.setattr(review_state, 'record_fallback', fallback, raising=False)

    result = review_state.mark_fair_use_review_consumed('owner-a', 'review-a')

    assert result is None
    assert_redis_fallback(fallback, 'pending_review_consume')


def test_pending_review_redis_failures_never_log_the_uid(monkeypatch, caplog):
    uid = 'private-owner-uid-9284'
    redis = Mock()
    redis.eval.side_effect = RuntimeError('redis unavailable')
    redis.get.side_effect = RuntimeError('redis unavailable')
    monkeypatch.setattr(review_state.redis_db, 'r', redis)

    with caplog.at_level(logging.WARNING, logger=review_state.logger.name):
        assert (
            review_state.create_pending_fair_use_review(
                uid,
                [{'trigger': 'daily'}],
                {'daily_ms': 7_200_001},
                PlanType.bounded,
            )
            is None
        )
        assert review_state.get_pending_fair_use_review(uid) is None
        assert review_state.mark_fair_use_review_consumed(uid, 'review-a') is None

    assert uid not in caplog.text


def make_client(uid: str = 'owner-a') -> TestClient:
    app = FastAPI()
    app.include_router(fair_use_reviews.router)
    app.dependency_overrides[get_current_user_uid] = lambda: uid
    return TestClient(app)


def test_authenticated_classify_uses_pending_uid_and_returns_content_free_receipt(monkeypatch):
    requested_at = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    monkeypatch.setattr(fair_use_reviews, '_now', lambda: requested_at + timedelta(hours=1))
    pending = {
        'review_id': 'review-1',
        'uid': 'owner-a',
        'trigger': 'daily',
        'window_speech_ms': {'daily_ms': 7_200_001, 'three_day_ms': 7_200_001, 'weekly_ms': 7_200_001},
        'thresholds_ms': {'daily_ms': 7_200_000, 'three_day_ms': 28_800_000, 'weekly_ms': 36_000_000},
        'classifier_contract': 'gemini/gemini-3.7-flash:prompt-v2',
        'requested_at': requested_at.isoformat(),
        'expires_at': (requested_at + timedelta(hours=12)).isoformat(),
        'session_id': 'listen-1',
    }
    monkeypatch.setattr(fair_use_reviews, 'get_pending_fair_use_review', lambda uid, review_id: pending)
    classify = AsyncMock(
        return_value={
            'misuse_score': 0.92,
            'usage_type': 'audiobook',
            'confidence': 0.88,
            'evidence': [{'title': 'must be discarded'}],
            'reasoning': 'must be discarded',
            'model': 'gemini/gemini-3.7-flash',
            'prompt_version': 'v2',
        }
    )
    monkeypatch.setattr(fair_use_reviews, 'classify_fair_use_evidence', classify)
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    apply = lambda uid, review, result, *, claim_token: {
        'review_id': review['review_id'],
        'accepted': True,
        'idempotent': False,
        'action': 'warning',
        'stage': 'warning',
        'case_ref': 'FU-ABC123',
    }
    monkeypatch.setattr(fair_use_reviews, 'apply_fair_use_review_result', apply)
    monkeypatch.setattr(fair_use_reviews, 'mark_fair_use_review_consumed', lambda *_: None)
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', lambda *_: 'claim-token')
    release = Mock()
    monkeypatch.setattr(fair_use_reviews, 'release_fair_use_review_processing', release)
    invalidate = Mock()
    monkeypatch.setattr(fair_use_reviews, 'invalidate_enforcement_cache', invalidate)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 200
    assert response.json() == {
        'review_id': 'review-1',
        'accepted': True,
        'idempotent': False,
        'action': 'warning',
        'stage': 'warning',
        'case_ref': 'FU-ABC123',
    }
    classify.assert_awaited_once_with('owner-a', [evidence()])
    invalidate.assert_called_once_with('owner-a')
    release.assert_called_once_with('owner-a', 'review-1', 'claim-token')
    assert 'title' not in response.text
    assert 'reasoning' not in response.text


def test_duplicate_returns_receipt_without_model_or_pending_payload(monkeypatch):
    receipt = {
        'review_id': 'review-1',
        'accepted': True,
        'idempotent': True,
        'action': 'warning',
        'stage': 'warning',
        'case_ref': 'FU-ABC123',
    }
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: receipt)
    pending = lambda *_: pytest.fail('duplicate must not need transient evidence state')
    monkeypatch.setattr(fair_use_reviews, 'get_pending_fair_use_review', pending)
    classify = AsyncMock()
    monkeypatch.setattr(fair_use_reviews, 'classify_fair_use_evidence', classify)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 200
    assert response.json()['idempotent'] is True
    classify.assert_not_awaited()


def test_unknown_or_other_owner_review_fails_closed(monkeypatch):
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(fair_use_reviews, 'get_pending_fair_use_review', lambda *_: None)

    response = make_client(uid='owner-b').post(
        '/v1/fair-use/reviews/review-for-owner-a/classify', json={'conversations': [evidence()]}
    )

    assert response.status_code == 404


@pytest.mark.parametrize(
    'conversations',
    [
        [evidence() | {'created_at': '2026-08-14T07:59:59Z'}],
        [evidence() | {'created_at': '2026-08-21T08:00:01Z'}],
        [
            evidence('older') | {'created_at': '2026-08-20T07:00:00Z'},
            evidence('newer') | {'created_at': '2026-08-20T08:00:00Z'},
        ],
    ],
)
def test_classify_rejects_evidence_outside_requested_seven_day_newest_first_window(monkeypatch, conversations):
    requested_at = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(
        fair_use_reviews,
        'get_pending_fair_use_review',
        lambda *_: {
            'review_id': 'review-1',
            'requested_at': requested_at.isoformat(),
        },
    )
    claim = Mock()
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', claim)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': conversations})

    assert response.status_code == 422
    assert response.json() == {'detail': 'invalid_evidence_window'}
    claim.assert_not_called()


def test_concurrent_duplicate_cannot_invoke_model_twice(monkeypatch):
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(
        fair_use_reviews,
        'get_pending_fair_use_review',
        lambda *_: {
            'review_id': 'review-1',
            'requested_at': datetime(2026, 8, 21, 8, tzinfo=timezone.utc).isoformat(),
        },
    )
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', lambda *_: None)
    classify = AsyncMock()
    monkeypatch.setattr(fair_use_reviews, 'classify_fair_use_evidence', classify)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 409
    assert response.json() == {'detail': 'review_in_progress'}
    classify.assert_not_awaited()


@pytest.mark.asyncio
async def test_processing_claim_storage_failure_fails_closed_before_model(monkeypatch):
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(
        fair_use_reviews,
        'get_pending_fair_use_review',
        lambda *_: {
            'review_id': 'review-1',
            'requested_at': datetime(2026, 8, 21, 8, tzinfo=timezone.utc).isoformat(),
            'expires_at': datetime(2026, 8, 21, 20, tzinfo=timezone.utc).isoformat(),
        },
    )
    monkeypatch.setattr(
        fair_use_reviews,
        'claim_fair_use_review_processing',
        Mock(side_effect=RuntimeError('firestore unavailable')),
    )
    classify = AsyncMock()
    monkeypatch.setattr(fair_use_reviews, 'classify_fair_use_evidence', classify)

    with pytest.raises(RuntimeError, match='firestore unavailable'):
        await fair_use_reviews.classify_review(
            'review-1',
            FairUseClassificationRequest(conversations=[evidence()]),
            uid='owner-a',
        )

    classify.assert_not_awaited()


def test_lock_loser_repairs_committed_cache(monkeypatch):
    receipt = {
        'review_id': 'review-1',
        'accepted': True,
        'idempotent': True,
        'action': 'warning',
        'stage': 'warning',
        'case_ref': 'FU-ABC123',
    }
    receipts = iter([None, receipt])
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: next(receipts))
    monkeypatch.setattr(
        fair_use_reviews,
        'get_pending_fair_use_review',
        lambda *_: {
            'review_id': 'review-1',
            'requested_at': datetime(2026, 8, 21, 8, tzinfo=timezone.utc).isoformat(),
        },
    )
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', lambda *_: None)
    invalidate = Mock()
    monkeypatch.setattr(fair_use_reviews, 'invalidate_enforcement_cache', invalidate)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 200
    invalidate.assert_called_once_with('owner-a')


def test_review_expiring_during_model_call_cannot_mutate_enforcement(monkeypatch):
    requested_at = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    pending = {
        'review_id': 'review-1',
        'requested_at': requested_at.isoformat(),
        'expires_at': (requested_at + timedelta(hours=12)).isoformat(),
    }
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(fair_use_reviews, 'get_pending_fair_use_review', lambda *_: pending)
    monkeypatch.setattr(fair_use_reviews, '_now', lambda: requested_at + timedelta(hours=12))
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', lambda *_: 'claim-token')
    monkeypatch.setattr(fair_use_reviews, 'release_fair_use_review_processing', Mock())
    monkeypatch.setattr(
        fair_use_reviews,
        'classify_fair_use_evidence',
        AsyncMock(return_value={'misuse_score': 1.0, 'usage_type': 'audiobook'}),
    )
    apply = Mock()
    monkeypatch.setattr(fair_use_reviews, 'apply_fair_use_review_result', apply)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 404
    apply.assert_not_called()


def test_worker_that_loses_processing_lease_cannot_accept_model_result(monkeypatch):
    requested_at = datetime.now(timezone.utc)
    pending = {
        'review_id': 'review-1',
        'requested_at': requested_at.isoformat(),
        'expires_at': (requested_at + timedelta(hours=12)).isoformat(),
    }
    monkeypatch.setattr(fair_use_reviews, 'get_fair_use_review_receipt', lambda *_: None)
    monkeypatch.setattr(fair_use_reviews, 'get_pending_fair_use_review', lambda *_: pending)
    monkeypatch.setattr(fair_use_reviews, 'claim_fair_use_review_processing', lambda *_: 'stale-token')
    monkeypatch.setattr(fair_use_reviews, 'release_fair_use_review_processing', Mock())
    monkeypatch.setattr(
        fair_use_reviews,
        'classify_fair_use_evidence',
        AsyncMock(return_value={'misuse_score': 1.0, 'usage_type': 'audiobook'}),
    )
    apply = Mock(side_effect=fair_use_reviews.FairUseReviewProcessingClaimLost('lease taken over'))
    monkeypatch.setattr(fair_use_reviews, 'apply_fair_use_review_result', apply)

    response = make_client().post('/v1/fair-use/reviews/review-1/classify', json={'conversations': [evidence()]})

    assert response.status_code == 409
    assert response.json() == {'detail': 'review_in_progress'}
    apply.assert_called_once()
