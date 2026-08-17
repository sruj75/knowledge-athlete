from typing import Any, Dict, Optional

from firebase_admin import auth

from database.redis_db import cache_user_name
import logging

logger = logging.getLogger(__name__)


def _firebase_get_user(uid: str) -> Any:
    """Wrap firebase_admin.auth.get_user at the SDK boundary.

    firebase_admin.auth ships incomplete type stubs; its UserRecord fields
    surface as partially-unknown. Sealing the call here lets callers treat the
    result as Any and read fields without propagating Unknown.
    """
    return auth.get_user(uid)  # type: ignore[reportUnknownMemberType]  # firebase_admin.auth stub gap


def get_user_from_uid(uid: str) -> Optional[Dict[str, Any]]:
    try:
        raw_user: Any = _firebase_get_user(uid) if uid else None
    except Exception as e:
        logger.error(e)
        raw_user = None
    if not raw_user:
        return None

    user: Any = raw_user

    return {
        'uid': user.uid,
        'email': user.email,
        'email_verified': user.email_verified,
        'phone_number': user.phone_number,
        'display_name': user.display_name,
        'photo_url': user.photo_url,
        'disabled': user.disabled,
    }


def get_user_name(uid: str, use_default: bool = True) -> Optional[str]:
    default_name: Optional[str] = 'The User' if use_default else None
    user = get_user_from_uid(uid)
    if not user:
        return default_name

    display_name_raw = user.get('display_name')
    if not display_name_raw:
        return default_name

    display_name: str = display_name_raw.split(' ')[0]
    if display_name == 'AnonymousUser':
        return default_name

    cache_user_name(uid, display_name, ttl=60 * 60)
    return display_name
