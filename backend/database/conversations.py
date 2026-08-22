"""Minimal Firestore primitives for the temporary S-25 worker drain.

No public conversation product reads or writes remain. These functions can
only finish an already-existing finalization/audio task and never create a
conversation document.
"""

from __future__ import annotations

import copy
import json
import logging
import zlib
from typing import Any, Dict, Optional

from google.api_core.exceptions import NotFound
from google.cloud import firestore

from models.conversation_enums import ConversationStatus
from utils import encryption
from ._client import db

logger = logging.getLogger(__name__)
conversations_collection = 'conversations'

_DRAIN_RESULT_FIELDS = frozenset({'structured', 'status', 'discarded', 'language'})


def _conversation_ref(uid: str, conversation_id: str):
    return db.collection('users').document(uid).collection(conversations_collection).document(conversation_id)


def _decode_historical_transcript(data: Dict[str, Any], uid: str) -> Dict[str, Any]:
    """Read old compressed/encrypted rows without preserving their public schema."""
    decoded = copy.deepcopy(data)
    raw_segments = decoded.get('transcript_segments')
    if not decoded.get('transcript_segments_compressed'):
        return decoded
    try:
        if isinstance(raw_segments, str):
            compressed = bytes.fromhex(encryption.decrypt(raw_segments, uid))
        elif isinstance(raw_segments, bytes):
            compressed = raw_segments
        else:
            return decoded
        decoded['transcript_segments'] = json.loads(zlib.decompress(compressed).decode('utf-8'))
    except (json.JSONDecodeError, TypeError, UnicodeDecodeError, ValueError, zlib.error):
        logger.error('Historical finalization transcript could not be decoded')
        decoded['transcript_segments'] = []
    return decoded


def get_conversation(uid: str, conversation_id: str) -> Optional[Dict[str, Any]]:
    snapshot = _conversation_ref(uid, conversation_id).get()
    if not getattr(snapshot, 'exists', False):
        return None
    data = snapshot.to_dict() or {}
    return _decode_historical_transcript(data, uid)


def update_conversation(uid: str, conversation_id: str, update_data: dict) -> None:
    """Let the existing audio worker stamp only its already-queued result."""
    _conversation_ref(uid, conversation_id).update(update_data)


def persist_processing_result_with_lifecycle(uid: str, conversation_data: dict) -> bool:
    """Merge the narrow computed result into an existing drain row only."""
    conversation_id = conversation_data['id']
    conversation_ref = _conversation_ref(uid, conversation_id)
    transaction = db.transaction()

    @firestore.transactional
    def persist(transaction) -> bool:
        snapshot = conversation_ref.get(transaction=transaction)
        if not getattr(snapshot, 'exists', False):
            return False
        update_data = {
            field: copy.deepcopy(conversation_data[field])
            for field in _DRAIN_RESULT_FIELDS
            if field in conversation_data
        }
        transaction.set(conversation_ref, update_data, merge=True)
        return True

    return persist(transaction)


def claim_conversation_status(
    uid: str,
    conversation_id: str,
    expected_status: ConversationStatus,
    claimed_status: ConversationStatus,
    extra_updates: Optional[Dict[str, Any]] = None,
) -> bool:
    conversation_ref = _conversation_ref(uid, conversation_id)
    transaction = db.transaction()

    @firestore.transactional
    def claim(transaction) -> bool:
        snapshot = conversation_ref.get(transaction=transaction)
        if not getattr(snapshot, 'exists', False):
            raise NotFound(f'Conversation {conversation_id} not found')
        current = snapshot.to_dict() or {}
        if current.get('discarded') or current.get('status') != expected_status.value:
            return False
        updates: Dict[str, Any] = {'status': claimed_status.value}
        if extra_updates:
            updates.update(extra_updates)
        transaction.update(conversation_ref, updates)
        return True

    return claim(transaction)
