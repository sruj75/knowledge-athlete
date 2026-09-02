"""
LLM Usage Database Operations.

Stores and queries LLM token usage by feature in Firestore.
Schema: users/{uid}/llm_usage/{date} -> {feature -> {model -> {input_tokens, output_tokens}}}
"""

import hashlib
from datetime import datetime, timezone
from typing import Any, Dict, Optional, cast

from google.cloud import firestore

from ._client import db

transactional = getattr(firestore, 'transactional', lambda fn: fn)  # pyright: ignore[reportUnknownMemberType]


def _typed_doc(doc: Any) -> Dict[str, Any]:
    raw: object = doc.to_dict()
    return cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}


def record_llm_usage(
    uid: str,
    feature: str,
    model: str,
    input_tokens: int,
    output_tokens: int,
) -> None:
    """
    Record LLM token usage for a user and feature.

    Uses Firestore atomic increments for safe concurrent updates.

    Args:
        uid: User ID
        feature: Feature name (e.g., "chat", "rag", "conversation_processing")
        model: Model name (e.g., "gemini-3.7-flash")
        input_tokens: Number of input/prompt tokens
        output_tokens: Number of output/completion tokens
    """
    if input_tokens == 0 and output_tokens == 0:
        return

    now = datetime.now(timezone.utc)
    doc_id = f"{now.year}-{now.month:02d}-{now.day:02d}"

    user_ref = db.collection("users").document(uid)
    usage_ref = user_ref.collection("llm_usage").document(doc_id)

    # Use nested field paths for atomic increments
    # Structure: {feature}.{model}.{input_tokens|output_tokens}
    # Firestore doesn't allow '.', '/', '[', ']', '*', '`', '~' in field names
    if not model:
        model = "unknown"

    safe_model = (
        model.replace(".", "_")
        .replace("/", "_")
        .replace("~", "_")
        .replace("*", "_")
        .replace("[", "_")
        .replace("]", "_")
        .replace("`", "_")
    )

    update_data: Dict[str, Any] = {
        f"{feature}.{safe_model}.input_tokens": firestore.Increment(input_tokens),
        f"{feature}.{safe_model}.output_tokens": firestore.Increment(output_tokens),
        f"{feature}.{safe_model}.call_count": firestore.Increment(1),
        "date": doc_id,  # Store date as a field for collection-group queries
        "last_updated": datetime.now(timezone.utc),
    }

    usage_ref.set(update_data, merge=True)


@transactional  # pyright: ignore[reportUntypedFunctionDecorator]
def _record_chat_quota_question_transaction(
    transaction: Any,
    usage_ref: Any,
    event_ref: Any,
    event_data: Dict[str, Any],
    doc_id: str,
) -> bool:
    event_snapshot = event_ref.get(transaction=transaction)
    if getattr(event_snapshot, "exists", False):
        return False

    now = datetime.now(timezone.utc)
    transaction.set(event_ref, event_data)
    transaction.set(
        usage_ref,
        {
            'backend_chat.quota_questions': firestore.Increment(1),
            'date': doc_id,
            'last_updated': now,
        },
        merge=True,
    )
    return True


def record_chat_quota_question(
    uid: str,
    idempotency_key: str,
    source: str,
    message_id: Optional[str] = None,
    chat_session_id: Optional[str] = None,
    platform: Optional[str] = None,
) -> bool:
    """Record one accepted visible backend chat question exactly once.

    This is the product-boundary quota counter for mobile/backend chat. It is
    intentionally separate from ``chat.*.call_count``, which is LLM telemetry
    and can vary with implementation details.
    """
    if not idempotency_key:
        raise ValueError('idempotency_key is required')

    now = datetime.now(timezone.utc)
    doc_id = now.strftime('%Y-%m-%d')
    event_id = hashlib.sha256(f'{uid}:{idempotency_key}'.encode('utf-8')).hexdigest()

    user_ref = db.collection('users').document(uid)
    usage_ref = user_ref.collection('llm_usage').document(doc_id)
    event_ref = user_ref.collection('chat_quota_events').document(event_id)
    event_data: Dict[str, Any] = {
        'idempotency_key': idempotency_key,
        'source': source,
        'message_id': message_id,
        'chat_session_id': chat_session_id,
        'platform': platform,
        'created_at': now,
        'date': doc_id,
    }

    transaction = db.transaction()
    return _record_chat_quota_question_transaction(transaction, usage_ref, event_ref, event_data, doc_id)


