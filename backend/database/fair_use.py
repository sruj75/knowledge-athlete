"""Firestore CRUD for fair-use tracking.

Required Firestore composite indexes (create before deploying):

1. Collection group: fair_use_state
   Fields: stage (Ascending), updated_at (Descending)
   Scope: Collection group
   Used by: get_flagged_users() — protected support operations

2. Collection group: fair_use_events
   Fields: case_ref (Ascending)
   Scope: Collection group
   Used by: lookup_case() — protected case reference lookup

Create via gcloud:
  gcloud firestore indexes composite create --project=<PROJECT> \\
    --collection-group=fair_use_state \\
    --query-scope=collection-group \\
    --field-config=field-path=stage,order=ascending \\
    --field-config=field-path=updated_at,order=descending

  gcloud firestore indexes composite create --project=<PROJECT> \\
    --collection-group=fair_use_events \\
    --query-scope=collection-group \\
    --field-config=field-path=case_ref,order=ascending
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, cast

from google.api_core.exceptions import AlreadyExists, FailedPrecondition, NotFound
from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter
from models.fair_use import normalize_usage_type

from ._client import db, get_firestore_client
from .firestore_index_registry import FAIR_USE_FLAGGED_STATES_QUERY

logger = logging.getLogger(__name__)

FAIR_USE_REVIEW_PROCESSING_TTL = timedelta(minutes=5)


class FairUseReviewProcessingClaimLost(RuntimeError):
    """Raised when a classifier worker no longer owns the acceptance lease."""


def _aware_utc(value: Any) -> datetime | None:
    if not isinstance(value, datetime):
        return None
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value.astimezone(timezone.utc)


def _review_requested_at(review: Dict[str, Any], fallback: datetime) -> datetime:
    value = review.get('requested_at')
    if isinstance(value, str):
        try:
            value = datetime.fromisoformat(value.replace('Z', '+00:00'))
        except ValueError:
            value = None
    return _aware_utc(value) or fallback


def _normalized_automatic_stage(state: Dict[str, Any], now: datetime) -> tuple[str, Dict[str, Any]]:
    stage = str(state.get('stage', 'none'))
    updates: Dict[str, Any] = {}
    if stage == 'restrict':
        restrict_until = _aware_utc(state.get('restrict_until'))
        if restrict_until is not None and now >= restrict_until:
            stage = 'throttle'
            updates = {
                'stage': 'throttle',
                'restrict_until': None,
                'throttle_until': now + timedelta(days=7),
            }
    if stage == 'throttle':
        throttle_until = _aware_utc(updates.get('throttle_until', state.get('throttle_until')))
        if throttle_until is not None and now >= throttle_until:
            stage = 'warning'
            updates.update({'stage': 'warning', 'throttle_until': None})
    return stage, updates


# ---------------------------------------------------------------------------
# Fair-use state (users/{uid}/fair_use_state/current)
# ---------------------------------------------------------------------------


def get_fair_use_state(
    uid: str,
    *,
    firestore_client: Any | None = None,
    now: datetime | None = None,
) -> Dict[str, Any]:
    """Transactionally read and normalize automatic timers for every state consumer."""
    client = firestore_client or get_firestore_client()
    effective_now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    ref = client.collection('users').document(uid).collection('fair_use_state').document('current')
    transaction = client.transaction()

    @firestore.transactional
    def _read(transaction: Any) -> Dict[str, Any]:
        doc = ref.get(transaction=transaction)
        if not getattr(doc, 'exists', False):
            return {}
        raw: object = doc.to_dict()
        state = cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}
        _stage, updates = _normalized_automatic_stage(state, effective_now)
        if updates:
            updates['updated_at'] = effective_now
            transaction.set(ref, updates, merge=True)
            state = {**state, **updates}
        return state

    return _read(transaction)


def update_fair_use_state(uid: str, updates: Dict[str, Any]) -> None:
    """Update fair-use state atomically."""
    ref = db.collection('users').document(uid).collection('fair_use_state').document('current')
    updates['updated_at'] = datetime.now(timezone.utc)
    ref.set(updates, merge=True)


def set_fair_use_stage(uid: str, stage: str, **kwargs: Any) -> None:
    """Set enforcement stage with optional extra fields."""
    updates: Dict[str, Any] = {'stage': stage, **kwargs}
    update_fair_use_state(uid, updates)


# ---------------------------------------------------------------------------
# Fair-use events (users/{uid}/fair_use_events/{event_id})
# ---------------------------------------------------------------------------


def _generate_case_ref() -> str:
    """Generate a human-readable case reference like FU-A1B2C3D4E5F6.

    Uses 12 hex chars from UUID4 (16^12 ≈ 281 trillion possibilities),
    safe for public unauthenticated lookup without enumeration risk.
    """
    return f'FU-{uuid.uuid4().hex[:12].upper()}'


def create_fair_use_event(uid: str, event_data: Dict[str, Any]) -> str:
    """Create a new fair-use violation event. Returns the event ID."""
    ref = db.collection('users').document(uid).collection('fair_use_events').document()
    event_data['created_at'] = datetime.now(timezone.utc)
    event_data['case_ref'] = _generate_case_ref()
    ref.set(event_data)
    return str(ref.id)


def _review_receipt_response(data: Dict[str, Any], *, idempotent: bool) -> Dict[str, Any]:
    return {
        'review_id': str(data.get('review_id', '')),
        'accepted': bool(data.get('accepted', True)),
        'idempotent': idempotent,
        'action': str(data.get('action', 'none')),
        'stage': str(data.get('stage', 'none')),
        'case_ref': str(data.get('case_ref', '')),
    }


def get_fair_use_review_receipt(
    uid: str,
    review_id: str,
    *,
    firestore_client: Any | None = None,
) -> Dict[str, Any] | None:
    client = firestore_client or get_firestore_client()
    ref = client.collection('users').document(uid).collection('fair_use_review_receipts').document(review_id)
    snapshot = ref.get()
    if not getattr(snapshot, 'exists', False):
        return None
    raw = snapshot.to_dict()
    return _review_receipt_response(raw if isinstance(raw, dict) else {}, idempotent=True)


def claim_fair_use_review_processing(
    uid: str,
    review_id: str,
    *,
    firestore_client: Any | None = None,
    now: datetime | None = None,
) -> str | None:
    """Acquire the sole durable lease allowed to invoke the classifier."""
    client = firestore_client or get_firestore_client()
    effective_now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    user_ref = client.collection('users').document(uid)
    processing_ref = user_ref.collection('fair_use_review_processing').document(review_id)
    receipt_ref = user_ref.collection('fair_use_review_receipts').document(review_id)
    token = str(uuid.uuid4())
    if getattr(receipt_ref.get(), 'exists', False):
        return None
    processing_snapshot = processing_ref.get()
    payload = {
        'review_id': review_id,
        'claim_token': token,
        'claimed_at': effective_now,
        'expires_at': effective_now + FAIR_USE_REVIEW_PROCESSING_TTL,
    }
    if not getattr(processing_snapshot, 'exists', False):
        try:
            processing_ref.create(payload)
            return token
        except AlreadyExists:
            return None

    raw = processing_snapshot.to_dict()
    processing = raw if isinstance(raw, dict) else {}
    expires_at = _aware_utc(processing.get('expires_at'))
    if processing.get('claim_token') and expires_at is not None and expires_at > effective_now:
        return None
    try:
        processing_ref.update(
            payload,
            option=client.write_option(last_update_time=processing_snapshot.update_time),
        )
        return token
    except (FailedPrecondition, NotFound):
        return None


def release_fair_use_review_processing(
    uid: str,
    review_id: str,
    token: str,
    *,
    firestore_client: Any | None = None,
    now: datetime | None = None,
) -> None:
    """Release only the caller's durable classifier lease."""
    client = firestore_client or get_firestore_client()
    effective_now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    ref = client.collection('users').document(uid).collection('fair_use_review_processing').document(review_id)
    transaction = client.transaction()

    @firestore.transactional
    def _release(transaction: Any) -> None:
        snapshot = ref.get(transaction=transaction)
        raw = snapshot.to_dict() if getattr(snapshot, 'exists', False) else {}
        processing = raw if isinstance(raw, dict) else {}
        if processing.get('claim_token') == token:
            transaction.set(
                ref,
                {'claim_token': None, 'released_at': effective_now, 'expires_at': effective_now},
                merge=True,
            )

    _release(transaction)


