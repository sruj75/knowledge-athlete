"""Provider-specific chat model construction for LLM feature routing.

This module owns the mechanics of turning a resolved provider/model route into a
LangChain ``BaseChatModel``. Keep product features out of this file: callers
should route by feature through ``utils.llm.clients.get_workload_client()`` and
let the explicit workload inventory decide which provider/model to use.
"""

import os
from typing import Any, Dict, Optional

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.language_models import BaseChatModel
from langchain_google_genai import ChatGoogleGenerativeAI
from pydantic import SecretStr

from utils.llm.provider_errors import handle_llm_error
from utils.llm.usage_tracker import get_usage_callback

_usage_callback = get_usage_callback()
_error_callbacks: Dict[tuple[str, str, str], BaseCallbackHandler] = {}


class _ManagedProviderErrorCallback(BaseCallbackHandler):
    def __init__(self, provider: str, model: str, feature: str) -> None:
        self.provider = provider
        self.model = model
        self.feature = feature

    def on_llm_error(self, error: BaseException, **_kwargs: Any) -> None:
        if isinstance(error, Exception):
            handle_llm_error(error, self.provider, feature=self.feature, model=self.model)


def _callbacks(provider: str, model: str, feature: str) -> list[BaseCallbackHandler]:
    key = (provider, model, feature)
    callback = _error_callbacks.get(key)
    if callback is None:
        callback = _ManagedProviderErrorCallback(provider, model, feature)
        _error_callbacks[key] = callback
    return [_usage_callback, callback]


_llm_cache: Dict[tuple, Any] = {}


def get_or_create_gemini_llm(
    model_name: str,
    streaming: bool = False,
    thinking_budget: Optional[int] = None,
    feature: str = '',
) -> BaseChatModel:
    """Get or create a cached native Gemini Developer API chat model."""

    key = (model_name, streaming, 'gemini', thinking_budget, feature)
    if key not in _llm_cache:
        gemini_key = os.environ.get('GEMINI_API_KEY', '')
        kwargs: Dict[str, Any] = {
            'callbacks': _callbacks('gemini', model_name, feature),
            'timeout': 120,
            'max_retries': 1,
            # Keep construction lazy-testable while runtime validation owns
            # rejecting an absent managed credential before serving traffic.
            'google_api_key': gemini_key or SecretStr('not-set'),
        }
        if streaming:
            kwargs['streaming'] = True
        if thinking_budget is not None:
            kwargs['thinking_budget'] = thinking_budget
        _llm_cache[key] = ChatGoogleGenerativeAI(model=model_name, **kwargs)
    return _llm_cache[key]


def get_default_client(
    model: str,
    provider: str,
    streaming: bool,
    options: Optional[Dict[str, Any]] = None,
    *,
    feature: str = '',
) -> BaseChatModel:
    """Get the cached default client for a model/provider combo."""

    options = options or {}
    if provider == 'gemini':
        return get_or_create_gemini_llm(
            model,
            streaming,
            thinking_budget=options.get('thinking_budget'),
            feature=feature,
        )
    raise ValueError(f"Unknown managed provider '{provider}'")
