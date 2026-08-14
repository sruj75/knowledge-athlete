"""First-party authorization for retained product-memory routes."""

from dataclasses import dataclass
from typing import Any, Callable, Dict, Optional, cast

from models.product_memory import MemoryAccessPolicy
from utils.memory import default_read_rollout as default_read_rollout_mod
from utils.memory.default_read_rollout import (
    DefaultReadRolloutDecision,
    GlobalReadGateDecision,
    MemoryReadDecision,
    read_archive_read_rollout,
    read_default_read_rollout,
    read_global_read_gate,
)

ObservabilityPayload = Dict[str, Any]
ReadGlobalGate = Callable[..., GlobalReadGateDecision]
ReadRollout = Callable[..., DefaultReadRolloutDecision]


@dataclass(frozen=True)
class ProductAuthorizationContext:
    uid: str
    consumer: str
    surface: str
    explicit_archive_request: bool = False
    requires_archive_capability: bool = False


@dataclass(frozen=True)
class ProductAuthorizationDecision:
    allowed: bool
    context: ProductAuthorizationContext
    db_client: object
    read_decision: MemoryReadDecision
    reason: str
    observability: ObservabilityPayload
    policy: Optional[MemoryAccessPolicy] = None
    global_gate: Optional[GlobalReadGateDecision] = None
    rollout: Optional[DefaultReadRolloutDecision] = None
    status_code: int = 403


def _gate_observability(gate: GlobalReadGateDecision, context: ProductAuthorizationContext) -> ObservabilityPayload:
    return {
        'consumer': context.consumer,
        'surface': context.surface,
        'source_path': gate.source_path,
        'read_decision': gate.read_decision.value,
        'fallback_reason': gate.fallback_reason,
        'reason': gate.fallback_reason or gate.reason,
        'archive_default_visible': False,
        'archive_capability_required': context.requires_archive_capability,
        'explicit_archive_request': context.explicit_archive_request,
    }


def _rollout_observability(
    rollout: DefaultReadRolloutDecision, context: ProductAuthorizationContext
) -> ObservabilityPayload:
    build = cast(
        Callable[[DefaultReadRolloutDecision], ObservabilityPayload],
        getattr(default_read_rollout_mod, 'build_default_read_rollout_observability'),
    )
    observability = build(rollout)
    observability.update(
        {
            'surface': context.surface,
            'archive_default_visible': False,
            'archive_capability_required': context.requires_archive_capability,
            'archive_capability_granted': rollout.archive_capability,
            'explicit_archive_request': context.explicit_archive_request,
        }
    )
    return observability


def _deny(
    context: ProductAuthorizationContext,
    db_client: object,
    decision: MemoryReadDecision,
    reason: str,
    observability: ObservabilityPayload,
    *,
    global_gate: GlobalReadGateDecision,
    rollout: DefaultReadRolloutDecision | None = None,
) -> ProductAuthorizationDecision:
    observability['reason'] = reason
    if decision != MemoryReadDecision.USE_MEMORY:
        observability['fallback_reason'] = reason
    return ProductAuthorizationDecision(
        allowed=False,
        context=context,
        db_client=db_client,
        read_decision=decision,
        reason=reason,
        observability=observability,
        global_gate=global_gate,
        rollout=rollout,
    )


def authorize_memory_product_memory_route(
    context: ProductAuthorizationContext,
    *,
    db_client: object,
    read_global_gate: ReadGlobalGate = read_global_read_gate,
    read_default_rollout: ReadRollout = read_default_read_rollout,
    read_archive_rollout: ReadRollout = read_archive_read_rollout,
) -> ProductAuthorizationDecision:
    """Authorize the retained authenticated memory product before reading data."""
    global_gate = read_global_gate(db_client=db_client)
    observability = _gate_observability(global_gate, context)
    if global_gate.read_decision != MemoryReadDecision.USE_MEMORY:
        return _deny(
            context,
            db_client,
            global_gate.read_decision,
            global_gate.fallback_reason or global_gate.reason,
            observability,
            global_gate=global_gate,
        )
    if context.requires_archive_capability and not context.explicit_archive_request:
        return _deny(
            context,
            db_client,
            MemoryReadDecision.DENY_MEMORY,
            'missing_explicit_archive_request',
            observability,
            global_gate=global_gate,
        )
    reader = read_archive_rollout if context.requires_archive_capability else read_default_rollout
    rollout = reader(uid=context.uid, db_client=db_client, consumer=context.consumer)
    observability = _rollout_observability(rollout, context)
    if rollout.read_decision != MemoryReadDecision.USE_MEMORY:
        return _deny(
            context,
            db_client,
            rollout.read_decision,
            rollout.fallback_reason or rollout.reason,
            observability,
            global_gate=global_gate,
            rollout=rollout,
        )
    archive = context.requires_archive_capability
    if not archive:
        observability['archive_capability_granted'] = False
    return ProductAuthorizationDecision(
        allowed=True,
        context=context,
        db_client=db_client,
        read_decision=MemoryReadDecision.USE_MEMORY,
        reason='ok',
        observability=observability,
        policy=MemoryAccessPolicy.for_omi_chat(archive_capability=archive),
        global_gate=global_gate,
        rollout=rollout,
        status_code=200,
    )
