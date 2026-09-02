"""Langfuse Prompt Management for the managed desktop Chat boundary."""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from typing import Any

from utils.observability.fallback import record_fallback
from utils.observability.langfuse import get_langfuse_client

logger = logging.getLogger(__name__)

DEFAULT_PROMPT_NAME = 'intentive-chat-system'
DEFAULT_PROMPT_CACHE_TTL_SECONDS = 300

# Intentive does not have access to Omi's private LangSmith prompt. Keep this
# fallback intentionally blank until Intentive authors its own managed Chat prompt.
FALLBACK_RUNTIME_PROMPT = ''


@dataclass(frozen=True)
class ResolvedRuntimePrompt:
    text: str
    name: str
    version: str
    source: str
    prompt_client: Any | None = None


def get_prompt_name() -> str:
    return os.environ.get('LANGFUSE_PROMPT_NAME', '').strip() or DEFAULT_PROMPT_NAME


def get_prompt_cache_ttl_seconds() -> int:
    raw = os.environ.get('LANGFUSE_PROMPT_CACHE_TTL_SECONDS', '').strip()
    if not raw:
        return DEFAULT_PROMPT_CACHE_TTL_SECONDS
    try:
        ttl = int(raw)
    except ValueError:
        return DEFAULT_PROMPT_CACHE_TTL_SECONDS
    return ttl if ttl >= 0 else DEFAULT_PROMPT_CACHE_TTL_SECONDS


def fallback_runtime_prompt(*, reason: str = 'config_incomplete') -> ResolvedRuntimePrompt:
    record_fallback(
        component='other',
        from_mode='langfuse_prompt',
        to_mode='repository_prompt',
        reason=reason,
        outcome='degraded',
        log=logger,
    )
    return ResolvedRuntimePrompt(
        text=FALLBACK_RUNTIME_PROMPT,
        name=get_prompt_name(),
        version='fallback',
        source='fallback',
    )


def get_runtime_prompt() -> ResolvedRuntimePrompt:
    """Resolve the production prompt through Langfuse's own TTL cache."""
    prompt_name = get_prompt_name()
    try:
        client = get_langfuse_client()
    except Exception as error:
        logger.warning('Langfuse prompt client initialization failed error_type=%s', type(error).__name__)
        return fallback_runtime_prompt(reason='other')
    if client is None:
        return fallback_runtime_prompt()
    try:
        prompt = client.get_prompt(
            prompt_name,
            label='production',
            type='text',
            cache_ttl_seconds=get_prompt_cache_ttl_seconds(),
        )
        compiled = prompt.compile()
        if not isinstance(compiled, str):
            raise TypeError('Langfuse text prompt did not compile to a string')
        if bool(getattr(prompt, 'is_fallback', False)):
            return fallback_runtime_prompt(reason='other')
        version = str(getattr(prompt, 'version', 'unknown'))
        logger.info('Resolved Langfuse prompt name=%s version=%s', prompt_name, version)
        return ResolvedRuntimePrompt(
            text=compiled,
            name=prompt_name,
            version=version,
            source='langfuse',
            prompt_client=prompt,
        )
    except Exception as error:
        logger.warning('Langfuse prompt fetch failed error_type=%s', type(error).__name__)
        return fallback_runtime_prompt(reason='other')


def compose_system_prompt(prompt: ResolvedRuntimePrompt, kernel_system_prompt: str | None) -> str:
    """Place the managed prompt before the existing Mac kernel policy."""
    managed = prompt.text.strip()
    kernel = (kernel_system_prompt or '').strip()
    if managed and kernel:
        return f'{managed}\n\n{kernel}'
    return managed or kernel
