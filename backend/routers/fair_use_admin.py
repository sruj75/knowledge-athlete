"""Admin endpoints for fair-use management."""

import hashlib
import hmac
import logging
import os
from datetime import datetime
from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, Header, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
from models.shared import StatusResponse

import database.fair_use as fair_use_db
from database._client import db
from utils.fair_use import (
    get_rolling_speech_ms,
    invalidate_enforcement_cache,
    FAIR_USE_ENABLED,
)

logger = logging.getLogger(__name__)

router = APIRouter()

ADMIN_KEY = os.getenv('ADMIN_KEY', '')


class FlaggedUsersResponse(BaseModel):
    """Protected support response for users with active fair-use enforcement."""

    users: list[Dict[str, Any]] = Field(description='Users with active enforcement, each a fair-use state dict.')
    fair_use_enabled: bool = Field(description='Whether fair-use enforcement is globally enabled.')


class FairUseSupportEventResponse(BaseModel):
    """Content-free fair-use history exposed to protected support tooling."""

    model_config = ConfigDict(extra='forbid')
    id: str = ''
    review_id: str = ''
    created_at: Optional[datetime] = None
    session_id: str = ''
    trigger: str = 'daily'
    window_speech_ms: Dict[str, int] = Field(default_factory=dict)
    thresholds_ms: Dict[str, int] = Field(default_factory=dict)
    classifier_score: float = 0.0
    classifier_type: str = 'none'
    classifier_confidence: float = 0.0
    classifier_model: str = ''
    classifier_prompt_version: str = ''
    enforcement_action: str = 'none'
    previous_stage: str = 'none'
    new_stage: str = 'none'
    case_ref: str = ''
    admin_notes: str = ''
    resolved: bool = False
    resolved_at: Optional[datetime] = None
    resolved_by: str = ''


class FairUseUserDetailResponse(BaseModel):
    """Admin per-user fair-use detail."""

    uid: str = Field(description='User UID.')
    state: Dict[str, Any] = Field(description='Current fair-use state document.')
    events: list[FairUseSupportEventResponse] = Field(description='Recent content-free fair-use events.')
    current_speech_ms: Dict[str, int] = Field(
        description='Rolling speech usage in milliseconds: daily_ms, three_day_ms, weekly_ms.'
    )


class FairUseSetStageResponse(BaseModel):
    """Ack for manual stage update; preserves the stage value."""

    status: str = Field(description='Ack status, e.g. "updated".')
    stage: str = Field(description='The enforcement stage that was set (none|warning|throttle|restrict).')


class FairUseCaseLookupResponse(FairUseSupportEventResponse):
    """A content-free fair-use event located by case reference."""

    uid: str = Field(description='User UID who owns the event.')
    event_id: str = Field(description='Event identifier.')


_SUPPORT_EVENT_FIELDS = frozenset(FairUseSupportEventResponse.model_fields)


def _content_free_support_event(event: Dict[str, Any]) -> Dict[str, Any]:
    return {key: value for key, value in event.items() if key in _SUPPORT_EVENT_FIELDS}


def _verify_admin_key(x_admin_key: str = Header(..., alias='X-Admin-Key')) -> str:
    """Validate admin key from request header using constant-time comparison.

    Returns a short hash of the key for audit logging (not the key itself).
    """
    if not ADMIN_KEY or not hmac.compare_digest(x_admin_key, ADMIN_KEY):
        raise HTTPException(status_code=403, detail='Invalid admin key')
    return f'admin:{hashlib.sha256(x_admin_key.encode()).hexdigest()[:8]}'


# ---------------------------------------------------------------------------
# Protected support reads
# ---------------------------------------------------------------------------


@router.get('/v1/admin/fair-use/flagged', tags=['admin'], response_model=FlaggedUsersResponse)
def get_flagged_users(
    admin_id: str = Depends(_verify_admin_key),
    stage: Optional[str] = None,
    limit: int = Query(default=50, le=200),
):
    """Get users with active fair-use enforcement."""
    # Clamp in-function (not only via Query) so direct/non-HTTP callers can't pass a
    # negative or huge limit straight through to the Firestore query.
    limit = max(1, min(limit, 200))
    users = fair_use_db.get_flagged_users(stage_filter=stage, limit=limit)
    return {'users': users, 'fair_use_enabled': FAIR_USE_ENABLED}


@router.get('/v1/admin/fair-use/user/{uid}', tags=['admin'], response_model=FairUseUserDetailResponse)
def get_user_fair_use_detail(uid: str, admin_id: str = Depends(_verify_admin_key)):
    """Get detailed fair-use state and events for a specific user."""
    state = fair_use_db.get_fair_use_state(uid)
    events = [_content_free_support_event(event) for event in fair_use_db.get_fair_use_events(uid, limit=50)]
    speech = get_rolling_speech_ms(uid)

    return {
        'uid': uid,
        'state': state,
        'events': events,
        'current_speech_ms': speech,
    }


# ---------------------------------------------------------------------------
# Admin actions
# ---------------------------------------------------------------------------


@router.post('/v1/admin/fair-use/user/{uid}/resolve-event/{event_id}', tags=['admin'], response_model=StatusResponse)
def resolve_event(uid: str, event_id: str, admin_id: str = Depends(_verify_admin_key), notes: str = Query(default='')):
    """Mark a fair-use event as resolved."""
    fair_use_db.resolve_fair_use_event(uid, event_id, admin_uid=admin_id, notes=notes)
    return {'status': 'resolved'}


@router.post('/v1/admin/fair-use/user/{uid}/reset', tags=['admin'], response_model=StatusResponse)
def reset_user_fair_use(uid: str, admin_id: str = Depends(_verify_admin_key)):
    """Reset a user's fair-use state to clean."""
    fair_use_db.reset_fair_use_state(uid, admin_uid=admin_id)
    invalidate_enforcement_cache(uid)
    return {'status': 'reset'}


@router.post('/v1/admin/fair-use/user/{uid}/set-stage', tags=['admin'], response_model=FairUseSetStageResponse)
def set_user_stage(uid: str, stage: str = Query(...), admin_id: str = Depends(_verify_admin_key)):
    """Manually set a user's enforcement stage."""
    valid_stages = {'none', 'warning', 'throttle', 'restrict'}
    if stage not in valid_stages:
        raise HTTPException(status_code=400, detail=f'Invalid stage. Must be one of: {valid_stages}')

    updates = {'stage': stage}
    if stage == 'none':
        updates['throttle_until'] = None
        updates['restrict_until'] = None

    fair_use_db.update_fair_use_state(uid, updates)
    invalidate_enforcement_cache(uid)
    return {'status': 'updated', 'stage': stage}


@router.get('/v1/admin/fair-use/case/{case_ref}', tags=['admin'], response_model=FairUseCaseLookupResponse)
def lookup_case(case_ref: str, admin_id: str = Depends(_verify_admin_key)):
    """Look up a fair-use event by case reference (for support team)."""
    # Search across all users' events for this case_ref
    query = db.collection_group('fair_use_events').where('case_ref', '==', case_ref).limit(1)
    for doc in query.stream():
        data = doc.to_dict()
        path_parts = doc.reference.path.split('/')
        if len(path_parts) >= 2:
            data['uid'] = path_parts[1]
        data['event_id'] = doc.id
        return _content_free_support_event(data) | {'uid': data.get('uid', ''), 'event_id': doc.id}
    raise HTTPException(status_code=404, detail=f'Case {case_ref} not found')