def get_daily_usage(uid: str, date: Optional[datetime] = None) -> Dict[str, Any]:
    """
    Get LLM usage for a specific day.

    Args:
        uid: User ID
        date: Date to query (defaults to today)

    Returns:
        Dict with usage data by feature and model
    """
    if date is None:
        date = datetime.now(timezone.utc)

    doc_id = f"{date.year}-{date.month:02d}-{date.day:02d}"
    user_ref = db.collection("users").document(uid)
    usage_ref = user_ref.collection("llm_usage").document(doc_id)

    doc = usage_ref.get()
    if getattr(doc, "exists", False):
        return _typed_doc(doc)
    return {}


def record_llm_usage_bucket(
    uid: str,
    input_tokens: int,
    output_tokens: int,
    cache_read_tokens: int = 0,
    cache_write_tokens: int = 0,
    total_tokens: int = 0,
    cost_usd: float = 0.0,
    bucket: str = 'desktop_chat',
    account: str = 'omi',
) -> None:
    """Record LLM token usage into a flat bucket with atomic increments.

    Dual-writes to both the primary bucket and a per-account alias
    (``{bucket}_{account}``) for per-account breakdown.
    """
    today = datetime.now(timezone.utc).strftime('%Y-%m-%d')
    ref = db.collection("users").document(uid).collection("llm_usage").document(today)

    acct_key = f'{bucket}_{account}'
    update: Dict[str, Any] = {
        f'{bucket}.input_tokens': firestore.Increment(input_tokens),
        f'{bucket}.output_tokens': firestore.Increment(output_tokens),
        f'{bucket}.cache_read_tokens': firestore.Increment(cache_read_tokens),
        f'{bucket}.cache_write_tokens': firestore.Increment(cache_write_tokens),
        f'{bucket}.total_tokens': firestore.Increment(total_tokens),
        f'{bucket}.cost_usd': firestore.Increment(cost_usd),
        f'{bucket}.call_count': firestore.Increment(1),
        f'{acct_key}.input_tokens': firestore.Increment(input_tokens),
        f'{acct_key}.output_tokens': firestore.Increment(output_tokens),
        f'{acct_key}.cache_read_tokens': firestore.Increment(cache_read_tokens),
        f'{acct_key}.cache_write_tokens': firestore.Increment(cache_write_tokens),
        f'{acct_key}.total_tokens': firestore.Increment(total_tokens),
        f'{acct_key}.cost_usd': firestore.Increment(cost_usd),
        f'{acct_key}.call_count': firestore.Increment(1),
        'date': today,
        'last_updated': datetime.now(timezone.utc),
    }
    ref.set(update, merge=True)


def get_total_llm_cost(uid: str, bucket: str = 'desktop_chat') -> float:
    """Sum cost_usd from the given bucket.

    When the bucket dual-writes to both ``{bucket}`` and ``{bucket}_{account}``,
    this reads only the primary bucket to avoid double-counting.
    """
    col = db.collection("users").document(uid).collection("llm_usage")
    total = 0.0
    for doc in col.stream():
        data = _typed_doc(doc)
        dc = data.get(bucket)
        if isinstance(dc, dict):
            dc_dict: Dict[str, Any] = cast(Dict[str, Any], dc)
            total += float(dc_dict.get('cost_usd', 0.0) or 0.0)
    return round(total, 6)
