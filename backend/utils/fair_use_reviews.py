"""Content-free pending-review state for the fair-use Mac classifier handoff."""

from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from database import redis_db

from .fair_use import FAIR_USE_CLASSIFIER_COOLDOWN_SECONDS, fair_use_caps_for_entitlement

FAIR_USE_CLASSIFIER_CONTRACT = 'openai/gpt-5.1:prompt-v2'
logger = logging.getLogger(__name__)

_CREATE_PENDING_REVIEW_SCRIPT = """
if redis.call("exists", KEYS[1]) == 1 then
    return 0
end
redis.call("set", KEYS[1], ARGV[1], "EX", ARGV[2])
redis.call("set", KEYS[2], ARGV[3], "EX", ARGV[2])
return 1
"""

_CONSUME_PENDING_REVIEW_SCRIPT = """
local raw = redis.call("get", KEYS[1])
if not raw then
    return 0
end
local request = cjson.decode(raw)
if request["review_id"] == ARGV[1] then
    return redis.call("del", KEYS[1])
end
return 0
"""


def _pending_key(uid: str) -> str:
    return f'fair_use:review:pending:{uid}'


def _cooldown_key(uid: str) -> str:
    return f'fair_use:review:cooldown:{uid}'


def create_pending_fair_use_review(
    uid: str,
    triggered_caps: list[dict[str, Any]],
    window_speech_ms: dict[str, int],
    entitlement_policy: Any = None,
    session_id: str = '',
    *,
    now: datetime | None = None,
) -> dict[str, Any] | None:
    """Create at most one content-free review request per retained cooldown."""
    if not triggered_caps:
        return None
    requested_at = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)
    review_id = str(uuid.uuid4())
    daily, three_day, weekly = fair_use_caps_for_entitlement(entitlement_policy)
    raw_trigger = triggered_caps[0].get('trigger', 'daily')
    trigger = raw_trigger.value if hasattr(raw_trigger, 'value') else str(raw_trigger)
    request = {
        'review_id': review_id,
        'trigger': trigger,
        'window_speech_ms': {
            'daily_ms': int(window_speech_ms.get('daily_ms', 0)),
            'three_day_ms': int(window_speech_ms.get('three_day_ms', 0)),
            'weekly_ms': int(window_speech_ms.get('weekly_ms', 0)),
        },
        'thresholds_ms': {'daily_ms': daily, 'three_day_ms': three_day, 'weekly_ms': weekly},
        'classifier_contract': FAIR_USE_CLASSIFIER_CONTRACT,
        'requested_at': requested_at.isoformat(),
        'expires_at': (requested_at + timedelta(seconds=FAIR_USE_CLASSIFIER_COOLDOWN_SECONDS)).isoformat(),
        'session_id': session_id,
    }
    payload = json.dumps(request, separators=(',', ':'))
    try:
        acquired = redis_db.r.eval(
            _CREATE_PENDING_REVIEW_SCRIPT,
            2,
            _cooldown_key(uid),
            _pending_key(uid),
            review_id,
            FAIR_USE_CLASSIFIER_COOLDOWN_SECONDS,
            payload,
        )
        if not acquired:
            return get_pending_fair_use_review(uid)
        return request
    except Exception as error:
        logger.error('fair_use: pending review Redis error for %s: %s', uid, type(error).__name__)
        return None


def get_pending_fair_use_review(uid: str, review_id: str | None = None) -> dict[str, Any] | None:
    try:
        raw = redis_db.r.get(_pending_key(uid))
    except Exception as error:
        logger.error('fair_use: pending review Redis read error for %s: %s', uid, type(error).__name__)
        return None
    if not raw:
        return None
    if isinstance(raw, bytes):
        raw = raw.decode('utf-8')
    try:
        request = json.loads(raw)
    except (TypeError, ValueError):
        return None
    if not isinstance(request, dict) or (review_id is not None and request.get('review_id') != review_id):
        return None
    expires_at = request.get('expires_at')
    try:
        expiry = datetime.fromisoformat(str(expires_at).replace('Z', '+00:00'))
    except ValueError:
        return None
    if datetime.now(timezone.utc) >= expiry.astimezone(timezone.utc):
        return None
    return request


def mark_fair_use_review_consumed(uid: str, review_id: str) -> None:
    try:
        redis_db.r.eval(_CONSUME_PENDING_REVIEW_SCRIPT, 1, _pending_key(uid), review_id)
    except Exception as error:
        logger.error('fair_use: pending review Redis consume error for %s: %s', uid, type(error).__name__)
