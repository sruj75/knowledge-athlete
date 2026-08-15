"""
LangSmith observability configuration and status logging.

This module provides utilities for checking and logging LangSmith tracing status
at application startup and creating per-request tracers for scoped tracing.
"""

import os
from typing import Optional, List, Any, Callable, Dict
import logging

logger = logging.getLogger(__name__)


def is_langsmith_enabled() -> bool:
    """
    Check if LangSmith tracing is enabled via environment variables.

    Checks both new (LANGSMITH_*) and legacy (LANGCHAIN_*) env var formats.

    Returns:
        True if tracing is enabled, False otherwise
    """
    # Check new-style env vars first
    langsmith_tracing = os.environ.get("LANGSMITH_TRACING", "").lower()
    if langsmith_tracing == "true":
        return True

    # Check legacy env vars
    langchain_tracing = os.environ.get("LANGCHAIN_TRACING_V2", "").lower()
    if langchain_tracing == "true":
        return True

    return False


def get_langsmith_project() -> str:
    """
    Get the configured LangSmith project name.

    Returns:
        Project name or "default" if not set
    """
    return os.environ.get("LANGSMITH_PROJECT") or os.environ.get("LANGCHAIN_PROJECT") or "default"


def get_langsmith_endpoint() -> str:
    """
    Get the configured LangSmith API endpoint.

    Returns:
        Endpoint URL or default LangSmith endpoint
    """
    return (
        os.environ.get("LANGSMITH_ENDPOINT")
        or os.environ.get("LANGCHAIN_ENDPOINT")
        or "https://api.smith.langchain.com"
    )


def has_langsmith_api_key() -> bool:
    """
    Check if a LangSmith API key is configured.

    Returns:
        True if an API key is set (doesn't validate the key)
    """
    api_key = os.environ.get("LANGSMITH_API_KEY") or os.environ.get("LANGCHAIN_API_KEY")
    return bool(api_key and len(api_key) > 0 and api_key != "lsv2_pt_REPLACE_WITH_YOUR_KEY")


def log_langsmith_status() -> None:
    """
    Log the current LangSmith tracing configuration status.

    This should be called at application startup to provide visibility
    into whether tracing is properly configured.
    """
    global_enabled = is_langsmith_enabled()
    has_key = has_langsmith_api_key()
    project = get_langsmith_project()
    endpoint = get_langsmith_endpoint()

    if global_enabled and has_key:
        logger.info(f"🔍 LangSmith: GLOBAL tracing ENABLED")
        logger.info(f"   Project: {project}")
        logger.info(f"   Endpoint: {endpoint}")
    elif has_key:
        # Global tracing off but API key present - per-request tracing for chat
        logger.info(f"🔍 LangSmith: Per-request tracing (chat only)")
        logger.info(f"   Project: {project}")
        logger.info(f"   Prompt Hub: enabled")
    else:
        logger.info(f"📊 LangSmith: DISABLED (no API key)")
        logger.info(f"   Set LANGSMITH_API_KEY to enable tracing and prompt fetching")


def get_chat_tracer_callbacks(
    run_name: Optional[str] = None,
    tags: Optional[List[str]] = None,
    metadata: Optional[Dict[str, Any]] = None,
) -> List[Any]:
    """
    Create LangSmith tracer callbacks for per-request tracing.

    This enables tracing for specific requests (e.g., chat) without enabling
    global tracing. Returns an empty list if API key is not configured.

    Args:
        run_name: Optional name for the run (e.g., "chat.agentic.stream")
        tags: Optional tags for the run (e.g., ["chat", "agentic"])
        metadata: Optional metadata dict for the run

    Returns:
        List containing LangChainTracer callback if API key is set, else empty list
    """
    if not has_langsmith_api_key():
        return []

    try:
        from langchain_core.tracers import LangChainTracer

        project = get_langsmith_project()

        tracer = LangChainTracer(
            project_name=project,
            tags=tags or [],
        )

        return [tracer]

    except Exception as e:
        logger.error(f"⚠️  Failed to create LangSmith tracer: {e}")
        return []


def bind_current_langsmith_run(
    callback_data: Optional[Dict[str, Any]],
    *,
    run_tree_getter: Optional[Callable[[], Any]] = None,
) -> Optional[str]:
    """Bind persisted chat metadata to the traceable wrapper's real run ID.

    A random UUID is not a LangSmith trace identity. When the decorated request
    has no current run (for example tracing is disabled), omit the field rather
    than persisting an ID that the operator website can never resolve.
    """
    try:
        if run_tree_getter is None:
            from langsmith.run_helpers import get_current_run_tree

            run_tree_getter = get_current_run_tree
        run_tree = run_tree_getter()
        run_id = getattr(run_tree, "id", None) if run_tree is not None else None
    except Exception as error:
        logger.error("Failed to resolve current LangSmith run error_type=%s", type(error).__name__)
        run_id = None

    resolved = str(run_id) if run_id else None
    if callback_data is not None:
        if resolved is None:
            callback_data.pop("langsmith_run_id", None)
        else:
            callback_data["langsmith_run_id"] = resolved
    return resolved
