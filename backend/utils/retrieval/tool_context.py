"""Invocation context shared by the retained backend retrieval tools."""

import contextvars
from typing import Any, Dict, Optional


tool_config_context: contextvars.ContextVar[Optional[Dict[str, Any]]] = contextvars.ContextVar(
    'tool_config', default=None
)
