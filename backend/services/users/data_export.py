from __future__ import annotations

import json
from datetime import datetime
from typing import Any, Iterator, cast

from database import llm_usage as llm_usage_db
from database.users import get_existing_user_subscription, get_user_profile
from utils.subscription import get_monthly_usage_for_subscription

JsonRecord = dict[str, Any]
_ACCOUNT_METADATA_FIELDS = (
    'uid',
    'email',
    'time_zone',
    'created_at',
    'language',
    'signup_platform',
    'signup_os',
)


def _json_default(obj: object) -> str:
    if isinstance(obj, datetime):
        return obj.isoformat()
    raise TypeError(f'Type {type(obj)} not serializable')


def _account_metadata(uid: str, profile: JsonRecord | None) -> JsonRecord:
    source = profile or {}
    return {
        field: uid if field == 'uid' else source[field]
        for field in _ACCOUNT_METADATA_FIELDS
        if field == 'uid' or field in source
    }


def iter_user_data_export(uid: str) -> Iterator[str]:
    """Export only retained server-owned account and entitlement metadata."""
    profile = _account_metadata(uid, cast(JsonRecord | None, get_user_profile(uid)))
    subscription = get_existing_user_subscription(uid)
    usage = get_monthly_usage_for_subscription(uid)
    payload = {
        'schema_version': 1,
        'account': profile,
        'subscription': subscription.model_dump(mode='json') if subscription is not None else None,
        'usage': {
            'transcription_seconds': int(usage.get('transcription_seconds', 0)),
            'words_transcribed': int(usage.get('words_transcribed', 0)),
            'insights_gained': int(usage.get('insights_gained', 0)),
            'managed_ai_total_cost_usd': float(llm_usage_db.get_total_llm_cost(uid)),
        },
    }
    yield json.dumps(payload, default=_json_default, indent=2, sort_keys=True) + '\n'