def _review_stage_transition(stage: str, positive_count_7d: int, positive: bool) -> tuple[str, str]:
    if not positive:
        return stage, 'none'
    if stage == 'none' and positive_count_7d >= 1:
        return 'warning', 'warning'
    if stage == 'warning' and positive_count_7d >= 2:
        return 'throttle', 'throttle'
    # Throttle is the final-warning state. A fresh positive must immediately
    # re-restrict even when the previous 30-day restriction expired and the
    # retained seven-day event count has fallen below three.
    if stage == 'throttle':
        return 'restrict', 'restrict'
    return stage, 'none'


def apply_fair_use_review_result(
    uid: str,
    review: Dict[str, Any],
    classifier_result: Dict[str, Any],
    *,
    claim_token: str,
    firestore_client: Any | None = None,
    now: datetime | None = None,
) -> Dict[str, Any]:
    """Atomically record one content-free classifier fact and enforcement receipt."""
    client = firestore_client or get_firestore_client()
    effective_now = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    score_created_at = _review_requested_at(review, effective_now)
    review_id = str(review['review_id'])
    user_ref = client.collection('users').document(uid)
    state_ref = user_ref.collection('fair_use_state').document('current')
    receipt_ref = user_ref.collection('fair_use_review_receipts').document(review_id)
    event_ref = user_ref.collection('fair_use_events').document(review_id)
    processing_ref = user_ref.collection('fair_use_review_processing').document(review_id)
    events_ref = user_ref.collection('fair_use_events')
    case_ref = _generate_case_ref()
    transaction = client.transaction()

    @firestore.transactional
    def _apply(transaction: Any) -> Dict[str, Any]:
        receipt_snapshot = receipt_ref.get(transaction=transaction)
        if getattr(receipt_snapshot, 'exists', False):
            raw = receipt_snapshot.to_dict()
            return _review_receipt_response(raw if isinstance(raw, dict) else {}, idempotent=True)

        processing_snapshot = processing_ref.get(transaction=transaction)
        raw_processing = processing_snapshot.to_dict() if getattr(processing_snapshot, 'exists', False) else {}
        processing = raw_processing if isinstance(raw_processing, dict) else {}
        expires_at = _aware_utc(processing.get('expires_at'))
        if processing.get('claim_token') != claim_token or expires_at is None or expires_at <= effective_now:
            raise FairUseReviewProcessingClaimLost('fair-use review processing claim is no longer current')

        state_snapshot = state_ref.get(transaction=transaction)
        raw_state = state_snapshot.to_dict() if getattr(state_snapshot, 'exists', False) else {}
        state = raw_state if isinstance(raw_state, dict) else {}
        reset_at = _aware_utc(state.get('reset_at'))
        cutoff_30d = (
            max(effective_now - timedelta(days=30), reset_at) if reset_at else effective_now - timedelta(days=30)
        )
        cutoff_7d = effective_now - timedelta(days=7)
        historical = events_ref.where('created_at', '>=', cutoff_30d).get(transaction=transaction)
        positive_times: list[datetime] = []
        for snapshot in historical:
            raw = snapshot.to_dict()
            event = raw if isinstance(raw, dict) else {}
            created_at = _aware_utc(event.get('created_at'))
            score = event.get('classifier_score', 0.0)
            if created_at is not None and (reset_at is None or created_at > reset_at) and float(score or 0.0) >= 0.7:
                positive_times.append(created_at)

        misuse_score = max(0.0, min(1.0, float(classifier_result.get('misuse_score') or 0.0)))
        positive = misuse_score >= 0.7
        # A reset is the counting boundary even if this transaction began before
        # the reset transaction committed and retries against its newer state.
        # Keep the classifier event as support history, but never let an event at
        # or before the boundary immediately re-enforce the reset owner.
        counting_positive = positive and (reset_at is None or score_created_at > reset_at)
        if counting_positive:
            positive_times.append(score_created_at)
        count_30d = len(positive_times)
        count_7d = sum(created_at >= cutoff_7d for created_at in positive_times)
        previous_stage, normalization = _normalized_automatic_stage(state, effective_now)
        new_stage, action = _review_stage_transition(previous_stage, count_7d, counting_positive)
        classifier_type = normalize_usage_type(classifier_result.get('usage_type')).value
        state_updates: Dict[str, Any] = {
            **normalization,
            'stage': new_stage,
            'violation_count_7d': count_7d,
            'violation_count_30d': count_30d,
            'last_classifier_score': misuse_score,
            'last_classifier_type': classifier_type,
            'updated_at': effective_now,
        }
        if counting_positive:
            state_updates['last_violation_at'] = effective_now
        if action == 'throttle':
            state_updates['throttle_until'] = effective_now + timedelta(days=7)
        elif action == 'restrict':
            state_updates['restrict_until'] = effective_now + timedelta(days=30)
        if action != 'none':
            state_updates['last_case_ref'] = case_ref

        event = {
            'review_id': review_id,
            # The score belongs to the server-created review request, not to
            # the later GPT completion. This preserves reset as a permanent
            # counting fence when a pre-reset request finishes afterward.
            'created_at': score_created_at,
            'session_id': str(review.get('session_id', '')),
            'trigger': str(review.get('trigger', 'daily')),
            'window_speech_ms': dict(review.get('window_speech_ms') or {}),
            'thresholds_ms': dict(review.get('thresholds_ms') or {}),
            'classifier_score': misuse_score,
            'classifier_type': classifier_type,
            'classifier_confidence': max(0.0, min(1.0, float(classifier_result.get('confidence') or 0.0))),
            'classifier_model': str(classifier_result.get('model') or 'gemini/gemini-3.7-flash'),
            'classifier_prompt_version': str(classifier_result.get('prompt_version') or 'v2'),
            'enforcement_action': action,
            'previous_stage': previous_stage,
            'new_stage': new_stage,
            'case_ref': case_ref,
            'resolved': False,
        }
        receipt = {
            'review_id': review_id,
            'accepted': True,
            'action': action,
            'stage': new_stage,
            'case_ref': case_ref,
            'created_at': effective_now,
        }
        transaction.set(event_ref, event)
        transaction.set(state_ref, state_updates, merge=True)
        transaction.set(receipt_ref, receipt)
        return _review_receipt_response(receipt, idempotent=False)

    return _apply(transaction)


