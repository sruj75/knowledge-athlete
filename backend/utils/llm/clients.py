import logging
import os
from functools import lru_cache
from typing import Any, Callable, Dict, List, Optional

import anthropic
import httpx

try:
    from langchain_core.callbacks import BaseCallbackHandler
except ImportError:

    class BaseCallbackHandler:
        pass


from langchain_core.language_models import BaseChatModel
from langchain_core.output_parsers import PydanticOutputParser
from langchain_openai import ChatOpenAI, OpenAIEmbeddings
import tiktoken

from models.structured_extraction import StructuredExtraction
from utils.llm.provider_errors import handle_llm_error
from utils.llm.model_config import (
    MODEL_QOS_PROFILES,
    _ANTHROPIC_ONLY_FEATURES,
    _DEFAULT_CONFIG,
    _OPENROUTER_TEMPERATURES,
    _PERPLEXITY_ONLY_FEATURES,
    _PINNED_FEATURES,
    _STRUCTURED_OUTPUT_FEATURES,
    _active_profile,
    _active_profile_name,
    get_active_profile,
    get_active_profile_name,
    get_all_configured_features,
    get_default_config,
    get_model,
    get_provider,
    get_route_options,
    is_anthropic_only_feature,
    is_perplexity_only_feature,
    is_structured_output_feature,
    supports_cache_retention,
    supports_prompt_cache,
    _get_model_config,
)
from utils.llm.providers import (
    ChatGoogleGenerativeAI,  # backward-compat re-export (was here pre-refactor)
    GEMINI_OPENAI_BASE_URL,
    get_default_client,
    get_or_create_gemini_llm as _get_or_create_gemini_llm,
    get_or_create_openai_compatible_llm,
    _llm_cache,
)

try:
    from utils.llm.providers import get_or_create_omi_gateway_llm
except ImportError as exc:
    if exc.name != 'utils.llm.providers' and 'get_or_create_omi_gateway_llm' not in str(exc):
        raise

    def get_or_create_omi_gateway_llm(*_args, **_kwargs):
        raise RuntimeError('Omi gateway LangChain client is unavailable')


try:
    from utils.llm.gateway_client import (
        BACKGROUND_CHAT_EXTRACTION_TIMEOUT_SECONDS,
        CHAT_STRUCTURED_AUTO_LANE_ID,
        feature_auto_lane_id,
        raise_if_gateway_feature_mode_blocks_direct_model_surface,
        should_route_features_through_gateway,
    )
except ImportError as exc:
    if exc.name != 'utils.llm.gateway_client':
        raise

    BACKGROUND_CHAT_EXTRACTION_TIMEOUT_SECONDS = 35.0
    CHAT_STRUCTURED_AUTO_LANE_ID = 'omi:auto:chat-structured'

    def feature_auto_lane_id(feature: str) -> str:
        return f"omi:auto:{feature.replace('_', '-')}"

    def should_route_features_through_gateway() -> bool:
        return False

    def raise_if_gateway_feature_mode_blocks_direct_model_surface(_surface: str) -> None:
        return None


try:
    from utils.llm.gateway_observability import record_direct_exception_surface
except ImportError:

    def record_direct_exception_surface(*, surface: str, reason: str = 'acknowledged') -> None:
        return None


try:
    from utils.llm.gateway_anthropic import get_gateway_anthropic_client
except ImportError:

    def get_gateway_anthropic_client():
        raise RuntimeError('Omi gateway Anthropic client is unavailable')


try:
    from utils.llm.gateway_shadow import maybe_wrap_dev_gateway_shadow
except ImportError as exc:
    if exc.name != 'utils.llm.gateway_shadow':
        raise

    def maybe_wrap_dev_gateway_shadow(*, legacy_model, **_kwargs):
        return legacy_model


from utils.llm.usage_tracker import get_usage_callback

logger = logging.getLogger(__name__)

_usage_callback = get_usage_callback()
_GEMINI_OPENAI_BASE_URL = GEMINI_OPENAI_BASE_URL


