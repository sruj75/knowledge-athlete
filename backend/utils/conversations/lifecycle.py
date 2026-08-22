"""Lifecycle primitives retained only for S-25 finalization backlog drain."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Mapping

from database import conversation_finalization_jobs as jobs_db
from database import conversations as conversations_db
from models.conversation_enums import ConversationStatus


class LifecycleTransitionError(ValueError):
    """Raised when a drain worker would reopen a terminal generation."""


def _status_value(status: ConversationStatus | str | None) -> str:
    if isinstance(status, ConversationStatus):
        return status.value
    if isinstance(status, str):
        return status
    raise LifecycleTransitionError('conversation status is required')


def _require_status(data: Mapping[str, Any], *allowed: ConversationStatus) -> None:
    status = _status_value(data.get('status'))
    if status not in {candidate.value for candidate in allowed}:
        raise LifecycleTransitionError(f'lifecycle persistence rejects status={status}')


def persist_processed_conversation(uid: str, conversation_data: dict[str, Any]) -> bool:
    _require_status(conversation_data, ConversationStatus.completed, ConversationStatus.failed)
    return conversations_db.persist_processing_result_with_lifecycle(uid, conversation_data)


def ensure_processing(uid: str, conversation_id: str) -> bool:
    """Claim one historical in-progress row without reopening terminals."""
    conversation = conversations_db.get_conversation(uid, conversation_id)
    if not conversation:
        raise LifecycleTransitionError(f'conversation {conversation_id} does not exist')
    status = _status_value(conversation.get('status'))
    if status == ConversationStatus.processing.value:
        return True
    if status in {ConversationStatus.completed.value, ConversationStatus.failed.value}:
        return False
    if status != ConversationStatus.in_progress.value:
        raise LifecycleTransitionError(f'invalid drain transition {status}->processing')
    return conversations_db.claim_conversation_status(
        uid,
        conversation_id,
        ConversationStatus.in_progress,
        ConversationStatus.processing,
        extra_updates={'processing_admitted_at': datetime.now(timezone.utc)},
    )


def claim_finalization_fanout(
    job_id: str,
    dispatch_generation: int,
    lease_epoch: int,
) -> jobs_db.FinalizationFanoutClaim:
    return jobs_db.claim_finalization_fanout(job_id, dispatch_generation, lease_epoch)


def complete_finalization_fanout(job_id: str, dispatch_generation: int, lease_epoch: int) -> bool:
    return jobs_db.mark_finalization_fanout_completed(job_id, dispatch_generation, lease_epoch)


def complete_fenced_finalization(job_id: str, dispatch_generation: int, lease_epoch: int) -> bool:
    return jobs_db.mark_finalization_fenced(job_id, dispatch_generation, lease_epoch)
