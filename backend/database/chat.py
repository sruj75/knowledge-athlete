import copy
import logging
from datetime import datetime, timezone
from typing import Any, Dict, Iterator, List, Optional, cast

from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter

from database.read_boundary import parse_snapshot_or_none
from models.chat import Message
from utils import encryption
from ._client import db

logger = logging.getLogger(__name__)


def _typed_doc(doc: Any) -> Dict[str, Any]:
    """Typed adapter for a Firestore DocumentSnapshot.to_dict() result.

    Returns an empty dict when the document has no fields (None payload),
    so callers can safely mutate and read keys without Optional checks.
    """
    raw: object = doc.to_dict()
    return cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}


# *********************************
# ******* ENCRYPTION HELPERS ******
# *********************************


def _decrypt_chat_data(chat_data: Dict[str, Any], uid: str) -> Dict[str, Any]:
    data = copy.deepcopy(chat_data)

    if 'text' in data and isinstance(data['text'], str):
        try:
            data['text'] = encryption.decrypt(data['text'], uid)
        except Exception:
            pass

    return data


def _prepare_message_for_read(message_data: Dict[str, Any], uid: str) -> Dict[str, Any]:
    level = message_data.get('data_protection_level')
    if level == 'enhanced':
        return _decrypt_chat_data(message_data, uid)

    return message_data


# *****************************
# ********** CRUD *************
# *****************************


def iter_all_messages(uid: str, batch_size: int = 1000) -> Iterator[Dict[str, Any]]:
    """Yield all chat messages for a user, decrypted, in batches. Used for streaming data export."""
    user_ref = db.collection('users').document(uid)
    msgs_ref = user_ref.collection('messages').order_by('created_at', direction=firestore.Query.DESCENDING)
    offset = 0
    while True:
        batch_ref = msgs_ref.limit(batch_size).offset(offset)
        batch: List[Dict[str, Any]] = []
        for doc in batch_ref.stream():
            msg: Dict[str, Any] = _typed_doc(doc)
            msg['id'] = doc.id
            msg = _prepare_message_for_read(msg, uid) or msg
            batch.append(msg)
        yield from batch
        if len(batch) < batch_size:
            break
        offset += batch_size


def get_message(uid: str, message_id: str) -> tuple[Message, str] | None:
    user_ref = db.collection('users').document(uid)
    message_ref = user_ref.collection('messages').where('id', '==', message_id).limit(1).stream()
    message_doc = next(message_ref, None)
    if not message_doc:
        return None

    message = parse_snapshot_or_none(
        Message,
        message_doc,
        payload_from_snapshot=lambda snapshot: _prepare_message_for_read(_typed_doc(snapshot), uid),
    )
    if message is None:
        return None

    return message, message_doc.id


def report_message(uid: str, msg_doc_id: str) -> Dict[str, str]:
    user_ref = db.collection('users').document(uid)
    message_ref = user_ref.collection('messages').document(msg_doc_id)
    try:
        message_ref.update({'reported': True})
        return {"message": "Message reported"}
    except Exception as e:
        logger.error(f"Update failed: {e}")
        return {"message": f"Update failed: {e}"}


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


# **************************************
# ********* MIGRATION HELPERS **********
# **************************************


def get_chats_to_migrate(uid: str, target_level: str) -> List[Dict[str, Any]]:
    """
    Finds all chat messages that are not at the target protection level by fetching all documents
    and filtering them in memory. This simplifies the code but may be less performant for
    users with a very large number of documents.
    """
    messages_ref = db.collection('users').document(uid).collection('messages')
    all_messages = messages_ref.select(['data_protection_level']).stream()

    to_migrate: List[Dict[str, Any]] = []
    for doc in all_messages:
        doc_data: Dict[str, Any] = _typed_doc(doc)
        current_level = doc_data.get('data_protection_level', 'standard')
        if target_level != current_level:
            to_migrate.append({'id': doc.id, 'type': 'chat'})

    return to_migrate


def migrate_chats_level_batch(uid: str, message_doc_ids: List[str], target_level: str) -> None:
    """
    Migrates a batch of chat messages to the target protection level.
    """
    batch = db.batch()
    messages_ref = db.collection('users').document(uid).collection('messages')
    doc_refs = [messages_ref.document(msg_id) for msg_id in message_doc_ids]
    doc_snapshots = db.get_all(doc_refs)

    for doc_snapshot in doc_snapshots:
        if not doc_snapshot.exists:
            logger.warning(f"Message {doc_snapshot.id} not found, skipping.")
            continue

        message_data: Dict[str, Any] = _typed_doc(doc_snapshot)
        current_level = message_data.get('data_protection_level', 'standard')

        if current_level == target_level:
            continue

        plain_data: Dict[str, Any] = _prepare_message_for_read(message_data, uid)
        plain_text = plain_data.get('text')
        migrated_text = plain_text
        if target_level == 'enhanced':
            if isinstance(plain_text, str):
                migrated_text = encryption.encrypt(plain_text, uid)

        update_data: Dict[str, Any] = {'data_protection_level': target_level, 'text': migrated_text}
        batch.update(doc_snapshot.reference, update_data)

    batch.commit()