def get_fair_use_events(uid: str, limit: int = 50) -> List[Dict[str, Any]]:
    """Get recent fair-use events for a user, newest first."""
    ref = db.collection('users').document(uid).collection('fair_use_events')
    docs = ref.order_by('created_at', direction=firestore.Query.DESCENDING).limit(limit).stream()
    events: List[Dict[str, Any]] = []
    for doc in docs:
        raw: object = doc.to_dict()
        data: Dict[str, Any] = cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}
        data['id'] = doc.id
        events.append(data)
    return events


def _qualifying_violation_times(
    events: List[Dict[str, Any]], *, reset_at: datetime | None, now: datetime
) -> List[datetime]:
    cutoff_30d = now - timedelta(days=30)
    reset_boundary = _aware_utc(reset_at)
    qualifying: List[datetime] = []
    for data in events:
        created = _aware_utc(data.get('created_at'))
        score = float(data.get('classifier_score', 0.0) or 0.0)
        if created is None or created < cutoff_30d or (reset_boundary is not None and created <= reset_boundary):
            continue
        if score >= 0.7:
            qualifying.append(created)
    return qualifying


def get_violation_counts(uid: str) -> Dict[str, int]:
    """Count qualifying post-reset violations in the last 7 and 30 days."""
    ref = db.collection('users').document(uid).collection('fair_use_events')
    now = datetime.now(timezone.utc)
    cutoff_30d = now - timedelta(days=30)
    cutoff_7d = now - timedelta(days=7)

    docs = ref.where('created_at', '>=', cutoff_30d).stream()
    events: List[Dict[str, Any]] = []
    for doc in docs:
        raw: object = doc.to_dict()
        data: Dict[str, Any] = cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}
        events.append(data)
    state = get_fair_use_state(uid)
    qualifying = _qualifying_violation_times(events, reset_at=state.get('reset_at'), now=now)

    return {
        'violation_count_7d': sum(created >= cutoff_7d for created in qualifying),
        'violation_count_30d': len(qualifying),
    }