class _LLMErrorCallback(BaseCallbackHandler):
    """LangChain callback that records managed-provider errors."""

    def __init__(self, provider: str, model: str = '', feature: str = ''):
        self.provider = provider
        self.model = model
        self.feature = feature

    def on_llm_error(self, error: BaseException, **kwargs) -> None:
        if isinstance(error, Exception):
            handle_llm_error(error, self.provider, feature=self.feature, model=self.model)


_llm_error_callbacks = {}


def _get_llm_error_callback(provider: str, model: str = '', feature: str = '') -> _LLMErrorCallback:
    key = (provider, model, feature)
    if key not in _llm_error_callbacks:
        _llm_error_callbacks[key] = _LLMErrorCallback(provider, model=model, feature=feature)
    return _llm_error_callbacks[key]


def _with_llm_callbacks(kwargs: Dict[str, Any], provider: str, model: str = '', feature: str = '') -> Dict[str, Any]:
    result = dict(kwargs)
    callbacks = list(result.get('callbacks') or [])
    if _usage_callback not in callbacks:
        callbacks.append(_usage_callback)
    error_callback = _get_llm_error_callback(provider, model=model, feature=feature)
    if error_callback not in callbacks:
        callbacks.append(error_callback)
    result['callbacks'] = callbacks
    return result


class _AnthropicClientProxy:
    """Lazily forwards attributes to the managed Anthropic client."""

    __slots__ = ('_default',)

    def __init__(self, default: Optional[anthropic.AsyncAnthropic] = None):
        object.__setattr__(self, '_default', default)

    def _default_client(self) -> anthropic.AsyncAnthropic:
        default = self._default
        if default is None:
            default = anthropic.AsyncAnthropic(timeout=120.0, max_retries=1)
            object.__setattr__(self, '_default', default)
        return default

    def _resolve(self) -> anthropic.AsyncAnthropic:
        if should_route_features_through_gateway():
            return get_gateway_anthropic_client()
        return self._default_client()

    def __getattr__(self, name: str):
        return getattr(self._resolve(), name)


class _OpenAIEmbeddingsProxy:
    """Lazily forwards embedding calls to the managed OpenAI client."""

    __slots__ = ('_model', '_default', '_ctor_kwargs')

    def __init__(self, model: str, default: Optional[OpenAIEmbeddings], ctor_kwargs: Dict[str, Any]):
        object.__setattr__(self, '_model', model)
        object.__setattr__(self, '_default', default)
        object.__setattr__(self, '_ctor_kwargs', ctor_kwargs)

    def _default_client(self) -> OpenAIEmbeddings:
        default = self._default
        if default is None:
            default = OpenAIEmbeddings(model=self._model, **self._ctor_kwargs)
            object.__setattr__(self, '_default', default)
        return default

    def embed_query(self, text: str) -> List[float]:
        return self._default_client().embed_query(text)

    def embed_documents(self, texts: List[str]) -> List[List[float]]:
        return self._default_client().embed_documents(texts)

    def __getattr__(self, name: str):
        return getattr(self._default_client(), name)


# Anthropic client for chat agent (module-level, managed credentials only).
# The proxy constructs the provider client at its first use so importing a
# deployable entrypoint never needs provider credentials.
anthropic_client = _AnthropicClientProxy()


def get_openai_chat(model: str, **kwargs) -> ChatOpenAI:
    """Explicit factory; equivalent to using the module-level proxies."""
    kwargs = _with_llm_callbacks(kwargs, 'openai', model=model)
    return ChatOpenAI(model=model, **kwargs)


# ---------------------------------------------------------------------------
# Model QoS and provider routing
# ---------------------------------------------------------------------------


# Compatibility wrappers for tests and legacy imports. New provider construction
# lives in providers.py.
def _get_or_create_openai_llm(model_name: str, streaming: bool = False) -> ChatOpenAI:
    options: Dict[str, Any] = {}
    if supports_cache_retention(model_name):
        options['extra_body'] = {"prompt_cache_retention": "24h"}
    return get_or_create_openai_compatible_llm('openai', model_name, streaming, options)


def _get_or_create_openrouter_llm(
    model_name: str, streaming: bool = False, temperature: Optional[float] = None
) -> ChatOpenAI:
    options: Dict[str, Any] = {}
    if temperature is not None:
        options['temperature'] = temperature
    return get_or_create_openai_compatible_llm('openrouter', model_name, streaming, options)


