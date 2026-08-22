import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, cast

from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter

from ._client import db

logger = logging.getLogger(__name__)


def _typed_doc(doc: Any) -> Dict[str, Any]:
    """Typed adapter for a Firestore DocumentSnapshot.to_dict() result.

    Returns an empty dict when the document has no fields (None payload),
    so callers can safely mutate and read keys without Optional checks.
    """
    raw: object = doc.to_dict()
    return cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}


def add_multi_files(uid: str, files_data: List[Dict[str, Any]]) -> None:
    batch = db.batch()
    user_ref = db.collection('users').document(uid)

    for file_data in files_data:
        file_ref = user_ref.collection('files').document(file_data['id'])
        batch.set(file_ref, file_data)

    batch.commit()


def get_chat_files(uid: str, files_id: Optional[List[str]] = None) -> List[Dict[str, Any]]:
    files_ref = db.collection('users').document(uid).collection('files')

    if files_id is None:
        files_id = []

    # If no specific files requested, return all
    if len(files_id) == 0:
        return [_typed_doc(doc) for doc in files_ref.stream()]

    # Firestore IN operator supports max 30 values, so chunk the queries
    if len(files_id) <= 30:
        files_ref = files_ref.where(filter=FieldFilter('id', 'in', files_id))
        return [_typed_doc(doc) for doc in files_ref.stream()]

    # Chunk into batches of 30
    results: List[Dict[str, Any]] = []
    for i in range(0, len(files_id), 30):
        chunk = files_id[i : i + 30]
        chunk_ref = db.collection('users').document(uid).collection('files')
        chunk_ref = chunk_ref.where(filter=FieldFilter('id', 'in', chunk))
        results.extend([_typed_doc(doc) for doc in chunk_ref.stream()])

    return results


def get_chat_files_desc(uid: str, files_id: Optional[List[str]] = None, limit: int = 10) -> List[Dict[str, Any]]:
    """Get the most recent chat files ordered by created_at descending, optionally filtered by file IDs"""
    files_ref = db.collection('users').document(uid).collection('files')

    if files_id is None:
        files_id = []

    # If no specific files requested, return most recent files
    if len(files_id) == 0:
        files_ref = files_ref.order_by('created_at', direction=firestore.Query.DESCENDING).limit(limit)
        return [_typed_doc(doc) for doc in files_ref.stream()]

    # If specific files requested, filter by them first
    # Firestore IN operator supports max 30 values
    if len(files_id) <= 30:
        files_ref = files_ref.where(filter=FieldFilter('id', 'in', files_id))
        files_ref = files_ref.order_by('created_at', direction=firestore.Query.DESCENDING).limit(limit)
        return [_typed_doc(doc) for doc in files_ref.stream()]

    # Chunk into batches of 30 if more than 30 files
    results: List[Dict[str, Any]] = []
    for i in range(0, len(files_id), 30):
        chunk = files_id[i : i + 30]
        chunk_ref = db.collection('users').document(uid).collection('files')
        chunk_ref = chunk_ref.where(filter=FieldFilter('id', 'in', chunk))
        chunk_ref = chunk_ref.order_by('created_at', direction=firestore.Query.DESCENDING)
        results.extend([_typed_doc(doc) for doc in chunk_ref.stream()])

    # Sort all results by created_at and limit. Use a tz-aware sentinel for a missing created_at so it
    # never TypeError-compares against the tz-aware Firestore datetimes and sinks to the bottom of the
    # descending sort (same class as the review-queue tz sentinel in #9571).
    results.sort(key=lambda x: x.get('created_at', datetime.min.replace(tzinfo=timezone.utc)), reverse=True)
    return results[:limit]


def delete_multi_files(uid: str, files_data: List[Dict[str, Any]]) -> None:
    batch = db.batch()
    user_ref = db.collection('users').document(uid)

    for file_data in files_data:
        file_ref = user_ref.collection('files').document(file_data["id"])
        batch.delete(file_ref)

    batch.commit()


def get_chat_session_by_id(uid: str, chat_session_id: str) -> Optional[Dict[str, Any]]:
    """Get a specific chat session by its ID"""
    user_ref = db.collection('users').document(uid)
    session_ref = user_ref.collection('chat_sessions').document(chat_session_id)
    session_doc = session_ref.get()

    if session_doc.exists:
        data = _typed_doc(session_doc)
        data['id'] = chat_session_id
        return data

    return None


def update_chat_session_openai_ids(uid: str, chat_session_id: str, thread_id: str, assistant_id: str) -> None:
    """Update OpenAI thread and assistant IDs for a chat session"""
    user_ref = db.collection('users').document(uid)
    session_ref = user_ref.collection('chat_sessions').document(chat_session_id)

    update_data: Dict[str, str] = {}
    if thread_id:
        update_data['openai_thread_id'] = thread_id
    if assistant_id:
        update_data['openai_assistant_id'] = assistant_id

    if update_data:
        session_ref.update(update_data)
        logger.info(f"Updated session {chat_session_id} with thread {thread_id} and assistant {assistant_id}")
