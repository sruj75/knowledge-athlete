from datetime import datetime, timedelta, timezone
import threading

import pytest

import database.fair_use as fair_use_db
from tests.unit.fixtures.strict_firestore_transaction import StrictFirestore


def test_concurrent_review_claims_finish_with_exactly_one_owner():
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-1')
    client = StrictFirestore()
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    processing_barrier = threading.Barrier(2)
    processing_claims: list[str | None] = []

    def claim_processing() -> None:
        processing_barrier.wait()
        processing_claims.append(
            fair_use_db.claim_fair_use_review_processing('owner-a', 'review-1', firestore_client=client, now=now)
        )

    processing_threads = [threading.Thread(target=claim_processing) for _ in range(2)]
    for thread in processing_threads:
        thread.start()
    for thread in processing_threads:
        thread.join(timeout=2)

    assert all(not thread.is_alive() for thread in processing_threads)
    assert len(processing_claims) == 2
    assert sum(claim is not None for claim in processing_claims) == 1

    client.rows[receipt_path] = {'notification_pending': True}
    notification_barrier = threading.Barrier(2)
    notification_claims: list[str | None] = []

    def claim_notification() -> None:
        notification_barrier.wait()
        notification_claims.append(
            fair_use_db.claim_fair_use_review_notification('owner-a', 'review-1', firestore_client=client, now=now)
        )

    notification_threads = [threading.Thread(target=claim_notification) for _ in range(2)]
    for thread in notification_threads:
        thread.start()
    for thread in notification_threads:
        thread.join(timeout=2)

    assert all(not thread.is_alive() for thread in notification_threads)
    assert len(notification_claims) == 2
    assert sum(claim is not None for claim in notification_claims) == 1


def test_notification_delivery_claim_is_single_owner_and_token_fenced(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-1')
    client = StrictFirestore({receipt_path: {'notification_pending': True}})
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)

    first = fair_use_db.claim_fair_use_review_notification('owner-a', 'review-1', firestore_client=client, now=now)
    concurrent = fair_use_db.claim_fair_use_review_notification('owner-a', 'review-1', firestore_client=client, now=now)

    assert first is not None
    assert concurrent is None
    fair_use_db.release_fair_use_review_notification('owner-a', 'review-1', 'stale-token', firestore_client=client)
    assert client.rows[receipt_path]['notification_dispatch_token'] == first
    fair_use_db.release_fair_use_review_notification('owner-a', 'review-1', first, firestore_client=client)
    assert client.rows[receipt_path]['notification_dispatch_token'] is None

    second = fair_use_db.claim_fair_use_review_notification('owner-a', 'review-1', firestore_client=client, now=now)
    assert second is not None and second != first
    assert (
        fair_use_db.mark_fair_use_review_notification_sent(
            'owner-a', 'review-1', first, firestore_client=client, now=now
        )
        is False
    )
    assert fair_use_db.mark_fair_use_review_notification_sent(
        'owner-a', 'review-1', second, firestore_client=client, now=now
    )
    assert client.rows[receipt_path]['notification_pending'] is False


def test_review_receipt_uses_the_injected_firestore_client():
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-1')
    client = StrictFirestore(
        {
            receipt_path: {
                'review_id': 'review-1',
                'accepted': True,
                'action': 'warning',
                'stage': 'warning',
                'case_ref': 'FU-ABC123',
            }
        }
    )

    assert fair_use_db.get_fair_use_review_receipt('owner-a', 'review-1', firestore_client=client) == {
        'review_id': 'review-1',
        'accepted': True,
        'idempotent': True,
        'action': 'warning',
        'stage': 'warning',
        'case_ref': 'FU-ABC123',
    }


