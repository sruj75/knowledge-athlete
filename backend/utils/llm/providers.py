"""Provider-specific chat model construction for LLM feature routing.

This module owns the mechanics of turning a resolved provider/model route into a
LangChain ``BaseChatModel``. Keep product features out of this file: callers
should route by feature through ``utils.llm.clients.get_workload_client()`` and
let the explicit workload inventory decide which provider/model to use.
"""

import logging
import os
from dataclasses import dataclass, field
from typing import Any, Dict, Optional

from langchain_core.callbacks import BaseCallbackHandler
from langchain_core.language_models import BaseChatModel
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_openai import ChatOpenAI
from pydantic import SecretStr

from utils.llm.provider_errors import handle_llm_error
from utils.llm.usage_tracker import get_usage_callback

logger = logging.getLogger(__name__)

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


# Google's OpenAI-compatible endpoint used by the credential-free placeholder
# when managed Gemini configuration is absent.
GEMINI_OPENAI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/openai/"


@dataclass(frozen=True)
class OpenAICompatibleProviderConfig:
    """Configuration for providers served through ChatOpenAI-compatible APIs."""

    name: str
    api_key_env: str
    base_url: Optional[str] = None
    default_headers: Dict[str, str] = field(default_factory=dict)
    prefix_google_models: bool = False


OPENAI_COMPATIBLE_PROVIDERS: Dict[str, OpenAICompatibleProviderConfig] = {
    'openai': OpenAICompatibleProviderConfig(name='openai', api_key_env='OPENAI_API_KEY'),
    'openrouter': OpenAICompatibleProviderConfig(
        name='openrouter',
        api_key_env='OPENROUTER_API_KEY',
        base_url="https://openrouter.ai/api/v1",
        default_headers={"X-Title": "Omi Chat"},
        prefix_google_models=True,
    ),
}

_llm_cache: Dict[tuple, Any] = {}


def _cache_key(provider: str, model_name: str, streaming: bool, options: Dict[str, Any]) -> tuple:
    option_items = tuple(sorted((key, repr(value)) for key, value in options.items()))
    return provider, model_name, streaming, option_items


def _api_model_name(provider_config: OpenAICompatibleProviderConfig, model_name: str) -> str:
    if provider_config.prefix_google_models and model_name.startswith('gemini'):
        return f'google/{model_name}'
    return model_name


def get_or_create_openai_compatible_llm(
    provider: str,
    model_name: str,
    streaming: bool = False,
    options: Optional[Dict[str, Any]] = None,
    feature: str = '',
) -> ChatOpenAI:
    """Get or create a cached ChatOpenAI-compatible chat model."""

    options = options or {}
    if provider not in OPENAI_COMPATIBLE_PROVIDERS:
        raise ValueError(f"Unknown OpenAI-compatible provider '{provider}'")

    provider_config = OPENAI_COMPATIBLE_PROVIDERS[provider]
    # Only include options that are actually transferred to kwargs in the cache key,
    # so arbitrary caller options don't create duplicate cache entries.
    _handled_options = {
        'request_timeout',
        'max_retries',
        'temperature',
        'extra_body',
        'base_url',
        'default_headers',
        'api_key',
    }
    _effective_options = {k: v for k, v in options.items() if k in _handled_options}
    key = (*_cache_key(provider, model_name, streaming, _effective_options), feature)
    if key not in _llm_cache:
        kwargs: Dict[str, Any] = {
            'callbacks': _callbacks(provider, model_name, feature),
            # The direct provider is the recovery path. Keep its established
            # deadline/retry budget; only the optional gateway hop is short.
            'request_timeout': options.get('request_timeout', 120),
            'max_retries': options.get('max_retries', 1),
        }
        api_key = os.environ.get(provider_config.api_key_env)
        if api_key:
            kwargs['api_key'] = api_key
        if provider_config.base_url:
            kwargs['base_url'] = provider_config.base_url
        if provider_config.default_headers:
            kwargs['default_headers'] = provider_config.default_headers
        if options.get('extra_body'):
            kwargs['extra_body'] = options['extra_body']
        if 'temperature' in options:
            kwargs['temperature'] = options['temperature']
        if streaming:
            kwargs['streaming'] = True
            kwargs['stream_options'] = {"include_usage": True}

        _llm_cache[key] = ChatOpenAI(model=_api_model_name(provider_config, model_name), **kwargs)
    return _llm_cache[key]


def get_or_create_gemini_llm(
    model_name: str,
    streaming: bool = False,
    thinking_budget: Optional[int] = None,
    feature: str = '',
) -> BaseChatModel:
    """Get or create a cached ChatGoogleGenerativeAI for a Gemini model via native SDK.

    Routing priority:
      1. USE_VERTEX_AI=true + GOOGLE_CLOUD_PROJECT → Vertex AI
      2. GEMINI_API_KEY set → AI Studio
      3. Neither → placeholder that fails at invoke time (unit tests)

    """

    # Build cache key — only include thinking_budget when we'll actually use it
    # (i.e., when Vertex AI or API key is configured). The fallback ChatOpenAI
    # path strips thinking_budget, so including it would create duplicate entries.
    _has_gemini_creds = bool(
        os.environ.get('USE_VERTEX_AI', '').lower() == 'true' and os.environ.get('GOOGLE_CLOUD_PROJECT', '')
    ) or bool(os.environ.get('GEMINI_API_KEY', ''))
    cache_budget = thinking_budget if _has_gemini_creds else None
    key = (model_name, streaming, 'gemini', cache_budget, feature)
    if key not in _llm_cache:
        use_vertex = os.environ.get('USE_VERTEX_AI', '').lower() == 'true'
        gcp_project = os.environ.get('GOOGLE_CLOUD_PROJECT', '') if use_vertex else ''
        gemini_key = os.environ.get('GEMINI_API_KEY', '')
        kwargs: Dict[str, Any] = {
            'callbacks': _callbacks('gemini', model_name, feature),
            'timeout': 120,
            'max_retries': 1,
        }
        if streaming:
            kwargs['streaming'] = True
        if thinking_budget is not None and model_name.startswith('gemini-2.5'):
            kwargs['thinking_budget'] = thinking_budget

        if gcp_project:
            gcp_location = os.environ.get('GCP_LOCATION', 'us-central1')
            _llm_cache[key] = ChatGoogleGenerativeAI(
                model=model_name, project=gcp_project, location=gcp_location, **kwargs
            )
        elif gemini_key:
            kwargs['google_api_key'] = gemini_key
            _llm_cache[key] = ChatGoogleGenerativeAI(model=model_name, **kwargs)
        else:
            logger.warning('No USE_VERTEX_AI or GEMINI_API_KEY — Gemini calls will fail at invoke time')
            # Strip thinking_budget — it's a ChatGoogleGenerativeAI-only param
            # that ChatOpenAI rejects at invoke time.
            fallback_kwargs = {k: v for k, v in kwargs.items() if k != 'thinking_budget'}
            _llm_cache[key] = ChatOpenAI(
                model=model_name,
                api_key=SecretStr('not-set'),
                base_url=GEMINI_OPENAI_BASE_URL,
                **fallback_kwargs,
            )
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
    return get_or_create_openai_compatible_llm(provider, model, streaming, options, feature=feature)