def resolve_fair_use_event(uid: str, event_id: str, admin_uid: str, notes: str = "") -> None:
    """Mark a fair-use event as resolved by admin."""
    ref = db.collection('users').document(uid).collection('fair_use_events').document(event_id)
    ref.update(
        {
            'resolved': True,
            'resolved_at': datetime.now(timezone.utc),
            'resolved_by': admin_uid,
            'admin_notes': notes,
        }
    )


def reset_fair_use_state(uid: str, admin_uid: str) -> None:
    """Reset a user's fair-use state to clean (admin action)."""
    update_fair_use_state(
        uid,
        {
            'stage': 'none',
            'violation_count_7d': 0,
            'violation_count_30d': 0,
            'last_violation_at': None,
            'throttle_until': None,
            'restrict_until': None,
            'last_classifier_score': 0.0,
            'last_classifier_type': 'none',
            'reset_by': admin_uid,
            'reset_at': datetime.now(timezone.utc),
        },
    )


# ---------------------------------------------------------------------------
# Admin queries
# ---------------------------------------------------------------------------


def get_flagged_users(
    stage_filter: Optional[str] = None,
    limit: int = 100,
    *,
    firestore_client: Any | None = None,
) -> List[Dict[str, Any]]:
    """Get users with active fair-use enforcement for protected support use."""
    # Query all users who have fair_use_state with stage != 'none'
    # This requires a collection group query on fair_use_state
    client = firestore_client or get_firestore_client()
    # Query all raw active stages, then apply ``stage_filter`` after each row has
    # passed through the authoritative recovery transaction. Filtering the raw
    # stage first would hide expired restrict -> throttle and throttle -> warning
    # transitions from support.
    query = FAIR_USE_FLAGGED_STATES_QUERY.build(
        client.collection_group('fair_use_state'),
        {'active_stages': ['warning', 'throttle', 'restrict']},
        field_filter_factory=FieldFilter,
    )

    query = query.order_by('updated_at', direction=firestore.Query.DESCENDING)

    results: List[Dict[str, Any]] = []
    page_size = 200
    cursor: Any | None = None
    while len(results) < limit:
        page_query = query.limit(page_size)
        if cursor is not None:
            page_query = page_query.start_after(cursor)
        page = list(page_query.stream())
        for doc in page:
            raw: object = doc.to_dict()
            data: Dict[str, Any] = cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}
            # Extract uid from document path: users/{uid}/fair_use_state/current
            path_parts = doc.reference.path.split('/')
            if len(path_parts) >= 2:
                uid = path_parts[1]
                data = get_fair_use_state(uid, firestore_client=client)
                data['uid'] = uid
            if data.get('stage', 'none') == 'none' or (stage_filter and data.get('stage') != stage_filter):
                continue
            data['id'] = doc.id
            results.append(data)
            if len(results) >= limit:
                break
        if len(page) < page_size:
            break
        cursor = page[-1]
    return results
