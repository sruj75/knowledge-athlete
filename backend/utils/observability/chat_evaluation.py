"""Short-lived owner-scoped prompt receipts; never stores conversation or provider input."""

import hashlib
import json
import logging

from database.redis_connection import get_redis_client
from models.desktop_ai import PromptReference

logger = logging.getLogger(__name__)


def _key(uid: str, request_id: str) -> str:
    identity = json.dumps([uid, request_id], separators=(',', ':')).encode()
    return 'desktop-chat-prompt:' + hashlib.sha256(identity).hexdigest()


def remember_chat_prompt(uid: str, request_id: str, prompt: PromptReference) -> None:
    try:
        get_redis_client().set(_key(uid, request_id), prompt.model_dump_json(), ex=86_400)
    except Exception as error:
        logger.warning('Chat prompt receipt unavailable error_type=%s', type(error).__name__)


def chat_prompt_reference(uid: str, request_id: str) -> PromptReference | None:
    try:
        value = get_redis_client().get(_key(uid, request_id))
        return PromptReference.model_validate_json(value) if value is not None else None
    except Exception as error:
        logger.warning('Chat prompt receipt unavailable error_type=%s', type(error).__name__)
        return None