def get_llm(
    feature: str,
    streaming: bool = False,
    cache_key: Optional[str] = None,
    prompt_cache_options: Optional[dict[str, str]] = None,
) -> BaseChatModel:
    """Get the LLM client for a feature based on the active Model QoS profile.

    Works for OpenAI, Gemini, OpenRouter, and other registered OpenAI-compatible
    providers. Returns a BaseChatModel. For Anthropic/Perplexity, use
    get_model(feature) to get the model string and the provider-specific client.
    """
    gateway_feature_mode = should_route_features_through_gateway()

    if is_anthropic_only_feature(feature) and not gateway_feature_mode:
        raise ValueError(
            f"Feature '{feature}' is Anthropic — use get_model('{feature}') with anthropic_client instead of get_llm()"
        )
    if is_perplexity_only_feature(feature) and not gateway_feature_mode:
        raise ValueError(
            f"Feature '{feature}' is Perplexity — use get_model('{feature}') with the Perplexity HTTP client instead of get_llm()"
        )

    model, provider = _get_model_config(feature)

    if provider == 'anthropic' and not gateway_feature_mode:
        raise ValueError(
            f"Feature '{feature}' resolved to Anthropic model '{model}' — use get_model() with anthropic_client"
        )
    if provider == 'perplexity' and not gateway_feature_mode:
        raise ValueError(
            f"Feature '{feature}' resolved to Perplexity model '{model}' — use get_model() with Perplexity HTTP client"
        )

    if is_structured_output_feature(feature) and provider == 'gemini':
        logger.debug(
            'QoS structured_output on gemini: feature=%s model=%s profile=%s',
            feature,
            model,
            get_active_profile_name(),
        )

    if gateway_feature_mode:
        result = get_or_create_omi_gateway_llm(feature_auto_lane_id(feature), streaming, feature=feature)
    else:
        result = get_default_client(model, provider, streaming, get_route_options(feature, model, provider))

    result = maybe_wrap_dev_gateway_shadow(
        feature=feature,
        model=model,
        provider=provider,
        streaming=streaming,
        legacy_model=result,
    )

    cache_params: Dict[str, Any] = {}
    if cache_key and supports_prompt_cache(model):
        cache_params['prompt_cache_key'] = cache_key
    # prompt_cache_options is accepted but not sent. The field is a contract
    # between this caller and the gateway, and the two deploy from separate
    # pipelines, so the gateway can be running a build that predates it and
    # rejects the request outright. Sending it broke conversation structuring
    # for every request that routed through the gateway.
    #
    # Restore the send once a gateway carrying the field in its forwarded
    # parameters is deployed. It travels in extra_body when it returns: the
    # client validates named arguments before building the request, so a
    # version that predates the field raises in process instead of reaching the
    # gateway at all.
    if cache_params:
        return result.bind(**cache_params)
    return result


def get_llm_gateway_chat_structured(
    streaming: bool = False,
    cache_key: Optional[str] = None,
    request_timeout: float | None = None,
) -> BaseChatModel:
    """Return the gateway chat-structured lane as a LangChain chat model.

    Use this for shadow/eval comparisons that must preserve the existing
    LangChain prompt and parser chain shape. Live feature routing should still
    go through ``get_llm(feature)`` until an explicit rollout promotes the
    gateway provider for that feature.
    """

    result = get_or_create_omi_gateway_llm(
        CHAT_STRUCTURED_AUTO_LANE_ID,
        streaming,
        options={
            'request_timeout': (
                request_timeout if request_timeout is not None else BACKGROUND_CHAT_EXTRACTION_TIMEOUT_SECONDS
            )
        },
        feature='chat_extraction',
    )
    if cache_key:
        return result.bind(prompt_cache_key=cache_key)
    return result


def get_qos_info() -> Dict[str, Dict[str, str]]:
    """Return full feature→(model, provider) mapping for the active profile (debugging/monitoring)."""
    info: Dict[str, Dict[str, str]] = {}
    all_features = get_all_configured_features()
    for feature in sorted(all_features):
        model, provider = _get_model_config(feature)
        info[feature] = {
            'model': model,
            'profile': get_active_profile_name(),
            'provider': provider,
        }
    return info


