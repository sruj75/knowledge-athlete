"""Provider-neutral request-attempt and usage metadata for the S-25 gateway handoff."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass, field
from enum import StrEnum
from typing import Any, cast


class CacheStatus(StrEnum):
    HIT = 'hit'
    PARTIAL_HIT = 'partial_hit'
    MISS = 'miss'
    NO_CACHE_READ_OBSERVED = 'no_cache_read_observed'
    NOT_REQUESTED = 'not_requested'
    NOT_REPORTED = 'not_reported'
    NOT_APPLICABLE = 'not_applicable'


class UsageStatus(StrEnum):
    CONFIRMED = 'confirmed'
    NOT_REPORTED = 'not_reported'
    INDETERMINATE = 'indeterminate'


@dataclass(frozen=True)
class ProviderUsage:
    """Normalized billable units reported by an upstream provider."""

    prompt_tokens: int = 0
    cached_input_tokens: int = 0
    uncached_input_tokens: int = 0
    output_tokens: int = 0
    reasoning_tokens: int = 0
    output_tokens_include_reasoning: bool = False
    tool_use_prompt_tokens: int = 0
    cache_write_tokens: int = 0
    cache_write_ttl: str | None = None
    total_tokens: int = 0
    cache_status: CacheStatus = CacheStatus.NOT_REPORTED
    unit_type: str = 'tokens'
    image_count: int = 0
    image_size: str | None = None
    image_quality: str | None = None

    @property
    def billable_output_tokens(self) -> int:
        # OpenAI completion tokens already include its reasoning-token subset;
        # Vertex reports thought tokens separately from candidate output.
        return (
            self.output_tokens if self.output_tokens_include_reasoning else self.output_tokens + self.reasoning_tokens
        )


@dataclass(frozen=True)
class ProviderResponseMetadata:
    usage: ProviderUsage | None = None
    provider_response_id: str | None = None
    actual_model_version: str | None = None
    traffic_type: str | None = None


@dataclass(frozen=True)
class ProviderAttempt:
    ordinal: int
    provider: str
    configured_model: str
    route_artifact_id: str | None
    fallback_reason: str | None
    retry_ordinal: int
    outcome: str
    error_class: str
    usage: ProviderUsage | None = None
    usage_status: UsageStatus = UsageStatus.NOT_REPORTED
    provider_response_id: str | None = None
    actual_model_version: str | None = None
    traffic_type: str | None = None


@dataclass
class AttemptTrace:
    """Ordered attempt trace for one logical gateway invocation."""

    attempts: list[ProviderAttempt] = field(default_factory=list)

    def record(
        self,
        *,
        provider: str,
        configured_model: str,
        route_artifact_id: str | None,
        fallback_reason: str | None,
        retry_ordinal: int,
        outcome: str,
        error_class: str,
        metadata: ProviderResponseMetadata | None = None,
        usage_status: UsageStatus | None = None,
    ) -> ProviderAttempt:
        response_metadata = metadata or ProviderResponseMetadata()
        status = usage_status or (
            UsageStatus.CONFIRMED if response_metadata.usage is not None else UsageStatus.NOT_REPORTED
        )
        attempt = ProviderAttempt(
            ordinal=len(self.attempts) + 1,
            provider=provider,
            configured_model=configured_model,
            route_artifact_id=route_artifact_id,
            fallback_reason=fallback_reason,
            retry_ordinal=retry_ordinal,
            outcome=outcome,
            error_class=error_class,
            usage=response_metadata.usage,
            usage_status=status,
            provider_response_id=response_metadata.provider_response_id,
            actual_model_version=response_metadata.actual_model_version,
            traffic_type=response_metadata.traffic_type,
        )
        self.attempts.append(attempt)
        return attempt


def openai_usage_from_response(
    response: Mapping[str, Any],
    *,
    cache_requested: bool = False,
) -> ProviderResponseMetadata:
    usage_value = response.get('usage')
    if not isinstance(usage_value, Mapping):
        return ProviderResponseMetadata(provider_response_id=_string_or_none(response.get('id')))
    raw_usage = cast(Mapping[str, Any], usage_value)
    if not _has_any_field(
        raw_usage, 'prompt_tokens', 'input_tokens', 'completion_tokens', 'output_tokens', 'total_tokens'
    ):
        return ProviderResponseMetadata(
            provider_response_id=_string_or_none(response.get('id')),
            actual_model_version=_string_or_none(response.get('model')),
        )
    usage = _openai_usage(raw_usage, cache_requested=cache_requested)
    return ProviderResponseMetadata(
        usage=usage,
        provider_response_id=_string_or_none(response.get('id')),
        actual_model_version=_string_or_none(response.get('model')),
    )


def openai_usage_from_sse_payload(
    payload: Mapping[str, Any],
    *,
    cache_requested: bool = False,
) -> ProviderResponseMetadata | None:
    if not isinstance(payload.get('usage'), Mapping):
        return None
    return openai_usage_from_response(payload, cache_requested=cache_requested)


def vertex_usage_from_response(response: Mapping[str, Any]) -> ProviderResponseMetadata:
    usage_value = response.get('usageMetadata')
    if not isinstance(usage_value, Mapping):
        return ProviderResponseMetadata(
            provider_response_id=_string_or_none(response.get('responseId')),
            actual_model_version=_string_or_none(response.get('modelVersion')),
            traffic_type=_string_or_none(response.get('trafficType')),
        )
    raw = cast(Mapping[str, Any], usage_value)
    if not _has_any_field(
        raw,
        'promptTokenCount',
        'cachedContentTokenCount',
        'candidatesTokenCount',
        'thoughtsTokenCount',
        'toolUsePromptTokenCount',
        'totalTokenCount',
    ):
        return ProviderResponseMetadata(
            provider_response_id=_string_or_none(response.get('responseId')),
            actual_model_version=_string_or_none(response.get('modelVersion')),
            traffic_type=_string_or_none(response.get('trafficType')),
        )
    prompt = _nonnegative_int(raw.get('promptTokenCount'))
    cached = min(prompt, _nonnegative_int(raw.get('cachedContentTokenCount')))
    candidates = _nonnegative_int(raw.get('candidatesTokenCount'))
    thoughts = _nonnegative_int(raw.get('thoughtsTokenCount'))
    tool_use = _nonnegative_int(raw.get('toolUsePromptTokenCount'))
    total = _nonnegative_int(raw.get('totalTokenCount'))
    if total == 0:
        total = prompt + candidates + thoughts
    cache_status = _cache_status(
        prompt_tokens=prompt,
        cached_tokens=cached,
        cache_requested=False,
        cache_field_reported='cachedContentTokenCount' in raw,
    )
    return ProviderResponseMetadata(
        usage=ProviderUsage(
            prompt_tokens=prompt,
            cached_input_tokens=cached,
            uncached_input_tokens=max(prompt - cached, 0),
            output_tokens=candidates,
            reasoning_tokens=thoughts,
            tool_use_prompt_tokens=tool_use,
            total_tokens=total,
            cache_status=cache_status,
        ),
        provider_response_id=_string_or_none(response.get('responseId')),
        actual_model_version=_string_or_none(response.get('modelVersion')),
        traffic_type=_string_or_none(response.get('trafficType')),
    )


def anthropic_usage_from_response(
    response: Mapping[str, Any],
    *,
    cache_requested: bool,
    cache_write_ttl: str | None = None,
) -> ProviderResponseMetadata:
    usage_value = response.get('usage')
    if not isinstance(usage_value, Mapping):
        return ProviderResponseMetadata(
            provider_response_id=_string_or_none(response.get('id')),
            actual_model_version=_string_or_none(response.get('model')),
        )
    raw = cast(Mapping[str, Any], usage_value)
    if not _has_any_field(
        raw, 'input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens', 'output_tokens'
    ):
        return ProviderResponseMetadata(
            provider_response_id=_string_or_none(response.get('id')),
            actual_model_version=_string_or_none(response.get('model')),
        )
    uncached = _nonnegative_int(raw.get('input_tokens'))
    cached = _nonnegative_int(raw.get('cache_read_input_tokens'))
    cache_write = _nonnegative_int(raw.get('cache_creation_input_tokens'))
    output = _nonnegative_int(raw.get('output_tokens'))
    return ProviderResponseMetadata(
        usage=ProviderUsage(
            prompt_tokens=uncached + cached,
            cached_input_tokens=cached,
            uncached_input_tokens=uncached,
            output_tokens=output,
            cache_write_tokens=cache_write,
            cache_write_ttl=cache_write_ttl if cache_write else None,
            total_tokens=uncached + cached + output,
            cache_status=_cache_status(
                prompt_tokens=uncached + cached,
                cached_tokens=cached,
                cache_requested=cache_requested,
                cache_field_reported='cache_read_input_tokens' in raw,
            ),
        ),
        provider_response_id=_string_or_none(response.get('id')),
        actual_model_version=_string_or_none(response.get('model')),
    )


def image_usage(*, count: int, size: object, quality: object) -> ProviderUsage:
    return ProviderUsage(
        cache_status=CacheStatus.NOT_APPLICABLE,
        unit_type='images',
        image_count=max(count, 0),
        image_size=_string_or_none(size),
        image_quality=_string_or_none(quality),
    )


def cache_requested_for_openai_request(request: Mapping[str, Any]) -> bool:
    prompt_cache_key = request.get('prompt_cache_key')
    if not isinstance(prompt_cache_key, str) or not prompt_cache_key.strip():
        return False
    # Pre-5.6 callers use implicit caching with only a routing key.  Explicit
    # GPT-5.6 requests without a marker deliberately opt out of cache writes.
    if request.get('prompt_cache_options') == {'mode': 'explicit', 'ttl': '30m'}:
        return _has_openai_cache_breakpoint(request.get('messages'))
    return True


def _has_openai_cache_breakpoint(messages: object) -> bool:
    if not isinstance(messages, list):
        return False
    for message in messages:
        if not isinstance(message, Mapping):
            continue
        content = message.get('content')
        if not isinstance(content, list):
            continue
        for part in content:
            if isinstance(part, Mapping) and part.get('prompt_cache_breakpoint') == {'mode': 'explicit'}:
                return True
    return False


def cache_requested_for_anthropic_request(request: Mapping[str, Any]) -> bool:
    return _contains_cache_control(request)


def cache_write_ttl_for_anthropic_request(request: Mapping[str, Any]) -> str | None:
    ttls = _cache_control_ttls(request)
    if len(ttls) == 1:
        return next(iter(ttls))
    return 'mixed' if ttls else None


def _openai_usage(raw: Mapping[str, Any], *, cache_requested: bool) -> ProviderUsage:
    prompt = _nonnegative_int(raw.get('prompt_tokens', raw.get('input_tokens')))
    output = _nonnegative_int(raw.get('completion_tokens', raw.get('output_tokens')))
    details = raw.get('prompt_tokens_details', raw.get('input_tokens_details'))
    cached = _nonnegative_int(details.get('cached_tokens')) if isinstance(details, Mapping) else 0
    cached = min(prompt, cached)
    cache_write = _nonnegative_int(details.get('cache_write_tokens')) if isinstance(details, Mapping) else 0
    completion_details = raw.get('completion_tokens_details', raw.get('output_tokens_details'))
    reasoning = (
        _nonnegative_int(completion_details.get('reasoning_tokens')) if isinstance(completion_details, Mapping) else 0
    )
    # OpenAI reports reasoning tokens as a subset of completion tokens, so its
    # omitted total is prompt + completion (unlike Vertex thought tokens).
    total = _nonnegative_int(raw.get('total_tokens')) or prompt + output
    return ProviderUsage(
        prompt_tokens=prompt,
        cached_input_tokens=cached,
        # OpenAI includes explicit cache-write tokens in prompt_tokens; their
        # write rate replaces the ordinary uncached-input rate for those units.
        uncached_input_tokens=max(prompt - cached - cache_write, 0),
        output_tokens=output,
        reasoning_tokens=reasoning,
        output_tokens_include_reasoning=True,
        cache_write_tokens=cache_write,
        cache_write_ttl='30m' if cache_write else None,
        total_tokens=total,
        cache_status=_cache_status(
            prompt_tokens=prompt,
            cached_tokens=cached,
            cache_requested=cache_requested,
            cache_field_reported=isinstance(details, Mapping) and 'cached_tokens' in details,
        ),
    )


def _cache_status(
    *,
    prompt_tokens: int,
    cached_tokens: int,
    cache_requested: bool,
    cache_field_reported: bool,
) -> CacheStatus:
    if cached_tokens > 0:
        return CacheStatus.HIT if prompt_tokens > 0 and cached_tokens >= prompt_tokens else CacheStatus.PARTIAL_HIT
    if cache_requested:
        return CacheStatus.MISS
    if cache_field_reported:
        return CacheStatus.NO_CACHE_READ_OBSERVED
    return CacheStatus.NOT_REPORTED


def _contains_cache_control(value: object) -> bool:
    if isinstance(value, Mapping):
        if 'cache_control' in value:
            return True
        return any(_contains_cache_control(item) for item in value.values())
    if isinstance(value, list):
        return any(_contains_cache_control(item) for item in value)
    return False


def _cache_control_ttls(values: object) -> set[str]:
    ttls: set[str] = set()

    def collect(value: object) -> None:
        if isinstance(value, Mapping):
            cache_control = value.get('cache_control')
            if isinstance(cache_control, Mapping):
                ttl = cache_control.get('ttl')
                ttls.add(ttl if ttl in {'5m', '1h'} else '5m')
            for child in value.values():
                collect(child)
        elif isinstance(value, (list, tuple)):
            for child in value:
                collect(child)

    collect(values)
    return ttls


def _nonnegative_int(value: object) -> int:
    if isinstance(value, bool):
        return 0
    if isinstance(value, int):
        return max(value, 0)
    if isinstance(value, float):
        return max(int(value), 0)
    return 0


def _string_or_none(value: object) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


def _has_any_field(raw: Mapping[str, Any], *keys: str) -> bool:
    return any(key in raw for key in keys)
