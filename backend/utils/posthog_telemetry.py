"""Small fail-open boundary for server-side PostHog events."""

import importlib
import logging
import os
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

_posthog_client: Optional[Any] = None
_posthog_disabled = False


def emit_posthog_event(distinct_id: Optional[str], event: str, properties: Dict[str, Any]) -> None:
    if not distinct_id:
        return
    try:
        client = _get_posthog_client()
        if client is not None:
            client.capture(distinct_id=distinct_id, event=event, properties=properties)
    except Exception as exc:
        logger.warning('posthog_emit_failed event=%s error=%s', event, type(exc).__name__)


def _get_posthog_client() -> Optional[Any]:
    global _posthog_client, _posthog_disabled
    if _posthog_disabled:
        return None
    if _posthog_client is not None:
        return _posthog_client

    api_key = os.getenv('POSTHOG_PROJECT_API_KEY') or os.getenv('POSTHOG_API_KEY')
    if not api_key:
        _posthog_disabled = True
        return None

    host = os.getenv('POSTHOG_HOST', 'https://app.posthog.com')
    try:
        posthog_module = importlib.import_module('posthog')
        posthog_client_cls = getattr(posthog_module, 'Posthog')
    except Exception as exc:
        logger.warning('posthog_import_failed error=%s', type(exc).__name__)
        _posthog_disabled = True
        return None

    _posthog_client = posthog_client_cls(project_api_key=api_key, host=host)
    return _posthog_client
