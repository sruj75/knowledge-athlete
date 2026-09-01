"""Fail-open Langfuse tracing for managed desktop Chat requests."""

from __future__ import annotations

import logging
import os
import re
import threading
from dataclasses import dataclass
from datetime import datetime
from typing import Any
from urllib.parse import urlsplit

from langfuse import Langfuse, propagate_attributes

from utils.observability.fallback import record_fallback

logger = logging.getLogger(__name__)

DEFAULT_LANGFUSE_BASE_URL = 'https://us.cloud.langfuse.com'
_CORRELATION_ID_PATTERN = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$')

_client: Any | None = None
_client_configuration: tuple[str, str, str] | None = None
_client_lock = threading.Lock()


def get_langfuse_base_url() -> str:
    return os.environ.get('LANGFUSE_BASE_URL', '').strip() or DEFAULT_LANGFUSE_BASE_URL


def get_langfuse_client() -> Any | None:
    """Return the process client, constructing it lazily after env loading."""
    public_key = os.environ.get('LANGFUSE_PUBLIC_KEY', '').strip()
    secret_key = os.environ.get('LANGFUSE_SECRET_KEY', '').strip()
    if not public_key or not secret_key:
        return None

    base_url = get_langfuse_base_url()
    configuration = (public_key, secret_key, base_url)
    global _client, _client_configuration
    if _client is not None and _client_configuration == configuration:
        return _client

    with _client_lock:
        if _client is None or _client_configuration != configuration:
            _client = Langfuse(public_key=public_key, secret_key=secret_key, base_url=base_url)
            _client_configuration = configuration
    return _client


def log_langfuse_status() -> None:
    """Log the configured observability state without exposing either key."""
    public_key = bool(os.environ.get('LANGFUSE_PUBLIC_KEY', '').strip())
    secret_key = bool(os.environ.get('LANGFUSE_SECRET_KEY', '').strip())
    if public_key and secret_key:
        try:
            endpoint_host = urlsplit(get_langfuse_base_url()).hostname or 'invalid'
        except ValueError:
            endpoint_host = 'invalid'
        logger.info(
            'Langfuse tracing enabled endpoint_host=%s environment=%s',
            endpoint_host,
            os.environ.get('LANGFUSE_TRACING_ENVIRONMENT', 'default'),
        )
    elif public_key or secret_key:
        logger.warning('Langfuse tracing disabled because the credential pair is incomplete')
    else:
        logger.info('Langfuse tracing disabled because credentials are not configured')


def normalize_session_id(value: str | None) -> str | None:
    """Accept only bounded, opaque, Langfuse-safe session identifiers."""
    if value is None:
        return None
    candidate = value.strip()
    return candidate if _CORRELATION_ID_PATTERN.fullmatch(candidate) else None


def create_chat_trace_id(uid: str, request_id: str) -> str:
    """Create the stable trace identity shared by one local desktop turn."""
    return Langfuse.create_trace_id(seed=f'desktop-chat:{uid}:{request_id}')


def _bounded_metadata(value: object) -> str | None:
    text = str(value or '').strip()
    if not text or len(text) > 200 or not text.isascii():
        return None
    return text


def _record_tracing_fallback(reason: str) -> None:
    record_fallback(
        component='other',
        from_mode='langfuse_tracing',
        to_mode='untraced_chat',
        reason=reason,
        outcome='degraded',
        log=logger,
    )


@dataclass
class ChatGeneration:
    """Small fail-open lifecycle wrapper around a Langfuse generation."""

    observation: Any | None
    trace_id: str | None
    _ended: bool = False

    def mark_completion_started(self, started_at: datetime) -> None:
        if self.observation is None or self._ended:
            return
        try:
            self.observation.update(completion_start_time=started_at)
        except Exception as error:
            logger.warning('Langfuse first-token update failed error_type=%s', type(error).__name__)
            _record_tracing_fallback('other')

    def finish(
        self,
        *,
        output: object,
        usage_details: dict[str, int] | None = None,
        level: str | None = None,
        status_message: str | None = None,
    ) -> None:
        if self._ended:
            return
        self._ended = True
        if self.observation is None:
            return
        try:
            self.observation.update(
                output=output,
                usage_details=usage_details,
                level=level,
                status_message=status_message,
            )
        except Exception as error:
            logger.warning('Langfuse generation update failed error_type=%s', type(error).__name__)
            _record_tracing_fallback('other')
        try:
            self.observation.end()
        except Exception as error:
            logger.warning('Langfuse generation end failed error_type=%s', type(error).__name__)
            _record_tracing_fallback('other')


def start_chat_generation(
    *,
    uid: str,
    request_id: str,
    session_id: str | None,
    platform: str | None,
    model: str,
    provider_input: dict[str, object],
    prompt_version: str,
    prompt_source: str,
    prompt_client: Any | None,
    streaming: bool,
) -> ChatGeneration:
    """Start the one generation corresponding to an actual managed-model request."""
    try:
        client = get_langfuse_client()
    except Exception as error:
        logger.warning('Langfuse client initialization failed error_type=%s', type(error).__name__)
        _record_tracing_fallback('other')
        return ChatGeneration(None, None)
    if client is None:
        return ChatGeneration(None, None)

    trace_id: str | None = None
    try:
        trace_id = create_chat_trace_id(uid, request_id)
        metadata = {
            key: bounded
            for key, value in {
                'request_id': request_id,
                'platform': platform,
                'prompt_source': prompt_source,
                'prompt_version': prompt_version,
            }.items()
            if (bounded := _bounded_metadata(value)) is not None
        }
        with propagate_attributes(
            user_id=uid,
            session_id=normalize_session_id(session_id),
            tags=['desktop', 'chat', 'streaming' if streaming else 'nonstreaming'],
            metadata=metadata,
            trace_name='desktop-chat-completion',
        ):
            observation = client.start_observation(
                trace_context={'trace_id': trace_id},
                name='desktop-chat-completion',
                as_type='generation',
                input=provider_input,
                model=model,
                prompt=prompt_client,
            )
        return ChatGeneration(observation, trace_id)
    except Exception as error:
        logger.warning('Langfuse generation start failed error_type=%s', type(error).__name__)
        _record_tracing_fallback('other')
        return ChatGeneration(None, trace_id)


def shutdown_langfuse() -> None:
    """Flush and stop the process client within the caller's shutdown budget."""
    global _client, _client_configuration
    with _client_lock:
        client = _client
        _client = None
        _client_configuration = None
    if client is None:
        return
    try:
        client.shutdown()
    except Exception as error:
        logger.warning('Langfuse shutdown failed error_type=%s', type(error).__name__)


def reset_langfuse_client_for_testing() -> None:
    """Clear only the local singleton; tests inject harmless fake clients."""
    global _client, _client_configuration
    with _client_lock:
        _client = None
        _client_configuration = None
