"""Small direct-provider client layer for explicit managed-model workloads."""

from typing import Any, Dict, List, Optional

import anthropic
from langchain_core.language_models import BaseChatModel
from langchain_core.output_parsers import PydanticOutputParser
from langchain_openai import OpenAIEmbeddings

from models.structured_extraction import StructuredExtraction
from utils.llm.model_config import get_route_options, get_workload, supports_prompt_cache
from utils.llm.providers import get_default_client


class _AnthropicClientProxy:
    """Construct the managed Anthropic client lazily at first use."""

    __slots__ = ('_default',)

    def __init__(self, default: Optional[anthropic.AsyncAnthropic] = None):
        object.__setattr__(self, '_default', default)

    def _default_client(self) -> anthropic.AsyncAnthropic:
        default = self._default
        if default is None:
            default = anthropic.AsyncAnthropic(timeout=120.0, max_retries=1)
            object.__setattr__(self, '_default', default)
        return default

    def __getattr__(self, name: str):
        return getattr(self._default_client(), name)


class _OpenAIEmbeddingsProxy:
    """Construct the managed OpenAI embeddings client lazily at first use."""

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


anthropic_client = _AnthropicClientProxy()


def get_workload_client(
    feature: str,
    streaming: bool = False,
    cache_key: Optional[str] = None,
) -> BaseChatModel:
    """Construct the one explicit in-process client declared for ``feature``."""

    workload = get_workload(feature)
    if workload.provider == 'anthropic':
        raise ValueError(f"Workload '{feature}' uses the retained Anthropic Messages adapter")
    result = get_default_client(
        workload.model,
        workload.provider,
        streaming,
        get_route_options(feature),
        feature=feature,
    )
    if cache_key and supports_prompt_cache(workload.model):
        return result.bind(prompt_cache_key=cache_key)
    return result


def bind_llm_output_token_limit(feature: str, llm: BaseChatModel, max_output_tokens: int) -> BaseChatModel:
    """Bind the completion cap using the workload's provider-native parameter."""

    if max_output_tokens <= 0:
        raise ValueError('max_output_tokens must be positive')
    provider = get_workload(feature).provider
    parameter = 'max_output_tokens' if provider == 'gemini' else 'max_tokens'
    return llm.bind(**{parameter: max_output_tokens})


embeddings = _OpenAIEmbeddingsProxy(
    model='text-embedding-3-large',
    default=None,
    ctor_kwargs={},
)
parser = PydanticOutputParser(pydantic_object=StructuredExtraction)


def generate_embedding(content: str) -> List[float]:
    return embeddings.embed_documents([content])[0]