# Startup logging — log active profile so cost issues are traceable.
_active_profile = get_active_profile()
logger.info('Model QoS profile=%s (%d features)', get_active_profile_name(), len(_active_profile))
for _feat, (_model, _provider) in sorted(_active_profile.items()):
    logger.info('  QoS %s: %s [%s]', _feat, _model, _provider)
_so_gemini = {f for f in _active_profile if is_structured_output_feature(f) and _get_model_config(f)[1] == 'gemini'}
if _so_gemini:
    logger.info('Structured output features on Gemini: %s', ', '.join(sorted(_so_gemini)))


# ---------------------------------------------------------------------------
# Anthropic — model resolved from active QoS profile
# ---------------------------------------------------------------------------
ANTHROPIC_AGENT_MODEL = get_model('chat_agent')
ANTHROPIC_AGENT_COMPLEX_MODEL = get_model('chat_agent')


# ---------------------------------------------------------------------------
# Legacy module-level alias (kept for test compatibility).
# Production code should use get_llm(feature) exclusively. The proxy preserves
# the legacy object shape without constructing a provider client at import time.
# ---------------------------------------------------------------------------


class _LazyClientProxy:
    """Resolve a compatibility client only when a caller first uses it."""

    __slots__ = ('_factory', '_instance')

    def __init__(self, factory: Callable[[], Any]):
        object.__setattr__(self, '_factory', factory)
        object.__setattr__(self, '_instance', None)

    def _resolve(self) -> Any:
        instance = self._instance
        if instance is None:
            instance = self._factory()
            object.__setattr__(self, '_instance', instance)
        return instance

    def __getattr__(self, name: str) -> Any:
        return getattr(self._resolve(), name)

    def __or__(self, other: Any) -> Any:
        return self._resolve() | other

    def __ror__(self, other: Any) -> Any:
        return other | self._resolve()


def _create_legacy_llm_mini() -> ChatOpenAI:
    return ChatOpenAI(model='gpt-4.1-mini', callbacks=[_usage_callback], request_timeout=120, max_retries=1)


llm_mini = _LazyClientProxy(_create_legacy_llm_mini)

# ---------------------------------------------------------------------------
# Embeddings, parser, utilities
# ---------------------------------------------------------------------------
embeddings = _OpenAIEmbeddingsProxy(
    model="text-embedding-3-large",
    default=None,
    ctor_kwargs={},
)
parser = PydanticOutputParser(pydantic_object=StructuredExtraction)


@lru_cache(maxsize=1)
def _get_encoding():
    return tiktoken.encoding_for_model('gpt-4')


def num_tokens_from_string(string: str) -> int:
    """Returns the number of tokens in a text string."""
    num_tokens = len(_get_encoding().encode(string))
    return num_tokens


def generate_embedding(content: str) -> List[float]:
    if should_route_features_through_gateway():
        record_direct_exception_surface(surface='openai_embeddings', reason='out_of_scope')
    return embeddings.embed_documents([content])[0]


def gemini_embed_query(text: str) -> List[float]:
    """Embed a query using Gemini embedding-001 (3072-dim) for screen activity search.

    Uses RETRIEVAL_QUERY task type to match the RETRIEVAL_DOCUMENT embeddings
    generated by the desktop app and the product-managed Gemini credential.
    """
    if should_route_features_through_gateway():
        record_direct_exception_surface(surface='gemini_screen_activity_query_embedding', reason='out_of_scope')
    api_key = os.environ.get('GEMINI_API_KEY', '')
    url = 'https://generativelanguage.googleapis.com/v1beta/models/embedding-001:embedContent'
    payload = {
        'model': 'models/embedding-001',
        'content': {'parts': [{'text': text}]},
        'taskType': 'RETRIEVAL_QUERY',
    }
    headers = {'x-goog-api-key': api_key, 'Content-Type': 'application/json'}
    resp = httpx.post(url, json=payload, headers=headers, timeout=10)
    resp.raise_for_status()
    return resp.json()['embedding']['values']
