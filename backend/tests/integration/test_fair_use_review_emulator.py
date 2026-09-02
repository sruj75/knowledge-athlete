"""Firestore-emulator proof for concurrent S-20 review acceptance.

Run from ``backend/`` with a local emulator:

``FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 .venv/bin/python -m pytest \
tests/integration/test_fair_use_review_emulator.py``
"""

from __future__ import annotations

import os
import threading
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from google.cloud import firestore

from database.fair_use import (
    FairUseReviewProcessingClaimLost,
    apply_fair_use_review_result,
    claim_fair_use_review_processing,
    release_fair_use_review_processing,
)

pytestmark = pytest.mark.skipif(
    not os.getenv('FIRESTORE_EMULATOR_HOST'),
    reason='requires FIRESTORE_EMULATOR_HOST',
)


def test_review_claims_and_commit_are_durable_in_firestore_emulator():
    client = firestore.Client(project='demo-fair-use-s20')
    uid = f's20-owner-{uuid.uuid4().hex}'
    review_id = str(uuid.uuid4())
    user = client.collection('users').document(uid)
    review = {
        'review_id': review_id,
        'session_id': 'listen-1',
        'trigger': 'daily',
        'window_speech_ms': {'daily_ms': 7_200_001},
        'thresholds_ms': {'daily_ms': 7_200_000},
    }
    result = {
        'misuse_score': 0.9,
        'usage_type': 'audiobook',
        'confidence': 0.8,
        'model': 'gemini/gemini-3.7-flash',
        'prompt_version': 'v2',
    }
    processing_claims: list[str | None] = []
    processing_errors: list[BaseException] = []

    def claim_processing() -> None:
        worker_client = firestore.Client(project='demo-fair-use-s20')
        try:
            processing_claims.append(claim_fair_use_review_processing(uid, review_id, firestore_client=worker_client))
        except BaseException as error:
            processing_errors.append(error)
        finally:
            worker_client.close()

    processing_threads = [threading.Thread(target=claim_processing) for _ in range(2)]
    for thread in processing_threads:
        thread.start()
    for thread in processing_threads:
        thread.join(timeout=20)

    assert all(not thread.is_alive() for thread in processing_threads)
    assert not processing_errors
    assert len(processing_claims) == 2
    assert sum(claim is not None for claim in processing_claims) == 1
    processing_token = next(claim for claim in processing_claims if claim is not None)

    # Expire the first owner and take over with a fresh token. The old worker
    # may still return from GPT, but the real acceptance transaction must reject
    # it before writing any event, state, or receipt.
    user.collection('fair_use_review_processing').document(review_id).update(
        {'expires_at': datetime.now(timezone.utc) - timedelta(seconds=1)}
    )
    replacement_token = claim_fair_use_review_processing(uid, review_id, firestore_client=client)
    assert replacement_token is not None and replacement_token != processing_token
    with pytest.raises(FairUseReviewProcessingClaimLost):
        apply_fair_use_review_result(
            uid,
            review,
            result,
            claim_token=processing_token,
            firestore_client=client,
            now=datetime(2026, 8, 21, 8, tzinfo=timezone.utc),
        )
    assert not list(user.collection('fair_use_events').stream())
    assert not list(user.collection('fair_use_review_receipts').stream())

    # Only the durable processing-claim winner reaches the enforcement
    # transaction in production. Replay the same accepted review after commit
    # to prove the receipt makes the state/event write idempotent without
    # manufacturing an impossible second lease owner.
    receipts = [
        apply_fair_use_review_result(
            uid,
            review,
            result,
            claim_token=replacement_token,
            firestore_client=client,
            now=datetime(2026, 8, 21, 8, tzinfo=timezone.utc),
        ),
        apply_fair_use_review_result(
            uid,
            review,
            result,
            claim_token=replacement_token,
            firestore_client=client,
            now=datetime(2026, 8, 21, 8, tzinfo=timezone.utc),
        ),
    ]

    assert sorted(receipt['idempotent'] for receipt in receipts) == [False, True]
    assert len(list(user.collection('fair_use_events').stream())) == 1
    state = user.collection('fair_use_state').document('current').get().to_dict() or {}
    assert state['stage'] == 'warning'
    assert state['violation_count_7d'] == 1
    release_fair_use_review_processing(
        uid,
        review_id,
        replacement_token,
        firestore_client=client,
    )

    for collection_name in (
        'fair_use_events',
        'fair_use_review_processing',
        'fair_use_review_receipts',
        'fair_use_state',
    ):
        for snapshot in user.collection(collection_name).stream():
            snapshot.reference.delete()
    user.delete()
