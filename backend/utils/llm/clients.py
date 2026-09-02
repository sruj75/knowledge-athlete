"""Small direct-provider client layer for explicit managed-model workloads."""

from langchain_core.language_models import BaseChatModel
from langchain_core.output_parsers import PydanticOutputParser

from models.structured_extraction import StructuredExtraction
from utils.llm.model_config import get_route_options, get_workload
from utils.llm.providers import get_default_client


def get_workload_client(
    feature: str,
    streaming: bool = False,
) -> BaseChatModel:
    """Construct the one explicit in-process client declared for ``feature``."""

    workload = get_workload(feature)
    return get_default_client(
        workload.model,
        workload.provider,
        streaming,
        get_route_options(feature),
        feature=feature,
    )


def bind_llm_output_token_limit(feature: str, llm: BaseChatModel, max_output_tokens: int) -> BaseChatModel:
    """Bind the completion cap using the workload's provider-native parameter."""

    if max_output_tokens <= 0:
        raise ValueError('max_output_tokens must be positive')
    return llm.bind(max_output_tokens=max_output_tokens)


parser = PydanticOutputParser(pydantic_object=StructuredExtraction)