def test_transactional_review_core_persists_one_content_free_transition_and_idempotent_receipt(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    state_path = ('users', 'owner-a', 'fair_use_state', 'current')
    historical_event_path = ('users', 'owner-a', 'fair_use_events', 'older-review')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-1')
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-1')
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-1')
    client = StrictFirestore(
        {
            state_path: {'stage': 'warning'},
            historical_event_path: {
                'created_at': now - timedelta(days=2),
                'classifier_score': 0.9,
            },
            processing_path: {
                'claim_token': 'claim-token',
                'expires_at': now + timedelta(minutes=5),
            },
        }
    )
    review = {
        'review_id': 'review-1',
        'session_id': 'listen-1',
        'trigger': 'daily',
        'window_speech_ms': {'daily_ms': 7_200_001},
        'thresholds_ms': {'daily_ms': 7_200_000},
    }
    classifier_result = {
        'misuse_score': 0.95,
        'usage_type': 'audiobook',
        'confidence': 0.8,
        'model': 'openai/gpt-5.1',
        'prompt_version': 'v2',
        'evidence': [{'title': 'must not persist'}],
        'reasoning': 'must not persist',
    }

    first = fair_use_db.apply_fair_use_review_result(
        'owner-a', review, classifier_result, claim_token='claim-token', firestore_client=client, now=now
    )
    replay = fair_use_db.apply_fair_use_review_result(
        'owner-a', review, classifier_result, claim_token='claim-token', firestore_client=client, now=now
    )

    assert first['idempotent'] is False
    assert first['stage'] == 'throttle'
    assert replay == {**first, 'idempotent': True}
    assert client.rows[state_path]['stage'] == 'throttle'
    assert client.rows[state_path]['violation_count_7d'] == 2
    assert client.rows[state_path]['violation_count_30d'] == 2
    assert client.rows[receipt_path]['notification_pending'] is True
    assert client.rows[event_path]['new_stage'] == 'throttle'
    for forbidden in ('title', 'overview', 'category', 'source', 'time', 'duration', 'evidence', 'reasoning'):
        assert forbidden not in client.rows[event_path]
        assert forbidden not in client.rows[receipt_path]


def test_expired_restriction_positive_restricts_again_with_only_one_retained_event(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    state_path = ('users', 'owner-a', 'fair_use_state', 'current')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-rerestrict')
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-rerestrict')
    client = StrictFirestore(
        {
            state_path: {
                'stage': 'restrict',
                'restrict_until': now - timedelta(seconds=1),
            },
            processing_path: {
                'claim_token': 'claim-token',
                'expires_at': now + timedelta(minutes=5),
            },
        }
    )

    result = fair_use_db.apply_fair_use_review_result(
        'owner-a',
        {
            'review_id': 'review-rerestrict',
            'session_id': 'listen-rerestrict',
            'trigger': 'daily',
            'window_speech_ms': {'daily_ms': 7_200_001},
            'thresholds_ms': {'daily_ms': 7_200_000},
        },
        {'misuse_score': 0.95, 'usage_type': 'audiobook'},
        claim_token='claim-token',
        firestore_client=client,
        now=now,
    )

    assert result['action'] == 'restrict'
    assert result['stage'] == 'restrict'
    assert client.rows[state_path]['violation_count_7d'] == 1
    assert client.rows[state_path]['restrict_until'] == now + timedelta(days=30)
    assert client.rows[event_path]['previous_stage'] == 'throttle'
    assert client.rows[event_path]['new_stage'] == 'restrict'


def test_positive_at_concurrent_reset_boundary_is_history_but_not_a_strike(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    reset_at = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    requested_at = reset_at - timedelta(minutes=1)
    applied_at = reset_at + timedelta(minutes=1)
    state_path = ('users', 'owner-a', 'fair_use_state', 'current')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-reset-race')
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-reset-race')
    client = StrictFirestore(
        {
            state_path: {
                'stage': 'none',
                'reset_at': reset_at,
                'violation_count_7d': 0,
                'violation_count_30d': 0,
            },
            processing_path: {
                'claim_token': 'claim-token',
                'expires_at': applied_at + timedelta(minutes=5),
            },
        }
    )

    result = fair_use_db.apply_fair_use_review_result(
        'owner-a',
        {
            'review_id': 'review-reset-race',
            'requested_at': requested_at.isoformat(),
            'session_id': 'listen-reset-race',
            'trigger': 'daily',
            'window_speech_ms': {'daily_ms': 7_200_001},
            'thresholds_ms': {'daily_ms': 7_200_000},
        },
        {'misuse_score': 0.95, 'usage_type': 'audiobook'},
        claim_token='claim-token',
        firestore_client=client,
        now=applied_at,
    )

    assert result['action'] == 'none'
    assert result['stage'] == 'none'
    assert client.rows[state_path]['violation_count_7d'] == 0
    assert client.rows[state_path]['violation_count_30d'] == 0
    assert 'last_violation_at' not in client.rows[state_path]
    assert client.rows[event_path]['classifier_score'] == 0.95
    assert client.rows[event_path]['created_at'] == requested_at


def test_transaction_defensively_projects_usage_type_to_closed_enum(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    state_path = ('users', 'owner-a', 'fair_use_state', 'current')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-closed-type')
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-closed-type')
    client = StrictFirestore(
        {
            processing_path: {
                'claim_token': 'claim-token',
                'expires_at': now + timedelta(minutes=5),
            }
        }
    )

    fair_use_db.apply_fair_use_review_result(
        'owner-a',
        {
            'review_id': 'review-closed-type',
            'session_id': 'listen-closed-type',
            'trigger': 'daily',
            'window_speech_ms': {'daily_ms': 7_200_001},
            'thresholds_ms': {'daily_ms': 7_200_000},
        },
        {'misuse_score': 0.95, 'usage_type': 'content-specific injected value'},
        claim_token='claim-token',
        firestore_client=client,
        now=now,
    )

    assert client.rows[state_path]['last_classifier_type'] == 'unknown'
    assert client.rows[event_path]['classifier_type'] == 'unknown'


def test_review_transaction_commit_failure_persists_no_partial_state():
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    state_path = ('users', 'owner-a', 'fair_use_state', 'current')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-failed')
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-failed')
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-failed')
    original_state = {'stage': 'warning', 'sentinel': 'preserved'}
    client = StrictFirestore(
        {
            state_path: original_state,
            processing_path: {
                'claim_token': 'claim-token',
                'expires_at': now + timedelta(minutes=5),
            },
        },
        stage_transaction_writes=True,
        fail_transaction_commit=True,
    )

    with pytest.raises(RuntimeError, match='injected Firestore transaction commit failure'):
        fair_use_db.apply_fair_use_review_result(
            'owner-a',
            {
                'review_id': 'review-failed',
                'session_id': 'listen-failed',
                'trigger': 'daily',
                'window_speech_ms': {'daily_ms': 7_200_001},
                'thresholds_ms': {'daily_ms': 7_200_000},
            },
            {'misuse_score': 0.95, 'usage_type': 'audiobook'},
            claim_token='claim-token',
            firestore_client=client,
            now=now,
        )

    assert client.rows[state_path] == original_state
    assert event_path not in client.rows
    assert receipt_path not in client.rows


def test_stale_processing_owner_cannot_apply_after_lease_takeover(monkeypatch):
    monkeypatch.setattr(fair_use_db.firestore, 'transactional', lambda function: function)
    now = datetime(2026, 8, 21, 8, tzinfo=timezone.utc)
    processing_path = ('users', 'owner-a', 'fair_use_review_processing', 'review-takeover')
    event_path = ('users', 'owner-a', 'fair_use_events', 'review-takeover')
    receipt_path = ('users', 'owner-a', 'fair_use_review_receipts', 'review-takeover')
    client = StrictFirestore(
        {
            processing_path: {
                'claim_token': 'replacement-token',
                'expires_at': now + timedelta(minutes=5),
            }
        }
    )

    with pytest.raises(fair_use_db.FairUseReviewProcessingClaimLost):
        fair_use_db.apply_fair_use_review_result(
            'owner-a',
            {
                'review_id': 'review-takeover',
                'session_id': 'listen-takeover',
                'trigger': 'daily',
                'window_speech_ms': {'daily_ms': 7_200_001},
                'thresholds_ms': {'daily_ms': 7_200_000},
            },
            {'misuse_score': 0.95, 'usage_type': 'audiobook'},
            claim_token='stale-token',
            firestore_client=client,
            now=now,
        )

    assert event_path not in client.rows
    assert receipt_path not in client.rows
