"""Managed-provider error logging shared by LLM client adapters."""

import asyncio
import logging
from typing import Optional

from utils.executors import storage_executor, submit_with_context
from utils.log_sanitizer import sanitize

logger = logging.getLogger(__name__)


def handle_llm_error(
    error: Exception,
    provider: Optional[str],
    feature: Optional[str] = None,
    model: Optional[str] = None,
    operation: str = 'chat',
) -> None:
    """Log a sanitized managed-provider failure without customer credentials."""
    status_code = getattr(error, 'status_code', None)
    if not isinstance(status_code, int):
        status_code = getattr(getattr(error, 'response', None), 'status_code', None)
    logger.error(
        'LLM error provider=%s feature=%s model=%s operation=%s status_code=%s error_type=%s error=%s',
        provider or 'unknown',
        feature or 'unknown',
        model or 'unknown',
        operation,
        status_code if isinstance(status_code, int) else 'unknown',
        type(error).__name__,
        sanitize(str(error)),
    )


async def handle_llm_error_async(
    error: Exception,
    provider: Optional[str],
    feature: Optional[str] = None,
    model: Optional[str] = None,
    operation: str = 'chat',
) -> None:
    """Run managed-provider error logging outside the event loop."""
    future = submit_with_context(storage_executor, handle_llm_error, error, provider, feature, model, operation)
    try:
        await asyncio.wrap_future(future)
    except Exception as handler_error:
        logger.error(
            'Async LLM error handler failed provider=%s feature=%s: %s',
            provider,
            feature,
            sanitize(str(handler_error)),
        )
