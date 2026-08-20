"""
Notifications database module

Structure:
users/{uid}/fcm_tokens (subcollection)
  └── {device_key} (document)
      ├── token: "actual_token_value"
      ├── created_at: timestamp
      └── time_zone: "America/New_York"
"""

from google.cloud.firestore_v1.base_query import FieldFilter
from google.cloud import firestore
from google.cloud.firestore import DELETE_FIELD
from ._client import db
import logging
from typing import Any, Dict, List, Optional, Tuple, Union, cast

logger = logging.getLogger(__name__)


def _typed_doc(doc: Any) -> Dict[str, Any]:
    raw: object = doc.to_dict()
    return cast(Dict[str, Any], raw) if isinstance(raw, dict) else {}


def save_token(uid: str, data: Dict[str, Any]) -> None:
    """
    Store token in subcollection with device key as document ID
    Structure: users/{uid}/fcm_tokens/{device_key}
    Also maintains time_zone in main user document for backward compatibility
    Migrates legacy fcm_token to subcollection
    """
    device_key = data.get('device_key', 'unknown_default')
    token = data.get('fcm_token')
    time_zone = data.get('time_zone')

    user_ref = db.collection('users').document(uid)

    # Step 1: Migrate legacy token if exists
    user_doc = user_ref.get()
    if getattr(user_doc, "exists", False):
        user_data = _typed_doc(user_doc)
        legacy_token = user_data.get('fcm_token')

        if legacy_token:
            # Check if legacy token already exists in subcollection
            existing_tokens: List[object] = [
                t for t in (_typed_doc(d).get('token') for d in user_ref.collection('fcm_tokens').stream())
            ]

            if legacy_token not in existing_tokens:
                # Migrate to unknown_default
                user_ref.collection('fcm_tokens').document('unknown_default').set(
                    {
                        'token': legacy_token,
                        'time_zone': user_data.get('time_zone'),
                        'created_at': firestore.SERVER_TIMESTAMP,
                    },
                    merge=True,
                )

            # Remove legacy field
            user_ref.update({'fcm_token': DELETE_FIELD})

    # Step 2: If new token has proper device_key, replace unknown_default
    if device_key != 'unknown_default':
        unknown_ref = user_ref.collection('fcm_tokens').document('unknown_default')
        unknown_doc = unknown_ref.get()
        if getattr(unknown_doc, "exists", False):
            unknown_token = _typed_doc(unknown_doc).get('token')
            # Only delete if it's the same token being migrated to proper device_key
            if unknown_token == token:
                unknown_ref.delete()

    # Step 3: Save new token to subcollection
    user_ref.collection('fcm_tokens').document(device_key).set(
        {'token': token, 'time_zone': time_zone, 'created_at': firestore.SERVER_TIMESTAMP}, merge=True
    )

    # Also update time_zone in main user document (for backward compatibility and efficient queries)
    if time_zone:
        user_ref.set({'time_zone': time_zone}, merge=True)


def get_user_time_zone(uid: str) -> Optional[str]:
    """Get timezone from main user document"""
    user_ref = db.collection('users').document(uid).get()
    if getattr(user_ref, "exists", False):
        user_data = _typed_doc(user_ref)
        tz = user_data.get('time_zone')
        return str(tz) if tz is not None else None
    return None


# **************************************
def get_all_tokens(uid: str) -> list[str]:
    """Get all device tokens for a user from subcollection and legacy field"""
    tokens: List[str] = []

    # Get tokens from new subcollection
    token_docs = db.collection('users').document(uid).collection('fcm_tokens').stream()
    for doc in token_docs:
        token_data = _typed_doc(doc)
        token_value = token_data.get('token')
        if token_value:
            tokens.append(str(token_value))

    # Get legacy token from main user document (backward compatibility)
    user_ref = db.collection('users').document(uid).get()
    if getattr(user_ref, "exists", False):
        user_data = _typed_doc(user_ref)
        legacy_token = user_data.get('fcm_token')
        if legacy_token and legacy_token not in tokens:
            tokens.append(str(legacy_token))

    return tokens


def remove_invalid_token(token: str) -> None:
    """Remove invalid token using collection group query (rare operation)"""
    # Query across ALL users' fcm_tokens subcollections
    query = db.collection_group('fcm_tokens').where(filter=FieldFilter('token', '==', token)).limit(1)

    for doc in query.stream():
        doc.reference.delete()
        return


def remove_bulk_tokens(tokens: list[str]) -> None:
    """Remove multiple invalid tokens efficiently using IN queries and batch deletes"""
    if not tokens:
        return

    # Firestore IN queries support up to 30 items
    chunk_size = 30
    token_chunks = [tokens[i : i + chunk_size] for i in range(0, len(tokens), chunk_size)]

    for chunk in token_chunks:
        # Query for all tokens in this chunk at once
        query = db.collection_group('fcm_tokens').where(filter=FieldFilter('token', 'in', chunk))

        # Batch delete for efficiency
        batch = db.batch()
        count = 0

        for doc in query.stream():
            batch.delete(doc.reference)
            count += 1

            # Firestore batch limit is 500 operations
            if count >= 500:
                batch.commit()
                batch = db.batch()
                count = 0

        # Commit remaining deletes
        if count > 0:
            batch.commit()


def get_users_token_in_timezones(timezones: list[str]) -> List[str]:
    return _get_users_in_timezones(timezones, 'fcm_token')


def get_users_id_in_timezones(timezones: list[str]) -> List[Union[str, Tuple[str, List[str], Any]]]:
    return _get_users_in_timezones(timezones, 'id')


def _get_users_in_timezones(timezones: list[str], filter: str) -> List[Any]:
    """Query main user documents by timezone, then get tokens from subcollection and legacy field"""
    users: List[Any] = []

    # 'Where in' query only supports 30 or fewer items in list so we split in chunks
    timezone_chunks = [timezones[i : i + 30] for i in range(0, len(timezones), 30)]

    for chunk in timezone_chunks:
        chunk_users: List[Any] = []
        try:
            # Query main user documents by time_zone
            query = db.collection('users').where(filter=FieldFilter('time_zone', 'in', chunk))

            for user_doc in query.stream():
                uid = str(user_doc.id)
                user_data = _typed_doc(user_doc)

                # Collect tokens from subcollection
                tokens: List[str] = []
                token_docs = db.collection('users').document(uid).collection('fcm_tokens').stream()
                for token_doc in token_docs:
                    token_data = _typed_doc(token_doc)
                    token_value = token_data.get('token')
                    if token_value:
                        tokens.append(str(token_value))

                # Add legacy token if exists and not already in list
                legacy_token = user_data.get('fcm_token')
                if legacy_token and legacy_token not in tokens:
                    tokens.append(str(legacy_token))

                # Skip users with no tokens
                if not tokens:
                    continue

                if filter == 'fcm_token':
                    # Return flat list of tokens
                    chunk_users.extend(tokens)
                else:
                    # Return list of (uid, [tokens], time_zone) tuples
                    time_zone = user_data.get('time_zone')
                    chunk_users.append((uid, tokens, time_zone))

        except Exception as e:
            logger.error(f"Error querying chunk {chunk}: {e}")
        users.extend(chunk_users)

    return users
