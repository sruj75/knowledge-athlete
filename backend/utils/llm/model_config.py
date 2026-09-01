"""Explicit managed-model workload inventory.

Every constructible workload names one provider, model, caller, result owner,
and failure policy. Runtime environment cannot select a global profile or an
implicit fallback route.
"""

from dataclasses import dataclass
from enum import Enum
from typing import Dict, Tuple


class WorkloadLifecycle(str, Enum):
    """Implementation ownership for one managed-model workload."""

    RETAINED = 'retained'
    DEPENDENCY_S20 = 'dependency_s20'


@dataclass(frozen=True)
class ManagedModelWorkload:
    """Auditable contract for one model-backed product workload."""

    key: str
    provider: str
    model: str
    caller: str
    input_contract: str
    output_contract: str
    usage_feature: str
    result_owner: str
    failure_policy: str
    lifecycle: WorkloadLifecycle


def _workload(
    key: str,
    provider: str,
    model: str,
    caller: str,
    input_contract: str,
    output_contract: str,
    usage_feature: str,
    result_owner: str,
    failure_policy: str,
    lifecycle: WorkloadLifecycle = WorkloadLifecycle.RETAINED,
) -> ManagedModelWorkload:
    return ManagedModelWorkload(
        key=key,
        provider=provider,
        model=model,
        caller=caller,
        input_contract=input_contract,
        output_contract=output_contract,
        usage_feature=usage_feature,
        result_owner=result_owner,
        failure_policy=failure_policy,
        lifecycle=lifecycle,
    )


_WORKLOADS: Dict[str, ManagedModelWorkload] = {
    'conv_action_items': _workload(
        'conv_action_items',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/conversation-compute/action-items',
        'bounded local transcript plus local time and related-task facts',
        'validated action-item candidates',
        'conversation_processing',
        'Mac ActionItemStorage transaction',
        'independent non-fatal candidate failure',
    ),
    'conv_structure': _workload(
        'conv_structure',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/conversation-compute/structure',
        'bounded local transcript plus language and local-time facts',
        'validated conversation structure candidate',
        'conversation_processing',
        'Mac conversation transaction',
        'independent non-fatal candidate failure',
    ),
    'conv_discard': _workload(
        'conv_discard',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/conversation-compute/discard',
        'bounded local transcript, duration, and word count',
        'validated discard candidate',
        'conversation_processing',
        'Mac conversation finalization transaction',
        'keep on provider or parse failure',
    ),
    'chat_greeting': _workload(
        'chat_greeting',
        'gemini',
        'gemini-3.7-flash',
        'POST /v2/chat/initial-message',
        'bounded local profile and memory context',
        'validated greeting candidate',
        'chat_greeting',
        'owner-scoped Mac Node journal',
        'non-fatal welcome fallback',
    ),
    'session_titles': _workload(
        'session_titles',
        'gemini',
        'gemini-2.5-flash-lite',
        'POST /v2/chat/generate-title',
        'bounded first accepted local Chat exchange',
        'validated six-word title candidate',
        'session_titles',
        'owner-scoped Mac Chat catalog',
        'non-fatal New Chat fallback',
    ),
    'translation': _workload(
        'translation',
        'gemini',
        'gemini-2.5-flash-lite',
        'POST /v4/listen translation coordinator',
        'bounded managed-STT segment batch and target language',
        'cardinality-matched translated candidates',
        'translation',
        'matching Mac transcript segments',
        'preserve original transcript on failure',
    ),
    'chat_agent': _workload(
        'chat_agent',
        'gemini',
        'gemini-3.7-flash',
        'POST /v2/models/gemini-3.7-flash:streamGenerateContent from local Node/Pi',
        'bounded owner-scoped local Chat context and tool schema',
        'native Gemini content and tool-call stream',
        'chat_agent',
        'owner-scoped Mac Node journal',
        'typed provider failure without cloud journal fallback',
    ),
    'fair_use': _workload(
        'fair_use',
        'gemini',
        'gemini-3.7-flash',
        'S-20 bounded fair-use classify route',
        'bounded local fair-use evidence packet',
        'validated classification candidate',
        'fair_use',
        'S-20 Mac GRDB evidence and content-free enforcement facts',
        'retain S-20 fail-open classification behavior',
        WorkloadLifecycle.DEPENDENCY_S20,
    ),
    'memory_l1': _workload(
        'memory_l1',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/memory/compute/extract',
        'bounded readable local transcript and evidence references',
        'validated grounded Memory candidates',
        'memory_l1',
        'Mac MemoryStorage lifecycle transaction',
        'no mutation on provider, parse, or evidence failure',
    ),
    'memory_l2': _workload(
        'memory_l2',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/memory/compute/normalize',
        'bounded explicit assertion, provenance, and revision',
        'validated normalized Memory proposal',
        'memory_l2',
        'Mac MemoryStorage lifecycle transaction',
        'retryable no-mutation failure',
    ),
    'memory_conflict': _workload(
        'memory_conflict',
        'gemini',
        'gemini-3.7-flash',
        'POST /v1/memory/compute/consolidate',
        'bounded due candidates and relevant local Memory references',
        'conserved lifecycle and relationship proposals',
        'memory_conflict',
        'Mac MemoryStorage atomic lifecycle transaction',
        'retry or review without partial mutation',
    ),
}

_STRUCTURED_OUTPUT_FEATURES = {'translation'}


def get_workload(feature: str) -> ManagedModelWorkload:
    try:
        return _WORKLOADS[feature]
    except KeyError as exc:
        raise KeyError(f"Unknown managed-model workload '{feature}'") from exc


def get_all_workloads() -> Dict[str, ManagedModelWorkload]:
    return {key: _WORKLOADS[key] for key in sorted(_WORKLOADS)}


def _get_model_config(feature: str) -> Tuple[str, str]:
    workload = get_workload(feature)
    return workload.model, workload.provider


def get_model_config(feature: str) -> Tuple[str, str]:
    return _get_model_config(feature)


def get_model(feature: str) -> str:
    return get_workload(feature).model


def get_provider(feature: str) -> str:
    return get_workload(feature).provider


def get_route_options(feature: str) -> Dict[str, object]:
    workload = get_workload(feature)
    options: Dict[str, object] = {}
    if workload.model.startswith('gemini-2.5') and not is_structured_output_feature(feature):
        options['thinking_budget'] = 0
    return options


def is_structured_output_feature(feature: str) -> bool:
    return feature in _STRUCTURED_OUTPUT_FEATURES


def get_all_configured_features() -> set[str]:
    return set(_WORKLOADS)
